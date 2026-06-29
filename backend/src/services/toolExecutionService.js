const { DynamicStructuredTool } = require('@langchain/core/tools');
const { z } = require('zod');
const logger = require('../utils/logger');
const toolsController = require('../controllers/toolsController');
const notificationService = require('./notificationService');
const eventBus = require('../core/eventBus');
const { EVENTS } = require('../core/events');

/**
 * @fileoverview IGRIS Tool Execution Service
 *
 * Wraps every available agent tool as a LangChain {@link DynamicTool} so the
 * LangChain agent runtime can invoke them by name. Each tool:
 *
 * - Validates inputs via a Zod schema
 * - Catches all errors and returns a descriptive error *string* instead of
 *   throwing (LangChain agents expect string returns)
 * - Is wrapped at retrieval time ({@link getTools}) with a closure that
 *   injects `userId` and logs execution to the `ToolUsage` table
 *
 * @module services/toolExecutionService
 */

/**
 * @typedef {Object} ToolDefinition
 * @property {string}  name                  - Unique tool identifier
 * @property {string}  description           - Human-readable purpose (consumed by LLM)
 * @property {import('zod').ZodObject} schema - Zod schema for parameter validation
 * @property {Function} func                 - Async executor receiving validated params
 * @property {boolean} [requiresConfirmation] - If true, the agent should ask the user
 *                                              for confirmation before executing
 */

