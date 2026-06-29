const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { authenticateToken } = require('../middleware/auth');
const { aiLimiter, uploadLimiter } = require('../middleware/rateLimiter');
const aiService = require('../services/aiService');
const { ToolUsage, User } = require('../models');
const logger = require('../utils/logger');

// Rule #8 — File Upload Security: MIME type + extension whitelist, UUID rename
const ALLOWED_AUDIO_MIMES = ['audio/wav', 'audio/mpeg', 'audio/mp4', 'audio/webm', 'audio/ogg'];
const ALLOWED_AUDIO_EXTS = ['.wav', '.mp3', '.mp4', '.webm', '.ogg', '.m4a'];

const audioStorage = multer.diskStorage({
  destination: 'uploads/voice/',
  filename: (_req, _file, cb) => {
    // Rule #8 — Never use original filename; rename to UUID
    const ext = path.extname(_file.originalname).toLowerCase();
    cb(null, `${uuidv4()}${ext}`);
  }
});

const audioFileFilter = (_req, file, cb) => {
  const ext = path.extname(file.originalname).toLowerCase();
  // Rule #8 — Validate both MIME type AND extension server-side
  if (ALLOWED_AUDIO_MIMES.includes(file.mimetype) && ALLOWED_AUDIO_EXTS.includes(ext)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only audio files (wav, mp3, mp4, webm, ogg) are allowed.'), false);
  }
};

/**
 * @route   GET /api/voice/settings
 * @desc    Get user voice settings
 * @access  Private
 */
router.get('/settings', authenticateToken, async (req, res) => {
  try {
    const { UserSettings } = require('../models');
    const settings = await UserSettings.findOne({ where: { userId: req.userId } });

    res.status(200).json({
      success: true,
      settings: settings ? {
        voiceId: settings.voiceId,
        voiceLanguage: settings.voiceLanguage,
        voiceStyle: settings.voiceStyle,
        voiceEnabled: settings.voiceEnabled,
      } : {
        voiceEnabled: true,
        voiceLanguage: 'en-US',
      }
    });
  } catch (error) {
    logger.error({ event: 'voice_settings_get_error', message: error.message, userId: req.userId });
    res.status(500).json({ error: 'Failed to fetch voice settings' });
  }
});

/**
 * @route   PUT /api/voice/settings
 * @desc    Update user voice settings
 * @access  Private
 */
router.put('/settings', authenticateToken, async (req, res) => {
  try {
    const { z } = require('zod');
    const settingsSchema = z.object({
      voiceId: z.string().max(128).optional(),
      voiceLanguage: z.string().max(10).optional(),
      voiceStyle: z.string().max(64).optional(),
      voiceEnabled: z.boolean().optional(),
    });

    const parsed = settingsSchema.safeParse(req.body);
    if (!parsed.success) {
      const issues = parsed.error.issues || parsed.error.errors || [];
      return res.status(400).json({
        error: 'Validation Error',
        details: issues.map(e => ({ path: e.path[0], message: e.message }))
      });
    }

    const { UserSettings } = require('../models');
    const [updated] = await UserSettings.update(parsed.data, {
      where: { userId: req.userId }
    });

    if (updated === 0) {
      // If settings don't exist, create them
      await UserSettings.create({
        userId: req.userId,
        ...parsed.data
      });
    }

    res.status(200).json({
      message: 'Voice settings updated successfully'
    });
  } catch (error) {
    logger.error({ event: 'voice_settings_update_error', message: error.message, userId: req.userId });
    res.status(500).json({ error: 'Failed to update voice settings' });
  }
});

// Rule #8 — 5MB audio file size limit

const upload = multer({
  storage: audioStorage,
  fileFilter: audioFileFilter,
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB
});

// Helper function to log tool usage
const logToolUsage = async (userId, toolName, action, parameters = {}, result = {}, status = 'success', errorMessage = null, executionTimeMs = null, ipAddress = null, userAgent = null) => {
  try {
    await ToolUsage.create({
      userId,
      toolName,
      action,
      parameters,
      result,
      status,
      errorMessage,
      executionTimeMs,
      ipAddress,
      userAgent
    });
  } catch (error) {
    console.error('Failed to log tool usage:', error);
  }
};

/**
 * @route   POST /api/voice/process
 * @desc    Process voice input (audio file) and return AI response
 * @access  Private — Rate limited: uploadLimiter + aiLimiter
 */
