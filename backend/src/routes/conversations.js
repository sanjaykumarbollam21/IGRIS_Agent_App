const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const { Conversation } = require('../models');
const { Op } = require('sequelize');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');

// ── List conversation sessions ─────────────────────────────────────────────
router.get('/sessions', authenticateToken, async (req, res) => {
  try {
    // Get unique sessions with the last message and count
    const sessions = await Conversation.findAll({
      where: { userId: req.userId, role: 'user' },
      attributes: [
        'sessionId',
        [Conversation.sequelize.fn('COUNT', Conversation.sequelize.col('id')), 'messageCount'],
        [Conversation.sequelize.fn('MAX', Conversation.sequelize.col('createdAt')), 'lastMessageAt'],
        [Conversation.sequelize.fn('MIN', Conversation.sequelize.col('content')), 'firstMessage'],
      ],
      group: ['sessionId'],
      order: [[Conversation.sequelize.fn('MAX', Conversation.sequelize.col('createdAt')), 'DESC']],
      limit: 20,
    });
    res.json({ success: true, sessions });
  } catch (e) {
    logger.error({ event: 'conversation_sessions_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Get messages in a session ──────────────────────────────────────────────
router.get('/sessions/:sessionId', authenticateToken, async (req, res) => {
  try {
    const messages = await Conversation.findAll({
      where: { userId: req.userId, sessionId: req.params.sessionId },
      order: [['createdAt', 'ASC']],
      limit: 100,
    });
    res.json({ success: true, messages });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Delete a session ───────────────────────────────────────────────────────
router.delete('/sessions/:sessionId', authenticateToken, async (req, res) => {
  try {
    await Conversation.destroy({
      where: { userId: req.userId, sessionId: req.params.sessionId },
    });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Clear all conversations ────────────────────────────────────────────────
router.delete('/all', authenticateToken, async (req, res) => {
  try {
    const count = await Conversation.destroy({ where: { userId: req.userId } });
    res.json({ success: true, deleted: count });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Get recent memory context (last N messages across sessions) ────────────
router.get('/memory', authenticateToken, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    const messages = await Conversation.findAll({
      where: { userId: req.userId },
      order: [['createdAt', 'DESC']],
      limit,
    });
    res.json({ success: true, messages: messages.reverse() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Helper: save a message to DB ──────────────────────────────────────────
const saveMessage = async (userId, sessionId, role, content, metadata = {}) => {
  try {
    return await Conversation.create({
      userId,
      sessionId,
      role,
      content: typeof content === 'string' ? content : JSON.stringify(content),
      metadata,
      tokenCount: Math.ceil((content?.length || 0) / 4),
    });
  } catch (e) {
    logger.warn(`[Memory] Could not save message: ${e.message}`);
    return null;
  }
};

// ── Helper: load recent context for a session ─────────────────────────────
const loadSessionHistory = async (userId, sessionId, maxMessages = 20) => {
  try {
    const messages = await Conversation.findAll({
      where: { userId, sessionId },
      order: [['createdAt', 'DESC']],
      limit: maxMessages,
    });
    return messages.reverse().map(m => ({
      role: m.role,
      parts: [{ text: m.content }],
    }));
  } catch {
    return [];
  }
};

module.exports = { router, saveMessage, loadSessionHistory };
