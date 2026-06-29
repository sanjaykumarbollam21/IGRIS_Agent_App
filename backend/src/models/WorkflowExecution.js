const { Sequelize, DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const WorkflowExecution = sequelize.define('WorkflowExecution', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true,
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
    },
    workflowName: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    status: {
      type: DataTypes.ENUM('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'COMPENSATED'),
      defaultValue: 'PENDING',
    },
    currentStep: {
      type: DataTypes.INTEGER,
      defaultValue: 0,
    },
    contextData: {
      type: DataTypes.JSON,
      defaultValue: {},
    },
    errorData: {
      type: DataTypes.TEXT,
      allowNull: true,
    }
  });

  return WorkflowExecution;
};
