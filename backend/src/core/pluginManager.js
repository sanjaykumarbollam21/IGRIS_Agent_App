const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');
const container = require('./container');

/**
 * PluginManager
 * Discovers and loads external agent plugins.
 * Plugins can register tools, routes, or event listeners.
 */
class PluginManager {
  constructor() {
    this.plugins = new Map();
    this.pluginsDir = path.join(__dirname, '../plugins');
  }

  /**
   * Load all plugins from the plugins directory
   */
  async loadAll() {
    if (!fs.existsSync(this.pluginsDir)) {
      fs.mkdirSync(this.pluginsDir, { recursive: true });
      logger.info('[PluginManager] Created plugins directory');
      return;
    }

    const entries = fs.readdirSync(this.pluginsDir, { withFileTypes: true });
    
    for (const entry of entries) {
      if (entry.isDirectory()) {
        await this.loadPlugin(entry.name);
      }
    }
    
    logger.info(`[PluginManager] Loaded ${this.plugins.size} plugins`);
  }

  /**
   * Load a specific plugin by folder name
   * @param {string} pluginName 
   */
  async loadPlugin(pluginName) {
    try {
      const pluginPath = path.join(this.pluginsDir, pluginName, 'index.js');
      
      if (!fs.existsSync(pluginPath)) {
        logger.warn(`[PluginManager] Plugin ${pluginName} missing index.js. Skipping.`);
        return;
      }

      const pluginModule = require(pluginPath);
      
      // Validate plugin structure
      if (!pluginModule.name || !pluginModule.register) {
        throw new Error('Plugin must export "name" and "register" function');
      }

      // Build context to pass to the plugin
      const toolExecutionService = container.resolve('toolExecutionService');
      const eventBus = container.resolve('eventBus');
      
      const context = {
        logger,
        eventBus,
        container,
        registerTool: (toolDef) => {
          if (toolExecutionService.registerExternalTool) {
            toolExecutionService.registerExternalTool(toolDef);
          }
        }
      };

      // Register the plugin
      await pluginModule.register(context);
      
      this.plugins.set(pluginModule.name, {
        name: pluginModule.name,
        version: pluginModule.version || '1.0.0',
        description: pluginModule.description || '',
        loadedAt: new Date()
      });

      logger.info(`[PluginManager] Successfully loaded plugin: ${pluginModule.name} v${pluginModule.version || '1.0.0'}`);

    } catch (error) {
      logger.error(`[PluginManager] Failed to load plugin ${pluginName}: ${error.message}`);
    }
  }

  getLoadedPlugins() {
    return Array.from(this.plugins.values());
  }
}

// Export singleton
module.exports = new PluginManager();
