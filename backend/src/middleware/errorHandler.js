const logger = require('../utils/logger');

/**
 * Rule #9 — Error Handling
 * Never return stack traces, raw error messages, or internal paths to the client.
 * Always return generic error messages in production.
 */
const errorHandler = (err, req, res, next) => {
  // Log full detail server-side only
  logger.error({
    event: 'request_error',
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    statusCode: err.statusCode || 500,
    userId: req.userId || null
  });

  const statusCode = err.statusCode || 500;

  // Rule #9 — Generic message to client; never expose internals
  const errorResponse = {
    error: statusCode >= 500 ? 'Internal Server Error' : (err.name || 'Error'),
    message: statusCode >= 500
      ? 'Something went wrong. Please try again later.'
      : (err.message || 'An error occurred')
  };

  // Only attach debug details in development (never in production)
  if (process.env.NODE_ENV === 'development') {
    errorResponse.debug = { stack: err.stack };
  }

  res.status(statusCode).json(errorResponse);
};

// Rule #9 — 404 handler: do not leak the original URL path
const notFound = (req, res, next) => {
  const error = new Error('The requested resource was not found');
  error.statusCode = 404;
  next(error);
};

module.exports = {
  errorHandler,
  notFound
};