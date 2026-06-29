/**
 * Abstract Base Class for LLM Providers
 * Implements the Strategy Pattern, ensuring all AI providers expose a consistent interface.
 */
class LLMProvider {
  constructor(name) {
    if (this.constructor === LLMProvider) {
      throw new Error("Abstract classes can't be instantiated.");
    }
    this.name = name;
  }

  /**
   * Check if the provider has the necessary configuration (e.g., API keys)
   * @returns {boolean}
   */
  isConfigured() {
    throw new Error("Method 'isConfigured()' must be implemented.");
  }

  /**
   * Get the primary chat model for this provider (LangChain BaseChatModel)
   * @param {Object} options Configuration options (temperature, model name, etc.)
   * @returns {Object} A LangChain-compatible model instance
   */
  getChatModel(options = {}) {
    throw new Error("Method 'getChatModel()' must be implemented.");
  }

  /**
   * Generate an embedding vector for a piece of text
   * @param {string} text 
   * @returns {Promise<number[]>} Float array embedding
   */
  async generateEmbedding(text) {
    throw new Error("Method 'generateEmbedding()' must be implemented.");
  }

  /**
   * Return metadata about the provider's capabilities
   * @returns {Object} { supportsImages, supportsTools, defaultModel }
   */
  getCapabilities() {
    return {
      supportsImages: false,
      supportsTools: false,
      defaultModel: 'unknown'
    };
  }
}

module.exports = LLMProvider;
