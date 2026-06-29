const cron = require('node-cron');
const { User } = require('../models');
const dispatcherService = require('../services/dispatcherService');
const logger = require('./logger');

/**
 * IGRIS Scheduler — v2.0 (attendance system removed)
 * Handles periodic AI agent maintenance tasks.
 */

// ── Daily AI usage digest ──────────────────────────────────────────────────
const sendDailyDigest = async () => {
  try {
    logger.info('[Scheduler] Generating daily AI usage digests...');
    const users = await User.findAll({
      where: { isActive: true },
      attributes: ['id', 'email', 'firstName', 'telegramId']
    });

    for (const user of users) {
      try {
        const { ToolUsage } = require('../models');
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1);

        const usageCount = await ToolUsage.count({
          where: {
            userId: user.id,
            createdAt: { $gte: today, $lt: tomorrow }
          }
        }).catch(() => 0);

        if (usageCount > 0) {
          await dispatcherService.dispatch(user.id, 'daily_digest', {
            message: `📊 IGRIS Daily Summary: You used ${usageCount} AI tools today. Keep exploring!`
          });
        }
      } catch (userErr) {
        logger.warn(`[Scheduler] Digest skipped for user ${user.id}: ${userErr.message}`);
      }
    }
    logger.info('[Scheduler] Daily digests complete.');
  } catch (err) {
    logger.error(`[Scheduler] sendDailyDigest error: ${err.message}`);
  }
};

// ── Weekly AI tips notification ────────────────────────────────────────────
const sendWeeklyTip = async () => {
  const tips = [
    'Try: "IGRIS, generate an image of a cyberpunk city at night" 🖼️',
    'Try: "IGRIS, search the latest AI news" 🔍',
    'Try: "IGRIS, analyze this photo" 📷 — upload any image!',
    'Try: "IGRIS, get directions to the nearest coffee shop" 🗺️',
    'Try: "IGRIS, transcribe this audio" 🎙️ — hands-free notes!',
    'Tip: Say "Think deeply about..." to activate Gemini\'s reasoning mode 🧠',
  ];
  const tip = tips[new Date().getDate() % tips.length];

  try {
    const users = await User.findAll({
      where: { isActive: true },
      attributes: ['id']
    });
    for (const user of users) {
      await dispatcherService.dispatch(user.id, 'weekly_tip', { message: tip }).catch(() => {});
    }
    logger.info(`[Scheduler] Weekly tip sent: ${tip}`);
  } catch (err) {
    logger.error(`[Scheduler] sendWeeklyTip error: ${err.message}`);
  }
};

// ── Keep-alive ping (prevents cold-start on low-tier hosts) ───────────────
const selfPing = () => {
  const http = require('http');
  const port = process.env.PORT || 8080;
  http.get(`http://localhost:${port}/health`, (res) => {
    logger.debug(`[Scheduler] Self-ping: ${res.statusCode}`);
  }).on('error', () => {});
};

// ── Initialize ────────────────────────────────────────────────────────────
const initializeScheduler = () => {
  logger.info('[Scheduler] Initializing tasks...');

  // Daily AI usage digest at 9 PM IST
  cron.schedule('0 21 * * *', sendDailyDigest, { timezone: 'Asia/Kolkata' });

  // Weekly AI tip every Monday at 9 AM IST
  cron.schedule('0 9 * * 1', sendWeeklyTip, { timezone: 'Asia/Kolkata' });

  // Self-ping every 10 minutes to stay warm
  cron.schedule('*/10 * * * *', selfPing);

  logger.info('[Scheduler] Tasks initialized: daily-digest, weekly-tip, self-ping.');
};

module.exports = { initializeScheduler, initialize: initializeScheduler };