const express = require('express');
const router = express.Router();
const { Attendance } = require('../models');
const { authenticateToken } = require('../middleware/auth');
const { validate, schemas } = require('../middleware/validate');
const logger = require('../utils/logger');
const myniatService = require('../services/myniatService');

// @route   GET /api/attendance/history
// @desc    Get user attendance history
// @access  Private
router.get('/history', authenticateToken, async (req, res) => {
  try {
    const records = await Attendance.findAll({
      where: { userId: req.userId },
      order: [['markedAt', 'DESC']],
      limit: 50
    });
    res.json({ success: true, records });
  } catch (error) {
    logger.error({ event: 'attendance_history_error', message: error.message });
    res.status(500).json({ error: 'Failed to fetch attendance history' });
  }
});

// @route   POST /api/attendance/mark
// @desc    Mark attendance for a session
// @access  Private
router.post('/mark', authenticateToken, validate(schemas.attendance.mark), async (req, res) => {
  try {
    const { subject, sessionTime, sessionDate, status } = req.body;

    if (!subject || !sessionTime) {
      return res.status(400).json({ error: 'Subject and session time are required' });
    }

    const record = await Attendance.create({
      userId: req.userId,
      subject,
      sessionTime,
      sessionDate: sessionDate || new Date(),
      status: status || 'Present',
      markedAt: new Date()
    });

    res.status(201).json({ success: true, record });
  } catch (error) {
    logger.error({ event: 'attendance_mark_error', message: error.message });
    res.status(500).json({ error: 'Failed to mark attendance' });
  }
});

// @route   POST /api/attendance/automate
// @desc    Trigger MyNiat automated attendance marking
// @access  Private
router.post('/automate', authenticateToken, async (req, res) => {
  try {
    const result = await myniatService.markAttendance(req.userId);
    if (result.success) {
      // Also record it in our local DB
      await Attendance.create({
        userId: req.userId,
        subject: 'Automated Portal Mark',
        sessionTime: new Date().toLocaleTimeString(),
        status: 'Present',
        markedAt: new Date()
      });
      res.json({ success: true, message: result.message });
    } else {
      res.status(500).json({ success: false, error: result.message });
    }
  } catch (error) {
    logger.error({ event: 'attendance_automate_error', message: error.message });
    res.status(500).json({ error: 'Automation failed', details: error.message });
  }
});

module.exports = router;
