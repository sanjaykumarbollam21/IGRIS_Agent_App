const BaseAgent = require('./BaseAgent');

class ResearchAgent extends BaseAgent {
  constructor() {
    super('ResearchAgent', 'Handles deep web research, factual queries, and knowledge base lookups.');
  }

  async execute(message, userId, sessionId, context) {
    // The ResearchAgent might automatically append instructions to cite sources
    const enhancedMessage = message + '\n\n[System Note: Please ensure to thoroughly search the web and cite your sources with URLs.]';
    
    return this.invokeLLM(enhancedMessage, userId, sessionId, context);
  }
}

module.exports = ResearchAgent;
