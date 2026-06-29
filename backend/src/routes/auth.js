const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const { z } = require('zod');
const authConfig = require('../config/auth');
const { User } = require('../models');
const { authLimiter } = require('../middleware/rateLimiter');
const { authenticateToken } = require('../middleware/auth');
const logger = require('../utils/logger');

// Zod schema for registration
const registerSchema = z.object({
  email: z.string().email('Invalid email format').max(256).transform(s => s.toLowerCase().trim()),
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
  firstName: z.string().min(1, 'First name is required').max(100).trim(),
  lastName: z.string().min(1, 'Last name is required').max(100).trim(),
  phoneNumber: z.string().max(20).optional(),
  dateOfBirth: z.string().optional()
});

// @route   POST /api/auth/register
// @desc    Register a new user (with email verification enabled)
// @access  Public — Rate limited
router.post('/register', authLimiter, async (req, res) => {
  try {
    const parsed = registerSchema.safeParse(req.body);
    if (!parsed.success) {
      const issues = parsed.error.issues || parsed.error.errors || [];
      return res.status(400).json({
        error: 'Validation Error',
        details: issues.map(e => ({ path: e.path[0], message: e.message }))
      });
    }

    const { email, password, firstName, lastName, phoneNumber, dateOfBirth } = parsed.data;

    // Check if user already exists
    const existingUser = await User.findOne({ where: { email } });
    if (existingUser) {
      return res.status(409).json({
        error: 'Conflict',
        message: 'User with this email already exists'
      });
    }

    // Generate email verification token (expires in 24 hours)
    const verificationToken = crypto.randomBytes(32).toString('hex');
    const verificationTokenExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    // Create user (password is hashed in hook with 12 rounds)
    const user = await User.create({
      email,
      password,
      firstName,
      lastName,
      phoneNumber: phoneNumber || null,
      dateOfBirth: dateOfBirth || null,
      isEmailVerified: false,
      emailVerificationToken: verificationToken,
      emailVerificationTokenExpiresAt: verificationTokenExpiresAt
    });

    // Simulate sending email verification link by logging it
    const verificationLink = `${req.protocol}://${req.get('host') || 'localhost:8080'}/api/auth/verify-email?token=${verificationToken}`;
    logger.info(`[Auth] Email verification link generated for user: ${email} -> ${verificationLink}`);

    const userJson = user.toJSON();
    delete userJson.password;
    delete userJson.geminiApiKey;
    delete userJson.murfApiKey;
    delete userJson.myniatPassword;

    res.status(201).json({
      message: 'Registration successful. Please check your email to verify your account.',
      user: userJson
    });
  } catch (error) {
    logger.error({ event: 'register_error', message: error.message });
    res.status(500).json({
      error: 'Registration Failed',
      message: 'Something went wrong. Please try again.'
    });
  }
});

// Zod schema for login
const loginSchema = z.object({
  login: z.string().min(1).max(256).optional(),
  email: z.string().email().max(256).optional(),
  password: z.string().min(1).max(128)
});

// @route   POST /api/auth/login
// @desc    Login user, returning access and refresh tokens (requires verification)
// @access  Public — Rate limited
router.post('/login', authLimiter, async (req, res) => {
  try {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      const issues = parsed.error.issues || parsed.error.errors || [];
      return res.status(400).json({
        error: 'Validation Error',
        details: issues.map(e => ({ path: e.path[0], message: e.message }))
      });
    }

    const { login, email, password } = parsed.data;
    const loginValue = login || email;

    if (!loginValue) {
      return res.status(400).json({
        error: 'Validation Error',
        message: 'Login (email/phone) and password are required'
      });
    }

    const user = await User.findByLogin(loginValue);
    if (!user) {
      return res.status(401).json({
        error: 'Authentication Failed',
        message: 'Invalid credentials'
      });
    }

    // Check if password matches
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({
        error: 'Authentication Failed',
        message: 'Invalid credentials'
      });
    }

    // Enforce email verification
    if (!user.isEmailVerified) {
      logger.warn({ event: 'login_blocked_unverified', email: user.email });
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Email not verified. Please verify your email before logging in.'
      });
    }

    // Generate tokens
    const token = jwt.sign(
      { userId: user.id },
      authConfig.jwtSecret,
      { expiresIn: authConfig.jwtExpiresIn }
    );

    const refreshToken = jwt.sign(
      { userId: user.id },
      authConfig.refreshTokenSecret,
      { expiresIn: authConfig.refreshTokenExpiresIn }
    );

    await user.update({ lastLoginAt: new Date() });

    const userJson = user.toJSON();
    delete userJson.password;
    delete userJson.geminiApiKey;
    delete userJson.murfApiKey;
    delete userJson.myniatPassword;

    res.status(200).json({
      message: 'Login successful',
      user: userJson,
      token,
      refreshToken
    });
  } catch (error) {
    logger.error({ event: 'login_error', message: error.message });
    res.status(500).json({
      error: 'Login Failed',
      message: 'Something went wrong. Please try again.'
    });
  }
});

