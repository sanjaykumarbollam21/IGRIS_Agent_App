const BaseRepository = require('./BaseRepository');
const { Op } = require('sequelize');

class ToolUsageRepository extends BaseRepository {
  constructor(models) {
    super(models.ToolUsage, 'ToolUsage');
  }

  /**
   * Get the most recent tool executions for a user
   * @param {string} userId 
   * @param {number} limit 
   */
  async findRecent(userId, limit = 5) {
    return this.findAll(
      { userId },
      { order: [['createdAt', 'DESC']], limit }
    );
  }

  /**
   * Get recent executions from the last hour (for Context Injection)
   * @param {string} userId 
   */
  async findRecentLastHour(userId) {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    return this.findAll(
      { 
        userId,
        createdAt: { [Op.gte]: oneHourAgo }
      },
      { order: [['createdAt', 'DESC']], limit: 10 }
    );
  }
}

module.exports = ToolUsageRepository;
