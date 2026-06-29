const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const { UserSettings, User } = require('../models');
const toolsController = require('../controllers/toolsController');
const logger = require('../utils/logger');
const { validate, schemas } = require('../middleware/validate');

// ── Get current settings / Busy Mode state ────────────────────────────────
router.get('/', authenticateToken, async (req, res) => {
  try {
    const [settings] = await UserSettings.findOrCreate({
      where: { userId: req.userId },
      defaults: { userId: req.userId },
    });
    res.json({ success: true, settings });
  } catch (e) {
    logger.error({ event: 'settings_get_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Update settings ────────────────────────────────────────────────────────
router.put('/', authenticateToken, validate(schemas.settings.update), async (req, res) => {
  try {
    const allowed = [
      'busyModeEnabled', 'busyModeAutoReply', 'busyModeRejectCalls',
      'busyModeNotifyTelegram', 'dailyDigestEnabled', 'weeklyTipEnabled',
      'agentName', 'agentTone',
    ];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => allowed.includes(k))
    );

    const [settings] = await UserSettings.findOrCreate({
      where: { userId: req.userId },
      defaults: { userId: req.userId },
    });
    await settings.update(updates);

    // If Busy Mode just turned ON, notify via Telegram if configured
    if (updates.busyModeEnabled === true && settings.busyModeNotifyTelegram) {
      try {
        const dispatcherService = require('../services/dispatcherService');
        await dispatcherService.dispatch(req.userId, 'busy_mode_on', {
          message: '🔴 Busy Mode activated. IGRIS will handle incoming messages.',
        });
      } catch (_) {}
    }
    if (updates.busyModeEnabled === false && settings.busyModeNotifyTelegram) {
      try {
        const dispatcherService = require('../services/dispatcherService');
        await dispatcherService.dispatch(req.userId, 'busy_mode_off', {
          message: '🟢 Busy Mode deactivated. Welcome back!',
        });
      } catch (_) {}
    }

    res.json({ success: true, settings });
  } catch (e) {
    logger.error({ event: 'settings_update_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Toggle Busy Mode (convenience endpoint) ────────────────────────────────
router.post('/busy-mode/toggle', authenticateToken, async (req, res) => {
  try {
    const [settings] = await UserSettings.findOrCreate({
      where: { userId: req.userId },
      defaults: { userId: req.userId },
    });
    const newState = !settings.busyModeEnabled;
    await settings.update({ busyModeEnabled: newState });

    try {
      const dispatcherService = require('../services/dispatcherService');
      await dispatcherService.dispatch(req.userId, newState ? 'busy_mode_on' : 'busy_mode_off', {
        message: newState
          ? '🔴 Busy Mode ON — IGRIS is handling your messages.'
          : '🟢 Busy Mode OFF — You\'re back online.',
      });
    } catch (_) {}

    res.json({ success: true, busyModeEnabled: newState });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Incoming call while in Busy Mode (AI Call Assistant) ─────────────────────────
router.post('/busy-mode/call-intercept', authenticateToken, validate(schemas.settings.callIntercept), async (req, res) => {
  try {
    const { callerName, callerNumber } = req.body;
    const settings = await UserSettings.findOne({ where: { userId: req.userId } });

    if (!settings?.busyModeEnabled) {
      return res.json({ handled: false, reason: 'Busy mode not active' });
    }

    const busyModeAIService = require('../services/busyModeAIService');
    const systemPrompt = await busyModeAIService.generateSystemPrompt(req.userId, {
      callerName,
      callerNumber,
    });

    // In a real scenario, we would now trigger the external Voice AI provider (Vapi, Retell, etc.)
    // and tell them to use this systemPrompt for the duration of the call.
    logger.info(`[BusyMode] Routing call from ${callerNumber} to AI Assistant for user ${req.userId}`);

    res.json({
      handled: true,
      action: 'route_to_ai',
      systemPrompt
    });
  } catch (e) {
    logger.error(`[BusyMode] call-intercept error: ${e.message}`);
    res.status(500).json({ error: e.message });
  }
});

const verifyWebhookSignature = (req, res, next) => {
  const signature = req.headers['x-webhook-signature'];
  if (process.env.WEBHOOK_SECRET && signature !== process.env.WEBHOOK_SECRET) {
    logger.warn({ event: 'call_summary_webhook_unauthorized', signature });
    return res.status(401).json({ error: 'Unauthorized', message: 'Invalid webhook signature' });
  }
  next();
};

// ── Webhook for AI Call Summary ───────────────────────────────────────────────────
router.post('/busy-mode/call-summary', verifyWebhookSignature, validate(schemas.settings.callSummary), async (req, res) => {
  try {
    const { userId, summary } = req.body;
    const busyModeAIService = require('../services/busyModeAIService');
    await busyModeAIService.handleCallSummary(userId, summary);

    res.json({ success: true });
  } catch (e) {
    logger.error(`[BusyMode] call-summary error: ${e.message}`);
    res.status(500).json({ error: e.message });
  }
});

// ── Get Call Summaries ──────────────────────────────────────────────────────────
router.get('/busy-mode/summaries', authenticateToken, async (req, res) => {
  try {
    const { CallSummary } = require('../models');
    const summaries = await CallSummary.findAll({
      where: { userId: req.userId },
      order: [['createdAt', 'DESC']],
      limit: 50
    });
    res.json({ success: true, summaries });
  } catch (e) {
    logger.error(`[BusyMode] summaries error: ${e.message}`);
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
