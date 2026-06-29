const BaseRepository = require('./BaseRepository');

class KnowledgeRepository extends BaseRepository {
  constructor(models) {
    super(models.KnowledgeDocument, 'Knowledge');
    this.models = models;
  }

  /**
   * Get documents for a specific user (lightweight, no content)
   * @param {string} userId 
   */
  async findDocumentsByUser(userId) {
    return this.findAll(
      { userId },
      { 
        attributes: ['id', 'title', 'status', 'chunkCount', 'sourceType', 'sourceUrl', 'createdAt', 'updatedAt'],
        order: [['createdAt', 'DESC']]
      }
    );
  }

  /**
   * Load chunks with embeddings for vector search
   * @param {string} userId 
   */
  async findChunksWithEmbeddings(userId) {
    return this.models.KnowledgeChunk.findAll({
      where: { userId },
      include: [{
        model: this.model,
        as: 'document',
        attributes: ['id', 'title', 'sourceType', 'metadata']
      }]
    });
  }

  /**
   * Delete a document and all its chunks securely
   * @param {string} userId 
   * @param {string} documentId 
   */
  async deleteWithChunks(userId, documentId) {
    const doc = await this.findOne({ id: documentId, userId });
    if (!doc) throw new Error('Document not found or access denied');
    
    // Delete children first
    await this.models.KnowledgeChunk.destroy({ where: { documentId } });
    await doc.destroy();
    return true;
  }
}

module.exports = KnowledgeRepository;
