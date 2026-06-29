const express = require('express');
const router = express.Router();
const cron = require('node-cron');
const { authenticateToken } = require('../middleware/auth');
const { Automation } = require('../models');
const logger = require('../utils/logger');
const { validate, schemas } = require('../middleware/validate');
const { aiLimiter } = require('../middleware/rateLimiter');

// In-memory map of active cron jobs: automationId → cronJob
const activeJobs = new Map();

// ── List automations ───────────────────────────────────────────────────────
router.get('/', authenticateToken, async (req, res) => {
  try {
    const items = await Automation.findAll({
      where: { userId: req.userId },
      order: [['createdAt', 'DESC']],
    });
    res.json({ success: true, automations: items });
  } catch (e) {
    logger.error({ event: 'automation_list_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Create automation ──────────────────────────────────────────────────────
router.post('/', authenticateToken, validate(schemas.automations.create), async (req, res) => {
  try {
    const { name, description, triggerType, triggerConfig, actionType, actionConfig } = req.body;

    // Calculate nextRunAt for time-based triggers
    let nextRunAt = null;
    if (triggerType === 'time_based' && triggerConfig?.cronExpr) {
      nextRunAt = getNextCronDate(triggerConfig.cronExpr);
    }

    const automation = await Automation.create({
      userId: req.userId,
      name, description, triggerType, triggerConfig,
      actionType, actionConfig, nextRunAt,
    });

    // Schedule immediately if time-based and active
    if (triggerType === 'time_based' && triggerConfig?.cronExpr && automation.isActive) {
      scheduleAutomation(automation);
    }

    res.status(201).json({ success: true, automation });
  } catch (e) {
    logger.error({ event: 'automation_create_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Update automation ──────────────────────────────────────────────────────
router.put('/:id', authenticateToken, validate(schemas.automations.update), async (req, res) => {
  try {
    const automation = await Automation.findOne({
      where: { id: req.params.id, userId: req.userId },
    });
    if (!automation) return res.status(404).json({ error: 'Automation not found' });

    const { name, description, triggerType, triggerConfig, actionType, actionConfig, isActive } = req.body;
    await automation.update({
      name: name !== undefined ? name : automation.name,
      description: description !== undefined ? description : automation.description,
      triggerType: triggerType !== undefined ? triggerType : automation.triggerType,
      triggerConfig: triggerConfig !== undefined ? triggerConfig : automation.triggerConfig,
      actionType: actionType !== undefined ? actionType : automation.actionType,
      actionConfig: actionConfig !== undefined ? actionConfig : automation.actionConfig,
      isActive: isActive !== undefined ? isActive : automation.isActive,
    });

    // Reschedule
    if (activeJobs.has(automation.id)) {
      activeJobs.get(automation.id).stop();
      activeJobs.delete(automation.id);
    }
    if (automation.isActive && automation.triggerType === 'time_based' && automation.triggerConfig?.cronExpr) {
      scheduleAutomation(automation);
    }

    res.json({ success: true, automation });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Toggle active state ────────────────────────────────────────────────────
router.patch('/:id/toggle', authenticateToken, async (req, res) => {
  try {
    const automation = await Automation.findOne({
      where: { id: req.params.id, userId: req.userId },
    });
    if (!automation) return res.status(404).json({ error: 'Not found' });

    await automation.update({ isActive: !automation.isActive });

    if (!automation.isActive && activeJobs.has(automation.id)) {
      activeJobs.get(automation.id).stop();
      activeJobs.delete(automation.id);
    } else if (automation.isActive && automation.triggerType === 'time_based') {
      scheduleAutomation(automation);
    }

    res.json({ success: true, isActive: automation.isActive });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Run manually ───────────────────────────────────────────────────────────
router.post('/:id/run', authenticateToken, async (req, res) => {
  try {
    const automation = await Automation.findOne({
      where: { id: req.params.id, userId: req.userId },
    });
    if (!automation) return res.status(404).json({ error: 'Not found' });

    const result = await executeAutomationAction(automation);
    await automation.update({
      lastRunAt: new Date(),
      runCount: automation.runCount + 1,
      lastResult: result,
    });

    res.json({ success: true, result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Delete automation ──────────────────────────────────────────────────────
router.delete('/:id', authenticateToken, async (req, res) => {
  try {
    const automation = await Automation.findOne({
      where: { id: req.params.id, userId: req.userId },
    });
    if (!automation) return res.status(404).json({ error: 'Not found' });

    if (activeJobs.has(automation.id)) {
      activeJobs.get(automation.id).stop();
      activeJobs.delete(automation.id);
    }
    await automation.destroy();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Natural language → automation creation (via Gemini) ───────────────────
router.post('/parse', authenticateToken, aiLimiter, async (req, res) => {
  try {
    const { text } = req.body;
    if (!text || typeof text !== 'string') return res.status(400).json({ error: 'text is required and must be a string' });

    const { GoogleGenerativeAI } = require('@google/generative-ai');
    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY_DEFAULT || '');
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

    const prompt = `Parse the following voice command into an automation JSON object.
Return ONLY valid JSON with these fields:
{
  "name": string,
  "description": string,
  "triggerType": "time_based" | "event_based" | "manual",
  "triggerConfig": {
    "cronExpr": string (if time_based, e.g. "0 9 * * 1-5"),
    "timezone": "Asia/Kolkata",
    "event": string (if event_based: "wifi_connected"|"dnd_on"|"app_opened"),
    "runOnce": boolean
  },
  "actionType": "send_message" | "make_call" | "notify" | "run_ai_task" | "set_reminder",
  "actionConfig": {
    "recipient": string,
    "message": string,
    "platform": "whatsapp"|"sms"|"telegram",
    "contact": string,
    "title": string,
    "time": string,
    "prompt": string
  }
}

Voice command: "${text}"`;

    const result = await model.generateContent(prompt);
    const raw = result.response.text().replace(/```json\n?|\n?```/g, '').trim();

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return res.status(422).json({ error: 'Could not parse automation from text', raw });
    }

    res.json({ success: true, automation: parsed });
  } catch (e) {
    logger.error({ event: 'automation_parse_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Helpers ────────────────────────────────────────────────────────────────
function scheduleAutomation(automation) {
  const { cronExpr, timezone = 'Asia/Kolkata' } = automation.triggerConfig || {};
  if (!cronExpr || !cron.validate(cronExpr)) return;

  const job = cron.schedule(cronExpr, async () => {
    try {
      const result = await executeAutomationAction(automation);
      await automation.update({
        lastRunAt: new Date(),
        runCount: automation.runCount + 1,
        lastResult: result,
        nextRunAt: getNextCronDate(cronExpr),
      });
      logger.info(`[Automation] Ran "${automation.name}" → ${result}`);
    } catch (err) {
      logger.error(`[Automation] Error running "${automation.name}": ${err.message}`);
    }
  }, { timezone });

  activeJobs.set(automation.id, job);
  logger.info(`[Automation] Scheduled "${automation.name}" (${cronExpr})`);
}

async function executeAutomationAction(automation) {
  const { actionType, actionConfig } = automation;

  switch (actionType) {
    case 'notify': {
      const dispatcherService = require('../services/dispatcherService');
      await dispatcherService.dispatch(automation.userId, 'automation_trigger', {
        message: actionConfig.message || `Automation "${automation.name}" triggered.`,
      });
      return `Notification sent: ${actionConfig.message}`;
    }

    case 'send_message': {
      const toolsController = require('../controllers/toolsController');
      const result = await toolsController.sendMessage(automation.userId, actionConfig);
      return `Message sent via ${actionConfig.platform}`;
    }

    case 'run_ai_task': {
      const aiService = require('../services/aiService');
      const { User } = require('../models');
      const user = await User.findByPk(automation.userId);

      const response = await aiService.processPrompt(
        actionConfig.prompt || 'What is today?',
        { apiKey: user?.geminiApiKey }
      );

      const dispatcherService = require('../services/dispatcherService');
      await dispatcherService.dispatch(automation.userId, 'ai_result', {
        message: response.text,
      });
      return `AI task completed: ${response.text.substring(0, 100)}...`;
    }

    case 'mark_attendance': {
      const myniatService = require('../services/myniatService');
      const result = await myniatService.markAttendance(automation.userId);
      if (!result.success) throw new Error(result.message);

      const { Attendance } = require('../models');
      await Attendance.create({
        userId: automation.userId,
        subject: 'Automated Portal Mark',
        sessionTime: new Date().toLocaleTimeString(),
        status: 'Present',
        markedAt: new Date()
      });
      return `Attendance marked successfully via MyNiat portal.`;
    }

    case 'set_reminder': {

      return `Reminder set: ${actionConfig.title} at ${actionConfig.time}`;
    }

    default:
      return `Action ${actionType} triggered`;
  }
}

const cronParser = require('cron-parser');

function getNextCronDate(cronExpr) {
  try {
    const interval = cronParser.parseExpression(cronExpr);
    return interval.next().toDate();
  } catch (e) {
    logger.warn(`Failed to parse cron expression "${cronExpr}": ${e.message}`);
    return null;
  }
}

// ── Boot: load active time-based automations ───────────────────────────────
const bootScheduler = async () => {
  try {
    const items = await Automation.findAll({
      where: { isActive: true, triggerType: 'time_based' },
    });
    for (const a of items) { scheduleAutomation(a); }
    logger.info(`[Automation] Booted ${items.length} scheduled automations.`);
  } catch (e) {
    logger.warn(`[Automation] Boot error: ${e.message}`);
  }
};

module.exports = router;
module.exports.bootScheduler = bootScheduler;
