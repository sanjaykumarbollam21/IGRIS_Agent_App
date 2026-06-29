const fs = require('fs');
const path = require('path');
const Sequelize = require('sequelize');
const basename = path.basename(__filename);
const env = process.env.NODE_ENV || 'development';
const config = require('../config/database')[env];
const db = {};

let sequelize;
if (config.use_env_variable) {
  sequelize = new Sequelize(process.env[config.use_env_variable], config);
} else {
  sequelize = new Sequelize(config.database, config.username, config.password, config);
}

// 1. Import model functions and initialize them
fs
  .readdirSync(__dirname)
  .filter(file => {
    return (
      file.indexOf('.') !== 0 &&
      file !== basename &&
      file.slice(-3) === '.js' &&
      file !== 'index.js'
    );
  })
  .forEach(file => {
    const modelDef = require(path.join(__dirname, file));
    const modelName = path.basename(file, '.js');
    if (typeof modelDef === 'function') {
      db[modelName] = modelDef(sequelize);
    } else {
      db[modelName] = modelDef;
    }
  });

// 2. Define associations using the initialized models
Object.keys(db).forEach(modelName => {
  if (db[modelName].associate) {
    db[modelName].associate(db);
  }
});

// ToolUsage associations
if (db.User && db.ToolUsage) {
  db.ToolUsage.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.ToolUsage, { foreignKey: 'userId', as: 'toolUsageRecords' });
}

// Automation associations
if (db.User && db.Automation) {
  db.Automation.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.Automation, { foreignKey: 'userId', as: 'automations' });
}

// UserSettings associations
if (db.User && db.UserSettings) {
  db.UserSettings.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasOne(db.UserSettings, { foreignKey: 'userId', as: 'settings' });
}

// Conversation associations
if (db.User && db.Conversation) {
  db.Conversation.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.Conversation, { foreignKey: 'userId', as: 'conversations' });
}

// KnowledgeDocument associations (RAG)
if (db.User && db.KnowledgeDocument) {
  db.KnowledgeDocument.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.KnowledgeDocument, { foreignKey: 'userId', as: 'knowledgeDocuments' });
}

// KnowledgeChunk associations (RAG)
if (db.KnowledgeDocument && db.KnowledgeChunk) {
  db.KnowledgeChunk.belongsTo(db.KnowledgeDocument, { foreignKey: 'documentId', as: 'document' });
  db.KnowledgeDocument.hasMany(db.KnowledgeChunk, { foreignKey: 'documentId', as: 'chunks' });
}
if (db.User && db.KnowledgeChunk) {
  db.KnowledgeChunk.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.KnowledgeChunk, { foreignKey: 'userId', as: 'knowledgeChunks' });
}

// WorkflowExecution associations
if (db.User && db.WorkflowExecution) {
  db.WorkflowExecution.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.WorkflowExecution, { foreignKey: 'userId', as: 'workflowExecutions' });
}

// CallSummary associations
if (db.User && db.CallSummary) {
  db.CallSummary.belongsTo(db.User, { foreignKey: 'userId', as: 'user' });
  db.User.hasMany(db.CallSummary, { foreignKey: 'userId', as: 'callSummaries' });
}

db.sequelize = sequelize;
db.Sequelize = Sequelize;

module.exports = db;
