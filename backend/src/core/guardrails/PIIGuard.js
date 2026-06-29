/**
 * PIIGuard
 * Redacts common Personally Identifiable Information from prompts.
 */
class PIIGuard {
  constructor() {
    this.name = 'PIIGuard';
    
    // Very basic regexes for demonstration.
    // In production, use dedicated libraries like Presidio.
    this.patterns = [
      {
        regex: /\b\d{3}-\d{2}-\d{4}\b/g, // SSN
        replacement: '[REDACTED_SSN]'
      },
      {
        regex: /\b(?:\d[ -]*?){13,16}\b/g, // Credit Card
        replacement: '[REDACTED_CC]'
      }
    ];
  }

  async evaluate(input, context) {
    let modifiedInput = input;
    let redactedCount = 0;

    for (const { regex, replacement } of this.patterns) {
      const original = modifiedInput;
      modifiedInput = modifiedInput.replace(regex, replacement);
      if (original !== modifiedInput) {
        redactedCount++;
      }
    }

    return {
      passed: true, // We don't block, we just sanitize
      modifiedInput,
      reason: redactedCount > 0 ? `Redacted ${redactedCount} PII elements` : 'Clean'
    };
  }
}

module.exports = PIIGuard;
