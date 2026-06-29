/**
 * InjectionGuard
 * Detects basic prompt injection attacks (Jailbreaks).
 */
class InjectionGuard {
  constructor() {
    this.name = 'InjectionGuard';
    
    // Heuristic phrases often used in jailbreaks
    this.blockedPhrases = [
      'ignore all previous instructions',
      'ignore previous instructions',
      'you are now',
      'system prompt:',
      'developer mode',
      'DAN', // Do Anything Now
      'bypass constraints'
    ];
  }

  async evaluate(input, context) {
    const lowerInput = input.toLowerCase();

    for (const phrase of this.blockedPhrases) {
      if (lowerInput.includes(phrase)) {
        return {
          passed: false,
          reason: `Detected potential prompt injection attempt: "${phrase}"`
        };
      }
    }

    return { passed: true, modifiedInput: input };
  }
}

module.exports = InjectionGuard;
