const express = require('express');
const router = express.Router();
const { ToolUsage, User, Attendance, UserSettings } = require('../models');
const axios = require('axios');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { authenticateToken } = require('../middleware/auth');
const logger = require('../utils/logger');
const { validate, schemas } = require('../middleware/validate');

// ── Helper: send a Telegram message ──────────────────────────────────────────
async function sendTelegramMessage(chatId, text, parseMode = 'HTML') {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) { logger.warn('[Telegram] Bot token not set'); return; }
  try {
    await axios.post(`https://api.telegram.org/bot${token}/sendMessage`, {
      chat_id: chatId, text, parse_mode: parseMode,
    });
  } catch (e) {
    logger.error({ event: 'telegram_send_error', message: e.message });
  }
}

// ── Proactive notification API (called by automations + busy mode) ────────────
// POST /api/telegram/notify  { message }
router.post('/notify', authenticateToken, validate(schemas.telegram.notify), async (req, res) => {
  try {
    const { message } = req.body;

    const user = await User.findByPk(req.userId);
    if (!user?.telegramChatId && !user?.telegramId) {
      return res.status(404).json({ error: 'User has no linked Telegram chat' });
    }

    const chatId = user.telegramChatId || user.telegramId;
    await sendTelegramMessage(chatId, `🤖 <b>IGRIS</b>\n\n${message}`);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Broadcast (admin / system) ────────────────────────────────────────────────
// POST /api/telegram/broadcast  { userIds[], message }
router.post('/broadcast', authenticateToken, validate(schemas.telegram.broadcast), async (req, res) => {
  try {
    const { userIds, message } = req.body;

    if (userIds && userIds.length > 0) {
      const isOnlySelf = userIds.every(id => id === req.userId);
      if (!isOnlySelf) {
        return res.status(403).json({
          error: 'Forbidden',
          message: 'You are only authorized to broadcast to your own linked Telegram chat.'
        });
      }
    }

    const users = await User.findAll({
      where: { id: userIds || [req.userId] },
    });

    let sent = 0;
    for (const u of users) {
      const chatId = u.telegramChatId || u.telegramId;
      if (chatId) { await sendTelegramMessage(chatId, `📢 <b>IGRIS Broadcast</b>\n\n${message}`); sent++; }
    }
    res.json({ success: true, sent });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Webhook (incoming messages from Telegram) ─────────────────────────────────
router.post('/webhook', async (req, res) => {
  res.status(200).send('OK'); // Acknowledge immediately
  try {
    const update = req.body;
    if (!update) return;
    if (update.message) await handleMessage(update.message);
    else if (update.callback_query) await handleCallback(update.callback_query);
  } catch (e) {
    logger.error({ event: 'telegram_webhook_error', message: e.message });
  }
});

// ── Set / Delete webhook ──────────────────────────────────────────────────────
router.get('/set-webhook', authenticateToken, async (req, res) => {
  try {
    const { webhookUrl } = req.query;
    const token = process.env.TELEGRAM_BOT_TOKEN;
    if (!token || !webhookUrl) return res.status(400).json({ error: 'token and webhookUrl required' });
    const r = await axios.post(`https://api.telegram.org/bot${token}/setWebhook`, { url: webhookUrl });
    res.json(r.data);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.get('/delete-webhook', authenticateToken, async (req, res) => {
  try {
    const token = process.env.TELEGRAM_BOT_TOKEN;
    const r = await axios.get(`https://api.telegram.org/bot${token}/deleteWebhook`);
    res.json(r.data);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Message handler ───────────────────────────────────────────────────────────
async function handleMessage(message) {
  const chatId = message.chat.id;
  const telegramUserId = message.from?.id;
  const text = message.text || message.caption || '';

  // Find linked user
  const user = await User.findOne({ where: { telegramId: String(telegramUserId) } });
  if (!user) {
    await sendTelegramMessage(chatId,
      '👋 Welcome! Your Telegram is not linked to IGRIS.\n\nOpen the IGRIS app → Settings → Link Telegram to connect.');
    return;
  }

  // Save linked chat ID for proactive messaging
  if (!user.telegramChatId || user.telegramChatId !== String(chatId)) {
    await user.update({ telegramChatId: String(chatId) });
  }

  // Log interaction
  try {
    await ToolUsage.create({
      userId: user.id, toolName: 'telegram', action: 'receive_message',
      parameters: { chatId, text }, result: { processed: true }, status: 'success',
    });
  } catch (_) {}

  if (text.startsWith('/')) {
    await handleCommand(chatId, user, text);
  } else if (text.trim()) {
    await handleAiMessage(chatId, user, text);
  }
}

// ── Command handler ───────────────────────────────────────────────────────────
async function handleCommand(chatId, user, text) {
  const cmd = text.split(' ')[0].toLowerCase();
  const args = text.substring(cmd.length).trim();

  switch (cmd) {
    case '/start':
      await sendTelegramMessage(chatId,
        `👋 Hello <b>${user.firstName || 'there'}</b>! I'm IGRIS, your personal AI assistant.\n\n` +
        `I can answer questions, check your schedule, manage tasks, and more.\n\n` +
        `Just type anything to start chatting, or use:\n` +
        `/help - Show commands\n/status - System status\n/busy - Toggle busy mode`);
      break;

    case '/help':
      await sendTelegramMessage(chatId,
        '<b>IGRIS Commands:</b>\n' +
        '/start - Welcome message\n' +
        '/help - Show this help\n' +
        '/status - System status\n' +
        '/busy - Toggle busy mode\n' +
        '/attendance - Check attendance\n\n' +
        'Or just <b>chat naturally</b> — IGRIS understands plain English!');
      break;

    case '/status':
      await sendTelegramMessage(chatId,
        `✅ <b>IGRIS System Status</b>\n\nAll systems operational.\nServer time: ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}`);
      break;

    case '/busy': {
      const settings = await UserSettings.findOne({ where: { userId: user.id } });
      const current = settings?.busyModeEnabled ?? false;
      if (settings) await settings.update({ busyModeEnabled: !current });
      await sendTelegramMessage(chatId,
        current ? '✅ Busy Mode <b>disabled</b>. You\'ll receive messages normally.' : '🔴 Busy Mode <b>enabled</b>. Auto-replies are active.');
      break;
    }

    case '/attendance': {
      try {
        const records = await Attendance.findAll({
          where: { userId: user.id }, order: [['sessionDate', 'DESC']], limit: 5,
        });
        if (!records.length) { await sendTelegramMessage(chatId, 'No attendance records found.'); break; }
        const list = records.map(r => `📅 ${r.sessionDate} — ${r.status}`).join('\n');
        await sendTelegramMessage(chatId, `<b>Recent Attendance:</b>\n${list}`);
      } catch (_) { await sendTelegramMessage(chatId, 'Could not fetch attendance.'); }
      break;
    }

    default:
      await sendTelegramMessage(chatId, `Unknown command: <code>${cmd}</code>\nType /help for available commands.`);
  }
}

// ── AI message handler (Gemini) ───────────────────────────────────────────────
async function handleAiMessage(chatId, user, text) {
  const typingToken = process.env.TELEGRAM_BOT_TOKEN;
  // Send typing indicator
  if (typingToken) {
    axios.post(`https://api.telegram.org/bot${typingToken}/sendChatAction`, {
      chat_id: chatId, action: 'typing',
    }).catch(() => {});
  }

  try {
    const apiKey = process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) {
      await sendTelegramMessage(chatId, 'AI is not configured. Add GEMINI_API_KEY_DEFAULT to the server.');
      return;
    }

    const settings = await UserSettings.findOne({ where: { userId: user.id } });
    if (settings?.busyModeEnabled) {
      const autoReply = settings.busyModeAutoReply || "I'm currently busy and will get back to you soon. — IGRIS AI";
      await sendTelegramMessage(chatId, `🔴 <b>Busy Mode Auto-Reply:</b>\n\n${autoReply}`);
      return;
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.0-flash',
      systemInstruction: `You are IGRIS, a personal AI assistant talking to ${user.firstName || 'the user'} via Telegram. Be concise, helpful, and friendly. Keep responses under 4 sentences unless more detail is explicitly requested. Format using plain text — no markdown (Telegram uses HTML).`,
    });

    const result = await model.generateContent(text);
    const reply = result.response.text().trim();
    await sendTelegramMessage(chatId, reply, 'HTML');

    // Log AI usage
    await ToolUsage.create({
      userId: user.id, toolName: 'telegram', action: 'ai_response',
      parameters: { input: text }, result: { output: reply.substring(0, 200) }, status: 'success',
    }).catch(() => {});
  } catch (e) {
    logger.error({ event: 'telegram_ai_error', message: e.message });
    await sendTelegramMessage(chatId, '⚠️ I encountered an error. Please try again.');
  }
}

// ── Callback handler ──────────────────────────────────────────────────────────
async function handleCallback(cb) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (token) {
    await axios.post(`https://api.telegram.org/bot${token}/answerCallbackQuery`, {
      callback_query_id: cb.id, text: 'Processing…',
    }).catch(() => {});
  }
}

// ── Export helper for other routes (automations, busy mode) ──────────────────
module.exports = router;
module.exports.sendTelegramMessage = sendTelegramMessage;