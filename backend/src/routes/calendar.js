const express = require('express');
const router = express.Router();
const { google } = require('googleapis');
const { authenticateToken } = require('../middleware/auth');
const { UserSettings } = require('../models');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const logger = require('../utils/logger');
const { validate, schemas } = require('../middleware/validate');
const { aiLimiter } = require('../middleware/rateLimiter');
const jwt = require('jsonwebtoken');
const authConfig = require('../config/auth');

// ── Test Route (Public) ───────────────────────────────────────────────────
router.get('/test', (req, res) => res.json({ success: true, message: 'Calendar router is ALIVE' }));

const getOAuthClient = () => {
  if (!process.env.GMAIL_CLIENT_ID) return null;
  return new google.auth.OAuth2(
    process.env.GMAIL_CLIENT_ID,        // reuse same OAuth app — Calendar + Gmail
    process.env.GMAIL_CLIENT_SECRET,
    process.env.GMAIL_REDIRECT_URI?.replace('gmail', 'calendar'),
  );
};

// ── Auth URL (request calendar scopes) ────────────────────────────────────
router.get('/auth-url', authenticateToken, (req, res) => {
  const stateToken = jwt.sign(
    { userId: req.userId, action: 'calendar' },
    authConfig.jwtSecret,
    { expiresIn: '15m' }
  );

  if (!process.env.GMAIL_CLIENT_ID) {
    // Generate a local mock redirect URL that will log in a mock calendar
    const host = req.get('host') || 'localhost:8080';
    const protocol = req.protocol || 'http';
    const mockUrl = `${protocol}://${host}/api/calendar/oauth/callback?code=mock_code&state=${stateToken}`;
    return res.json({ success: true, authUrl: mockUrl, isMock: true });
  }
  const oauth2Client = getOAuthClient();
  const url = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: [
      'https://www.googleapis.com/auth/calendar.readonly',
      'https://www.googleapis.com/auth/calendar.events',
    ],
    state: stateToken,
    prompt: 'consent',
  });
  res.json({ success: true, authUrl: url });
});

// ── OAuth callback ─────────────────────────────────────────────────────────
router.get('/oauth/callback', async (req, res) => {
  try {
    const { code, state } = req.query;
    let userId;
    try {
      const decoded = jwt.verify(state, authConfig.jwtSecret);
      if (decoded.action !== 'calendar') {
        throw new Error('Invalid state action');
      }
      userId = decoded.userId;
    } catch (stateErr) {
      logger.error({ event: 'calendar_oauth_invalid_state', message: stateErr.message });
      return res.status(400).send('<h2>❌ Calendar OAuth failed: Invalid state parameter.</h2>');
    }
    
    let tokens;
    if (code === 'mock_code' || !process.env.GMAIL_CLIENT_ID) {
      tokens = {
        access_token: 'mock_access_token',
        refresh_token: 'mock_refresh_token',
        expiry_date: Date.now() + 3600 * 1000
      };
    } else {
      const oauth2Client = getOAuthClient();
      const tokenResp = await oauth2Client.getToken(code);
      tokens = tokenResp.tokens;
    }

    const [settings] = await UserSettings.findOrCreate({ where: { userId } });
    await settings.update({
      calendarAccessToken: tokens.access_token,
      calendarRefreshToken: tokens.refresh_token,
      calendarTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
    });

    res.send(`<html><body><h2>✅ Google Calendar connected!</h2><p>You can close this tab.</p></body></html>`);
  } catch (e) {
    logger.error({ event: 'calendar_oauth_callback_error', message: e.message });
    res.status(500).send('<h2>❌ Calendar OAuth failed.</h2>');
  }
});

// ── Connection status ──────────────────────────────────────────────────────
router.get('/status', authenticateToken, async (req, res) => {
  try {
    const settings = await UserSettings.findOne({ where: { userId: req.userId } });
    res.json({ connected: !!(settings?.calendarAccessToken) });
  } catch (e) {
    res.json({ connected: false });
  }
});

