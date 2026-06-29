const { EventEmitter } = require('events');
const logger = require('../utils/logger');

/**
 * EventBus
 * A robust, asynchronous publish-subscribe event bus built on top of Node's EventEmitter.
 * Decouples services by allowing them to communicate via events rather than direct method calls.
 */
class EventBus extends EventEmitter {
  constructor() {
    super();
    // Allow more listeners than the default (10) since this is an application-wide bus
    this.setMaxListeners(50);
    
    // Dead letter queue for events that threw errors in their handlers
    this.deadLetters = [];
    
    // Circular buffer of the last 100 events for debugging/telemetry
    this.history = [];
    this.historyLimit = 100;
  }

  /**
   * Publish an event asynchronously to all registered listeners.
   * Listeners are executed concurrently without blocking the emitter.
   * 
   * @param {string} eventName - The name of the event (use EVENTS constants)
   * @param {Object} payload - Data payload to send to listeners
   */
  async publish(eventName, payload = {}) {
    this._recordHistory(eventName, payload);
    
    // Node.js EventEmitter is synchronous by default.
    // By wrapping in setImmediate, we ensure emitting doesn't block the caller's call stack.
    setImmediate(() => {
      try {
        // Emit returns true if the event had listeners, false otherwise
        const hasListeners = this.emit(eventName, payload);
        if (!hasListeners) {
          logger.debug(`[EventBus] Dropped event '${eventName}' (no listeners)`);
        } else {
          logger.debug(`[EventBus] Published event '${eventName}'`);
        }
      } catch (error) {
        logger.error(`[EventBus] Error emitting event '${eventName}': ${error.message}`);
        this._recordDeadLetter(eventName, payload, error);
      }
    });
  }

  /**
   * Subscribe to an event with robust error handling for the handler.
   * 
   * @param {string} eventName - The name of the event
   * @param {Function} handler - Async or sync function to execute
   */
  subscribe(eventName, handler) {
    // Wrap the handler to catch any unhandled promise rejections or sync errors
    const safeHandler = async (payload) => {
      try {
        await handler(payload);
      } catch (error) {
        logger.error({
          event: 'event_handler_error',
          eventName,
          error: error.message,
          stack: error.stack
        });
        this._recordDeadLetter(eventName, payload, error);
      }
    };

    this.on(eventName, safeHandler);
    logger.debug(`[EventBus] Subscribed to '${eventName}'`);
    
    // Return an unsubscribe function for convenience
    return () => this.off(eventName, safeHandler);
  }

  /**
   * Get the recent event history
   * @returns {Array} Array of historical events
   */
  getHistory() {
    return [...this.history];
  }

  /**
   * Get failed events
   * @returns {Array} Array of dead letter events
   */
  getDeadLetters() {
    return [...this.deadLetters];
  }

  // --- Private Helpers ---

  _recordHistory(eventName, payload) {
    this.history.unshift({
      eventName,
      timestamp: new Date().toISOString(),
      payload: this._sanitize(payload)
    });

    if (this.history.length > this.historyLimit) {
      this.history.pop();
    }
  }

  _recordDeadLetter(eventName, payload, error) {
    this.deadLetters.push({
      eventName,
      timestamp: new Date().toISOString(),
      payload: this._sanitize(payload),
      error: error.message
    });
    
    // Keep DLQ from growing indefinitely
    if (this.deadLetters.length > 50) {
      this.deadLetters.shift();
    }
  }

  _sanitize(payload) {
    // Basic sanitization to prevent storing massive objects or sensitive data in memory arrays
    if (!payload) return payload;
    const clean = { ...payload };
    
    for (const key in clean) {
      if (typeof clean[key] === 'string' && clean[key].length > 500) {
        clean[key] = clean[key].substring(0, 500) + '...[truncated]';
      }
      if (/password|secret|token|key/i.test(key)) {
        clean[key] = '[REDACTED]';
      }
    }
    return clean;
  }
}

// Export as singleton
module.exports = new EventBus();