class ToolExecutionService {
  constructor() {
    /** @type {Map<string, ToolDefinition>} */
    this.tools = new Map();

    /** @type {DynamicTool[]} */
    this._langchainTools = [];

    /** @private */
    this._initialized = false;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Initialization
  // ───────────────────────────────────────────────────────────────────────────

  /**
   * Build every DynamicTool instance. Safe to call more than once (no-op after
   * the first successful run).
   * @returns {void}
   */
  initialize() {
    if (this._initialized) return;

    this._registerWebSearch();
    this._registerKnowledgeSearch();
    this._registerSendEmail();
    this._registerSetReminder();
    this._registerGetCalendarEvents();
    this._registerCreateCalendarEvent();
    this._registerGenerateImage();
    this._registerGetCurrentDatetime();
    this._registerOpenApp();
    this._registerSystemCommand();

    this._initialized = true;
    logger.info({
      event: 'tool_execution_service_initialized',
      toolCount: this.tools.size,
      tools: [...this.tools.keys()],
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tool registrations (private)
  // ───────────────────────────────────────────────────────────────────────────

  /**
   * Register a single tool definition and its corresponding DynamicTool.
   * @param {ToolDefinition} def
   * @private
   */
  _register(def) {
    this.tools.set(def.name, def);

    const dynamicTool = new DynamicStructuredTool({
      name: def.name,
      description: def.description,
      schema: def.schema,
      func: def.func,
    });

    this._langchainTools.push(dynamicTool);
  }

  /** @private */
  _registerWebSearch() {
    this._register({
      name: 'web_search',
      description:
        'Search the web for real-time information, current events, news, facts, ' +
        'or anything the user asks about that requires up-to-date data. ' +
        'Returns a JSON string with search results and an optional AI summary.',
      schema: z.object({
        query: z.string().describe('The search query to look up on the web'),
      }),
      func: async ({ query }, userId) => {
        try {
          const results = await toolsController.webSearch(userId, query);
          return JSON.stringify(results, null, 2);
        } catch (err) {
          logger.error({ event: 'tool_web_search_error', error: err.message });
          return `Error performing web search: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerKnowledgeSearch() {
    this._register({
      name: 'knowledge_search',
      description:
        'Search the user\'s personal knowledge base (uploaded documents, notes, ' +
        'and files). Use this when the user asks about their own data, documents, ' +
        'or previously saved information. Returns relevant text chunks.',
      schema: z.object({
        query: z.string().describe('Natural-language query to search the knowledge base'),
      }),
      func: async ({ query }, userId) => {
        try {
          // Lazy-require to avoid circular dependency with ragService
          const ragService = require('./ragService');
          const chunks = await ragService.search(userId, query);

          if (!chunks || chunks.length === 0) {
            return 'No relevant information found in your knowledge base.';
          }

          const formatted = chunks
            .map((c, i) => `[${i + 1}] (score: ${(c.score ?? 0).toFixed(3)}) ${c.content}`)
            .join('\n\n');

          return formatted;
        } catch (err) {
          logger.error({ event: 'tool_knowledge_search_error', error: err.message });
          return `Error searching knowledge base: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerSendEmail() {
    this._register({
      name: 'send_email',
      description:
        'Compose and send an email to a recipient. Requires the recipient\'s email ' +
        'address, a subject line, and the email body. This action is irreversible ' +
        'so the agent should confirm with the user before sending.',
      schema: z.object({
        to: z.string().describe('Recipient email address'),
        subject: z.string().describe('Email subject line'),
        body: z.string().describe('Email body content (plain text)'),
      }),
      requiresConfirmation: true,
      func: async ({ to, subject, body }, userId) => {
        try {
          const result = await toolsController.sendMessage(userId, {
            recipient: to,
            message: `Subject: ${subject}\n\n${body}`,
            provider: 'email',
          });
          return JSON.stringify(result, null, 2);
        } catch (err) {
          logger.error({ event: 'tool_send_email_error', error: err.message });
          return `Error sending email: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerSetReminder() {
    this._register({
      name: 'set_reminder',
      description:
        'Set a reminder or alarm for the user. Provide a title and a time ' +
        '(ISO 8601 datetime string or natural-language like "in 30 minutes", ' +
        '"tomorrow at 9am"). Optionally set a repeat frequency.',
      schema: z.object({
        title: z.string().describe('Short reminder title or description'),
        time: z.string().describe('When the reminder should fire — ISO 8601 datetime or natural language (e.g. "in 30 minutes", "tomorrow at 9am")'),
        repeat: z
          .enum(['once', 'daily', 'weekdays', 'weekly'])
          .optional()
          .describe('Repeat frequency — defaults to "once"'),
      }),
      func: async ({ title, time, repeat = 'once' }) => {
        try {
          const scheduler = require('../utils/scheduler');

          // Attempt to parse the time into a Date
          let reminderDate;
          try {
            reminderDate = new Date(time);
            if (isNaN(reminderDate.getTime())) {
              // If native parse fails, return guidance for the agent
              return (
                `Could not parse the time "${time}". Please provide an ISO 8601 ` +
                'datetime (e.g. "2026-05-22T09:00:00+05:30") and try again.'
              );
            }
          } catch (_) {
            return `Invalid time format: "${time}". Use ISO 8601.`;
          }

          // Emit a reminder event through notification service so the client
          // app can schedule a local notification.
          await notificationService.broadcast('reminder_set', {
            title,
            time: reminderDate.toISOString(),
            repeat,
          });

          const readableTime = reminderDate.toLocaleString('en-IN', {
            dateStyle: 'medium',
            timeStyle: 'short',
            timeZone: 'Asia/Kolkata',
          });

          return `✅ Reminder set: "${title}" at ${readableTime}${repeat !== 'once' ? ` (repeats ${repeat})` : ''}.`;
        } catch (err) {
          logger.error({ event: 'tool_set_reminder_error', error: err.message });
          return `Error setting reminder: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerGetCalendarEvents() {
    this._register({
      name: 'get_calendar_events',
      description:
        'Retrieve the user\'s upcoming calendar events for the next N days ' +
        '(default 7). Returns event titles, times, and locations.',
      schema: z.object({
        days: z
          .number()
          .optional()
          .describe('Number of days ahead to look (default 7)'),
      }),
      func: async ({ days = 7 }) => {
        try {
          // TODO: Integrate with Google Calendar OAuth flow once tokens are available.
          // For now, return an informative stub.
          return (
            '⚠️ Calendar integration requires Google OAuth setup. ' +
            `Once configured, this tool will fetch your events for the next ${days} day(s). ` +
            'Please connect your Google Calendar in Settings → Integrations.'
          );
        } catch (err) {
          logger.error({ event: 'tool_get_calendar_error', error: err.message });
          return `Error fetching calendar events: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerCreateCalendarEvent() {
    this._register({
      name: 'create_calendar_event',
      description:
        'Create a new event on the user\'s Google Calendar. Requires a title and ' +
        'start time. End time, description, and location are optional. The agent ' +
        'should confirm details with the user before creating.',
      schema: z.object({
        title: z.string().describe('Event title'),
        start: z.string().describe('Start time in ISO 8601 format'),
        end: z.string().optional().describe('End time in ISO 8601 format (defaults to 1 hour after start)'),
        description: z.string().optional().describe('Event description or notes'),
        location: z.string().optional().describe('Event location or meeting link'),
      }),
      requiresConfirmation: true,
      func: async ({ title, start, end, description, location }) => {
        try {
          // TODO: Integrate with Google Calendar API using stored OAuth tokens.
          return (
            '⚠️ Calendar integration requires Google OAuth setup. ' +
            `Event "${title}" starting at ${start} will be created once configured. ` +
            'Please connect your Google Calendar in Settings → Integrations.'
          );
        } catch (err) {
          logger.error({ event: 'tool_create_calendar_error', error: err.message });
          return `Error creating calendar event: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerGenerateImage() {
    this._register({
      name: 'generate_image',
      description:
        'Generate an AI image from a text description. Provide a detailed prompt ' +
        'and an optional visual style (photorealistic, anime, painting, digital_art, sketch). ' +
        'Returns the generated image as a base64-encoded data URI.',
      schema: z.object({
        prompt: z.string().describe('Detailed description of the image to generate'),
        style: z
          .enum(['photorealistic', 'anime', 'painting', 'digital_art', 'sketch'])
          .optional()
          .describe('Visual style for the generated image'),
      }),
      func: async ({ prompt, style }) => {
        try {
          const { GoogleGenAI } = require('@google/genai');
          const apiKey = process.env.GEMINI_API_KEY_DEFAULT;

          if (!apiKey) {
            return 'Error: GEMINI_API_KEY_DEFAULT is not configured. Cannot generate images.';
          }

          const ai = new GoogleGenAI({ apiKey });

          const enhancedPrompt = style
            ? `${prompt}, in ${style.replace('_', ' ')} style`
            : prompt;

          const response = await ai.models.generateContent({
            model: 'gemini-2.0-flash',
            contents: enhancedPrompt,
            config: {
              responseModalities: ['TEXT', 'IMAGE'],
            },
          });

          // Extract image parts from the response
          const parts = response.candidates?.[0]?.content?.parts || [];
          const imagePart = parts.find((p) => p.inlineData?.mimeType?.startsWith('image/'));

          if (imagePart) {
            const { mimeType, data } = imagePart.inlineData;
            return JSON.stringify({
              success: true,
              imageDataUri: `data:${mimeType};base64,${data}`,
              prompt: enhancedPrompt,
            });
          }

          // Fallback: return any text response
          const textPart = parts.find((p) => p.text);
          return textPart?.text || 'Image generation completed but no image was returned.';
        } catch (err) {
          logger.error({ event: 'tool_generate_image_error', error: err.message });
          return `Error generating image: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerGetCurrentDatetime() {
    this._register({
      name: 'get_current_datetime',
      description:
        'Get the current date, time, day of the week, and timezone. Use this ' +
        'whenever you need to know the current time to answer questions, set ' +
        'reminders at the right time, or provide time-aware responses.',
      schema: z.object({}),
      func: async () => {
        try {
          const now = new Date();
          const options = { timeZone: 'Asia/Kolkata' };

          const info = {
            iso: now.toISOString(),
            date: now.toLocaleDateString('en-IN', { ...options, dateStyle: 'full' }),
            time: now.toLocaleTimeString('en-IN', { ...options, timeStyle: 'medium' }),
            dayOfWeek: now.toLocaleDateString('en-IN', { ...options, weekday: 'long' }),
            timezone: 'Asia/Kolkata (IST, UTC+05:30)',
            unixTimestamp: Math.floor(now.getTime() / 1000),
          };

          return JSON.stringify(info, null, 2);
        } catch (err) {
          logger.error({ event: 'tool_datetime_error', error: err.message });
          return `Error getting current datetime: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerOpenApp() {
    this._register({
      name: 'open_app',
      description:
        'Open an application on the user\'s device (e.g. "Chrome", "Spotify", ' +
        '"VS Code", "Calculator"). Sends a Socket.IO command to the user\'s ' +
        'connected client. The agent should confirm with the user before opening.',
      schema: z.object({
        appName: z.string().describe('Name of the application to open'),
      }),
      requiresConfirmation: true,
      func: async ({ appName }, userId) => {
        try {
          await notificationService.notifyUser(userId, 'device_command', {
            action: 'open_app',
            appName,
          });

          return `✅ Command sent to open "${appName}" on your device.`;
        } catch (err) {
          logger.error({ event: 'tool_open_app_error', error: err.message });
          return `Error opening app: ${err.message}`;
        }
      },
    });
  }

  /** @private */
  _registerSystemCommand() {
    this._register({
      name: 'system_command',
      description:
        'Execute a system command on the user\'s device. Supported commands: ' +
        'lock, sleep, shutdown, restart, mute, unmute, volume_up, volume_down, screenshot. ' +
        'Sends a Socket.IO command to the user\'s connected client.',
      schema: z.object({
        command: z
          .enum([
            'lock',
            'sleep',
            'shutdown',
            'restart',
            'mute',
            'unmute',
            'volume_up',
            'volume_down',
            'screenshot',
          ])
          .describe('The system command to execute'),
      }),
      func: async ({ command }, userId) => {
        try {
          await notificationService.notifyUser(userId, 'device_command', {
            action: 'system_command',
            command,
          });

          const labels = {
            lock: '🔒 Device locked',
            sleep: '😴 Device going to sleep',
            shutdown: '⏹️ Shutting down',
            restart: '🔄 Restarting',
            mute: '🔇 Audio muted',
            unmute: '🔊 Audio unmuted',
            volume_up: '🔊 Volume increased',
            volume_down: '🔉 Volume decreased',
            screenshot: '📸 Screenshot captured',
          };

          return `${labels[command] || `Command "${command}" sent`} — command dispatched to your device.`;
        } catch (err) {
          logger.error({ event: 'tool_system_command_error', error: err.message });
          return `Error executing system command: ${err.message}`;
        }
      },
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Public API
  // ───────────────────────────────────────────────────────────────────────────

  /**
   * Externally register a tool (e.g. from a plugin)
   * @param {ToolDefinition} def 
   */
  registerExternalTool(def) {
    this._register(def);
    logger.info({ event: 'external_tool_registered', tool: def.name });
  }

  /**
   * Return an array of DynamicTool instances ready for a LangChain agent.
   *
   * Each tool's `func` is wrapped in a closure that:
   * 1. Injects the `userId` into the call
   * 2. Records execution timing
   * 3. Logs a row to the `ToolUsage` table
   *
   * @param {string} userId - The authenticated user's ID
   * @returns {DynamicTool[]} Array of LangChain-compatible tool instances
   */
  getTools(userId) {
    this.initialize(); // ensure tools are built

    return [...this.tools.entries()].map(([name, def]) => {
      return new DynamicStructuredTool({
        name: def.name,
        description: def.description,
        schema: def.schema,
        func: async (input) => {
          const startMs = Date.now();
          let result;
          let status = 'success';
          let errorMessage = null;

          try {
            logger.info({
              event: 'tool_execution_start',
              tool: name,
              userId,
              params: this._sanitizeForLog(input),
            });

            // For tools that need userId (open_app, system_command, etc.)
            // we pass it as a second argument.
            result = await def.func(input, userId);

            logger.info({
              event: 'tool_execution_complete',
              tool: name,
              userId,
              durationMs: Date.now() - startMs,
            });

            return result;
          } catch (err) {
            status = 'error';
            errorMessage = err.message;
            result = `Error executing ${name}: ${err.message}`;

            logger.error({
              event: 'tool_execution_error',
              tool: name,
              userId,
              error: err.message,
              stack: err.stack,
            });

            return result;
          } finally {
            // Fire-and-forget usage logging — never block the agent
            this._logUsage(
              userId,
              name,
              'execute',
              this._sanitizeForLog(input),
              typeof result === 'string' ? { response: result.substring(0, 2000) } : result,
              status,
              errorMessage,
              Date.now() - startMs,
            ).catch((logErr) => {
              logger.warn({
                event: 'tool_usage_log_failed',
                tool: name,
                error: logErr.message,
              });
            });

            // Publish execution event
            eventBus.publish(status === 'error' ? EVENTS.TOOL_ERROR : EVENTS.TOOL_EXECUTED, {
              userId,
              toolName: name,
              params: this._sanitizeForLog(input),
              status,
              durationMs: Date.now() - startMs,
              errorMessage
            });
          }
        },
      });
    });
  }

  /**
   * Log a tool invocation to the ToolUsage table.
   *
   * @param {string}      userId       - Authenticated user ID
   * @param {string}      toolName     - Tool identifier
   * @param {string}      action       - Action label (usually "execute")
   * @param {Object}      params       - Sanitized input parameters
   * @param {Object}      result       - Truncated result payload
   * @param {string}      status       - "success" | "error" | "pending"
   * @param {string|null} error        - Error message if status is "error"
   * @param {number}      [durationMs] - Execution time in milliseconds
   * @returns {Promise<void>}
   * @private
   */
  async _logUsage(userId, toolName, action, params, result, status, error, durationMs = 0) {
    try {
      // Guard: skip logging if userId is missing (e.g. during tests)
      if (!userId) return;

      const { ToolUsage } = require('../models');
      await ToolUsage.create({
        userId,
        toolName,
        action,
        parameters: params || {},
        result: result || {},
        status,
        errorMessage: error,
        executionTimeMs: durationMs,
      });
    } catch (err) {
      // Intentionally swallowed — logging should never crash the agent
      logger.error({
        event: 'tool_usage_db_error',
        toolName,
        error: err.message,
      });
    }
  }

  /**
   * Return human-readable metadata for all registered tools.
   *
   * Useful for:
   * - Building system prompts that list available capabilities
   * - Rendering a "tools" panel in the frontend
   * - Auditing which tools require user confirmation
   *
   * @returns {{ name: string, description: string, requiresConfirmation: boolean }[]}
   */
  getToolDescriptions() {
    this.initialize();

    return [...this.tools.values()].map((def) => ({
      name: def.name,
      description: def.description,
      requiresConfirmation: !!def.requiresConfirmation,
    }));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  /**
   * Strip or truncate sensitive / oversized fields before writing to logs or DB.
   *
   * @param {*} input - Raw tool input
   * @returns {Object} Sanitized copy safe for persistence
   * @private
   */
  _sanitizeForLog(input) {
    if (!input || typeof input !== 'object') return {};

    const clean = { ...input };

    // Truncate very long string values (e.g. base64 image data)
    for (const [key, value] of Object.entries(clean)) {
      if (typeof value === 'string' && value.length > 500) {
        clean[key] = `${value.substring(0, 500)}… [truncated, ${value.length} chars]`;
      }
    }

    // Never persist anything that looks like a key or token
    const sensitiveKeys = /api[_-]?key|token|secret|password|credential/i;
    for (const key of Object.keys(clean)) {
      if (sensitiveKeys.test(key)) {
        clean[key] = '[REDACTED]';
      }
    }

    return clean;
  }
}

module.exports = new ToolExecutionService();