// ── Disconnect ─────────────────────────────────────────────────────────────
router.delete('/disconnect', authenticateToken, async (req, res) => {
  try {
    await UserSettings.update(
      { calendarAccessToken: null, calendarRefreshToken: null },
      { where: { userId: req.userId } }
    );
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Helper: build authed calendar client
const getCalendarClient = async (userId) => {
  const settings = await UserSettings.findOne({ where: { userId } });
  if (!settings?.calendarAccessToken) throw new Error('Calendar not connected');

  if (settings.calendarAccessToken === 'mock_access_token' || !process.env.GMAIL_CLIENT_ID) {
    // Return a mock calendar client that implements list, insert, delete
    return {
      isMock: true,
      events: {
        list: async () => ({
          data: {
            items: [
              {
                id: 'mock-event-1',
                summary: 'Project Sync with Antigravity AI',
                description: 'Reviewing implementation of multi-agent and memory systems.',
                location: 'Google Meet',
                start: { dateTime: new Date(Date.now() + 2 * 3600 * 1000).toISOString() },
                end: { dateTime: new Date(Date.now() + 3 * 3600 * 1000).toISOString() },
              },
              {
                id: 'mock-event-2',
                summary: 'Design Review & Feedback',
                description: 'Discussing the premium design and layout options.',
                location: 'Conference Room A',
                start: { dateTime: new Date(Date.now() + 24 * 3600 * 1000).toISOString() },
                end: { dateTime: new Date(Date.now() + 25 * 3600 * 1000).toISOString() },
              }
            ]
          }
        }),
        insert: async ({ requestBody }) => ({
          data: {
            id: `mock-event-${Date.now()}`,
            summary: requestBody.summary,
            description: requestBody.description,
            location: requestBody.location,
            start: requestBody.start,
            end: requestBody.end,
            htmlLink: 'https://calendar.google.com/calendar/r/event/mock'
          }
        }),
        delete: async () => ({})
      }
    };
  }

  const oauth2Client = getOAuthClient();
  oauth2Client.setCredentials({
    access_token: settings.calendarAccessToken,
    refresh_token: settings.calendarRefreshToken,
  });
  oauth2Client.on('tokens', async (tokens) => {
    if (tokens.access_token) {
      await settings.update({
        calendarAccessToken: tokens.access_token,
        calendarTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
      });
    }
  });
  return google.calendar({ version: 'v3', auth: oauth2Client });
};

// ── List upcoming events ───────────────────────────────────────────────────
router.get('/events', authenticateToken, aiLimiter, async (req, res) => {
  try {
    const calendar = await getCalendarClient(req.userId);
    const { maxResults = 20, days = 7 } = req.query;

    const timeMin = new Date().toISOString();
    const timeMax = new Date(Date.now() + parseInt(days) * 24 * 3600 * 1000).toISOString();

    const eventsResp = await calendar.events.list({
      calendarId: 'primary',
      timeMin,
      timeMax,
      maxResults: parseInt(maxResults),
      singleEvents: true,
      orderBy: 'startTime',
    });

    const events = (eventsResp.data.items || []).map(e => ({
      id: e.id,
      title: e.summary,
      description: e.description,
      location: e.location,
      start: e.start?.dateTime || e.start?.date,
      end: e.end?.dateTime || e.end?.date,
      isAllDay: !e.start?.dateTime,
      htmlLink: e.htmlLink,
      colorId: e.colorId,
    }));

    // AI summary if Gemini key present
    let summary = null;
    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (apiKey && events.length > 0) {
      try {
        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        const eventText = events.slice(0, 10).map(e =>
          `• ${e.title} — ${e.start}${e.location ? ' @ ' + e.location : ''}`
        ).join('\n');
        const result = await model.generateContent(
          `Briefly summarize the user's upcoming schedule:\n${eventText}`
        );
        summary = result.response.text();
      } catch (_) {}
    }

    res.json({ success: true, events, count: events.length, summary });
  } catch (e) {
    logger.error({ event: 'calendar_list_error', message: e.message });
    res.status(e.message === 'Calendar not connected' ? 401 : 500)
      .json({ error: e.message });
  }
});

// ── Create event ───────────────────────────────────────────────────────────
router.post('/events', authenticateToken, aiLimiter, validate(schemas.calendar.createEvent), async (req, res) => {
  try {
    const { title, description, location, start, end, isAllDay } = req.body;
    if (!title || !start) {
      return res.status(400).json({ error: 'title and start are required' });
    }

    const calendar = await getCalendarClient(req.userId);

    const event = {
      summary: title,
      description,
      location,
      start: isAllDay ? { date: start.split('T')[0] } : { dateTime: start, timeZone: 'Asia/Kolkata' },
      end: isAllDay
        ? { date: (end || start).split('T')[0] }
        : { dateTime: end || start, timeZone: 'Asia/Kolkata' },
    };

    const created = await calendar.events.insert({
      calendarId: 'primary',
      requestBody: event,
    });

    res.status(201).json({
      success: true,
      event: {
        id: created.data.id,
        title: created.data.summary,
        start: created.data.start?.dateTime || created.data.start?.date,
        htmlLink: created.data.htmlLink,
      },
    });
  } catch (e) {
    logger.error({ event: 'calendar_create_error', message: e.message });
    res.status(500).json({ error: e.message });
  }
});

// ── Delete event ───────────────────────────────────────────────────────────
router.delete('/events/:eventId', authenticateToken, async (req, res) => {
  try {
    const calendar = await getCalendarClient(req.userId);
    await calendar.events.delete({
      calendarId: 'primary',
      eventId: req.params.eventId,
    });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Natural-language event creation via Gemini ─────────────────────────────
router.post('/events/parse', authenticateToken, async (req, res) => {
  try {
    const { text } = req.body;
    if (!text) return res.status(400).json({ error: 'text is required' });

    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    if (!apiKey) return res.status(503).json({ error: 'Gemini not configured' });

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
    const now = new Date().toISOString();

    const prompt = `Current time: ${now}. Parse this into a calendar event JSON:
{
  "title": string,
  "description": string (optional),
  "location": string (optional),
  "start": "ISO8601 datetime",
  "end": "ISO8601 datetime",
  "isAllDay": boolean
}
Only return valid JSON, no markdown.
Input: "${text}"`;

    const result = await model.generateContent(prompt);
    const raw = result.response.text().replace(/\`\`\`json\n?|\n?\`\`\`/g, '').trim();
    const parsed = JSON.parse(raw);
    res.json({ success: true, event: parsed });
  } catch (e) {
    logger.error({ event: 'calendar_parse_error', message: e.message });
    res.status(500).json({ error: 'Could not parse event', message: e.message });
  }
});

module.exports = router;
