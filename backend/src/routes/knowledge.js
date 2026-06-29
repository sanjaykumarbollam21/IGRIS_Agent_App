const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const multer = require('multer');
const logger = require('../utils/logger');
const { validate, schemas } = require('../middleware/validate');
const { uploadLimiter, aiLimiter } = require('../middleware/rateLimiter');
const path = require('path');

// Configure multer for PDF uploads (Rule #8 — file upload security)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE) || 5 * 1024 * 1024, // 5MB default
  },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const allowedMimes = ['application/pdf', 'text/plain', 'text/markdown'];
    const allowedExts = ['.pdf', '.txt', '.md', '.markdown'];
    if (allowedMimes.includes(file.mimetype) && allowedExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`Unsupported file type: ${file.mimetype} (${ext}). Allowed: PDF, TXT, Markdown`));
    }
  },
});

/**
 * @route   POST /api/knowledge/documents
 * @desc    Ingest a document into the user's knowledge base
 * @access  Private
 * @body    { title, content, sourceType, sourceUrl } OR multipart/form-data with file
 */
router.post('/documents', authenticateToken, uploadLimiter, upload.single('file'), async (req, res) => {
  try {
    const ragService = require('../services/ragService');

    // Handle direct text/URL ingestion validation if no file uploaded
    if (!req.file) {
      const parsed = schemas.knowledge.documents.safeParse(req.body);
      if (!parsed.success) {
        const issues = parsed.error.issues || parsed.error.errors || [];
        return res.status(400).json({
          error: 'Validation Error',
          details: issues.map(e => ({ path: e.path[0], message: e.message }))
        });
      }
      req.body = parsed.data;
    }

    // Handle file upload (PDF, TXT)
    if (req.file) {
      const title = req.body.title || req.file.originalname;

      if (req.file.mimetype === 'application/pdf') {
        const doc = await ragService.ingestPDF(req.userId, req.file.buffer, title);
        return res.status(201).json({ success: true, document: formatDocResponse(doc) });
      } else {
        // Plain text / markdown
        const content = req.file.buffer.toString('utf-8');
        const doc = await ragService.ingestDocument(req.userId, {
          title,
          content,
          sourceType: 'upload',
        });
        return res.status(201).json({ success: true, document: formatDocResponse(doc) });
      }
    }

    // Handle URL ingestion
    if (req.body.sourceUrl) {
      const doc = await ragService.ingestURL(req.userId, req.body.sourceUrl);
      return res.status(201).json({ success: true, document: formatDocResponse(doc) });
    }

    // Handle direct text ingestion
    const { title, content, sourceType = 'text' } = req.body;
    if (!title || !content) {
      return res.status(400).json({ error: 'Title and content are required (or provide a file/URL)' });
    }

    const doc = await ragService.ingestDocument(req.userId, {
      title,
      content,
      sourceType,
    });

    res.status(201).json({ success: true, document: formatDocResponse(doc) });
  } catch (error) {
    logger.error({ event: 'knowledge_ingest_error', message: error.message, userId: req.userId });
    res.status(500).json({ error: 'Document ingestion failed', message: error.message });
  }
});

/**
 * @route   GET /api/knowledge/documents
 * @desc    List all documents in the user's knowledge base
 * @access  Private
 */
router.get('/documents', authenticateToken, async (req, res) => {
  try {
    const ragService = require('../services/ragService');
    const documents = await ragService.listDocuments(req.userId);
    res.json({ success: true, documents });
  } catch (error) {
    logger.error({ event: 'knowledge_list_error', message: error.message });
    res.status(500).json({ error: 'Failed to list documents' });
  }
});

/**
 * @route   GET /api/knowledge/documents/:id
 * @desc    Get a specific document's details
 * @access  Private
 */
router.get('/documents/:id', authenticateToken, async (req, res) => {
  try {
    const { KnowledgeDocument } = require('../models');
    const doc = await KnowledgeDocument.findOne({
      where: { id: req.params.id, userId: req.userId }, // IDOR protection
    });

    if (!doc) {
      return res.status(404).json({ error: 'Document not found' });
    }

    res.json({ success: true, document: doc });
  } catch (error) {
    logger.error({ event: 'knowledge_get_error', message: error.message });
    res.status(500).json({ error: 'Failed to get document' });
  }
});

/**
 * @route   DELETE /api/knowledge/documents/:id
 * @desc    Delete a document and its chunks
 * @access  Private
 */
router.delete('/documents/:id', authenticateToken, async (req, res) => {
  try {
    const ragService = require('../services/ragService');
    // IDOR protection: deleteDocument verifies ownership
    const result = await ragService.deleteDocument(req.userId, req.params.id);
    res.json({ success: true, ...result });
  } catch (error) {
    logger.error({ event: 'knowledge_delete_error', message: error.message });
    res.status(500).json({ error: 'Failed to delete document' });
  }
});

/**
 * @route   POST /api/knowledge/search
 * @desc    Search the user's knowledge base
 * @access  Private
 */
router.post('/search', authenticateToken, aiLimiter, validate(schemas.knowledge.search), async (req, res) => {
  try {
    const { query, topK } = req.body;

    const ragService = require('../services/ragService');
    const results = await ragService.search(req.userId, query, topK);

    res.json({
      success: true,
      query,
      results: results.map(r => ({
        content: r.content,
        similarity: Math.round(r.similarity * 1000) / 1000,
        documentTitle: r.documentTitle,
        documentId: r.documentId,
      })),
    });
  } catch (error) {
    logger.error({ event: 'knowledge_search_error', message: error.message });
    res.status(500).json({ error: 'Knowledge search failed' });
  }
});

/**
 * @route   GET /api/knowledge/stats
 * @desc    Get knowledge base statistics
 * @access  Private
 */
router.get('/stats', authenticateToken, async (req, res) => {
  try {
    const ragService = require('../services/ragService');
    const stats = await ragService.getStats(req.userId);
    res.json({ success: true, ...stats });
  } catch (error) {
    logger.error({ event: 'knowledge_stats_error', message: error.message });
    res.status(500).json({ error: 'Failed to get stats' });
  }
});

/**
 * Format document for API response (exclude sensitive/large fields)
 */
function formatDocResponse(doc) {
  if (!doc) return null;
  const data = doc.toJSON ? doc.toJSON() : doc;
  return {
    id: data.id,
    title: data.title,
    sourceType: data.sourceType,
    sourceUrl: data.sourceUrl,
    status: data.status,
    chunkCount: data.chunkCount,
    metadata: data.metadata,
    createdAt: data.createdAt,
  };
}

module.exports = router;
