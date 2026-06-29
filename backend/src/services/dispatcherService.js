const notificationService = require('./notificationService');
const logger = require('../utils/logger');
const { User } = require('../models');

/**
 * IGRIS Dispatcher Service
 * Routes notifications to the appropriate communication channels based on user preferences
 */
class DispatcherService {
  constructor() {
    this.channels = {
      socket: notificationService,
      telegram: null, // Will be initialized with Telegram Bot API
      whatsapp: null, // Will be initialized with Twilio
      email: null,    // Will be initialized with Nodemailer/SendGrid
    };
  }

  /**
   * Initialize channel providers
   * @param {Object} providers Configuration for external providers
   */
  async init(providers) {
    // This would be expanded to initialize real API clients
    logger.info('Dispatcher Service initializing channels...');
    this.channels.telegram = providers.telegram;
    this.channels.whatsapp = providers.whatsapp;
    this.channels.email = providers.email;
  }

  /**
   * Send a notification to a user via their preferred channels
   * @param {string} userId The target user ID
   * @param {string} event The event name
   * @param {Object} data The payload
   */
  async dispatch(userId, event, data) {
    try {
      const user = await User.findByPk(userId);
      if (!user) {
        logger.error(`Dispatch failed: User ${userId} not found`);
        return;
      }

      // 1. Always send real-time Socket.IO notification if available
      await this.channels.socket.notifyUser(userId, event, data);

      // 2. Route to external channels based on user preferences
      const preferences = user.notificationPreferences || {};

      if (preferences.whatsapp && this.channels.whatsapp) {
        await this._sendWhatsApp(user, event, data);
      }

      if (preferences.telegram && this.channels.telegram) {
        await this._sendTelegram(user, event, data);
      }

      if (preferences.email && this.channels.email) {
        await this._sendEmail(user, event, data);
      }

    } catch (error) {
      logger.error({ event: 'dispatch_error', message: error.message, userId });
    }
  }

  async _sendWhatsApp(user, event, data) {
    logger.info(`[Dispatcher] Sending WhatsApp to ${user.phoneNumber} for event ${event}`);
    // Integration with Twilio API would go here
  }

  async _sendTelegram(user, event, data) {
    logger.info(`[Dispatcher] Sending Telegram to ${user.telegramId} for event ${event}`);
    // Integration with Telegram Bot API would go here
  }

  async _sendEmail(user, event, data) {
    logger.info(`[Dispatcher] Sending Email to ${user.email} for event ${event}`);
    // Integration with Email API would go here
  }
}

module.exports = new DispatcherService();
