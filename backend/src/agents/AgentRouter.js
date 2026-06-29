const logger = require('../utils/logger');
const ResearchAgent = require('./ResearchAgent');
const CreativeAgent = require('./CreativeAgent');

/**
 * AgentRouter
 * Determines which specialized agent should handle a user request based on intent.
 */
class AgentRouter {
  constructor() {
    this.agents = new Map();
    this.registerAgent(new ResearchAgent());
    this.registerAgent(new CreativeAgent());
  }

  registerAgent(agent) {
    this.agents.set(agent.name, agent);
  }

  /**
   * Route the request to the appropriate agent
   */
  async route(message, userId, sessionId, context = {}) {
    // A real router would use a lightweight LLM call or embedding classifier
    // to determine intent. Here we use basic heuristics for demonstration.
    
    const lowerMsg = message.toLowerCase();
    let selectedAgentName = null;

    if (lowerMsg.includes('research') || lowerMsg.includes('search') || lowerMsg.includes('find facts') || lowerMsg.includes('who is')) {
      selectedAgentName = 'ResearchAgent';
    } else if (lowerMsg.includes('create') || lowerMsg.includes('draw') || lowerMsg.includes('write a poem') || lowerMsg.includes('generate image')) {
      selectedAgentName = 'CreativeAgent';
    }

    if (selectedAgentName && this.agents.has(selectedAgentName)) {
      logger.info(`[AgentRouter] Routing request to ${selectedAgentName}`);
      const agent = this.agents.get(selectedAgentName);
      return agent.execute(message, userId, sessionId, context);
    }

    // Default to a general pass-through to LangChain
    logger.info('[AgentRouter] No specialized agent matched. Using General fallback.');
    const langchainService = require('../services/langchainService');
    return langchainService.chat(message, userId, sessionId, context);
  }
}

module.exports = new AgentRouter();
