const { Sequelize, DataTypes } = require('sequelize');

/**
 * Automation model — stores user-created automations.
 * Trigger types: time_based, event_based
 * Action types: send_message, make_call, web_search, set_reminder, notify, run_ai_task
 */
const Automation = (sequelize) => {
  return sequelize.define('Automation', {
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
    name: {
      type: DataTypes.STRING,
      allowNull: false,
    },
    description: {
      type: DataTypes.TEXT,
      allowNull: true,
    },
    isActive: {
      type: DataTypes.BOOLEAN,
      defaultValue: true,
    },
    // Trigger configuration
    triggerType: {
      type: DataTypes.ENUM('time_based', 'event_based', 'manual'),
      allowNull: false,
    },
    triggerConfig: {
      // time_based: { cronExpr, timezone, runOnce }
      // event_based: { event: 'wifi_connected'|'dnd_on'|'app_opened', appName? }
      // manual: {}
      type: DataTypes.JSONB,
      defaultValue: {},
    },
    // Action configuration
    actionType: {
      type: DataTypes.ENUM(
        'send_message', 'make_call', 'web_search',
        'set_reminder', 'notify', 'run_ai_task',
        'send_email', 'busy_mode_on', 'busy_mode_off'
      ),
      allowNull: false,
    },
    actionConfig: {
      // send_message: { recipient, message, platform }
      // make_call: { contact }
      // set_reminder: { title, time }
      // run_ai_task: { prompt }
      type: DataTypes.JSONB,
      defaultValue: {},
    },
    // Execution state
    lastRunAt: { type: DataTypes.DATE, allowNull: true },
    nextRunAt: { type: DataTypes.DATE, allowNull: true },
    runCount: { type: DataTypes.INTEGER, defaultValue: 0 },
    lastResult: { type: DataTypes.TEXT, allowNull: true },
    createdAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
    updatedAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
  }, {
    tableName: 'automations',
    timestamps: true,
    indexes: [
      { fields: ['userId'] },
      { fields: ['isActive', 'nextRunAt'] },
    ],
  });
};

module.exports = Automation;
