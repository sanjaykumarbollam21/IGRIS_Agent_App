const jwt = require('jsonwebtoken');
const authConfig = require('../config/auth');
const { User } = require('../models');

const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({
      error: 'Access Denied',
      message: 'No token provided'
    });
  }

  try {
    const decoded = jwt.verify(token, authConfig.jwtSecret);
    req.userId = decoded.userId;

    // Attach user information to request
    const user = await User.findByPk(req.userId, {
      attributes: { exclude: ['password', 'geminiApiKey', 'murfApiKey', 'myniatPassword'] }
    });

    if (!user) {
      return res.status(401).json({
        error: 'Access Denied',
        message: 'Invalid token'
      });
    }

    req.user = user;
    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token Expired',
        message: 'Your session has expired. Please log in again.'
      });
    }

    return res.status(403).json({
      error: 'Invalid Token',
      message: 'Failed to authenticate token'
    });
  }
};

const authorizeRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Access Denied',
        message: 'Authentication required'
      });
    }

    // For now, we'll implement role-based access control later
    // This is a placeholder for future implementation
    next();
  };
};

module.exports = {
  authenticateToken,
  authorizeRole
};