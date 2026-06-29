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

const getOAuthClient = () => {
  if (!process.env.GMAIL_CLIENT_ID) return null;
  return new google.auth.OAuth2(
    process.env.GMAIL_CLIENT_ID,
    process.env.GMAIL_CLIENT_SECRET,
    process.env.GMAIL_REDIRECT_URI,
  );
};

// ── OAuth: Get authorization URL ───────────────────────────────────────────
router.get('/auth-url', authenticateToken, (req, res) => {
  const stateToken = jwt.sign(
    { userId: req.userId, action: 'gmail' },
    authConfig.jwtSecret,
    { expiresIn: '15m' }
  );

  if (!process.env.GMAIL_CLIENT_ID) {
    const host = req.get('host') || 'localhost:8080';
    const protocol = req.protocol || 'http';
    const mockUrl = `${protocol}://${host}/api/gmail/oauth/callback?code=mock_code&state=${stateToken}`;
    return res.json({ success: true, authUrl: mockUrl, isMock: true });
  }
  const oauth2Client = getOAuthClient();
  const url = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: [
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.send',
    ],
    state: stateToken,
    prompt: 'consent',
  });
  res.json({ success: true, authUrl: url });
});

// ── OAuth: Handle callback ─────────────────────────────────────────────────
router.get('/oauth/callback', async (req, res) => {
  try {
    const { code, state } = req.query;
    let userId;
    try {
      const decoded = jwt.verify(state, authConfig.jwtSecret);
      if (decoded.action !== 'gmail') {
        throw new Error('Invalid state action');
      }
      userId = decoded.userId;
    } catch (stateErr) {
      logger.error({ event: 'gmail_oauth_invalid_state', message: stateErr.message });
      return res.status(400).send('<h2>❌ Gmail OAuth failed: Invalid state parameter.</h2>');
    }
    
    let tokens;
    let email = 'admin@igris.ai';

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
      oauth2Client.setCredentials(tokens);
      const gmail = google.gmail({ version: 'v1', auth: oauth2Client });
      const profile = await gmail.users.getProfile({ userId: 'me' });
      email = profile.data.emailAddress;
    }

    const [settings] = await UserSettings.findOrCreate({ where: { userId } });
    await settings.update({
      gmailAccessToken: tokens.access_token,
      gmailRefreshToken: tokens.refresh_token,
      gmailTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
      gmailEmail: email,
    });

    res.send(`<html><body><h2>✅ Gmail connected for ${email}</h2><p>You can close this tab.</p></body></html>`);
  } catch (e) {
    logger.error({ event: 'gmail_oauth_callback_error', message: e.message });
    res.status(500).send('<h2>❌ Gmail OAuth failed. Check server logs.</h2>');
  }
});

// ── Check Gmail connection status ──────────────────────────────────────────
router.get('/status', authenticateToken, async (req, res) => {
  try {
    const settings = await UserSettings.findOne({ where: { userId: req.userId } });
    const connected = !!(settings?.gmailAccessToken);
    res.json({ connected, email: settings?.gmailEmail ?? null });
  } catch (e) {
    res.json({ connected: false, email: null });
  }
});

