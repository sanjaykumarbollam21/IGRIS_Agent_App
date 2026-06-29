const logger = require('../../utils/logger');

/**
 * GuardrailPipeline
 * Evaluates inputs against a series of security guards before allowing them to proceed.
 */
class GuardrailPipeline {
  constructor() {
    this.guards = [];
  }

  /**
   * Register a new guard
   * @param {Object} guard - Must implement evaluate(input, context)
   */
  addGuard(guard) {
    if (!guard || typeof guard.evaluate !== 'function') {
      throw new Error('Guard must implement evaluate() method');
    }
    this.guards.push(guard);
    return this;
  }

  /**
   * Run the input through all registered guards
   * @param {string} input 
   * @param {Object} context { userId, sessionId }
   * @returns {Promise<{ passed: boolean, modifiedInput: string, reason?: string }>}
   */
  async evaluate(input, context = {}) {
    let currentInput = input;

    for (const guard of this.guards) {
      try {
        const result = await guard.evaluate(currentInput, context);
        
        if (!result.passed) {
          logger.warn(`[Guardrail] Blocked by ${guard.name}: ${result.reason}`);
          return {
            passed: false,
            modifiedInput: currentInput, // Return unmodified on block
            reason: result.reason
          };
        }

        // Some guards (like PII) might sanitize and modify the input
        if (result.modifiedInput) {
          currentInput = result.modifiedInput;
        }

      } catch (error) {
        // Fail open or fail closed? Generally fail closed for security.
        logger.error(`[Guardrail] Error in ${guard.name}: ${error.message}`);
        return {
          passed: false,
          modifiedInput: currentInput,
          reason: 'Internal security check failed'
        };
      }
    }

    return {
      passed: true,
      modifiedInput: currentInput
    };
  }
}

module.exports = GuardrailPipeline;
