const { Sequelize, DataTypes } = require('sequelize');

const isSqlite = (process.env.DB_DIALECT || 'postgres') === 'sqlite';

/**
 * KnowledgeChunk model — stores individual text chunks with vector embeddings.
 * Used by the RAG service for similarity search.
 */
const KnowledgeChunk = (sequelize) => {
  return sequelize.define('KnowledgeChunk', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true,
    },
    documentId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: { model: 'knowledge_documents', key: 'id' },
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: { model: 'users', key: 'id' },
    },
    content: {
      // The text content of this chunk
      type: DataTypes.TEXT,
      allowNull: false,
    },
    embedding: {
      // Vector embedding stored as JSON array of floats
      // In production with pgvector, this would be a VECTOR type
      type: isSqlite ? DataTypes.JSON : DataTypes.JSONB,
      allowNull: true,
    },
    chunkIndex: {
      // Position of this chunk within the original document
      type: DataTypes.INTEGER,
      allowNull: false,
      defaultValue: 0,
    },
    metadata: {
      // Additional context: section title, page number, etc.
      type: isSqlite ? DataTypes.JSON : DataTypes.JSONB,
      defaultValue: {},
    },
    tokenCount: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    createdAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
  }, {
    tableName: 'knowledge_chunks',
    timestamps: false,
    indexes: [
      { fields: ['documentId'] },
      { fields: ['userId'] },
      { fields: ['userId', 'documentId'] },
    ],
  });
};

module.exports = KnowledgeChunk;
