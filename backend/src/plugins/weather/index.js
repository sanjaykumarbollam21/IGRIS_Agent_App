const { z } = require('zod');

module.exports = {
  name: 'weather',
  version: '1.0.0',
  description: 'Provides weather lookups via OpenWeatherMap',
  
  register: async (context) => {
    const { registerTool, logger } = context;

    registerTool({
      name: 'get_weather',
      description: 'Get the current weather for a specific city or location.',
      schema: z.object({
        location: z.string().describe('The city and state/country to look up, e.g., "San Francisco, CA"'),
        unit: z.enum(['celsius', 'fahrenheit']).optional().describe('Temperature unit')
      }),
      func: async ({ location, unit = 'celsius' }) => {
        logger.debug(`[Plugin:Weather] Looking up weather for ${location}`);
        
        // STUB: In a real implementation, this would call OpenWeatherMap API
        // For now, we return a functional stub so it works without API keys
        return JSON.stringify({
          location,
          condition: 'Partly Cloudy',
          temperature: unit === 'celsius' ? 22 : 72,
          unit: unit === 'celsius' ? 'C' : 'F',
          humidity: '45%',
          forecast: 'Clear skies expected later in the evening.'
        });
      }
    });

    logger.info('[Plugin:Weather] Registered get_weather tool');
  }
};
