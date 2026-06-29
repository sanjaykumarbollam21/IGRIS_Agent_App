const request = require('supertest');
const { app } = require('../src/server');
const { initializeDatabase } = require('../src/utils/dbInit');
const { bootstrap } = require('../src/core/bootstrap');
const { sequelize, User, ToolUsage } = require('../src/models');
const { ChatGoogleGenerativeAI } = require('@langchain/google-genai');

// Mock @langchain/google-genai module
jest.mock('@langchain/google-genai');

describe('Agentic Chat Endpoints', () => {
  let token;
  let userId;
  let mockInvoke;

  beforeAll(async () => {
    // Set a dummy default API key so route doesn't fail with 503
    process.env.GEMINI_API_KEY_DEFAULT = 'dummy-test-key';

    // Bootstrap the DI container for the new architectures
    await bootstrap();

    // Initialize DB tables
    await initializeDatabase();

    // Register a test user
    const email = `chattest-${Date.now()}@example.com`;
    const password = 'password123';
    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email,
        password,
        firstName: 'Chat',
        lastName: 'Tester'
      });
    
    userId = regRes.body.user.id;

    // Mark the user as email verified in the DB
    await User.update({ isEmailVerified: true }, { where: { id: userId } });

    // Login to get token
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({
        login: email,
        password
      });

    token = loginRes.body.token;
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockInvoke = jest.fn();

    // Setup default mock implementation for ChatGoogleGenerativeAI
    ChatGoogleGenerativeAI.mockImplementation(() => {
      return {
        bindTools: jest.fn().mockImplementation(function() {
          return {
            invoke: mockInvoke
          };
        }),
        invoke: mockInvoke
      };
    });
  });

  afterAll(async () => {
    await sequelize.close();
  });

  describe('POST /api/ai/chat', () => {
    it('should fail if unauthorized', async () => {
      const response = await request(app)
        .post('/api/ai/chat')
        .send({ message: 'Hello' });

      expect(response.status).toBe(401);
    });

    it('should handle standard chat messages successfully without calling tools', async () => {
      // Mock LLM response to be a simple text answer
      mockInvoke.mockResolvedValueOnce({
        content: 'Hello human! I am IGRIS, your personal AI assistant. How can I help you today?',
        tool_calls: []
      });

      const response = await request(app)
        .post('/api/ai/chat')
        .set('Authorization', `Bearer ${token}`)
        .send({
          message: 'Hello'
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.response).toBe('Hello human! I am IGRIS, your personal AI assistant. How can I help you today?');
      expect(response.body.toolResults).toEqual([]);
      expect(response.body.iterations).toBe(1);
    });

    it('should successfully execute the tool-calling loop and log tool execution', async () => {
      // Set up sequential mock responses:
      // Turn 1: LLM decides to call the datetime tool
      mockInvoke.mockResolvedValueOnce({
        content: '',
        tool_calls: [
          {
            name: 'get_current_datetime',
            args: {},
            id: 'call_datetime_1'
          }
        ]
      });

      // Turn 2: LLM processes the tool result and provides final answer
      mockInvoke.mockResolvedValueOnce({
        content: 'The current date is Friday, May 22, 2026 and the time is 9:00 AM IST.',
        tool_calls: []
      });

      const response = await request(app)
        .post('/api/ai/chat')
        .set('Authorization', `Bearer ${token}`)
        .send({
          message: 'What time is it?'
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.response).toContain('Friday, May 22, 2026');
      expect(response.body.iterations).toBe(2);
      expect(response.body.toolResults.length).toBe(1);
      expect(response.body.toolResults[0].tool).toBe('get_current_datetime');

      // Verify that ToolUsage was logged to the database
      const usageLogs = await ToolUsage.findAll({ where: { userId, toolName: 'get_current_datetime' } });
      expect(usageLogs.length).toBeGreaterThan(0);
      expect(usageLogs[0].status).toBe('success');
    });

    it('should route creative requests to CreativeAgent', async () => {
      mockInvoke.mockResolvedValueOnce({
        content: 'I have generated a creative story for you.',
        tool_calls: []
      });

      const response = await request(app)
        .post('/api/ai/chat')
        .set('Authorization', `Bearer ${token}`)
        .send({
          message: 'write a poem about quantum computers'
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.response).toContain('creative story');
    });

    it('should route research requests to ResearchAgent', async () => {
      mockInvoke.mockResolvedValueOnce({
        content: 'Here is some deep research on quantum computing.',
        tool_calls: []
      });

      const response = await request(app)
        .post('/api/ai/chat')
        .set('Authorization', `Bearer ${token}`)
        .send({
          message: 'research quantum computing'
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.response).toContain('deep research');
    });

    it('should handle multi-turn agent execution with errors gracefully', async () => {
      // Turn 1: LLM requests a tool call to a tool that will fail (web_search with missing key or incorrect query)
      // Since web_search uses toolsController.webSearch which might reject or fail, or if it is mocked
      mockInvoke.mockResolvedValueOnce({
        content: '',
        tool_calls: [
          {
            name: 'web_search',
            args: { query: 'fail_me_now' },
            id: 'call_search_1'
          }
        ]
      });

      // Turn 2: LLM gets the error string and replies with a fallback message
      mockInvoke.mockResolvedValueOnce({
        content: 'I had trouble searching the web, but I can tell you that generally, search is offline.',
        tool_calls: []
      });

      const response = await request(app)
        .post('/api/ai/chat')
        .set('Authorization', `Bearer ${token}`)
        .send({
          message: 'Search for recent events'
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.iterations).toBe(2);
      expect(response.body.toolResults.length).toBe(1);
      expect(response.body.toolResults[0].tool).toBe('web_search');
      expect(response.body.toolResults[0].result).toContain('Web search is not configured');
    });
  });
});