// @route   GET /api/auth/verify-email
// @desc    Verify user's email using a token
// @access  Public — Rate limited
router.get('/verify-email', authLimiter, async (req, res) => {
  try {
    const { token } = req.query;
    if (!token) {
      return res.status(400).json({ error: 'Validation Error', message: 'Verification token is required' });
    }

    const user = await User.findOne({
      where: {
        emailVerificationToken: token,
        emailVerificationTokenExpiresAt: { [require('sequelize').Op.gt]: new Date() }
      }
    });

    if (!user) {
      logger.warn({ event: 'verify_email_invalid_token', token });
      return res.status(400).json({
        error: 'Invalid Token',
        message: 'Invalid or expired email verification token.'
      });
    }

    await user.update({
      isEmailVerified: true,
      emailVerificationToken: null,
      emailVerificationTokenExpiresAt: null
    });

    logger.info({ event: 'email_verified', email: user.email });

    res.send(`<html><body><h2>✅ Email verified successfully!</h2><p>You can now log in to your account.</p></body></html>`);
  } catch (error) {
    logger.error({ event: 'verify_email_error', message: error.message });
    res.status(500).json({ error: 'Verification Failed', message: 'Failed to verify email' });
  }
});

// @route   POST /api/auth/resend-verification
// @desc    Resend verification email
// @access  Public — Rate limited
router.post('/resend-verification', authLimiter, async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Validation Error', message: 'Email is required' });
    }

    const user = await User.findOne({ where: { email: email.toLowerCase().trim() } });
    if (!user) {
      // Return 200 anyway to prevent user enumeration
      return res.status(200).json({
        message: 'If the account exists, a verification link has been sent.'
      });
    }

    if (user.isEmailVerified) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Email is already verified.'
      });
    }

    const verificationToken = crypto.randomBytes(32).toString('hex');
    const verificationTokenExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    await user.update({
      emailVerificationToken: verificationToken,
      emailVerificationTokenExpiresAt: verificationTokenExpiresAt
    });

    const verificationLink = `${req.protocol}://${req.get('host') || 'localhost:8080'}/api/auth/verify-email?token=${verificationToken}`;
    logger.info(`[Auth] Email verification link regenerated for user: ${email} -> ${verificationLink}`);

    res.status(200).json({
      message: 'If the account exists, a verification link has been sent.'
    });
  } catch (error) {
    logger.error({ event: 'resend_verification_error', message: error.message });
    res.status(500).json({ error: 'Resend Failed', message: 'Failed to resend verification link' });
  }
});

// @route   POST /api/auth/forgot-password
// @desc    Initiate password reset flow
// @access  Public — Rate limited
router.post('/forgot-password', authLimiter, async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Validation Error', message: 'Email is required' });
    }

    const user = await User.findOne({ where: { email: email.toLowerCase().trim() } });
    if (!user) {
      // Prevent user enumeration by returning a generic message
      return res.status(200).json({
        message: 'If the account exists, a password reset link has been sent.'
      });
    }

    // Generate reset token (expires in 1 hour)
    const resetToken = crypto.randomBytes(32).toString('hex');
    const resetTokenExpiresAt = new Date(Date.now() + 60 * 60 * 1000);

    await user.update({
      passwordResetToken: resetToken,
      passwordResetTokenExpiresAt: resetTokenExpiresAt
    });

    // Log the simulated link
    const resetLink = `${req.protocol}://${req.get('host') || 'localhost:8080'}/api/auth/reset-password?token=${resetToken}`;
    logger.info(`[Auth] Password reset link generated for: ${email} -> ${resetLink}`);

    res.status(200).json({
      message: 'If the account exists, a password reset link has been sent.'
    });
  } catch (error) {
    logger.error({ event: 'forgot_password_error', message: error.message });
    res.status(500).json({ error: 'Forgot Password Failed', message: 'Failed to request password reset' });
  }
});

