const { GoogleGenerativeAI } = require("@google/generative-ai");
require('dotenv').config();
const logger = require('../utils/logger');

if (!process.env.GEMINI_API_KEY_DEFAULT) {
  logger.warn('GEMINI_API_KEY_DEFAULT not set. AI service will use per-user keys only.');
}

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY_DEFAULT || '');

/**
 * IGRIS AI Service — v2.0
 * Gemini 2.0 Flash with expanded tool-calling schema
 */
class AIService {
  constructor() {
    this.tools = [
      {
        functionDeclarations: [
          // ── Search & Information ──
          {
            name: "web_search",
            description: "Search the web for real-time information, news, current events, or facts.",
            parameters: {
              type: "object",
              properties: {
                query: { type: "string", description: "The search query" }
              },
              required: ["query"]
            }
          },
          {
            name: "get_directions",
            description: "Get directions or route between two locations.",
            parameters: {
              type: "object",
              properties: {
                origin: { type: "string", description: "Starting location" },
                destination: { type: "string", description: "Destination location" },
                mode: { type: "string", enum: ["driving", "walking", "transit", "bicycling"], description: "Travel mode" }
              },
              required: ["origin", "destination"]
            }
          },
          {
            name: "find_nearby_places",
            description: "Find nearby places, restaurants, hospitals, or points of interest.",
            parameters: {
              type: "object",
              properties: {
                query: { type: "string", description: "Type of place to find (e.g. 'coffee shop', 'hospital')" },
                location: { type: "string", description: "Location to search near. Omit to use current location." },
                radius: { type: "number", description: "Search radius in meters (default 1000)" }
              },
              required: ["query"]
            }
          },

          // ── Image & Vision ──
          {
            name: "generate_image",
            description: "Generate an image from a text prompt using AI.",
            parameters: {
              type: "object",
              properties: {
                prompt: { type: "string", description: "Detailed description of the image to generate" },
                aspectRatio: { type: "string", enum: ["1:1", "16:9", "9:16", "4:3", "3:4"], description: "Image aspect ratio" },
                style: { type: "string", enum: ["photorealistic", "anime", "painting", "digital_art", "sketch"], description: "Visual style" }
              },
              required: ["prompt"]
            }
          },
          {
            name: "analyze_image",
            description: "Analyze an image and describe its contents, extract text, or answer questions about it.",
            parameters: {
              type: "object",
              properties: {
                imageUrl: { type: "string", description: "URL or base64 data URI of the image" },
                task: { type: "string", enum: ["describe", "extract_text", "translate", "summarize", "answer"], description: "What to do with the image" },
                question: { type: "string", description: "Specific question about the image (for 'answer' task)" }
              },
              required: ["imageUrl", "task"]
            }
          },

          // ── Video & Audio ──
          {
            name: "analyze_video",
            description: "Analyze a video to extract key moments, summaries, or highlights.",
            parameters: {
              type: "object",
              properties: {
                videoUrl: { type: "string", description: "URL of the video to analyze" },
                task: { type: "string", enum: ["summarize", "extract_highlights", "transcribe", "describe"], description: "Analysis type" }
              },
              required: ["videoUrl", "task"]
            }
          },
          {
            name: "transcribe_audio",
            description: "Transcribe audio from a file or recording to text.",
            parameters: {
              type: "object",
              properties: {
                audioUrl: { type: "string", description: "URL or base64 of the audio file" },
                language: { type: "string", description: "Language code (e.g. 'en', 'hi'). Auto-detect if omitted." }
              },
              required: ["audioUrl"]
            }
          },

          // ── Communication & Device ──
          {
            name: "send_message",
            description: "Send a message via WhatsApp, SMS, or Email.",
            parameters: {
              type: "object",
              properties: {
                recipient: { type: "string", description: "Recipient phone number or email" },
                message: { type: "string", description: "Message content" },
                platform: { type: "string", enum: ["whatsapp", "sms", "email"], description: "Platform" }
              },
              required: ["recipient", "message", "platform"]
            }
          },
          {
            name: "open_app",
            description: "Open an application on the user's device.",
            parameters: {
              type: "object",
              properties: {
                appName: { type: "string", description: "Name of the app to open" }
              },
              required: ["appName"]
            }
          },
          {
            name: "set_reminder",
            description: "Set a reminder or alarm for the user.",
            parameters: {
              type: "object",
              properties: {
                title: { type: "string", description: "Reminder title" },
                time: { type: "string", description: "Time for the reminder in ISO 8601 or natural language" },
                repeat: { type: "string", enum: ["once", "daily", "weekdays", "weekly"], description: "Repeat frequency" }
              },
              required: ["title", "time"]
            }
          },
          {
            name: "make_call",
            description: "Initiate a phone call to a contact or number.",
            parameters: {
              type: "object",
              properties: {
                contact: { type: "string", description: "Contact name or phone number" }
              },
              required: ["contact"]
            }
          },
          {
            name: "send_email",
            description: "Compose and send an email via Gmail.",
            parameters: {
              type: "object",
              properties: {
                to: { type: "string", description: "Recipient email address" },
                subject: { type: "string", description: "Email subject line" },
                body: { type: "string", description: "Email body content" }
              },
              required: ["to", "subject", "body"]
            }
          },
          {
            name: "summarize_emails",
            description: "Summarize recent unread emails from Gmail inbox.",
            parameters: {
              type: "object",
              properties: {
                maxEmails: { type: "number", description: "Max number of emails to retrieve (default 10)" }
              },
              required: []
            }
          },
          {
            name: "summarize_emails",
            description: "Summarize recent unread emails from Gmail inbox.",
            parameters: {
              type: "object",
              properties: {
                maxEmails: { type: "number", description: "Max number of emails to retrieve (default 10)" }
              },
              required: []
            }
          },
          // ── Calendar ──
          {
            name: "get_calendar_events",
            description: "Get upcoming events from the user's Google Calendar.",
            parameters: {
              type: "object",
              properties: {
                days: { type: "number", description: "Number of days ahead to fetch (default 7)" },
                maxResults: { type: "number", description: "Max events to return (default 10)" }
              },
              required: []
            }
          },
          {
            name: "create_calendar_event",
            description: "Create a new event in the user's Google Calendar.",
            parameters: {
              type: "object",
              properties: {
                title: { type: "string", description: "Event title" },
                start: { type: "string", description: "Start time in ISO 8601 format" },
                end: { type: "string", description: "End time in ISO 8601 format" },
                description: { type: "string", description: "Event description" },
                location: { type: "string", description: "Event location" },
                isAllDay: { type: "boolean", description: "True if all-day event" }
              },
              required: ["title", "start"]
            }
          },
          // ── Navigation ──
          {
            name: "get_directions",
            description: "Get directions or estimated route between two locations.",
            parameters: {
              type: "object",
              properties: {
                origin: { type: "string", description: "Starting location" },
                destination: { type: "string", description: "Destination" },
                mode: { type: "string", enum: ["driving", "walking", "transit", "bicycling"] }
              },
              required: ["origin", "destination"]
            }
          },
          {
            name: "find_nearby_places",
            description: "Find nearby restaurants, hospitals, or places of interest.",
            parameters: {
              type: "object",
              properties: {
                query: { type: "string", description: "Type of place (e.g. 'coffee shop', 'hospital')" },
                location: { type: "string", description: "Search near this location. Omit for current location." },
                radius: { type: "number", description: "Search radius in meters (default 1000)" }
              },
              required: ["query"]
            }
          }
        ]
      }
    ];

    this.model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      systemInstruction: `You are IGRIS (Intelligent General-purpose Robotic Intelligence System), a powerful personal AI agent. 
You assist users with a wide range of tasks: answering questions, generating images, searching the web, getting directions, analyzing photos and videos, setting reminders, and controlling devices.
You have access to tools — use them naturally when the user asks for something that requires real-world data or actions.
Be concise, helpful, and proactive. If the user's request is ambiguous, make a reasonable assumption and proceed.`,
      tools: this.tools
    });

    this.MAX_PROMPT_LENGTH = 8000;
    this.MAX_OUTPUT_TOKENS = 2048;
  }

  /**
   * Process a user prompt (text or multimodal) and return a response.
   */
  async processMultimodalPrompt(content, userContext = {}) {
    try {
      let parts = Array.isArray(content) ? content : [{ text: content }];

      parts = parts.map(part => {
        if (part.text && typeof part.text === 'string') {
          const sanitized = part.text
            .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
            .substring(0, this.MAX_PROMPT_LENGTH);
          return { ...part, text: sanitized };
        }
        return part;
      });

      const apiKeyToUse = userContext.apiKey || process.env.GEMINI_API_KEY_DEFAULT;
      let modelToUse = this.model;

      // If a custom API key is provided, create a temporary model instance
      if (userContext.apiKey && userContext.apiKey !== process.env.GEMINI_API_KEY_DEFAULT) {
        const tempGenAI = new GoogleGenerativeAI(userContext.apiKey);
        modelToUse = tempGenAI.getGenerativeModel({
          model: "gemini-2.0-flash",
          systemInstruction: this.model.systemInstruction,
          tools: this.tools
        });
      }

      const result = await modelToUse.generateContent({
        contents: [{ role: 'user', parts }],
        generationConfig: { maxOutputTokens: this.MAX_OUTPUT_TOKENS }
      });
      const response = await result.response;
      const rawText = response.text();

      const text = typeof rawText === 'string'
        ? rawText.replace(/</g, '&lt;').replace(/>/g, '&gt;')
        : '';

      const toolCalls = response.functionCalls()
        ? response.functionCalls().map(call => ({
            tool: call.name,
            action: 'execute',
            parameters: call.args
          }))
        : [];

      return { text, toolCalls, context: userContext };
    } catch (error) {
      logger.error({ event: 'ai_processing_error', message: error.message });
      throw new Error('AI processing failed. Please try again.');
    }
  }

  async processPrompt(prompt, userContext = {}) {
    return this.processMultimodalPrompt(prompt, userContext);
  }
}

module.exports = new AIService();
