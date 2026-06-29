const { Sequelize, DataTypes } = require('sequelize');

const isSqlite = (process.env.DB_DIALECT || 'postgres') === 'sqlite';

/**
 * KnowledgeDocument model — tracks documents ingested into the RAG knowledge base.
 * Each document belongs to a user and is split into chunks for vector search.
 */
const KnowledgeDocument = (sequelize) => {
  return sequelize.define('KnowledgeDocument', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true,
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: { model: 'users', key: 'id' },
    },
    title: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    sourceType: {
      type: isSqlite ? DataTypes.STRING : DataTypes.ENUM('upload', 'url', 'text', 'pdf'),
      allowNull: false,
      ...(isSqlite ? { validate: { isIn: [['upload', 'url', 'text', 'pdf']] } } : {}),
    },
    sourceUrl: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    content: {
      // Raw extracted text content of the document
      type: DataTypes.TEXT,
      allowNull: false,
    },
    metadata: {
      type: isSqlite ? DataTypes.JSON : DataTypes.JSONB,
      defaultValue: {},
    },
    chunkCount: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    status: {
      type: isSqlite ? DataTypes.STRING : DataTypes.ENUM('processing', 'ready', 'error'),
      defaultValue: 'processing',
      ...(isSqlite ? { validate: { isIn: [['processing', 'ready', 'error']] } } : {}),
    },
    errorMessage: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    createdAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
    updatedAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
  }, {
    tableName: 'knowledge_documents',
    timestamps: true,
    indexes: [
      { fields: ['userId'] },
      { fields: ['status'] },
      { fields: ['userId', 'status'] },
      { fields: ['createdAt'] },
    ],
  });
};

module.exports = KnowledgeDocument;
