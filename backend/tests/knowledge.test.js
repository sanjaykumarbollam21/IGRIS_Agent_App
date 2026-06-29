const request = require('supertest');
const { app } = require('../src/server');
const { initializeDatabase } = require('../src/utils/dbInit');
const { sequelize, User, KnowledgeDocument, KnowledgeChunk } = require('../src/models');
const ragService = require('../src/services/ragService');

describe('Knowledge / RAG Endpoints', () => {
  let token;
  let userId;
  let embedSpy;

  beforeAll(async () => {
    // Initialize DB tables
    await initializeDatabase();

    // Register a test user
    const email = `ragtest-${Date.now()}@example.com`;
    const password = 'password123';
    const regRes = await request(app)
      .post('/api/auth/register')
      .send({
        email,
        password,
        firstName: 'RAG',
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

    // Mock embedding generation to avoid real external API calls during testing
    embedSpy = jest.spyOn(ragService, 'generateEmbedding').mockImplementation(async (text) => {
      // Return a dummy 768-dimension vector filled with a hash value of the text
      const hash = text.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
      const val = (hash % 100) / 100.0;
      return new Array(768).fill(val);
    });
  });

  afterAll(async () => {
    if (embedSpy) {
      embedSpy.mockRestore();
    }
    await sequelize.close();
  });

  describe('Document Ingestion', () => {
    it('should fail if not authenticated', async () => {
      const response = await request(app)
        .post('/api/knowledge/documents')
        .send({
          title: 'Unauthorized Doc',
          content: 'Some text content here.'
        });
      
      expect(response.status).toBe(401);
    });

    it('should successfully ingest text content and create chunks', async () => {
      const response = await request(app)
        .post('/api/knowledge/documents')
        .set('Authorization', `Bearer ${token}`)
        .send({
          title: 'My Custom Manual',
          content: 'This is the first sentence. This is the second sentence. IGRIS stands for Intelligent General-purpose Robotic Intelligence System.'
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.document.title).toBe('My Custom Manual');
      expect(response.body.document.status).toBe('ready');
      expect(response.body.document.chunkCount).toBeGreaterThan(0);

      // Verify DB records exist
      const doc = await KnowledgeDocument.findByPk(response.body.document.id);
      expect(doc).toBeDefined();
      expect(doc.userId).toBe(userId);

      const chunks = await KnowledgeChunk.findAll({ where: { documentId: doc.id } });
      expect(chunks.length).toBe(doc.chunkCount);
      expect(chunks[0].embedding).toBeDefined();
      expect(chunks[0].embedding.length).toBe(768);
    });
  });

  describe('Document Listing and Stats', () => {
    it('should list user documents', async () => {
      const response = await request(app)
        .get('/api/knowledge/documents')
        .set('Authorization', `Bearer ${token}`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.documents.length).toBeGreaterThan(0);
      expect(response.body.documents[0].title).toBe('My Custom Manual');
    });

    it('should get knowledge base stats', async () => {
      const response = await request(app)
        .get('/api/knowledge/stats')
        .set('Authorization', `Bearer ${token}`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.documentCount).toBe(1);
      expect(response.body.chunkCount).toBeGreaterThan(0);
    });
  });

  describe('Knowledge Search', () => {
    it('should perform vector similarity search', async () => {
      const response = await request(app)
        .post('/api/knowledge/search')
        .set('Authorization', `Bearer ${token}`)
        .send({
          query: 'what is IGRIS?',
          topK: 2
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.results.length).toBeGreaterThan(0);
      expect(response.body.results[0].content).toContain('IGRIS');
      expect(response.body.results[0].similarity).toBeCloseTo(1.0, 5);
      expect(response.body.results[0].documentTitle).toBe('My Custom Manual');
    });
  });

  describe('Document Deletion', () => {
    it('should delete document and associated chunks', async () => {
      // Get documents first
      const listRes = await request(app)
        .get('/api/knowledge/documents')
        .set('Authorization', `Bearer ${token}`);
      
      const docId = listRes.body.documents[0].id;

      // Delete document
      const delRes = await request(app)
        .delete(`/api/knowledge/documents/${docId}`)
        .set('Authorization', `Bearer ${token}`);

      expect(delRes.status).toBe(200);
      expect(delRes.body.success).toBe(true);
      expect(delRes.body.deleted).toBe(true);

      // Verify deletion from database
      const doc = await KnowledgeDocument.findByPk(docId);
      expect(doc).toBeNull();

      const chunks = await KnowledgeChunk.findAll({ where: { documentId: docId } });
      expect(chunks.length).toBe(0);
    });
  });
});
