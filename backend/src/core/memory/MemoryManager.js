const ShortTermMemory = require('./ShortTermMemory');
const LongTermMemory = require('./LongTermMemory');
const logger = require('../../utils/logger');

/**
 * MemoryManager
 * Coordinates short-term (contextual) and long-term (semantic/RAG) memory
 * to provide a unified memory retrieval system for the agent.
 */
class MemoryManager {
  constructor(models, ragService, container) {
    this.shortTerm = new ShortTermMemory(models, container);
    this.longTerm = new LongTermMemory(ragService);
  }

  /**
   * Consolidate memory for a given prompt
   * Retrieves both recent conversational context and semantic long-term facts
   * @param {string} userId 
   * @param {string} sessionId 
   * @param {string} currentQuery 
   */
  async retrieveContext(userId, sessionId, currentQuery) {
    try {
      const [shortTermData, longTermData] = await Promise.all([
        this.shortTerm.retrieve(userId, sessionId),
        this.longTerm.retrieve(userId, currentQuery)
      ]);

      return {
        recentMessages: shortTermData.messages,
        recentToolUses: shortTermData.tools,
        semanticFacts: longTermData.facts
      };
    } catch (error) {
      logger.error(`[MemoryManager] Error retrieving context: ${error.message}`);
      return {
        recentMessages: [],
        recentToolUses: [],
        semanticFacts: ''
      };
    }
  }

  /**
   * Save a new memory
   * @param {string} userId 
   * @param {string} sessionId 
   * @param {string} role 
   * @param {string} content 
   */
  async store(userId, sessionId, role, content) {
    // Storing to DB is handled by ConversationRepository, 
    // but here we might trigger background summarization or fact extraction
    this.longTerm.extractAndStoreFacts(userId, role, content);
  }
}

module.exports = MemoryManager;