// ── Disconnect Gmail ───────────────────────────────────────────────────────
router.delete('/disconnect', authenticateToken, async (req, res) => {
  try {
    await UserSettings.update(
      { gmailAccessToken: null, gmailRefreshToken: null, gmailEmail: null },
      { where: { userId: req.userId } }
    );
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Helper: build authed gmail client
const getGmailClient = async (userId) => {
  const settings = await UserSettings.findOne({ where: { userId } });
  if (!settings?.gmailAccessToken) throw new Error('Gmail not connected');

  if (settings.gmailAccessToken === 'mock_access_token' || !process.env.GMAIL_CLIENT_ID) {
    return {
      isMock: true,
      users: {
        messages: {
          list: async () => ({
            data: {
              messages: [
                { id: 'msg-1' },
                { id: 'msg-2' },
                { id: 'msg-3' }
              ]
            }
          }),
          get: async ({ id }) => {
            const mockEmails = {
              'msg-1': {
                id: 'msg-1',
                snippet: 'Important security alert: new login detected on your local IGRIS server.',
                payload: {
                  headers: [
                    { name: 'From', value: 'Google Security <no-reply@accounts.google.com>' },
                    { name: 'Subject', value: 'Security Alert' },
                    { name: 'Date', value: new Date().toUTCString() }
                  ]
                }
              },
              'msg-2': {
                id: 'msg-2',
                snippet: 'Your weekly development summary is ready. 12 commits merged, 4 architectures deployed.',
                payload: {
                  headers: [
                    { name: 'From', value: 'GitHub <noreply@github.com>' },
                    { name: 'Subject', value: '[GitHub] Weekly digest' },
                    { name: 'Date', value: new Date(Date.now() - 3600 * 1000).toUTCString() }
                  ]
                }
              },
              'msg-3': {
                id: 'msg-3',
                snippet: 'Let\'s schedule a follow-up session to verify the mobile and desktop builds.',
                payload: {
                  headers: [
                    { name: 'From', value: 'Sanjay <sanjay@igris.ai>' },
                    { name: 'Subject', value: 'Mobile App Verification' },
                    { name: 'Date', value: new Date(Date.now() - 7200 * 1000).toUTCString() }
                  ]
                }
              }
            };
            return { data: mockEmails[id] || { id, snippet: 'Mock email', payload: { headers: [] } } };
          },
          send: async () => ({})
        }
      }
    };
  }

  const oauth2Client = getOAuthClient();
  oauth2Client.setCredentials({
    access_token: settings.gmailAccessToken,
    refresh_token: settings.gmailRefreshToken,
  });

  oauth2Client.on('tokens', async (tokens) => {
    if (tokens.access_token) {
      await settings.update({
        gmailAccessToken: tokens.access_token,
        gmailTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
      });
    }
  });

  return google.gmail({ version: 'v1', auth: oauth2Client });
};

// ── Summarize unread emails / Fetch emails ───────────────────────────────────
const getEmailsAndSummary = async (req, res) => {
  try {
    const gmail = await getGmailClient(req.userId);
    const { maxEmails = 10, query = 'is:unread' } = req.query;

    // Fetch unread emails
    const listResp = await gmail.users.messages.list({
      userId: 'me',
      q: query,
      maxResults: parseInt(maxEmails),
    });

    const messages = listResp.data.messages || [];
    if (messages.length === 0) {
      return res.json({ success: true, summary: 'No unread emails found.', emails: [] });
    }

    // Fetch each email's content
    const emails = [];
    for (const msg of messages) {
      const detail = await gmail.users.messages.get({
        userId: 'me',
        id: msg.id,
        format: 'metadata',
        metadataHeaders: ['From', 'Subject', 'Date'],
      });
      const headers = detail.data.payload?.headers || [];
      const get = (name) => headers.find(h => h.name === name)?.value ?? '';
      emails.push({
        id: msg.id,
        from: get('From'),
        subject: get('Subject'),
        date: get('Date'),
        snippet: detail.data.snippet,
      });
    }

    // Summarize using Gemini
    const apiKey = req.headers['x-gemini-api-key'] || process.env.GEMINI_API_KEY_DEFAULT;
    let summary = emails.map(e => `• ${e.subject} — from ${e.from}`).join('\n');

    if (apiKey) {
      try {
        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        const emailText = emails.map(e =>
          `Subject: ${e.subject}\nFrom: ${e.from}\nSnippet: ${e.snippet}`
        ).join('\n---\n');

        const result = await model.generateContent(
          `Summarize these ${emails.length} unread emails concisely for the user. Group by urgency if possible.\n\n${emailText}`
        );
        summary = result.response.text();
      } catch (geminiError) {
        logger.error({ event: 'gmail_summarize_gemini_error', message: geminiError.message });
      }
    }

    res.json({ success: true, summary, emails, count: emails.length });
  } catch (e) {
    logger.error({ event: 'gmail_summarize_error', message: e.message });
    res.status(e.message === 'Gmail not connected' ? 401 : 500)
      .json({ error: 'Gmail summarization failed', message: e.message });
  }
};

router.get('/summarize', authenticateToken, aiLimiter, getEmailsAndSummary);
router.get('/emails', authenticateToken, aiLimiter, getEmailsAndSummary);

// ── Send an email via Gmail ────────────────────────────────────────────────
router.post('/send', authenticateToken, validate(schemas.gmail.sendEmail), async (req, res) => {
  try {
    const { to, subject, body } = req.body;
    if (!to || !subject || !body) {
      return res.status(400).json({ error: 'to, subject, and body are required' });
    }

    const settings = await UserSettings.findOne({ where: { userId: req.userId } });
    const gmail = await getGmailClient(req.userId);

    // Build RFC 2822 MIME message
    const from = settings?.gmailEmail || 'me';
    const rawMessage = [
      `From: ${from}`,
      `To: ${to}`,
      `Subject: ${subject}`,
      'Content-Type: text/plain; charset=utf-8',
      'MIME-Version: 1.0',
      '',
      body,
    ].join('\r\n');

    // base64url encode
    const encodedMessage = Buffer.from(rawMessage)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');

    await gmail.users.messages.send({
      userId: 'me',
      requestBody: { raw: encodedMessage },
    });

    res.json({ success: true, to, subject });
  } catch (e) {
    logger.error({ event: 'gmail_send_error', message: e.message });
    res.status(e.message === 'Gmail not connected' ? 401 : 500)
      .json({ error: 'Gmail send failed', message: e.message });
  }
});

module.exports = router;
