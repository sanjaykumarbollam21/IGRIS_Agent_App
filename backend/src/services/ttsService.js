const axios = require('axios');
require('dotenv').config();

/**
 * Murf.ai TTS Service
 * Handles text-to-speech synthesis using Murf.ai API
 */
class TTSService {
  constructor() {
    this.baseUrl = 'https://api.murf.ai/v1';
    this.defaultApiKey = process.env.MURF_API_KEY_DEFAULT;
  }

  /**
   * Synthesize text to speech
   * @param {string} text The text to synthesize
   * @param {Object} options Voice and style options
   * @param {string} userApiKey The user's specific Murf API key (optional)
   * @returns {Promise<{audioUrl: string, audioId: string}>}
   */
  async synthesize(text, options = {}, userApiKey = null) {
    try {
      const apiKey = userApiKey || this.defaultApiKey;
      if (!apiKey) {
        throw new Error('Murf.ai API key not configured');
      }

      const response = await axios.post(`${this.baseUrl}/speech/generate`, {
        text: text,
        voiceId: options.voiceId || 'en-US-male-1',
        style: options.style || 'conversational',
        language: options.language || 'en-US',
        format: 'mp3'
      }, {
        headers: {
          'apiKey': apiKey,
          'Content-Type': 'application/json'
        }
      });

      return {
        audioUrl: response.data.audioUrl,
        audioId: response.data.audioId,
        duration: response.data.duration
      };
    } catch (error) {
      console.error('Murf.ai TTS Error:', error.response?.data || error.message);
      throw new Error(`Speech synthesis failed: ${error.message}`);
    }
  }
}

module.exports = new TTSService();
