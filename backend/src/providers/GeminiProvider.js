const { ChatGoogleGenerativeAI } = require('@langchain/google-genai');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const LLMProvider = require('./LLMProvider');
const logger = require('../utils/logger');

class GeminiProvider extends LLMProvider {
  constructor() {
    super('Gemini');
    this.defaultModel = 'gemini-2.0-flash';
    this.embeddingModel = 'text-embedding-004';
  }

  isConfigured() {
    return !!process.env.GEMINI_API_KEY_DEFAULT;
  }

  getCapabilities() {
    return {
      supportsImages: true,
      supportsTools: true,
      defaultModel: this.defaultModel
    };
  }

  getChatModel(options = {}) {
    if (!this.isConfigured()) {
      throw new Error('Gemini API key is not configured');
    }

    return new ChatGoogleGenerativeAI({
      apiKey: options.apiKey || process.env.GEMINI_API_KEY_DEFAULT,
      modelName: options.modelName || this.defaultModel,
      temperature: options.temperature || 0.7,
      maxOutputTokens: options.maxTokens || 2048,
    });
  }

  async generateEmbedding(text, options = {}) {
    if (!this.isConfigured()) {
      throw new Error('Gemini API key is not configured');
    }

    try {
      const genAI = new GoogleGenerativeAI(options.apiKey || process.env.GEMINI_API_KEY_DEFAULT);
      const model = genAI.getGenerativeModel({ model: this.embeddingModel });
      const result = await model.embedContent(text);
      return result.embedding.values;
    } catch (error) {
      logger.error(`[GeminiProvider] Embedding error: ${error.message}`);
      throw error;
    }
  }
}

module.exports = GeminiProvider;
