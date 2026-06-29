const axios = require('axios');
const { ToolUsage } = require('../models');
const CircuitBreaker = require('../core/circuitBreaker');

/**
 * Tools Controller
 * Handles execution of various agent capabilities using actual API integrations
 */
class ToolsController {
  constructor() {
    this.googleSearchApi = process.env.GOOGLE_SEARCH_API_KEY;
    this.googleSearchCx = process.env.GOOGLE_SEARCH_CX;
    this.twilioSid = process.env.TWILIO_ACCOUNT_SID;
    this.twilioToken = process.env.TWILIO_AUTH_TOKEN;

    // Bind internal methods for context
    this._webSearchInternal = this._webSearchInternal.bind(this);
    this._sendMessageInternal = this._sendMessageInternal.bind(this);

    // Set up circuit breakers
    this.searchBreaker = new CircuitBreaker('GoogleSearch', this._webSearchInternal, {
      failureThreshold: 3,
      resetTimeoutMs: 30000 // 30s timeout
    }).fallbackTo((userId, query) => ({
      query,
      items: [],
      aiSummary: '⚠️ Web search is currently unavailable due to repeated API failures. Please try again later.',
      totalResults: 0
    }));

    this.messagingBreaker = new CircuitBreaker('ExternalMessaging', this._sendMessageInternal, {
      failureThreshold: 3,
      resetTimeoutMs: 60000 // 60s timeout
    }).fallbackTo((userId, params, err) => {
      throw new Error(`Messaging service unavailable (Circuit Open): ${err.message}`);
    });
  }

  /**
   * Public interface wrapped in circuit breaker
   */
  async webSearch(userId, query, customApiKey = null) {
    return this.searchBreaker.execute(userId, query, customApiKey);
  }

  /**
   * Perform a real web search using Google Custom Search API
   */
  async _webSearchInternal(userId, query, customApiKey = null) {
    try {
      // If no API key, return a stub so the app doesn't crash
      if (!this.googleSearchApi || !this.googleSearchCx) {
        return {
          query,
          items: [],
          aiSummary: `Web search is not configured. Add GOOGLE_SEARCH_API_KEY and GOOGLE_SEARCH_CX to the server .env to enable real-time search.\n\nYou asked: **${query}**`,
          totalResults: 0,
        };
      }

      const response = await axios.get('https://www.googleapis.com/customsearch/v1', {
        params: { key: this.googleSearchApi, cx: this.googleSearchCx, q: query }
      });

      const items = (response.data.items || []).map(item => ({
        title: item.title,
        link: item.link,
        snippet: item.snippet,
      }));

      // Generate AI summary from snippets using Gemini
      let aiSummary = '';
      try {
        const { GoogleGenerativeAI } = require('@google/generative-ai');
        const apiKey = customApiKey || process.env.GEMINI_API_KEY_DEFAULT || '';
        if (apiKey) {
          const genAI = new GoogleGenerativeAI(apiKey);
          const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
          const snippets = items.slice(0, 5).map(i => `- ${i.title}: ${i.snippet}`).join('\n');
          const result = await model.generateContent(
            `Based on these search results for "${query}", give a concise 2-3 sentence summary:\n${snippets}`
          );
          aiSummary = result.response.text();
        }
      } catch (_) { /* Summary is optional */ }

      const finalResult = { query, items, aiSummary, totalResults: response.data.searchInformation?.totalResults || 0 };
      await this._logUsage(userId, 'web_search', 'search', { query }, finalResult);
      return finalResult;
    } catch (error) {
      await this._logUsage(userId, 'web_search', 'search', { query }, {}, 'error', error.message);
      throw error;
    }
  }

  /**
   * Public interface wrapped in circuit breaker
   */
  async sendMessage(userId, params) {
    return this.messagingBreaker.execute(userId, params);
  }

  /**
   * Send a real message via Twilio (WhatsApp/SMS) or SendGrid (Email)
   */
  async _sendMessageInternal(userId, params) {
    const { recipient, message, provider = 'whatsapp' } = params;
    try {
      let result = {};

      if (provider === 'whatsapp' || provider === 'sms') {
        // Free approach: Local mobile app handles Busy Mode auto-replies.
        // Direct server-side WhatsApp/SMS is disabled to avoid Twilio costs.
        result = { 
          status: 'skipped', 
          message: 'WhatsApp/SMS sending is handled locally by the IGRIS mobile app to avoid costs.',
          provider 
        };
      } else if (provider === 'email') {
        if (!process.env.SENDGRID_API_KEY) {
          throw new Error('SendGrid API key not configured');
        }

        const sendGridResponse = await axios.post(
          'https://api.sendgrid.com/v3/mail/send',
          {
            personalizations: [{ to: [{ email: recipient }] }],
            from: { email: process.env.EMAIL_FROM || 'noreply@igris.ai' },
            content: [{ type: 'text/plain', value: message }]
          },
          {
            headers: { 'Authorization': `Bearer ${process.env.SENDGRID_API_KEY}` }
          }
        );
        result = { status: 'sent', provider: 'email' };
      } else {
        throw new Error(`Unsupported provider: ${provider}`);
      }

      await this._logUsage(userId, 'messaging', 'send', params, result);
      return result;
    } catch (error) {
      await this._logUsage(userId, 'messaging', 'send', params, {}, 'error', error.message);
      throw error;
    }
  }

  /**
   * Log tool usage to database
   */
  async _logUsage(userId, toolName, action, parameters, result, status = 'success', errorMessage = null) {
    try {
      const { ToolUsage } = require('../models');
      await ToolUsage.create({
        userId,
        toolName,
        action,
        parameters,
        result,
        status,
        errorMessage,
        executionTimeMs: 0, // In real impl, calculate diff
      });
    } catch (error) {
      console.error('Failed to log tool usage:', error);
    }
  }
}

module.exports = new ToolsController();
