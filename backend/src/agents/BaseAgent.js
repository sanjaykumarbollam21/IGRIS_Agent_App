const langchainService = require('../services/langchainService');

/**
 * BaseAgent
 * Abstract base class for specialized sub-agents.
 */
class BaseAgent {
  constructor(name, description) {
    this.name = name;
    this.description = description;
  }

  /**
   * Execute the agent's specialized task
   * @param {string} message 
   * @param {string} userId 
   * @param {string} sessionId 
   * @param {Object} context 
   */
  async execute(message, userId, sessionId, context) {
    throw new Error('execute() must be implemented by subclass');
  }

  /**
   * Helper to invoke the core LLM via the shared service
   * but potentially with a specialized system prompt override
   */
  async invokeLLM(message, userId, sessionId, contextOverride = {}) {
    // In a full implementation, we would pass the specialized context 
    // down to langchainService.chat(). For now, we delegate directly.
    return langchainService.chat(message, userId, sessionId, contextOverride);
  }
}

module.exports = BaseAgent;
