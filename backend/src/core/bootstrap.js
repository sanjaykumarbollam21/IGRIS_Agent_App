const container = require('./container');
const logger = require('../utils/logger');
const eventBus = require('./eventBus');
const pluginManager = require('./pluginManager');
const models = require('../models');

// Repositories
const UserRepository = require('../repositories/UserRepository');
const KnowledgeRepository = require('../repositories/KnowledgeRepository');
const ConversationRepository = require('../repositories/ConversationRepository');
const ToolUsageRepository = require('../repositories/ToolUsageRepository');

// Import existing legacy singletons
const ragService = require('../services/ragService');
const MemoryManager = require('./memory/MemoryManager');
const contextService = require('../services/contextService');
const toolExecutionService = require('../services/toolExecutionService');
const cacheService = require('../services/cacheService');
const notificationService = require('../services/notificationService');
const dispatcherService = require('../services/dispatcherService');
const langchainService = require('../services/langchainService');

// Guardrails
const GuardrailPipeline = require('./guardrails/GuardrailPipeline');
const PIIGuard = require('./guardrails/PIIGuard');
const InjectionGuard = require('./guardrails/InjectionGuard');

/**
 * Bootstrap the Dependency Injection Container
 * Registers all services, repositories, and configurations.
 */
async function bootstrap() {
  logger.info('[Bootstrap] Initializing application context...');

  // 1. Register Core Configurations
  container.registerValue('config', {
    env: process.env.NODE_ENV || 'development',
    port: process.env.PORT || 5000,
    redisUrl: process.env.REDIS_URL,
    geminiKey: process.env.GEMINI_API_KEY_DEFAULT,
  });

  // 2. Register Existing Legacy Services (as pre-instantiated values)
  // As we refactor to classes, these will change to container.register(..., factory)
  container.registerValue('logger', logger);
  container.registerValue('cacheService', cacheService);
  container.registerValue('notificationService', notificationService);
  container.registerValue('dispatcherService', dispatcherService);
  container.registerValue('eventBus', eventBus);
  
  // Domain Services
  container.registerValue('ragService', ragService);
  container.registerValue('contextService', contextService);
  container.registerValue('toolExecutionService', toolExecutionService);
  container.registerValue('langchainService', langchainService);

  // Repositories
  container.registerValue('userRepository', new UserRepository(models));
  container.registerValue('knowledgeRepository', new KnowledgeRepository(models));
  container.registerValue('conversationRepository', new ConversationRepository(models));
  container.registerValue('toolUsageRepository', new ToolUsageRepository(models));

  // Memory Architecture
  container.registerValue('memoryManager', new MemoryManager(models, ragService, container));

  // Guardrails
  const guardrails = new GuardrailPipeline()
    .addGuard(new InjectionGuard())
    .addGuard(new PIIGuard());
  container.registerValue('guardrails', guardrails);

  // Plugins
  container.registerValue('pluginManager', pluginManager);
  await pluginManager.loadAll();

  logger.info('[Bootstrap] Dependency injection container ready.');
  return container;
}

module.exports = { bootstrap, container };