// @route   POST /api/auth/reset-password
// @desc    Complete password reset
// @access  Public — Rate limited
router.post('/reset-password', authLimiter, async (req, res) => {
  try {
    const { token, password } = req.body;
    if (!token || !password) {
      return res.status(400).json({ error: 'Validation Error', message: 'Token and new password are required' });
    }

    if (password.length < 8) {
      return res.status(400).json({ error: 'Validation Error', message: 'Password must be at least 8 characters long' });
    }

    const user = await User.findOne({
      where: {
        passwordResetToken: token,
        passwordResetTokenExpiresAt: { [require('sequelize').Op.gt]: new Date() }
      }
    });

    if (!user) {
      logger.warn({ event: 'reset_password_invalid_token', token });
      return res.status(400).json({
        error: 'Invalid Token',
        message: 'Invalid or expired password reset token.'
      });
    }

    // Update password (hashing happens automatically in User model update hook)
    await user.update({
      password,
      passwordResetToken: null,
      passwordResetTokenExpiresAt: null
    });

    logger.info({ event: 'password_reset_success', email: user.email });

    res.status(200).json({
      message: 'Password reset successful. You can now log in with your new password.'
    });
  } catch (error) {
    logger.error({ event: 'reset_password_error', message: error.message });
    res.status(500).json({ error: 'Reset Password Failed', message: 'Failed to reset password' });
  }
});

// @route   POST /api/auth/refresh-token
// @desc    Refresh access token using refresh token
// @access  Public
router.post('/refresh-token', async (req, res) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({
        error: 'Validation Error',
        message: 'Refresh token is required'
      });
    }

    try {
      const decoded = jwt.verify(refreshToken, authConfig.refreshTokenSecret);
      const userId = decoded.userId;

      // Check if user exists
      const user = await User.findByPk(userId);
      if (!user) {
        return res.status(401).json({
          error: 'Authentication Failed',
          message: 'Invalid refresh token'
        });
      }

      // Generate new access token
      const token = jwt.sign(
        { userId: user.id },
        authConfig.jwtSecret,
        { expiresIn: authConfig.jwtExpiresIn }
      );

      // Generate new refresh token
      const newRefreshToken = jwt.sign(
        { userId: user.id },
        authConfig.refreshTokenSecret,
        { expiresIn: authConfig.refreshTokenExpiresIn }
      );

      res.status(200).json({
        message: 'Token refreshed successfully',
        token,
        refreshToken: newRefreshToken
      });
    } catch (error) {
      if (error.name === 'TokenExpiredError') {
        return res.status(401).json({
          error: 'Token Expired',
          message: 'Refresh token has expired'
        });
      }

      return res.status(401).json({
        error: 'Invalid Token',
        message: 'Invalid refresh token'
      });
    }
  } catch (error) {
    logger.error({ event: 'refresh_token_error', message: error.message });
    res.status(500).json({
      error: 'Token Refresh Failed',
      message: 'Failed to refresh token'
    });
  }
});

// @route   POST /api/auth/logout
// @desc    Logout user (client-side token removal)
// @access  Private
router.post('/logout', async (req, res) => {
  res.status(200).json({
    message: 'Logout successful'
  });
});

// @route   GET /api/auth/profile
// @desc    Get user profile
// @access  Private
router.get('/profile', authenticateToken, async (req, res) => {
  try {
    res.status(200).json({
      user: req.user || null
    });
  } catch (error) {
    logger.error({ event: 'profile_error', message: error.message });
    res.status(500).json({
      error: 'Profile Fetch Failed',
      message: 'Failed to fetch user profile'
    });
  }
});

module.exports = router;