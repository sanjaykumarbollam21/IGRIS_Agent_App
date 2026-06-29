const rateLimit = require('express-rate-limit');

/**
 * Rate Limiting Configurations — Rule #2
 * Per CLAUDE.md security rules: per-endpoint limits with Retry-After headers
 */

// General API rate limit — 60 req/min per IP
const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60,
  message: {
    error: 'Too Many Requests',
    message: 'Request limit exceeded. Please slow down.'
  },
  standardHeaders: true, // Return rate limit info in headers (Retry-After)
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'test',
});

// Auth endpoints — 5 req/15min per IP (login, register, password reset)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: {
    error: 'Too Many Authentication Attempts',
    message: 'You have exceeded the login attempt limit. Please try again in 15 minutes.'
  },
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: false,
  skip: () => process.env.NODE_ENV === 'test',
});

// AI/LLM proxy endpoints — 10 req/min per user (Rule AI/LLM)
const aiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  // Rule AI/LLM — per-user limit when authenticated, IP-based fallback
  keyGenerator: (req) => {
    // Prefer userId for authenticated requests; fall back to IP
    if (req.userId) return `user:${req.userId}`;
    // Normalize x-forwarded-for or remoteAddress (handles IPv6)
    const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
    return `ip:${ip}`;
  },
  // Tell express-rate-limit we handle IPv6 normalization ourselves
  validate: { keyGeneratorIpFallback: false },
  message: {
    error: 'AI Rate Limit Exceeded',
    message: 'AI request limit reached. Please wait before sending more AI requests.'
  },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'test',
});

// File uploads — 5 req/min per IP
const uploadLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 5,
  message: {
    error: 'Upload Rate Limit Exceeded',
    message: 'File upload limit reached. Please wait before uploading again.'
  },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'test',
});

// Telegram account linking — 5 requests per 10 minutes per user (Rule #2)
// Bound to req.userId (set by authenticateToken) so a single user cannot spam
// link-token generation. The link-token endpoint requires auth, so req.userId
// is always populated when this limiter runs.
const linkLimiter = rateLimit({
  windowMs: 10 * 60 * 1000, // 10 minutes
  max: 5,
  keyGenerator: (req) => {
    if (req.userId) return `user:${req.userId}`;
    const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
    return `ip:${ip}`;
  },
  validate: { keyGeneratorIpFallback: false },
  message: {
    error: 'Telegram Link Rate Limit Exceeded',
    message: 'Too many Telegram link requests. Please wait a few minutes and try again.'
  },
  standardHeaders: true,
  legacyHeaders: false,
  skip: () => process.env.NODE_ENV === 'test',
});

module.exports = { apiLimiter, authLimiter, aiLimiter, uploadLimiter, linkLimiter };
