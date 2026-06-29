const { Sequelize, DataTypes } = require('sequelize');

const isSqlite = (process.env.DB_DIALECT || 'postgres') === 'sqlite';

const ToolUsage = (sequelize) => {
  return sequelize.define('ToolUsage', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'users',
        key: 'id'
      }
    },
    toolName: {
      type: DataTypes.STRING,
      allowNull: false
    },
    action: {
      type: DataTypes.STRING,
      allowNull: false
    },
    parameters: {
      type: isSqlite ? DataTypes.JSON : DataTypes.JSONB,
      allowNull: true,
      defaultValue: {}
    },
    result: {
      type: isSqlite ? DataTypes.JSON : DataTypes.JSONB,
      allowNull: true
    },
    status: {
      type: isSqlite ? DataTypes.STRING : DataTypes.ENUM('success', 'error', 'pending'),
      defaultValue: 'success',
      ...(isSqlite ? { validate: { isIn: [['success', 'error', 'pending']] } } : {})
    },
    errorMessage: {
      type: DataTypes.TEXT,
      allowNull: true
    },
    executionTimeMs: {
      type: DataTypes.INTEGER,
      allowNull: true
    },
    ipAddress: {
      type: DataTypes.STRING,
      allowNull: true
    },
    userAgent: {
      type: DataTypes.TEXT,
      allowNull: true
    },
    createdAt: {
      type: DataTypes.DATE,
      defaultValue: Sequelize.NOW
    }
  }, {
    tableName: 'tool_usages',
    timestamps: true,
    indexes: [
      {
        name: 'tool_usage_user_idx',
        fields: ['userId']
      },
      {
        name: 'tool_usage_tool_action_idx',
        fields: ['toolName', 'action']
      },
      {
        name: 'tool_usage_created_at_idx',
        fields: ['createdAt']
      }
    ]
  });
};

module.exports = ToolUsage;
