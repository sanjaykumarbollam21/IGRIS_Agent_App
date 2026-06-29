// Authentication configuration \u2014 Rule #1 + Rule #4
require('dotenv').config();

// Rule #1 \u2014 Never use hardcoded fallback secrets. Fail at startup if not set.
if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  throw new Error('FATAL: JWT_SECRET must be set in environment variables and be at least 32 characters.');
}
if (!process.env.REFRESH_TOKEN_SECRET || process.env.REFRESH_TOKEN_SECRET.length < 32) {
  throw new Error('FATAL: REFRESH_TOKEN_SECRET must be set in environment variables and be at least 32 characters.');
}

module.exports = {
  jwtSecret: process.env.JWT_SECRET,
  // Rule #4 \u2014 Short JWT expiry (1h default, not 24h)
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1h',
  refreshTokenSecret: process.env.REFRESH_TOKEN_SECRET,
  refreshTokenExpiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || '7d',
  // One-time Telegram link JWT. Falls back to jwtSecret if TELEGRAM_LINK_SECRET
  // is unset, so a single shared secret works for development. In production
  // the link secret SHOULD be set to a distinct value so revoking it does not
  // also revoke user session tokens.
  linkTokenSecret: process.env.TELEGRAM_LINK_SECRET || process.env.JWT_SECRET,
  linkTokenExpiresIn: process.env.TELEGRAM_LINK_EXPIRES_IN || '15m',
};