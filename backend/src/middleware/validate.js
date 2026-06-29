const { z } = require('zod');
const logger = require('../utils/logger');

/**
 * API Validation Schemas — Rule #3
 * Server-side schema validation using Zod.
 */
const schemas = {
  auth: {
    register: z.object({
      email: z.string().email('Invalid email format').max(256).transform(s => s.toLowerCase().trim()),
      password: z.string().min(8, 'Password must be at least 8 characters').max(128),
      firstName: z.string().min(1, 'First name is required').max(100).trim(),
      lastName: z.string().min(1, 'Last name is required').max(100).trim(),
      phoneNumber: z.string().max(20).optional(),
      dateOfBirth: z.string().optional(),
    }),
    login: z.object({
      login: z.string().min(1, 'Login (email/phone) is required').max(256).optional(),
      email: z.string().email().max(256).optional(),
      password: z.string().min(1, 'Password is required').max(128),
    }),
  },
  users: {
    profile: z.object({
      firstName: z.string().min(1).max(100).trim().optional(),
      lastName: z.string().min(1).max(100).trim().optional(),
      phoneNumber: z.string().max(20).nullable().optional(),
      dateOfBirth: z.string().nullable().optional()
    }),
    apiKeys: z.object({
      geminiApiKey: z.string().max(256).nullable().optional(),
      murfApiKey: z.string().max(256).nullable().optional()
    }),
    myniat: z.object({
      username: z.string().max(100).nullable().optional(),
      password: z.string().max(100).nullable().optional(),
      collegeWifiSsids: z.array(z.string().max(100)).nullable().optional()
    })
  },
  attendance: {
    mark: z.object({
      subject: z.string().min(1, 'Subject is required').max(100).trim(),
      sessionTime: z.string().min(1, 'Session time is required').max(50),
      sessionDate: z.string().optional(),
      status: z.enum(['Present', 'Absent', 'Late']).optional()
    }),
  },
  tools: {
    webSearch: z.object({
      query: z.string().min(1, 'Search query is required').max(500).trim(),
      numResults: z.number().int().min(1).max(10).optional(),
    }),
    sendMessage: z.object({
      platform: z.enum(['whatsapp', 'sms', 'telegram', 'email']),
      recipient: z.string().min(1, 'Recipient is required').max(200).trim(),
      message: z.string().min(1, 'Message content is required').max(4000).trim(),
      messageType: z.string().max(50).optional(),
    }),
  },
  voice: {
    synthesize: z.object({
      text: z.string().min(1, 'Text is required').max(2000).trim(),
      voiceId: z.string().max(100).optional(),
      language: z.string().max(20).optional(),
      style: z.string().max(50).optional(),
    }),
  },
  telegram: {
    linkTokenRequest: z.object({}).strict(),
    completeLinkRequest: z.object({
      token: z.string().min(20, 'Link token is too short').max(2000, 'Link token is too long'),
      telegramUserId: z.number().int().positive('telegramUserId must be a positive integer'),
      chatId: z.number().int().positive('chatId must be a positive integer'),
    }).strict(),
    notify: z.object({
      message: z.string().min(1, 'Message is required').max(4000).trim()
    }),
    broadcast: z.object({
      userIds: z.array(z.string().uuid()).optional(),
      message: z.string().min(1, 'Message is required').max(4000).trim()
    })
  },
  ai: {
    generateImage: z.object({
      prompt: z.string().min(1, 'Prompt is required').max(500).trim(),
      aspectRatio: z.enum(['1:1', '16:9', '9:16', '4:3', '3:4']).optional(),
      style: z.enum(['photorealistic', 'anime', 'painting', 'digital_art', 'sketch']).optional()
    }),
    analyzeImage: z.object({
      imageData: z.string().min(1, 'imageData is required'),
      prompt: z.string().max(1000).optional(),
      mimeType: z.string().max(50).optional()
    }),
    transcribe: z.object({
      audioData: z.string().min(1, 'audioData is required'),
      mimeType: z.string().max(50).optional(),
      language: z.string().max(20).optional()
    }),
    chat: z.object({
      message: z.string().min(1, 'message is required').max(5000),
      sessionId: z.string().max(100).optional(),
      imageData: z.string().optional(),
      mimeType: z.string().max(50).optional()
    }),
    analyzeVideo: z.object({
      videoUrl: z.string().url('Invalid videoUrl').max(1000).optional(),
      videoData: z.string().optional(),
      mimeType: z.string().max(50).optional(),
      task: z.enum(['summarize', 'extract_highlights', 'transcribe', 'describe']).optional()
    })
  },
  knowledge: {
    documents: z.object({
      title: z.string().max(256).optional(),
      content: z.string().max(100000).optional(),
      sourceType: z.string().max(50).optional(),
      sourceUrl: z.string().url('Invalid sourceUrl').max(1000).optional()
    }),
    search: z.object({
      query: z.string().min(1, 'Query is required').max(500).trim(),
      topK: z.number().int().min(1).max(20).optional()
    })
  },
  settings: {
    update: z.object({
      busyModeEnabled: z.boolean().optional(),
      busyModeAutoReply: z.string().max(500).optional(),
      busyModeRejectCalls: z.boolean().optional(),
      busyModeNotifyTelegram: z.boolean().optional(),
      dailyDigestEnabled: z.boolean().optional(),
      weeklyTipEnabled: z.boolean().optional(),
      agentName: z.string().max(100).optional(),
      agentTone: z.string().max(100).optional(),
    }),
    callIntercept: z.object({
      callerName: z.string().max(100).optional(),
      callerNumber: z.string().min(1).max(50)
    }),
    callSummary: z.object({
      userId: z.string().uuid(),
      summary: z.object({
        caller_name: z.string().max(100).nullable().optional(),
        caller_number: z.string().min(1).max(50),
        reason: z.string().min(1).max(1000),
        urgency: z.enum(['low', 'medium', 'high', 'emergency']),
        callback_requested: z.boolean(),
        notes: z.string().max(1000).nullable().optional()
      })
    })
  },
  calendar: {
    createEvent: z.object({
      title: z.string().min(1, 'Title is required').max(256).trim(),
      description: z.string().max(1000).optional(),
      location: z.string().max(256).optional(),
      start: z.string().min(1, 'Start time/date is required').max(100),
      end: z.string().max(100).optional(),
      isAllDay: z.boolean().optional()
    })
  },
  gmail: {
    sendEmail: z.object({
      to: z.string().email('Invalid recipient email').max(256),
      subject: z.string().min(1, 'Subject is required').max(256).trim(),
      body: z.string().min(1, 'Email body is required').max(10000)
    })
  },
  automations: {
    create: z.object({
      name: z.string().min(1, 'Name is required').max(100).trim(),
      description: z.string().max(500).optional(),
      triggerType: z.enum(['time_based', 'event_based', 'manual']),
      triggerConfig: z.object({
        cronExpr: z.string().max(100).optional(),
        timezone: z.string().max(50).optional(),
        event: z.string().max(100).optional(),
        runOnce: z.boolean().optional()
      }).optional(),
      actionType: z.enum(['send_message', 'make_call', 'notify', 'run_ai_task', 'set_reminder', 'mark_attendance']),
      actionConfig: z.object({
        recipient: z.string().max(200).optional(),
        message: z.string().max(4000).optional(),
        platform: z.enum(['whatsapp', 'sms', 'telegram', 'email']).optional(),
        contact: z.string().max(100).optional(),
        title: z.string().max(256).optional(),
        time: z.string().max(50).optional(),
        prompt: z.string().max(2000).optional()
      }).optional(),
      isActive: z.boolean().optional()
    }),
    update: z.object({
      name: z.string().min(1).max(100).trim().optional(),
      description: z.string().max(500).optional(),
      triggerType: z.enum(['time_based', 'event_based', 'manual']).optional(),
      triggerConfig: z.object({
        cronExpr: z.string().max(100).optional(),
        timezone: z.string().max(50).optional(),
        event: z.string().max(100).optional(),
        runOnce: z.boolean().optional()
      }).optional(),
      actionType: z.enum(['send_message', 'make_call', 'notify', 'run_ai_task', 'set_reminder', 'mark_attendance']).optional(),
      actionConfig: z.object({
        recipient: z.string().max(200).optional(),
        message: z.string().max(4000).optional(),
        platform: z.enum(['whatsapp', 'sms', 'telegram', 'email']).optional(),
        contact: z.string().max(100).optional(),
        title: z.string().max(256).optional(),
        time: z.string().max(50).optional(),
        prompt: z.string().max(2000).optional()
      }).optional(),
      isActive: z.boolean().optional()
    })
  }
};

/**
 * Validation Middleware
 * Wraps the request body and validates it against the provided schema
 */
const validate = (schema) => (req, res, next) => {
  if (!schema) {
    logger.error('Validation schema is undefined');
    return res.status(500).json({ error: 'Internal Server Error', message: 'Schema not configured' });
  }
  try {
    const parsed = schema.parse(req.body);
    req.body = parsed; // Use parsed data with sanitizations
    next();
  } catch (error) {
    const issues = error.issues || error.errors;
    if (error && issues) {
      return res.status(400).json({
        error: 'Validation Error',
        details: issues.map(e => ({
          path: e.path.join('.'),
          message: e.message
        }))
      });
    }
    logger.error('Unexpected validation error:', error);
    return res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
};

module.exports = { schemas, validate };
