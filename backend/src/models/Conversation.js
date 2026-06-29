const { Sequelize, DataTypes } = require('sequelize');

/**
 * Conversation model — stores IGRIS chat history for long-term memory.
 * Each row is one message turn (user or assistant).
 */
const Conversation = (sequelize) => {
  return sequelize.define('Conversation', {
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
    sessionId: {
      // Groups messages into one conversation session
      type: DataTypes.STRING,
      allowNull: false,
    },
    role: {
      type: DataTypes.ENUM('user', 'model'),
      allowNull: false,
    },
    content: {
      // Text content of the message
      type: DataTypes.TEXT,
      allowNull: false,
    },
    metadata: {
      // Extra info: toolCalls, imageUrls, attachments, etc.
      type: DataTypes.JSONB,
      defaultValue: {},
    },
    tokenCount: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    createdAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
    updatedAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
  }, {
    tableName: 'conversations',
    timestamps: true,
    indexes: [
      { fields: ['userId'] },
      { fields: ['sessionId'] },
      { fields: ['userId', 'sessionId'] },
      { fields: ['createdAt'] },
    ],
  });
};

module.exports = Conversation;
