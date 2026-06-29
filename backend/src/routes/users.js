const express = require('express');
const router = express.Router();
const { User } = require('../models');
const { Sequelize } = require('sequelize');
const { authenticateToken } = require('../middleware/auth');
const { validate, schemas } = require('../middleware/validate');

// Apply auth middleware to all user routes
router.use(authenticateToken);

// @route   PUT /api/users/profile
// @desc    Update user profile
// @access  Private
router.put('/profile', validate(schemas.users.profile), async (req, res) => {
  try {
    const { firstName, lastName, phoneNumber, dateOfBirth } = req.body;
    const userId = req.userId; // From auth middleware

    // Update user profile
    const updatedUser = await User.update(
      {
        firstName: firstName || undefined,
        lastName: lastName || undefined,
        phoneNumber: phoneNumber || null,
        dateOfBirth: dateOfBirth || null
      },
      {
        where: { id: userId },
        returning: true
      }
    );

    if (updatedUser[0] === 0) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'User not found'
      });
    }

    const user = await User.findByPk(userId, {
      attributes: { exclude: ['password', 'geminiApiKey', 'murfApiKey', 'myniatPassword'] }
    });

    res.status(200).json({
      message: 'Profile updated successfully',
      user: user.toJSON()
    });
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({
      error: 'Update Failed',
      message: 'Failed to update profile'
    });
  }
});

// @route   PUT /api/users/api-keys
// @desc    Update user API keys (Gemini, Murf.ai)
// @access  Private
router.put('/api-keys', validate(schemas.users.apiKeys), async (req, res) => {
  try {
    const { geminiApiKey, murfApiKey } = req.body;
    const userId = req.userId; // From auth middleware

    // Update user API keys
    const updatedUser = await User.update(
      {
        geminiApiKey: geminiApiKey || null,
        murfApiKey: murfApiKey || null
      },
      {
        where: { id: userId },
        returning: true
      }
    );

    if (updatedUser[0] === 0) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'User not found'
      });
    }

    const user = await User.findByPk(userId, {
      attributes: { exclude: ['password', 'geminiApiKey', 'murfApiKey', 'myniatPassword'] }
    });

    res.status(200).json({
      message: 'API keys updated successfully',
      user: user.toJSON()
    });
  } catch (error) {
    console.error('Update API keys error:', error);
    res.status(500).json({
      error: 'Update Failed',
      message: 'Failed to update API keys'
    });
  }
});

// @route   PUT /api/users/myniat
// @desc    Update user MyNiat credentials
// @access  Private
router.put('/myniat', validate(schemas.users.myniat), async (req, res) => {
  try {
    const { username, password, collegeWifiSsids } = req.body;
    const userId = req.userId; // From auth middleware

    // Update user MyNiat credentials
    const updatedUser = await User.update(
      {
        myniatUsername: username || null,
        myniatPassword: password || null,
        collegeWifiSsids: collegeWifiSsids ? JSON.stringify(collegeWifiSsids) : null
      },
      {
        where: { id: userId },
        returning: true
      }
    );

    if (updatedUser[0] === 0) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'User not found'
      });
    }

    const user = await User.findByPk(userId, {
      attributes: { exclude: ['password', 'geminiApiKey', 'murfApiKey', 'myniatPassword'] }
    });

    res.status(200).json({
      message: 'MyNiat credentials updated successfully',
      user: user.toJSON()
    });
  } catch (error) {
    console.error('Update MyNiat error:', error);
    res.status(500).json({
      error: 'Update Failed',
      message: 'Failed to update MyNiat credentials'
    });
  }
});

// @route   GET /api/users/dashboard
// @desc    Get user dashboard data
// @access  Private
router.get('/dashboard', async (req, res) => {
  try {
    const userId = req.userId; // From auth middleware

    // Get user data
    const user = await User.findByPk(userId, {
      attributes: { exclude: ['password', 'geminiApiKey', 'murfApiKey', 'myniatPassword'] }
    });

    if (!user) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'User not found'
      });
    }

    res.status(200).json({
      user: user.toJSON()
    });
  } catch (error) {
    console.error('Dashboard error:', error);
    res.status(500).json({
      error: 'Dashboard Fetch Failed',
      message: 'Failed to fetch dashboard data'
    });
  }
});

module.exports = router;