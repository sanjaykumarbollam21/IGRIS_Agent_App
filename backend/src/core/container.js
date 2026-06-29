const logger = require('../utils/logger');

/**
 * Lightweight Dependency Injection Container
 * Manages service registration, resolution, and lifecycles.
 */
class DIContainer {
  constructor() {
    this.services = new Map();
    this.instances = new Map();
    this.values = new Map();
  }

  /**
   * Register a service factory
   * @param {string} name - Service identifier
   * @param {Function} factory - Factory function that receives the container and returns the service
   * @param {Object} options - Configuration options
   * @param {boolean} [options.singleton=true] - If true, the same instance is returned every time
   */
  register(name, factory, { singleton = true } = {}) {
    this.services.set(name, { factory, singleton });
    logger.debug(`[DI] Registered service factory: ${name}`);
    return this;
  }

  /**
   * Register a static value or pre-instantiated object
   * @param {string} name - Value identifier
   * @param {any} value - The value to store
   */
  registerValue(name, value) {
    this.values.set(name, value);
    logger.debug(`[DI] Registered static value: ${name}`);
    return this;
  }

  /**
   * Resolve a service or value by name
   * @param {string} name - The identifier to resolve
   * @returns {any} The resolved service instance or value
   * @throws {Error} If the dependency is not found
   */
  resolve(name) {
    // 1. Check if it's a static value
    if (this.values.has(name)) {
      return this.values.get(name);
    }

    // 2. Check if it's a registered service factory
    if (this.services.has(name)) {
      const def = this.services.get(name);

      // If singleton and already instantiated, return the instance
      if (def.singleton && this.instances.has(name)) {
        return this.instances.get(name);
      }

      // Instantiate using the factory, passing the container itself
      // so the factory can resolve its own dependencies
      try {
        logger.debug(`[DI] Instantiating service: ${name}`);
        const instance = def.factory(this);
        
        // Cache if singleton
        if (def.singleton) {
          this.instances.set(name, instance);
        }
        
        return instance;
      } catch (error) {
        logger.error(`[DI] Error instantiating service ${name}: ${error.message}`);
        throw new Error(`Failed to resolve dependency '${name}': ${error.message}`);
      }
    }

    throw new Error(`Dependency not found in container: ${name}`);
  }

  /**
   * Clear all instances (useful for testing)
   */
  clearInstances() {
    this.instances.clear();
  }
}

// Export as singleton to serve as the global container
module.exports = new DIContainer();