router.post('/process', authenticateToken, uploadLimiter, aiLimiter, upload.single('audio'), async (req, res) => {
  const startTime = Date.now();
  let uploadedFilePath = null;

  try {
    const userId = req.userId;
    if (!req.file) {
      return res.status(400).json({
        error: 'Missing Audio File',
        message: 'Please provide an audio file in the request'
      });
    }

    uploadedFilePath = req.file.path;

    const user = await User.findByPk(userId);
    if (!user || !user.geminiApiKey) {
      return res.status(400).json({
        error: 'Configuration Error',
        message: 'Gemini API key not configured for user'
      });
    }

    // Rule #8 — File already renamed to UUID by multer storage; read safely
    const audioBuffer = fs.readFileSync(uploadedFilePath);
    const base64Audio = audioBuffer.toString('base64');

    const customApiKey = req.headers['x-gemini-api-key'];

    // Rule AI/LLM — Sanitize prompt sent to LLM; max_tokens set in generationConfig
    const aiResponse = await aiService.processMultimodalPrompt([
      {
        inlineData: {
          mimeType: req.file.mimetype,
          data: base64Audio
        }
      },
      { text: 'Please transcribe this audio and respond to the user request concisely.' }
    ], { userId, apiKey: customApiKey });

    // Rule AI/LLM — Sanitize LLM output before sending to client (prevent XSS)
    const sanitizedText = typeof aiResponse.text === 'string'
      ? aiResponse.text.replace(/</g, '&lt;').replace(/>/g, '&gt;')
      : '';

    const result = {
      transcription: 'Audio processed by Gemini',
      response: sanitizedText,
      toolCalls: aiResponse.toolCalls,
      processedAt: new Date().toISOString()
    };

    const executionTimeMs = Date.now() - startTime;

    await logToolUsage(
      userId, 'voice', 'process_voice_input',
      { fileName: req.file.filename },
      { status: 'success' }, // Rule #9 — Don't log full AI output in tool usage
      'success', null, executionTimeMs, req.ip, req.get('User-Agent')
    );

    res.status(200).json({
      message: 'Voice input processed successfully',
      result
    });
  } catch (error) {
    const executionTimeMs = Date.now() - startTime;
    logger.error({ event: 'voice_process_error', message: error.message, userId: req.userId });

    await logToolUsage(
      req.userId || null, 'voice', 'voice_process_error',
      {}, {}, 'error', 'Processing failed', executionTimeMs, req.ip, req.get('User-Agent')
    );

    res.status(500).json({
      error: 'Voice Processing Failed',
      message: 'Something went wrong while processing voice input.'
    });
  } finally {
    // Rule #8 — Clean up temp file after processing
    if (uploadedFilePath && fs.existsSync(uploadedFilePath)) {
      fs.unlink(uploadedFilePath, () => {});
    }
  }
});

/**
 * @route   POST /api/voice/synthesize
 * @desc    Convert text to speech using Murf.ai
 * @access  Private — Rate limited: aiLimiter
 */
router.post('/synthesize', authenticateToken, aiLimiter, async (req, res) => {
  const startTime = Date.now();
  try {
    const userId = req.userId;

    // Rule #3 — Validate and sanitize synthesize input
    const { z } = require('zod');
    const synthesizeSchema = require('../middleware/validate').schemas.voice.synthesize;
    const parsed = synthesizeSchema.safeParse(req.body);
    if (!parsed.success) {
      const issues = parsed.error.issues || parsed.error.errors || [];
      return res.status(400).json({
        error: 'Validation Error',
        details: issues.map(e => ({ path: e.path[0], message: e.message }))
      });
    }

    const { text, voiceId, language, style } = parsed.data;

    const user = await User.findByPk(userId);
    if (!user || !user.murfApiKey) {
      return res.status(400).json({
        error: 'Configuration Error',
        message: 'Murf.ai API key not configured for user'
      });
    }

    const ttsService = require('../services/ttsService');
    const ttsResult = await ttsService.synthesize(text, { voiceId, language, style }, user.murfApiKey);

    const result = {
      audioId: ttsResult.audioId,
      audioUrl: ttsResult.audioUrl,
      generatedAt: new Date().toISOString()
      // Rule AI/LLM — Do not echo back raw user text in the response
    };

    const executionTimeMs = Date.now() - startTime;
    await logToolUsage(userId, 'voice', 'synthesize_speech', {}, result, 'success', null, executionTimeMs, req.ip, req.get('User-Agent'));

    res.status(200).json({
      message: 'Speech synthesized successfully',
      result
    });
  } catch (error) {
    logger.error({ event: 'synthesize_error', message: error.message, userId: req.userId });
    res.status(500).json({ error: 'Speech Synthesis Failed', message: 'Something went wrong during synthesis.' });
  }
});

/**
 * @route   POST /api/voice/wake-word
 * @desc    Detect wake word "Hey IGRIS" in audio
 * @access  Public
 */
router.post('/wake-word', upload.single('audio'), async (req, res) => {
  const startTime = Date.now();
  let uploadedFilePath = null;

  try {
    if (!req.file) {
      return res.status(400).json({
        error: 'Missing Audio File',
        message: 'Please provide an audio file'
      });
    }

    uploadedFilePath = req.file.path;
    const audioBuffer = fs.readFileSync(uploadedFilePath);
    const base64Audio = audioBuffer.toString('base64');

    const customApiKey = req.headers['x-gemini-api-key'];

    // Use Gemini to check for the wake word in the audio
    const aiResponse = await aiService.processMultimodalPrompt([
      {
        inlineData: {
          mimeType: req.file.mimetype,
          data: base64Audio
        }
      },
      { text: 'Did the user say "Hey IGRIS" or "IGRIS" in this audio? Respond with ONLY "YES" or "NO".' }
    ], { apiKey: customApiKey });

    const detected = aiResponse.text.toUpperCase().includes('YES');

    res.status(200).json({
      detected,
      message: detected ? 'Wake word detected!' : 'Wake word not detected'
    });
  } catch (error) {
    logger.error({ event: 'wake_word_error', message: error.message });
    res.status(500).json({
      error: 'Wake Word Detection Failed',
      message: 'Something went wrong while detecting the wake word.'
    });
  } finally {
    if (uploadedFilePath && fs.existsSync(uploadedFilePath)) {
      fs.unlink(uploadedFilePath, () => {});
    }
  }
});

module.exports = router;
