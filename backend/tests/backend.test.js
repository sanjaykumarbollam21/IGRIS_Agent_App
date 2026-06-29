// Basic backend test
const request = require('supertest');
const { app } = require('../src/server');
const { initializeDatabase } = require('../src/utils/dbInit');
const { sequelize, User } = require('../src/models');

beforeAll(async () => {
  await initializeDatabase();
});

afterAll(async () => {
  await sequelize.close();
});

describe('Backend Health Check', () => {
  it('should return OK status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('OK');
  });
});

describe('Authentication Routes', () => {
  it('should register a new user', async () => {
    const response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'test@example.com',
        password: 'password123',
        firstName: 'Test',
        lastName: 'User'
      });

    expect(response.status).toBe(201);
    expect(response.body.user.email).toBe('test@example.com');
  });

  it('should login existing user', async () => {
    // First register a user
    await request(app)
      .post('/api/auth/register')
      .send({
        email: 'test2@example.com',
        password: 'password123',
        firstName: 'Test2',
        lastName: 'User2'
      });

    // Mark the user as email verified in the DB
    await User.update({ isEmailVerified: true }, { where: { email: 'test2@example.com' } });

    // Then login
    const response = await request(app)
      .post('/api/auth/login')
      .send({
        login: 'test2@example.com',
        password: 'password123'
      });

    expect(response.status).toBe(200);
    expect(response.body.user.email).toBe('test2@example.com');
    expect(response.body.token).toBeDefined();
  });
});