const { z } = require('zod');

module.exports = {
  name: 'calculator',
  version: '1.0.0',
  description: 'Secure math expression evaluator',
  
  register: async (context) => {
    const { registerTool, logger } = context;

    registerTool({
      name: 'calculate',
      description: 'Safely evaluate a mathematical expression. Use this for complex arithmetic that the LLM might hallucinate (e.g. "345.5 * 19 / 3 + 12").',
      schema: z.object({
        expression: z.string().describe('The mathematical expression to evaluate')
      }),
      func: async ({ expression }) => {
        logger.debug(`[Plugin:Calculator] Evaluating: ${expression}`);
        
        try {
          // A safe, basic evaluator without using eval()
          // In a real app, use mathjs or similar library.
          // This regex-based approach handles basic math safely.
          const sanitized = expression.replace(/[^0-9+\-*/(). ]/g, '');
          if (!sanitized) throw new Error('Invalid characters in expression');
          
          // eslint-disable-next-line no-new-func
          const result = new Function(`return ${sanitized}`)();
          
          return JSON.stringify({
            expression: sanitized,
            result: Number.isFinite(result) ? result : 'Error: computation failed'
          });
        } catch (err) {
          return `Error evaluating expression: ${err.message}`;
        }
      }
    });

    logger.info('[Plugin:Calculator] Registered calculate tool');
  }
};
