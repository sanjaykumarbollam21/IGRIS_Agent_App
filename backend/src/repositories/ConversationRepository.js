const BaseRepository = require('./BaseRepository');

class ConversationRepository extends BaseRepository {
  constructor(models) {
    super(models.Conversation, 'Conversation');
  }

  /**
   * Find messages for a specific session ordered chronologically
   * @param {string} userId 
   * @param {string} sessionId 
   */
  async findBySession(userId, sessionId) {
    return this.findAll(
      { userId, sessionId },
      { order: [['createdAt', 'ASC']] }
    );
  }

  /**
   * Save a single message
   */
  async saveMessage(userId, sessionId, role, content, metadata = {}) {
    return this.create({
      userId,
      sessionId,
      role,
      content,
      metadata
    });
  }
}

module.exports = ConversationRepository;
