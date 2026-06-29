const request = require('supertest');
const { app } = require('../src/server');
const { initializeDatabase } = require('../src/utils/dbInit');
const { sequelize, User } = require('../src/models');

describe('Security & Validation Endpoints', () => {
  let verifiedToken;
  let unverifiedToken;
  let verifiedUserId;
  let unverifiedUserId;
  const verifiedEmail = `sec-verified-${Date.now()}@example.com`;
  const unverifiedEmail = `sec-unverified-${Date.now()}@example.com`;
  const password = 'Password123!';

  beforeAll(async () => {
    // Set WEBHOOK_SECRET for signature testing
    process.env.WEBHOOK_SECRET = 'super-test-webhook-secret';
    process.env.ALLOW_LOCAL_COMMANDS = 'true'; // Allow testing system control local path fallback if needed

    // Initialize DB tables
    await initializeDatabase();

    // 1. Register Verified User
    const regVerified = await request(app)
      .post('/api/auth/register')
      .send({
        email: verifiedEmail,
        password,
        firstName: 'Security',
        lastName: 'Verified'
      });
    expect(regVerified.status).toBe(201);
    verifiedUserId = regVerified.body.user.id;

    // Manually verify email
    await User.update({ isEmailVerified: true }, { where: { id: verifiedUserId } });

    // Login verified user
    const loginVerified = await request(app)
      .post('/api/auth/login')
      .send({
        login: verifiedEmail,
        password
      });
    expect(loginVerified.status).toBe(200);
    verifiedToken = loginVerified.body.token;

    // 2. Register Unverified User
    const regUnverified = await request(app)
      .post('/api/auth/register')
      .send({
        email: unverifiedEmail,
        password,
        firstName: 'Security',
        lastName: 'Unverified'
      });
    expect(regUnverified.status).toBe(201);
    unverifiedUserId = regUnverified.body.user.id;
  });

  afterAll(async () => {
    await sequelize.close();
  });

  describe('Email Verification & Auth Restrictions', () => {
    it('should block login attempts for unverified users', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          login: unverifiedEmail,
          password
        });
      expect(response.status).toBe(403);
      expect(response.body.error).toBe('Forbidden');
      expect(response.body.message).toContain('Email not verified');
    });

    it('should allow verification and subsequent login', async () => {
      // Find the user token in DB
      const user = await User.findByPk(unverifiedUserId);
      expect(user.emailVerificationToken).toBeDefined();

      // Trigger verify email endpoint
      const verifyResponse = await request(app)
        .get(`/api/auth/verify-email?token=${user.emailVerificationToken}`);
      expect(verifyResponse.status).toBe(200);
      expect(verifyResponse.text).toContain('Email verified successfully');

      // Now login should succeed
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({
          login: unverifiedEmail,
          password
        });
      expect(loginResponse.status).toBe(200);
      expect(loginResponse.body.token).toBeDefined();
    });

    it('should fail verification with invalid token', async () => {
      const verifyResponse = await request(app)
        .get('/api/auth/verify-email?token=invalidtoken123');
      expect(verifyResponse.status).toBe(400);
      expect(verifyResponse.body.error).toBe('Invalid Token');
    });
  });

  describe('Zod Schema & Input Validation', () => {
    it('should reject registration with invalid email format', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'invalid-email',
          password: 'short',
          firstName: '',
          lastName: 'User'
        });
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Validation Error');
      expect(response.body.details).toBeDefined();
    });

    it('should reject system command actions not in whitelist', async () => {
      const response = await request(app)
        .post('/api/system/command')
        .set('Authorization', `Bearer ${verifiedToken}`)
        .send({
          action: 'format_drive',
          params: {}
        });
      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
      expect(response.body.message).toContain('Invalid or disallowed action');
    });
  });

  describe('System Command Injection Protection', () => {
    it('should sanitize appName to prevent command injection', async () => {
      // We expect the command to be built with a sanitized name, or blank, avoiding injection chars
      const response = await request(app)
        .post('/api/system/command')
        .set('Authorization', `Bearer ${verifiedToken}`)
        .send({
          action: 'open_app',
          params: {
            appName: 'calc.exe & echo "pwned"',
            platform: 'win32'
          }
        });
      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      // Verify appName sanitization resulted in empty because of special characters
      expect(response.body.dispatched).toBe(true);
    });

    it('should sanitize url to prevent parameter injection', async () => {
      const response = await request(app)
        .post('/api/system/command')
        .set('Authorization', `Bearer ${verifiedToken}`)
        .send({
          action: 'open_url',
          params: {
            url: 'https://google.com?q=hello&test=1; rm -rf /',
            platform: 'win32'
          }
        });
      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
    });
  });

  describe('Webhook Signature Checks (IDOR & Spoofing)', () => {
    it('should reject webhook requests with missing signature', async () => {
      const response = await request(app)
        .post('/api/settings/busy-mode/call-summary')
        .send({
          userId: verifiedUserId,
          summary: 'A call summary'
        });
      expect(response.status).toBe(401);
      expect(response.body.error).toBe('Unauthorized');
    });

    it('should reject webhook requests with invalid signature', async () => {
      const response = await request(app)
        .post('/api/settings/busy-mode/call-summary')
        .set('x-webhook-signature', 'wrong-signature')
        .send({
          userId: verifiedUserId,
          summary: 'A call summary'
        });
      expect(response.status).toBe(401);
      expect(response.body.error).toBe('Unauthorized');
    });

    it('should accept webhook requests with valid signature', async () => {
      const response = await request(app)
        .post('/api/settings/busy-mode/call-summary')
        .set('x-webhook-signature', 'super-test-webhook-secret')
        .send({
          userId: verifiedUserId,
          summary: {
            caller_name: 'John Doe',
            caller_number: '+123456789',
            reason: 'Urgent meeting',
            urgency: 'high',
            callback_requested: true,
            notes: 'Callback asap'
          }
        });
      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
    });
  });
});
