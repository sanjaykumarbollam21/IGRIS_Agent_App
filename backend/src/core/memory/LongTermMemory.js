const logger = require('../../utils/logger');

/**
 * LongTermMemory
 * Interfaces with the RAG Service to fetch semantic facts and user knowledge base items.
 */
class LongTermMemory {
  constructor(ragService) {
    this.ragService = ragService;
  }

  async retrieve(userId, query) {
    try {
      const results = await this.ragService.search(userId, query, 3);
      if (!results || results.length === 0) {
        return { facts: '' };
      }
      return { facts: this.ragService.formatSearchResults(results) };
    } catch (error) {
      logger.warn(`[LongTermMemory] Retrieval failed: ${error.message}`);
      return { facts: '' };
    }
  }

  /**
   * In a complete implementation, this would use a lightweight LLM call
   * to extract core facts ("User lives in London") from the conversation
   * and asynchronously save them to the KnowledgeBase.
   */
  async extractAndStoreFacts(userId, role, content) {
    // Stub for background fact extraction
    if (role === 'user' && content.toLowerCase().includes('remember that')) {
      logger.info(`[LongTermMemory] Explicit fact memory triggered for user ${userId}`);
      // this.ragService.ingestDocument(...)
    }
  }
}

module.exports = LongTermMemory;
