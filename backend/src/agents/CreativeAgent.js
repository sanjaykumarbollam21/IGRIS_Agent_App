const BaseAgent = require('./BaseAgent');

class CreativeAgent extends BaseAgent {
  constructor() {
    super('CreativeAgent', 'Handles creative writing, brainstorming, and image generation.');
  }

  async execute(message, userId, sessionId, context) {
    // The CreativeAgent adopts a more vibrant persona
    const enhancedMessage = message + '\n\n[System Note: Please use a highly creative, enthusiastic tone and feel free to use image generation tools if appropriate.]';
    
    return this.invokeLLM(enhancedMessage, userId, sessionId, context);
  }
}

module.exports = CreativeAgent;
