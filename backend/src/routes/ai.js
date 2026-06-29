const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const { saveMessage, loadSessionHistory } = require('./conversations');
const { aiLimiter } = require('../middleware/rateLimiter');
const { validate, schemas } = require('../middleware/validate');

// ── Image Generation via Pollinations.ai (Free, No API Key) ──────────────────
router.post('/generate-image', authenticateToken, aiLimiter, validate(schemas.ai.generateImage), async (req, res) => {
  try {
    const { prompt, aspectRatio = '1:1', style = 'photorealistic' } = req.body;
    if (!prompt) return res.status(400).json({ error: 'Prompt is required' });

    // Style → enhanced prompt suffix
    const styleMap = {
      photorealistic: 'photorealistic, highly detailed, professional photography, 8k',
      anime: 'anime style, manga art, vibrant colors, studio quality',
      painting: 'oil painting, artistic brushstrokes, fine art, masterpiece',
      digital_art: 'digital art, concept art, vibrant, highly detailed, artstation',
      sketch: 'pencil sketch, hand-drawn, detailed linework, black and white',
    };
    const enhancedPrompt = `${prompt}, ${styleMap[style] || styleMap.photorealistic}`;

    // Aspect ratio → dimensions
    const sizeMap = {
      '1:1':  { width: 1024, height: 1024 },
      '16:9': { width: 1280, height: 720  },
      '9:16': { width: 720,  height: 1280 },
      '4:3':  { width: 1024, height: 768  },
      '3:4':  { width: 768,  height: 1024 },
    };
    const { width, height } = sizeMap[aspectRatio] || sizeMap['1:1'];

    // Pollinations.ai — 100% free, no key needed
    const encodedPrompt = encodeURIComponent(enhancedPrompt.substring(0, Math.min(enhancedPrompt.length, 300)));
    const seed = Math.floor(Math.random() * 999999);
    const imageUrl = `https://image.pollinations.ai/prompt/${encodedPrompt}?width=${width}&height=${height}&seed=${seed}&model=flux`;

    logger.info({ event: 'image_gen_start', prompt: prompt.substring(0, 60), style, aspectRatio });

    const https = require('https');
    const imageBytes = await new Promise((resolve, reject) => {
      https.get(imageUrl, (response) => {
        if (response.statusCode !== 200) {
          reject(new Error(`Pollinations returned ${response.statusCode}`));
          return;
        }
        const chunks = [];
        response.on('data', chunk => chunks.push(chunk));
        response.on('end', () => resolve(Buffer.concat(chunks)));
        response.on('error', reject);
      }).on('error', reject);
    });

    const imageData = imageBytes.toString('base64');
    logger.info({ event: 'image_gen_success', bytes: imageBytes.length });

    res.json({ success: true, imageData, mimeType: 'image/jpeg', prompt: enhancedPrompt });
  } catch (error) {
    logger.error({ event: 'image_gen_error', message: error.message });
    res.status(500).json({ error: 'Image generation failed', message: error.message });
  }
});

// ── Image Analysis via Gemini Vision ─────────────────────────────────────────
router.post('/analyze-image', authenticateToken, aiLimiter, validate(schemas.ai.analyzeImage), async (req, res) => {
  try {
    const { imageData, prompt = 'Describe this image in detail.', mimeType = 'image/jpeg' } = req.body;
    if (!imageData) return res.status(400).json({ error: 'imageData is required' });

    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) return res.status(503).json({ error: 'Gemini API key not configured' });

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const result = await model.generateContent([
      { text: prompt },
      { inlineData: { data: imageData, mimeType } },
    ]);

    const text = result.response.text();
    res.json({ success: true, analysis: text });
  } catch (error) {
    logger.error({ event: 'image_analysis_error', message: error.message });
    res.status(500).json({ error: 'Image analysis failed', message: error.message });
  }
});

// ── Audio Transcription via Gemini ────────────────────────────────────────────
router.post('/transcribe', authenticateToken, aiLimiter, validate(schemas.ai.transcribe), async (req, res) => {
  try {
    const { audioData, mimeType = 'audio/m4a', language } = req.body;
    if (!audioData) return res.status(400).json({ error: 'audioData is required' });

    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) return res.status(503).json({ error: 'Gemini API key not configured' });

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const langInstruction = language ? `The audio is in ${language}. ` : '';
    const result = await model.generateContent([
      { text: `${langInstruction}Transcribe the following audio accurately. Return only the transcription text, no commentary.` },
      { inlineData: { data: audioData, mimeType } },
    ]);

    const transcription = result.response.text();
    res.json({ success: true, transcription });
  } catch (error) {
    logger.error({ event: 'transcription_error', message: error.message });
    res.status(500).json({ error: 'Transcription failed', message: error.message });
  }
});

// ── Agentic Chat with LangChain + Tool Calling + RAG ─────────────────────────
router.post('/chat', authenticateToken, aiLimiter, validate(schemas.ai.chat), async (req, res) => {
  try {
    const { message, sessionId: clientSessionId, imageData, mimeType } = req.body;
    if (!message) return res.status(400).json({ error: 'message is required' });

    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) return res.status(503).json({ error: 'Gemini API key not configured' });

    // Use provided session or create a new one
    const sessionId = clientSessionId || uuidv4();

    // Route through Multi-Agent Router
    const agentRouter = require('../agents/AgentRouter');
    const result = await agentRouter.route(message, req.userId, sessionId, {
      apiKey,
      imageData,
      mimeType,
    });

    res.json({
      success: true,
      response: result.response,
      sessionId,
      toolResults: result.toolResults || [],
      ragSources: result.ragSources || null,
      iterations: result.iterations || 0,
    });
  } catch (error) {
    logger.error({ event: 'chat_error', message: error.message });
    res.status(500).json({ error: 'Chat failed', message: error.message });
  }
});


// ── Video Analysis via Gemini ─────────────────────────────────────────────────
router.post('/analyze-video', authenticateToken, aiLimiter, validate(schemas.ai.analyzeVideo), async (req, res) => {
  try {
    const { videoUrl, videoData, mimeType = 'video/mp4', task = 'summarize' } = req.body;
    if (!videoUrl && !videoData) {
      return res.status(400).json({ error: 'videoUrl or videoData is required' });
    }

    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) return res.status(503).json({ error: 'Gemini API key not configured' });

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const taskPrompts = {
      summarize: 'Provide a clear, structured summary of this video. Include the main topic, key points, and conclusion.',
      extract_highlights: 'Extract the key moments and highlights from this video. Format as a timestamped list if possible.',
      transcribe: 'Transcribe all spoken content in this video accurately.',
      describe: 'Describe this video in detail: what is shown, any text visible, context, and mood.',
    };
    const prompt = taskPrompts[task] || taskPrompts.summarize;

    let contentParts;
    if (videoUrl) {
      // Use file URI for YouTube/hosted videos via Gemini Files API
      contentParts = [
        { text: prompt },
        { fileData: { mimeType: 'video/mp4', fileUri: videoUrl } },
      ];
    } else {
      contentParts = [
        { text: prompt },
        { inlineData: { data: videoData, mimeType } },
      ];
    }

    const result = await model.generateContent(contentParts);
    const analysis = result.response.text();
    res.json({ success: true, analysis, task });
  } catch (error) {
    logger.error({ event: 'video_analysis_error', message: error.message });
    res.status(500).json({ error: 'Video analysis failed', message: error.message });
  }
});

module.exports = router;

