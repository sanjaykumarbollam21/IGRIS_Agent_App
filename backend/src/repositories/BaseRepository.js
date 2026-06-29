const logger = require('../utils/logger');

/**
 * Base Repository
 * Provides generic CRUD operations to abstract the ORM (Sequelize).
 */
class BaseRepository {
  /**
   * @param {Object} model - The Sequelize model instance
   * @param {string} name - The human-readable name of the repository
   */
  constructor(model, name) {
    if (!model) {
      throw new Error(`Model not provided to ${name}Repository`);
    }
    this.model = model;
    this.name = name;
  }

  /**
   * Find a record by its primary key
   * @param {string|number} id - The primary key
   * @param {Object} options - Sequelize options (include, attributes, etc.)
   * @returns {Promise<Object|null>}
   */
  async findById(id, options = {}) {
    try {
      return await this.model.findByPk(id, options);
    } catch (error) {
      logger.error(`[${this.name}Repository] findById error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Find a single record matching the query
   * @param {Object} where - Where clause
   * @param {Object} options - Additional options
   * @returns {Promise<Object|null>}
   */
  async findOne(where, options = {}) {
    try {
      return await this.model.findOne({ where, ...options });
    } catch (error) {
      logger.error(`[${this.name}Repository] findOne error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Find all records matching the query
   * @param {Object} where - Where clause
   * @param {Object} options - Additional options (order, include, etc.)
   * @returns {Promise<Object[]>}
   */
  async findAll(where = {}, options = {}) {
    try {
      return await this.model.findAll({ where, ...options });
    } catch (error) {
      logger.error(`[${this.name}Repository] findAll error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Create a new record
   * @param {Object} data - Data to insert
   * @returns {Promise<Object>}
   */
  async create(data) {
    try {
      return await this.model.create(data);
    } catch (error) {
      logger.error(`[${this.name}Repository] create error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Update records matching the query
   * @param {Object} where - Where clause
   * @param {Object} data - Data to update
   * @returns {Promise<number>} Number of affected rows
   */
  async update(where, data) {
    try {
      const [affectedRows] = await this.model.update(data, { where });
      return affectedRows;
    } catch (error) {
      logger.error(`[${this.name}Repository] update error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Delete records matching the query
   * @param {Object} where - Where clause
   * @returns {Promise<number>} Number of deleted rows
   */
  async delete(where) {
    try {
      return await this.model.destroy({ where });
    } catch (error) {
      logger.error(`[${this.name}Repository] delete error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Count records matching the query
   * @param {Object} where - Where clause
   * @returns {Promise<number>}
   */
  async count(where = {}) {
    try {
      return await this.model.count({ where });
    } catch (error) {
      logger.error(`[${this.name}Repository] count error: ${error.message}`);
      throw error;
    }
  }

  /**
   * Find records with pagination
   * @param {Object} where - Where clause
   * @param {number} page - Page number (1-indexed)
   * @param {number} limit - Items per page
   * @param {Object} options - Additional options
   * @returns {Promise<{ rows: Object[], count: number, totalPages: number }>}
   */
  async findPaginated(where = {}, page = 1, limit = 10, options = {}) {
    try {
      const offset = (page - 1) * limit;
      const { count, rows } = await this.model.findAndCountAll({
        where,
        limit,
        offset,
        ...options
      });
      return {
        rows,
        count,
        totalPages: Math.ceil(count / limit),
        currentPage: page
      };
    } catch (error) {
      logger.error(`[${this.name}Repository] findPaginated error: ${error.message}`);
      throw error;
    }
  }
}

module.exports = BaseRepository;
