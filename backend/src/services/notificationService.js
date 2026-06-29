// No external dependencies needed

/**
 * IGRIS Notification Service
 * Handles real-time event dispatching via Socket.IO
 */
class NotificationService {
  constructor() {
    this.io = null;
  }

  /**
   * Initialize the service with the server's IO instance
   * @param {Server} io The Socket.IO server instance
   */
  init(io) {
    this.io = io;
    console.log('Notification Service initialized');
  }

  /**
   * Notify a specific user about an event
   * @param {string} userId The target user ID
   * @param {string} event The event name (e.g., 'attendance_marked')
   * @param {Object} data The payload to send
   */
  async notifyUser(userId, event, data) {
    if (!this.io) {
      console.error('Notification Service not initialized');
      return;
    }

    // We assume users join a room named after their userId upon connection
    this.io.to(userId).emit(event, {
      ...data,
      timestamp: new Date().toISOString()
    });

    console.log(`[Notification] Dispatched ${event} to user ${userId}`);
  }

  /**
   * Broadcast a system-wide notification
   * @param {string} event The event name
   * @param {Object} data The payload
   */
  broadcast(event, data) {
    if (this.io) {
      this.io.emit(event, { ...data, timestamp: new Date().toISOString() });
    }
  }
}

module.exports = new NotificationService();
