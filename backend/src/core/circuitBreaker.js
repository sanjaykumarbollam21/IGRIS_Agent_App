const logger = require('../utils/logger');
const eventBus = require('./eventBus');
const { EVENTS } = require('./events');
const CircuitOpenError = require('./CircuitOpenError');

const STATES = {
  CLOSED: 'CLOSED',       // Normal operation
  OPEN: 'OPEN',           // Failing fast
  HALF_OPEN: 'HALF_OPEN'  // Testing recovery
};

/**
 * Circuit Breaker Pattern Implementation
 * Protects the system from cascading failures when external dependencies go down.
 */
class CircuitBreaker {
  /**
   * @param {string} name - Identifier for logging and events
   * @param {Function} action - Async function to execute
   * @param {Object} options - Configuration options
   * @param {number} options.failureThreshold - Consecutive failures before opening
   * @param {number} options.resetTimeoutMs - Time in ms before attempting recovery
   */
  constructor(name, action, options = {}) {
    this.name = name;
    this.action = action;
    this.failureThreshold = options.failureThreshold || 5;
    this.resetTimeoutMs = options.resetTimeoutMs || 30000; // 30 seconds default
    
    // Internal state
    this.state = STATES.CLOSED;
    this.failureCount = 0;
    this.successCount = 0;
    this.nextAttempt = null;
    this.fallback = null;
  }

  /**
   * Set a fallback function to run when the circuit is open or the action fails
   * @param {Function} fallbackFn 
   */
  fallbackTo(fallbackFn) {
    this.fallback = fallbackFn;
    return this;
  }

  /**
   * Execute the protected action
   * @param  {...any} args Arguments to pass to the action
   * @returns {Promise<any>}
   */
  async execute(...args) {
    // 1. Check if we should fail fast (OPEN) or trial (HALF_OPEN)
    if (this.state === STATES.OPEN) {
      if (Date.now() > this.nextAttempt) {
        // Time to trial recovery
        this._halfOpen();
      } else {
        // Still open, fail fast or run fallback
        return this._handleOpen(args);
      }
    }

    // 2. Execute the action
    try {
      const result = await this.action(...args);
      this._onSuccess();
      return result;
    } catch (error) {
      this._onFailure(error);
      if (this.fallback) {
        logger.debug(`[CircuitBreaker:${this.name}] Executing fallback due to error: ${error.message}`);
        return this.fallback(...args, error);
      }
      throw error;
    }
  }

  /**
   * Force the circuit closed (manual override)
   */
  reset() {
    this.failureCount = 0;
    this.state = STATES.CLOSED;
    this.nextAttempt = null;
    logger.info(`[CircuitBreaker:${this.name}] Manually reset to CLOSED`);
  }

  // --- Private State Machine ---

  _onSuccess() {
    this.failureCount = 0;
    this.successCount++;
    
    if (this.state === STATES.HALF_OPEN) {
      this.state = STATES.CLOSED;
      this.nextAttempt = null;
      logger.info(`[CircuitBreaker:${this.name}] Recovery successful. Circuit is CLOSED.`);
      eventBus.publish(EVENTS.CIRCUIT_CLOSED, { breaker: this.name });
    }
  }

  _onFailure(error) {
    this.failureCount++;
    logger.warn(`[CircuitBreaker:${this.name}] Failure ${this.failureCount}/${this.failureThreshold} - ${error.message}`);
    
    if (this.state === STATES.HALF_OPEN || this.failureCount >= this.failureThreshold) {
      this._open();
    }
  }

  _open() {
    this.state = STATES.OPEN;
    this.nextAttempt = Date.now() + this.resetTimeoutMs;
    logger.error(`[CircuitBreaker:${this.name}] Circuit OPENED. Failing fast for ${this.resetTimeoutMs}ms.`);
    eventBus.publish(EVENTS.CIRCUIT_OPENED, { 
      breaker: this.name,
      timeoutMs: this.resetTimeoutMs
    });
  }

  _halfOpen() {
    this.state = STATES.HALF_OPEN;
    logger.info(`[CircuitBreaker:${this.name}] Circuit HALF_OPEN. Attempting trial request.`);
    eventBus.publish(EVENTS.CIRCUIT_HALF_OPEN, { breaker: this.name });
  }

  _handleOpen(args) {
    if (this.fallback) {
      logger.debug(`[CircuitBreaker:${this.name}] Executing fallback (Circuit OPEN)`);
      return this.fallback(...args, new CircuitOpenError(this.name));
    }
    throw new CircuitOpenError(this.name);
  }
}

module.exports = CircuitBreaker;
