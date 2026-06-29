const logger = require('../utils/logger');
const GeminiProvider = require('./GeminiProvider');

/**
 * ProviderRegistry
 * Manages the available LLM providers, determines which one to use based on configuration,
 * and handles fallbacks if a provider is unavailable.
 */
class ProviderRegistry {
  constructor() {
    this.providers = new Map();
    this.primaryProviderName = process.env.PRIMARY_LLM_PROVIDER || 'Gemini';
    
    // Register default providers
    this.register(new GeminiProvider());
  }

  /**
   * Register a new LLM provider
   * @param {LLMProvider} providerInstance 
   */
  register(providerInstance) {
    this.providers.set(providerInstance.name, providerInstance);
    logger.debug(`[ProviderRegistry] Registered provider: ${providerInstance.name}`);
  }

  /**
   * Get the best available provider for Chat operations
   * @param {string} [preferredName] Optional specific provider name
   * @returns {LLMProvider}
   */
  getChatProvider(preferredName) {
    const name = preferredName || this.primaryProviderName;
    const provider = this.providers.get(name);

    if (provider && provider.isConfigured()) {
      return provider;
    }

    // Fallback logic
    logger.warn(`[ProviderRegistry] Primary provider ${name} not available. Seeking fallback...`);
    for (const [fallbackName, fallbackProvider] of this.providers.entries()) {
      if (fallbackProvider.isConfigured()) {
        logger.info(`[ProviderRegistry] Using fallback provider: ${fallbackName}`);
        return fallbackProvider;
      }
    }

    throw new Error('No configured LLM providers available');
  }

  /**
   * Get the best available provider for Embedding operations
   * @param {string} [preferredName] 
   * @returns {LLMProvider}
   */
  getEmbeddingProvider(preferredName) {
    // For now, same logic as chat. In the future, could split out specific logic
    // e.g. "always use OpenAI for embeddings, Gemini for chat"
    return this.getChatProvider(preferredName);
  }
}

// Export singleton
module.exports = new ProviderRegistry();
