/**
 * Error thrown when a Circuit Breaker is in the OPEN state.
 * Status code 503 signifies Service Unavailable.
 */
class CircuitOpenError extends Error {
  constructor(breakerName) {
    super(`Circuit breaker '${breakerName}' is OPEN. Failing fast to prevent cascading failures.`);
    this.name = 'CircuitOpenError';
    this.statusCode = 503;
    this.breakerName = breakerName;
  }
}

module.exports = CircuitOpenError;
