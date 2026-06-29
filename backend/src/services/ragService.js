/**
 * @fileoverview RAG (Retrieval Augmented Generation) Service for IGRIS Agent.
 *
 * Handles the full RAG pipeline:
 *  1. Document ingestion — text, URL, PDF
 *  2. Smart chunking with paragraph / sentence / word boundary awareness
 *  3. Embedding generation via Google Generative AI (text-embedding-004)
 *  4. Vector similarity search (cosine similarity)
 *  5. Knowledge-base CRUD (list, delete, stats)
 *
 * Models are lazy-loaded inside each method via `require('../models')` to
 * avoid startup timing issues with Sequelize initialisation.
 *
 * @module services/ragService
 */

const { GoogleGenerativeAI } = require('@google/generative-ai');
const logger = require('../utils/logger');
const eventBus = require('../core/eventBus');
const { EVENTS } = require('../core/events');
const CircuitBreaker = require('../core/circuitBreaker');

// ---------------------------------------------------------------------------
// RAG Service
// ---------------------------------------------------------------------------

class RAGService {
  /**
   * Create a RAGService instance.
   * Configuration is pulled from environment variables with sensible defaults.
   */
  constructor() {
    /** @type {number} Maximum characters per chunk */
    this.chunkSize = parseInt(process.env.RAG_CHUNK_SIZE) || 1000;

    /** @type {number} Overlap characters between consecutive chunks */
    this.chunkOverlap = parseInt(process.env.RAG_CHUNK_OVERLAP) || 200;

    /** @type {number} Default number of results to return from search */
    this.topK = parseInt(process.env.RAG_TOP_K) || 5;

    /** @type {string} Google embedding model identifier */
    this.embeddingModel = process.env.RAG_EMBEDDING_MODEL || 'text-embedding-004';

    /**
     * In-memory cache for query embeddings.
     * Key = raw query text, Value = embedding float array.
     * @type {Map<string, number[]>}
     */
    this.embeddingCache = new Map();

    // Circuit Breaker for embedding API to prevent cascading failures
    this.embeddingBreaker = new CircuitBreaker('GeminiEmbedding', async (text, apiKey) => {
      const genAI = new GoogleGenerativeAI(apiKey || process.env.GEMINI_API_KEY_DEFAULT);
      const model = genAI.getGenerativeModel({ model: this.embeddingModel });
      const result = await model.embedContent(text);
      return result.embedding.values;
    }, {
      failureThreshold: 5,
      resetTimeoutMs: 60000 // 60 seconds
    });
  }

  // -----------------------------------------------------------------------
  // Embedding generation
  // -----------------------------------------------------------------------

