/**
 * @fileoverview LangChain Orchestration Service for IGRIS Agent
 *
 * Main AI entry point that replaces the legacy aiService.js for chat operations.
 * Uses a manual ReAct-style tool-calling loop with Google Gemini via LangChain,
 * providing reliable agentic behavior without depending on AgentExecutor.
 *
 * @module services/langchainService
 */

const providerRegistry = require('../providers/ProviderRegistry');
const {
  HumanMessage,
  AIMessage,
  SystemMessage,
  ToolMessage,
} = require('@langchain/core/messages');
const {
  ChatPromptTemplate,
  MessagesPlaceholder,
} = require('@langchain/core/prompts');

const logger = require('../utils/logger');
const contextService = require('./contextService');
const toolExecutionService = require('./toolExecutionService');

/**
 * LangChain-based AI orchestration service.
 *
 * Manages the full chat lifecycle: context assembly, model invocation,
 * iterative tool execution, response sanitisation, and conversation persistence.
 *
 * @class LangchainService
 */
class LangchainService {
  constructor() {
    /** @type {number} Maximum tool-calling iterations before forced termination */
    this.maxIterations = parseInt(process.env.LANGCHAIN_MAX_ITERATIONS, 10) || 10;

    /** @type {boolean} Whether to enable verbose LangChain logging */
    this.verbose = process.env.LANGCHAIN_VERBOSE === 'true';

    /** @type {boolean} Tracks whether the service has been initialised */
    this.initialized = false;
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /**
   * Initialise the service and its dependencies.
   * Safe to call multiple times — subsequent calls are no-ops.
   *
   * @returns {Promise<void>}
   */
  async initialize() {
    if (this.initialized) return;

    try {
      await toolExecutionService.initialize();
      this.initialized = true;
      logger.info({ event: 'langchain_service_initialized' });
    } catch (error) {
      logger.error({
        event: 'langchain_service_init_error',
        message: error.message,
        stack: error.stack,
      });
      throw error;
    }
  }

  // ─── Model Factory ─────────────────────────────────────────────────────────

  /**
   * Create a ChatGoogleGenerativeAI instance configured for IGRIS.
   *
   * @param {string} [apiKey] - Optional per-user Gemini API key.
   *   Falls back to `GEMINI_API_KEY_DEFAULT` from the environment.
   * @returns {ChatGoogleGenerativeAI} A LangChain chat model bound to Gemini.
   * @private
   */
  _createModel(apiKey) {
    const provider = providerRegistry.getChatProvider();
    return provider.getChatModel({
      apiKey: apiKey || process.env.GEMINI_API_KEY_DEFAULT,
      temperature: 0.7,
      maxTokens: 2048
    });
  }

  // ─── Main Chat Method ──────────────────────────────────────────────────────

  /**
   * Process a user chat message through the full agentic pipeline.
   *
   * Flow:
   *  1. Lazy-initialise the service
   *  2. Build context (system prompt, conversation history, RAG)
   *  3. Resolve the user's API key
   *  4. Create & bind model + tools
   *  5. Run the ReAct-style tool-calling loop
   *  6. Sanitise the response (XSS prevention)
   *  7. Persist both user and model messages to the database
   *
   * @param {string}  message              - The user's chat message text.
   * @param {string}  userId               - UUID of the authenticated user.
   * @param {string}  sessionId            - UUID of the current conversation session.
   * @param {Object}  [options={}]         - Additional options.
   * @param {string}  [options.apiKey]     - Override API key for this request.
   * @param {string}  [options.imageData]  - Base64-encoded image data.
   * @param {string}  [options.mimeType]   - MIME type of the attached image.
   * @returns {Promise<{
   *   response: string,
   *   toolResults: Array<{tool: string, args: Object, result: *}>,
   *   ragSources: *|null,
   *   sessionId: string,
   *   iterations: number,
   *   error?: boolean
   * }>}
   */
  async chat(message, userId, sessionId, options = {}) {
    try {
      // ── 1. Lazy initialisation ────────────────────────────────────────────
      if (!this.initialized) {
        await this.initialize();
      }

      // ── 1.b. Guardrails ───────────────────────────────────────────────────
      const guardrails = require('../core/container').resolve('guardrails');
      const guardResult = await guardrails.evaluate(message, { userId, sessionId });
      
      if (!guardResult.passed) {
        logger.warn({ event: 'guardrail_blocked', userId, reason: guardResult.reason });
        return {
          response: `I'm sorry, I cannot process this request. Reason: ${guardResult.reason}`,
          toolResults: [],
          ragSources: null,
          sessionId,
          iterations: 0
        };
      }
      
      const safeMessage = guardResult.modifiedInput;

      // ── 2. Build context (system prompt + conversation history + RAG) ─────
      const context = await contextService.buildContext(userId, sessionId, safeMessage);

      // ── 3. Resolve API key (per-user → env default) ───────────────────────
      const { User } = require('../models');
      const user = await User.findByPk(userId);
      const apiKey =
        options.apiKey || user?.geminiApiKey || process.env.GEMINI_API_KEY_DEFAULT;

      // ── 4. Create model & bind tools ──────────────────────────────────────
      const model = this._createModel(apiKey);
      const tools = toolExecutionService.getTools(userId);

      const modelWithTools =
        tools && tools.length > 0 ? model.bindTools(tools) : model;

      // ── 5. Assemble message history ───────────────────────────────────────
      const messages = [
        new SystemMessage(context.systemPrompt),
        ...context.conversationHistory.map((m) =>
          m.role === 'human'
            ? new HumanMessage(m.content)
            : new AIMessage(m.content)
        ),
      ];

      // Handle multimodal (image) input
      if (options.imageData && options.mimeType) {
        messages.push(
          new HumanMessage({
            content: [
              { type: 'text', text: safeMessage },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${options.mimeType};base64,${options.imageData}`,
                },
              },
            ],
          })
        );
      } else {
        messages.push(new HumanMessage(safeMessage));
      }

      // ── 6. ReAct-style tool-calling loop ──────────────────────────────────
      const toolResults = [];
      let response;
      let iterations = 0;

      while (iterations < this.maxIterations) {
        iterations++;
        response = await modelWithTools.invoke(messages);

        // If the model does not request any tool calls we have the final answer
        if (!response.tool_calls || response.tool_calls.length === 0) {
          break;
        }

        // Append the AI message (with tool_calls metadata) to the history
        messages.push(response);

        // Execute each requested tool
        for (const toolCall of response.tool_calls) {
          logger.info({
            event: 'tool_call',
            tool: toolCall.name,
            args: toolCall.args,
            userId,
          });

          const tool = tools.find((t) => t.name === toolCall.name);
          let toolResult;

          if (tool) {
            try {
              toolResult = await tool.invoke(toolCall.args);
            } catch (error) {
              toolResult = `Error executing ${toolCall.name}: ${error.message}`;
              logger.error({
                event: 'tool_error',
                tool: toolCall.name,
                error: error.message,
              });
            }
          } else {
            toolResult = `Unknown tool: ${toolCall.name}`;
            logger.warn({
              event: 'unknown_tool_requested',
              tool: toolCall.name,
              userId,
            });
          }

          toolResults.push({
            tool: toolCall.name,
            args: toolCall.args,
            result: toolResult,
          });

          // Feed the tool result back to the model
          messages.push(
            new ToolMessage({
              content:
                typeof toolResult === 'string'
                  ? toolResult
                  : JSON.stringify(toolResult),
              tool_call_id: toolCall.id || toolCall.name,
              name: toolCall.name,
            })
          );
        }
      }

      if (iterations >= this.maxIterations) {
        logger.warn({
          event: 'max_iterations_reached',
          userId,
          sessionId,
          iterations,
        });
      }

      // ── 7. Extract final text response ────────────────────────────────────
      const responseText =
        typeof response.content === 'string'
          ? response.content
          : response.content?.map((c) => c.text || '').join('') ||
            'I was unable to generate a response.';

      // ── 8. Sanitise output (basic XSS prevention) ─────────────────────────
      const sanitizedResponse = responseText
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

      // ── 9. Persist conversation to database ───────────────────────────────
      try {
        const { saveMessage } = require('../routes/conversations');

        await saveMessage(
          userId,
          sessionId,
          'user',
          safeMessage,
          options.imageData ? { hasImage: true } : {}
        );

        await saveMessage(userId, sessionId, 'model', sanitizedResponse, {
          toolCalls: toolResults,
          ragSources: context.ragContext ? true : false,
        });
      } catch (saveError) {
        // Conversation save is non-critical — log and continue
        logger.error({
          event: 'conversation_save_error',
          message: saveError.message,
          userId,
          sessionId,
        });
      }

      // ── 10. Return structured result ──────────────────────────────────────
      return {
        response: sanitizedResponse,
        toolResults,
        ragSources: context.ragContext || null,
        sessionId,
        iterations,
      };
    } catch (error) {
      logger.error({
        event: 'langchain_chat_error',
        message: error.message,
        stack: error.stack,
        userId,
        sessionId,
      });

      return {
        response:
          'I encountered an error processing your request. Please try again.',
        toolResults: [],
        ragSources: null,
        sessionId,
        error: true,
      };
    }
  }

  // ─── Backward-Compatible Wrapper ───────────────────────────────────────────

  /**
   * Process a prompt in the same shape the legacy `aiService.processMultimodalPrompt`
   * accepted, routing it through the new {@link chat} pipeline.
   *
   * Supported `content` formats:
   * - **string** — plain text prompt
   * - **Array** — array of parts, each having `{ text }` or
   *   `{ inlineData: { data, mimeType } }`
   *
   * @param {string|Array<Object>} content     - The user prompt content.
   * @param {Object}               [userContext={}] - Legacy user-context bag.
   * @param {string}               [userContext.userId]
   * @param {string}               [userContext.sessionId]
   * @param {string}               [userContext.apiKey]
   * @returns {Promise<Object>} Chat result (see {@link chat}).
   */
  async processMultimodalPrompt(content, userContext = {}) {
    const { userId, sessionId, ...rest } = userContext;

    // Simple text prompt
    if (typeof content === 'string') {
      return this.chat(content, userId, sessionId, rest);
    }

    // Multimodal array — extract text and first image part
    if (Array.isArray(content)) {
      let textPart = '';
      let imageData = null;
      let mimeType = null;

      for (const part of content) {
        if (part.text) {
          textPart += part.text;
        }
        if (part.inlineData && !imageData) {
          imageData = part.inlineData.data;
          mimeType = part.inlineData.mimeType;
        }
      }

      return this.chat(textPart || 'Describe this image.', userId, sessionId, {
        ...rest,
        imageData,
        mimeType,
      });
    }

    // Fallback — treat as string
    return this.chat(String(content), userId, sessionId, rest);
  }
}

module.exports = new LangchainService();
