const BaseRepository = require('./BaseRepository');

class UserRepository extends BaseRepository {
  constructor(models) {
    super(models.User, 'User');
    this.models = models;
  }

  /**
   * Find a user by email
   * @param {string} email 
   */
  async findByEmail(email) {
    return this.findOne({ email });
  }

  /**
   * Find a user and include their settings
   * @param {string} id 
   */
  async findWithSettings(id) {
    return this.findById(id, {
      include: [{ model: this.models.UserSettings, as: 'settings' }]
    });
  }

  /**
   * Get all active users
   */
  async findActive() {
    return this.findAll({ isActive: true });
  }
}

module.exports = UserRepository;