  /**
   * Generate an embedding vector for the given text.
   *
   * @param {string}  text   - The text to embed.
   * @param {string} [apiKey] - Optional per-user Gemini API key.
   * @returns {Promise<number[]|null>} Embedding values array, or `null` on failure.
   */
  async generateEmbedding(text, apiKey) {
    try {
      if (!text || typeof text !== 'string' || text.trim().length === 0) {
        logger.warn({ event: 'rag_embed_skip', reason: 'empty_text' });
        return null;
      }

      // Execute through circuit breaker
      return await this.embeddingBreaker.execute(text, apiKey);
    } catch (error) {
      logger.error({
        event: 'rag_embed_error',
        message: error.message,
        textLength: text?.length,
      });
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Text chunking
  // -----------------------------------------------------------------------

  /**
   * Split text into overlapping chunks, preferring natural boundaries.
   *
   * Strategy:
   *  1. Try to break on paragraph boundaries (`\n\n`).
   *  2. Fall back to sentence boundaries (`. `).
   *  3. Fall back to word boundaries (` `).
   *  4. Hard-cut as a last resort.
   *
   * @param {string} text - The full document text.
   * @returns {{ content: string, chunkIndex: number, tokenCount: number }[]}
   */
  splitTextIntoChunks(text) {
    if (!text || typeof text !== 'string') return [];

    const chunks = [];
    let start = 0;
    let chunkIndex = 0;

    while (start < text.length) {
      let end = Math.min(start + this.chunkSize, text.length);

      // If we haven't reached the end of the document, try to find a clean
      // break point so we don't slice a word / sentence in half.
      if (end < text.length) {
        let breakPoint = -1;

        // 1. Paragraph boundary
        breakPoint = text.lastIndexOf('\n\n', end);
        if (breakPoint > start) {
          end = breakPoint + 2; // include the double-newline
        } else {
          // 2. Sentence boundary
          breakPoint = text.lastIndexOf('. ', end);
          if (breakPoint > start) {
            end = breakPoint + 2; // include the period + space
          } else {
            // 3. Word boundary
            breakPoint = text.lastIndexOf(' ', end);
            if (breakPoint > start) {
              end = breakPoint + 1; // include the space
            }
            // else: hard-cut at chunkSize
          }
        }
      }

      const content = text.slice(start, end).trim();

      if (content.length > 0) {
        chunks.push({
          content,
          chunkIndex,
          tokenCount: Math.ceil(content.length / 4), // rough estimate
        });
        chunkIndex++;
      }

      if (end >= text.length) {
        break;
      }

      // Advance with overlap, ensuring we make forward progress
      const nextStart = end - this.chunkOverlap;
      start = nextStart <= start ? end : nextStart;
    }

    return chunks;
  }

  // -----------------------------------------------------------------------
  // Document ingestion
  // -----------------------------------------------------------------------

  /**
   * Ingest a document into the knowledge base.
   *
   * Creates a `KnowledgeDocument` record, splits the content into chunks,
   * generates embeddings for each chunk, and creates `KnowledgeChunk` records.
   *
   * @param {string} userId - Owner user ID (UUID).
   * @param {Object} params
   * @param {string} params.title      - Document title.
   * @param {string} params.content    - Raw text content to ingest.
   * @param {string} params.sourceType - One of 'upload', 'url', 'text', 'pdf'.
   * @param {string} [params.sourceUrl]  - Original source URL (if applicable).
   * @param {Object} [params.metadata]   - Arbitrary metadata object.
   * @returns {Promise<Object>} The created KnowledgeDocument record.
   */
  async ingestDocument(userId, { title, content, sourceType, sourceUrl, metadata }) {
    const { User, KnowledgeDocument, KnowledgeChunk } = require('../models');

    // Resolve the user's API key (prefer per-user, fall back to default)
    let apiKey = process.env.GEMINI_API_KEY_DEFAULT;
    try {
      const user = await User.findByPk(userId);
      if (user?.geminiApiKey) {
        apiKey = user.geminiApiKey;
      }
    } catch (err) {
      logger.warn({ event: 'rag_user_key_fallback', userId, message: err.message });
    }

    // Sanitize content — strip null bytes and excessive whitespace runs
    const sanitizedContent = (content || '')
      .replace(/\0/g, '')
      .replace(/\r\n/g, '\n')
      .trim();

    if (!sanitizedContent) {
      throw new Error('Cannot ingest empty content.');
    }

    // Create the document record in 'processing' state
    let document;
    try {
      document = await KnowledgeDocument.create({
        userId,
        title: (title || 'Untitled').substring(0, 255),
        content: sanitizedContent,
        sourceType: sourceType || 'text',
        sourceUrl: sourceUrl || null,
        metadata: metadata || {},
        status: 'processing',
        chunkCount: 0,
      });

      logger.info({
        event: 'rag_ingest_start',
        documentId: document.id,
        userId,
        title,
        contentLength: sanitizedContent.length,
      });

      // Split into chunks
      const chunks = this.splitTextIntoChunks(sanitizedContent);

      // Generate embeddings and persist chunks
      let successCount = 0;
      for (const chunk of chunks) {
        try {
          const embedding = await this.generateEmbedding(chunk.content, apiKey);

          await KnowledgeChunk.create({
            documentId: document.id,
            userId,
            content: chunk.content,
            embedding,
            chunkIndex: chunk.chunkIndex,
            tokenCount: chunk.tokenCount,
            metadata: {},
          });

          if (embedding) successCount++;
        } catch (chunkErr) {
          logger.error({
            event: 'rag_chunk_error',
            documentId: document.id,
            chunkIndex: chunk.chunkIndex,
            message: chunkErr.message,
          });
          // Continue processing remaining chunks
        }
      }

      // Mark document as ready
      await document.update({
        status: 'ready',
        chunkCount: chunks.length,
      });

      logger.info({
        event: 'rag_ingest_complete',
        documentId: document.id,
        totalChunks: chunks.length,
        embeddedChunks: successCount,
      });

      eventBus.publish(EVENTS.DOCUMENT_INGESTED, {
        userId,
        documentId: document.id,
        title,
        sourceType,
        totalChunks: chunks.length,
      });

      return document;
    } catch (error) {
      logger.error({
        event: 'rag_ingest_error',
        userId,
        title,
        message: error.message,
      });

      // Attempt to mark the document as errored
      if (document) {
        try {
          await document.update({
            status: 'error',
            errorMessage: error.message.substring(0, 1000),
          });
        } catch (_) {
          // Best-effort; the outer error is more important.
        }
      }

      throw error;
    }
  }

  /**
   * Ingest a document from a URL.
   *
   * Fetches the page, strips boilerplate HTML elements, extracts readable
   * text, and delegates to {@link ingestDocument}.
   *
   * @param {string} userId - Owner user ID.
   * @param {string} url    - The URL to fetch and ingest.
   * @returns {Promise<Object>} The created KnowledgeDocument record.
   */
  async ingestURL(userId, url) {
    const axios = require('axios');
    const cheerio = require('cheerio');

    try {
      logger.info({ event: 'rag_url_fetch', userId, url });

      const { data: html } = await axios.get(url, {
        timeout: 15000,
        maxContentLength: 10 * 1024 * 1024, // 10 MB cap
        headers: { 'User-Agent': 'IGRIS-Agent/1.0' },
      });

      const $ = cheerio.load(html);

      // Remove non-content elements
      $('script, style, nav, footer, header, aside, iframe, noscript').remove();

      const title = $('title').text().trim() || new URL(url).hostname;
      const text = $('body').text().replace(/\s+/g, ' ').trim();

      if (!text) {
        throw new Error('No extractable text content found at the provided URL.');
      }

      return this.ingestDocument(userId, {
        title,
        content: text,
        sourceType: 'url',
        sourceUrl: url,
      });
    } catch (error) {
      logger.error({ event: 'rag_url_error', userId, url, message: error.message });
      throw error;
    }
  }

  /**
   * Ingest a PDF document from an in-memory buffer.
   *
   * @param {string} userId - Owner user ID.
   * @param {Buffer} buffer - PDF file contents.
   * @param {string} title  - Human-readable title for the document.
   * @returns {Promise<Object>} The created KnowledgeDocument record.
   */
  async ingestPDF(userId, buffer, title) {
    const pdfParse = require('pdf-parse');

    try {
      logger.info({ event: 'rag_pdf_parse', userId, title, bufferSize: buffer?.length });

      const data = await pdfParse(buffer);

      if (!data.text || data.text.trim().length === 0) {
        throw new Error('PDF contains no extractable text.');
      }

      return this.ingestDocument(userId, {
        title: title || 'Untitled PDF',
        content: data.text,
        sourceType: 'pdf',
        metadata: { pages: data.numpages },
      });
    } catch (error) {
      logger.error({ event: 'rag_pdf_error', userId, title, message: error.message });
      throw error;
    }
  }

  // -----------------------------------------------------------------------
  // Vector similarity search
  // -----------------------------------------------------------------------

  /**
   * Compute the cosine similarity between two vectors.
   *
   * @param {number[]} vecA - First vector.
   * @param {number[]} vecB - Second vector.
   * @returns {number} Cosine similarity in the range [-1, 1], or 0 for edge cases.
   */
  static cosineSimilarity(vecA, vecB) {
    if (
      !Array.isArray(vecA) ||
      !Array.isArray(vecB) ||
      vecA.length === 0 ||
      vecB.length === 0 ||
      vecA.length !== vecB.length
    ) {
      return 0;
    }

    let dotProduct = 0;
    let magA = 0;
    let magB = 0;

    for (let i = 0; i < vecA.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      magA += vecA[i] * vecA[i];
      magB += vecB[i] * vecB[i];
    }

    const magnitudeA = Math.sqrt(magA);
    const magnitudeB = Math.sqrt(magB);

    if (magnitudeA === 0 || magnitudeB === 0) return 0;

    return dotProduct / (magnitudeA * magnitudeB);
  }

  /**
   * Search the user's knowledge base for chunks similar to a query.
   *
   * Generates an embedding for the query, loads all of the user's embedded
   * chunks, computes cosine similarity, and returns the top-K results
   * enriched with document metadata.
   *
   * @param {string} userId         - Owner user ID.
   * @param {string} query          - Natural-language search query.
   * @param {number} [topK]         - Number of results to return (defaults to `this.topK`).
   * @returns {Promise<{ content: string, similarity: number, documentTitle: string, metadata: Object, documentId: string }[]>}
   */
  async search(userId, query, topK) {
    const { User, KnowledgeChunk, KnowledgeDocument } = require('../models');

    const k = topK || this.topK;

    try {
      // Resolve user's API key
      let apiKey = process.env.GEMINI_API_KEY_DEFAULT;
      const user = await User.findByPk(userId);
      if (user?.geminiApiKey) {
        apiKey = user.geminiApiKey;
      }

      // Check embedding cache first
      let queryEmbedding = this.embeddingCache.get(query);

      if (!queryEmbedding) {
        queryEmbedding = await this.generateEmbedding(query, apiKey);

        if (!queryEmbedding) {
          logger.error({ event: 'rag_search_no_embedding', userId, query });
          return [];
        }

        // Cache (bounded — evict oldest when over 500 entries)
        if (this.embeddingCache.size >= 500) {
          const firstKey = this.embeddingCache.keys().next().value;
          this.embeddingCache.delete(firstKey);
        }
        this.embeddingCache.set(query, queryEmbedding);
      }

      // Load all embedded chunks for this user
      const chunks = await KnowledgeChunk.findAll({
        where: { userId },
        include: [
          {
            model: KnowledgeDocument,
            as: 'document',
            attributes: ['id', 'title', 'sourceType', 'metadata'],
          },
        ],
      });

      // Score each chunk
      const scored = chunks
        .filter((c) => c.embedding && Array.isArray(c.embedding))
        .map((c) => ({
          content: c.content,
          similarity: RAGService.cosineSimilarity(queryEmbedding, c.embedding),
          documentTitle: c.document?.title || 'Unknown',
          metadata: c.document?.metadata || {},
          documentId: c.documentId,
        }));

      // Sort descending by similarity, take top-K
      scored.sort((a, b) => b.similarity - a.similarity);

      const results = scored.slice(0, k);

      logger.info({
        event: 'rag_search_complete',
        userId,
        query: query.substring(0, 100),
        totalChunks: chunks.length,
        resultsReturned: results.length,
        topSimilarity: results[0]?.similarity ?? null,
      });

      return results;
    } catch (error) {
      logger.error({ event: 'rag_search_error', userId, message: error.message });
      throw error;
    }
  }

  // -----------------------------------------------------------------------
  // Knowledge-base CRUD
  // -----------------------------------------------------------------------

  /**
   * Delete a document and all of its chunks.
   * Verifies ownership before deleting (IDOR protection).
   *
   * @param {string} userId     - Requesting user's ID.
   * @param {string} documentId - Document to delete.
   * @returns {Promise<{ deleted: boolean }>}
   */
  async deleteDocument(userId, documentId) {
    const { KnowledgeDocument, KnowledgeChunk } = require('../models');

    const document = await KnowledgeDocument.findOne({
      where: { id: documentId, userId },
    });

    if (!document) {
      throw new Error('Document not found or access denied.');
    }

    // Remove chunks first (child rows)
    await KnowledgeChunk.destroy({ where: { documentId } });
    await document.destroy();

    logger.info({ event: 'rag_doc_deleted', userId, documentId });

    eventBus.publish(EVENTS.DOCUMENT_DELETED, {
      userId,
      documentId
    });

    return { deleted: true };
  }

  /**
   * List all documents belonging to a user.
   * Omits full content for performance; returns lightweight metadata.
   *
   * @param {string} userId - Owner user ID.
   * @returns {Promise<Object[]>}
   */
  async listDocuments(userId) {
    const { KnowledgeDocument } = require('../models');

    const documents = await KnowledgeDocument.findAll({
      where: { userId },
      attributes: ['id', 'title', 'status', 'chunkCount', 'sourceType', 'sourceUrl', 'createdAt'],
      order: [['createdAt', 'DESC']],
    });

    return documents;
  }

  /**
   * Get aggregate stats for a user's knowledge base.
   *
   * @param {string} userId - Owner user ID.
   * @returns {Promise<{ documentCount: number, chunkCount: number, lastUpdated: Date|null }>}
   */
  async getStats(userId) {
    const { KnowledgeDocument, KnowledgeChunk } = require('../models');

    const [documentCount, chunkCount, lastDoc] = await Promise.all([
      KnowledgeDocument.count({ where: { userId } }),
      KnowledgeChunk.count({ where: { userId } }),
      KnowledgeDocument.findOne({
        where: { userId },
        order: [['updatedAt', 'DESC']],
        attributes: ['updatedAt'],
      }),
    ]);

    return {
      documentCount,
      chunkCount,
      lastUpdated: lastDoc?.updatedAt || null,
    };
  }

  // -----------------------------------------------------------------------
  // Formatting helpers
  // -----------------------------------------------------------------------

  /**
   * Format search results into a text block suitable for LLM context injection.
   *
   * @param {{ content: string, similarity: number, documentTitle: string }[]} results
   * @returns {string} Formatted string with separator lines.
   */
  formatSearchResults(results) {
    if (!results || results.length === 0) {
      return 'No relevant knowledge base results found.';
    }

    return results
      .map((r) => {
        const sim = r.similarity.toFixed(2);
        return (
          `--- Knowledge Base Result (similarity: ${sim}) ---\n` +
          `Source: ${r.documentTitle}\n\n` +
          `${r.content}\n` +
          `---`
        );
      })
      .join('\n\n');
  }
}

// ---------------------------------------------------------------------------
// Singleton export
// ---------------------------------------------------------------------------

module.exports = new RAGService();
