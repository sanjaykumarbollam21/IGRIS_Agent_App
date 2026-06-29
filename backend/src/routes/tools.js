const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const toolsController = require('../controllers/toolsController');
const notificationService = require('../services/notificationService');

/**
 * @route   POST /api/tools/web-search
 * @desc    Perform a web search
 * @access  Private
 */
router.post('/web-search', authenticateToken, async (req, res) => {
  try {
    const { query } = req.body;
    if (!query) return res.status(400).json({ error: 'Query is required' });

    const customApiKey = req.headers['x-gemini-api-key'];
    const result = await toolsController.webSearch(req.userId, query, customApiKey);
    res.status(200).json({ message: 'Search successful', result });
  } catch (error) {
    res.status(500).json({ error: 'Search Failed', message: error.message });
  }
});

/**
 * @route   POST /api/tools/send-message
 * @desc    Send a message (WhatsApp/SMS/Email)
 * @access  Private
 */
router.post('/send-message', authenticateToken, async (req, res) => {
  try {
    const params = req.body;
    if (!params.recipient || !params.message) {
      return res.status(400).json({ error: 'Recipient and message are required' });
    }

    const result = await toolsController.sendMessage(req.userId, params);
    res.status(200).json({ message: 'Message sent successfully', result });
  } catch (error) {
    res.status(500).json({ error: 'Messaging Failed', message: error.message });
  }
});

/**
 * @route   POST /api/tools/open-app
 * @desc    Open an application on the device (Bridges to Desktop/Mobile)
 * @access  Private
 */
router.post('/open-app', authenticateToken, async (req, res) => {
  try {
    const { appName, appIdentifier, platform } = req.body;
    if (!appName || !appIdentifier) {
      return res.status(400).json({ error: 'App name and identifier are required' });
    }

    // This will be picked up by the Desktop/Mobile app via Socket.io or push
    const userId = req.userId;

    // Emit command to the user's connected devices via the notification service
    notificationService.notifyUser(userId, 'device_command', {
      command: 'open_app',
      payload: {
        appName,
        appIdentifier,
        platform: platform || 'unknown',
        timestamp: new Date().toISOString()
      }
    });

    const result = {
      action: 'app_opened',
      appName,
      appIdentifier,
      platform: platform || 'unknown',
      timestamp: new Date().toISOString()
    };

    res.status(200).json({ message: 'App open request sent', result });
  } catch (error) {
    res.status(500).json({ error: 'App Control Failed', message: error.message });
  }
});

/**
 * @route   POST /api/tools/file-operation
 * @desc    Perform file operations (Bridges to Desktop App)
 * @access  Private
 */
router.post('/file-operation', authenticateToken, async (req, res) => {
  try {
    const { operation, filePath, content } = req.body;
    if (!operation || !filePath) {
      return res.status(400).json({ error: 'Operation and path are required' });
    }

    const userId = req.userId;

    // Emit command to the user's connected devices via the notification service
    notificationService.notifyUser(userId, 'device_command', {
      command: 'file_operation',
      payload: {
        operation,
        filePath,
        content,
        timestamp: new Date().toISOString()
      }
    });

    const result = {
      operation,
      filePath,
      status: 'requested',
      timestamp: new Date().toISOString()
    };

    res.status(200).json({ message: 'File operation request sent', result });
  } catch (error) {
    res.status(500).json({ error: 'File Operation Failed', message: error.message });
  }
});

module.exports = router;
