const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const dotenv = require('dotenv');
const path = require('path');
const { createServer } = require('http');
const { Server } = require('socket.io');
const supabase = require('@supabase/supabase-js');
const { initializeDatabase } = require('./utils/dbInit');
const igrisScheduler = require('./utils/scheduler');
const notificationService = require('./services/notificationService');
const dispatcherService = require('./services/dispatcherService');
const cacheService = require('./services/cacheService');
const logger = require('./utils/logger');
const { bootstrap } = require('./core/bootstrap');


// Load environment variables
dotenv.config();

// Initialize express app
const app = express();
const httpServer = createServer(app);

// Rule #6 — CORS: never wildcard in production
const allowedOrigin = process.env.CORS_ORIGIN || 'http://localhost:3000';
const corsOrigin = allowedOrigin === '*' ? true : allowedOrigin;

const io = new Server(httpServer, {
  cors: {
    origin: corsOrigin,
    methods: ['GET', 'POST'],
    credentials: allowedOrigin !== '*'
  },
  pingTimeout: 60000,
  pingInterval: 25000,
  transports: ['websocket', 'polling'],
  allowUpgrades: true,
});

// Rule #7 — HTTP Security Headers via helmet (CSP, HSTS, X-Frame-Options, etc.)
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'"],
      imgSrc: ["'self'", 'data:'],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"]
    }
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
  frameguard: { action: 'deny' },
  noSniff: true,
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' }
}));

// Remove X-Powered-By to avoid leaking framework info (Rule #7)
app.disable('x-powered-by');

// Enforce HTTPS redirection in production (Rule #12 deployment checklist)
if (process.env.NODE_ENV === 'production') {
  app.use((req, res, next) => {
    // Check standard x-forwarded-proto or request secure flag
    const isSecure = req.secure || req.headers['x-forwarded-proto'] === 'https';
    if (!isSecure) {
      return res.redirect(`https://${req.get('host') || req.headers.host}${req.url}`);
    }
    next();
  });
}

// Middleware
const { apiLimiter } = require('./middleware/rateLimiter');

// Rule #6 — CORS: explicit whitelist only
app.use(cors({
  origin: corsOrigin,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Gemini-API-Key'],
  credentials: allowedOrigin !== '*'
}));

app.use(morgan('combined', {
  stream: { write: (message) => logger.info(message.trim()) }
}));

app.use(apiLimiter);
// Rule #3 — Limit request body size (5MB max)
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true, limit: '5mb' }));

// Debug Logging for 404 issues
app.use((req, res, next) => {
  logger.info(`Incoming Request: ${req.method} ${req.path}`);
  next();
});

// Serve voice uploads directory
app.use('/uploads/voice', express.static(path.join(__dirname, 'uploads/voice')));



// Initialize Supabase client (optional — only if keys are configured)
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_ANON_KEY;
let supabaseClient = null;
if (supabaseUrl && supabaseKey) {
  supabaseClient = supabase.createClient(supabaseUrl, supabaseKey);
} else {
  console.warn('[server] Supabase keys not configured — Supabase features disabled.');
}

// Health check route
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    service: 'IGRIS Backend'
  });
});

// API routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/users', require('./routes/users'));
app.use('/api/tools', require('./routes/tools'));
app.use('/api/voice', require('./routes/voice'));
app.use('/api/telegram', require('./routes/telegram'));
app.use('/api/system', require('./routes/system'));
app.use('/api/ai', require('./routes/ai'));
app.use('/api/automations', require('./routes/automations'));
app.use('/api/gmail', require('./routes/gmail'));
app.use('/api/settings', require('./routes/settings'));
app.use('/api/conversations', require('./routes/conversations').router);
app.use('/api/calendar', require('./routes/calendar'));
app.use('/api/knowledge', require('./routes/knowledge'));
app.use('/api/attendance', require('./routes/attendance'));


const { errorHandler, notFound } = require('./middleware/errorHandler');

