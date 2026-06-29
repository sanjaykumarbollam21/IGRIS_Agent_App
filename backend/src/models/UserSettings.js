const { Sequelize, DataTypes } = require('sequelize');

/**
 * UserSettings model — stores per-user preferences and state.
 * Used for Busy Mode, auto-reply config, notification preferences.
 */
const UserSettings = (sequelize) => {
  return sequelize.define('UserSettings', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true,
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      unique: true,
      references: { model: 'users', key: 'id' },
    },
    // Busy Mode
    busyModeEnabled: { type: DataTypes.BOOLEAN, defaultValue: false },
    busyModeAutoReply: {
      type: DataTypes.TEXT,
      defaultValue: "Sanjay is Busy",
    },
    busyModeRejectCalls: { type: DataTypes.BOOLEAN, defaultValue: false },
    busyModeNotifyTelegram: { type: DataTypes.BOOLEAN, defaultValue: true },

    // Notification preferences
    dailyDigestEnabled: { type: DataTypes.BOOLEAN, defaultValue: true },
    weeklyTipEnabled: { type: DataTypes.BOOLEAN, defaultValue: true },

    // Agent personality
    agentName: { type: DataTypes.STRING, defaultValue: 'IGRIS' },
    agentTone: {
      type: DataTypes.ENUM('professional', 'casual', 'concise', 'detailed'),
      defaultValue: 'professional',
    },

    // Voice settings
    voiceId: { type: DataTypes.STRING, allowNull: true },
    voiceLanguage: { type: DataTypes.STRING, defaultValue: 'en-US' },
    voiceStyle: { type: DataTypes.STRING, allowNull: true },
    voiceEnabled: { type: DataTypes.BOOLEAN, defaultValue: true },

    // Gmail OAuth token (encrypted in production)
    gmailAccessToken: { type: DataTypes.TEXT, allowNull: true },
    gmailRefreshToken: { type: DataTypes.TEXT, allowNull: true },
    gmailTokenExpiry: { type: DataTypes.DATE, allowNull: true },
    gmailEmail: { type: DataTypes.STRING, allowNull: true },

    // Google Calendar OAuth token
    calendarAccessToken: { type: DataTypes.TEXT, allowNull: true },
    calendarRefreshToken: { type: DataTypes.TEXT, allowNull: true },
    calendarTokenExpiry: { type: DataTypes.DATE, allowNull: true },

    createdAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
    updatedAt: { type: DataTypes.DATE, defaultValue: Sequelize.NOW },
  }, {
    tableName: 'user_settings',
    timestamps: true,
  });
};

module.exports = UserSettings;