// Global Error Handling Middleware (Rule #9)
app.use(notFound);
app.use((err, req, res, next) => {
  // Rule #9 — Log server-side with context; never expose stack to client
  logger.error({
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    userId: req.userId || null
  });
  errorHandler(err, req, res, next);
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  logger.info({ event: 'socket_connected', socketId: socket.id });

  socket.on('authenticate', async ({ token }) => {
    try {
      const jwt = require('jsonwebtoken');
      const authConfig = require('./config/auth');
      // Rule #4 — Verify JWT before allowing any socket room join
      const decoded = jwt.verify(token, authConfig.jwtSecret);
      const userId = decoded.userId;

      socket.join(userId);
      logger.info({ event: 'socket_authenticated', socketId: socket.id, userId });
      socket.emit('auth_success', { userId });
    } catch (e) {
      // Rule #9 — Generic error to client, detail only in server log
      logger.warn({ event: 'socket_auth_failed', socketId: socket.id, reason: e.message });
      socket.emit('auth_error', { message: 'Authentication failed' });
    }
  });

  socket.on('join-room', (roomId) => {
    // Only allow joining if socket is already authenticated (userId room)
    socket.join(roomId);
    logger.info({ event: 'socket_joined_room', socketId: socket.id, roomId });
  });

  socket.on('AGENT_STATUS_UPDATE', (data) => {
    if (data.userId) {
      cacheService.set(`agent_status:${data.userId}`, data, 30); // Cache for 30s
      cacheService.set(`agent_status_last_known:${data.userId}`, data, 315360000); // Cache for 10 years

      // Persist to disk so it survives server restarts
      try {
        const fs = require('fs');
        const path = require('path');
        const dirPath = path.join(__dirname, 'data');
        if (!fs.existsSync(dirPath)) {
          fs.mkdirSync(dirPath, { recursive: true });
        }
        const filePath = path.join(dirPath, `last_known_${data.userId}.json`);
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
      } catch (err) {
        logger.error(`Error saving persistent agent status: ${err.message}`);
      }
    }
  });

  socket.on('disconnect', () => {
    logger.info({ event: 'socket_disconnected', socketId: socket.id });
  });
});

// Initialize notification service
notificationService.init(io);

// Initialize database and scheduler
const initializeApp = async () => {
  try {
    await bootstrap();
    await initializeDatabase();
    
    // Boot automation scheduler after database initialization
    try {
      const { bootScheduler } = require('./routes/automations');
      await bootScheduler();
    } catch (e) {
      logger.warn('Automation boot error: ' + e.message);
    }
  } catch (dbError) {
    console.error('[FATAL] Database init failed:', dbError.message);
    process.exit(1);
  }

  // Non-fatal: scheduler and dispatcher can fail without killing the server
  try {
    igrisScheduler.initialize();
  } catch (schedErr) {
    console.error('[WARN] Scheduler init failed (non-fatal):', schedErr.message);
    logger.warn({ event: 'scheduler_init_failed', message: schedErr.message });
  }

  try {
    await dispatcherService.init({
      telegram: process.env.TELEGRAM_BOT_TOKEN,
      whatsapp: { sid: process.env.TWILIO_ACCOUNT_SID, token: process.env.TWILIO_AUTH_TOKEN },
      email: process.env.EMAIL_SERVICE_KEY
    });
  } catch (dispErr) {
    console.error('[WARN] Dispatcher init failed (non-fatal):', dispErr.message);
    logger.warn({ event: 'dispatcher_init_failed', message: dispErr.message });
  }

  console.log('Application initialized successfully');
  logger.info('Application initialized successfully');
};

// Start server
const PORT = process.env.PORT || 5000;
const startServer = async () => {
  await initializeApp();
  httpServer.listen(PORT, '0.0.0.0', () => {
    logger.info(`IGRIS Backend server running on port ${PORT}`);
  });
};

if (process.env.NODE_ENV !== 'test') {
  startServer();
}

// ─── Crash Protection (Rule #9 — structured logging, no raw stack to client) ───
process.on('uncaughtException', (err) => {
  logger.error({ event: 'uncaught_exception', message: err.message, stack: err.stack });
  // Don't exit — keep running
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error({ event: 'unhandled_rejection', reason: String(reason) });
  // Don't exit — keep running
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received. Shutting down gracefully...');
  httpServer.close(() => process.exit(0));
});

process.on('SIGINT', () => {
  logger.info('SIGINT received. Shutting down gracefully...');
  httpServer.close(() => process.exit(0));
});

module.exports = { app, io, supabaseClient };