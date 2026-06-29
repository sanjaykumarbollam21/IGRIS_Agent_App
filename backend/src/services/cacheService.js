/**
 * IGRIS Cache Service
 * High-performance caching layer with graceful degradation.
 * Uses an in-memory Map when Redis is unavailable.
 */
class CacheService {
  constructor() {
    this.memoryCache = new Map();
    this.memoryCacheTTL = new Map();
    this.redisClient = null;
    this.isRedisConnected = false;
  }

  async initialize() {
    try {
      const redis = require('redis');
      this.redisClient = redis.createClient({
        url: process.env.REDIS_URL || 'redis://localhost:6379'
      });

      this.redisClient.on('error', (err) => {
        if (this.isRedisConnected) {
          console.warn('Redis Client Error — falling back to in-memory cache:', err.message);
          this.isRedisConnected = false;
        }
      });

      await this.redisClient.connect();
      this.isRedisConnected = true;
      console.log('Connected to Redis cache successfully');
    } catch (error) {
      console.warn('Redis connection failed — using in-memory cache instead:', error.message);
      this.isRedisConnected = false;
    }
  }

  /**
   * Set a value in cache with an expiration time
   * @param {string} key Cache key
   * @param {any} value Value to store
   * @param {number} ttl Time-to-live in seconds (default 1 hour)
   */
  async set(key, value, ttl = 3600) {
    try {
      const stringifiedValue = JSON.stringify(value);

      if (this.isRedisConnected && this.redisClient) {
        await this.redisClient.set(key, stringifiedValue, { EX: ttl });
      } else {
        this.memoryCache.set(key, stringifiedValue);
        this.memoryCacheTTL.set(key, Date.now() + ttl * 1000);
      }
    } catch (error) {
      console.error(`Cache set error for ${key}:`, error.message);
    }
  }

  /**
   * Get a value from cache
   * @param {string} key Cache key
   * @returns {Promise<any|null>} Parsed value or null if not found
   */
  async get(key) {
    try {
      if (this.isRedisConnected && this.redisClient) {
        const value = await this.redisClient.get(key);
        return value ? JSON.parse(value) : null;
      } else {
        // Check TTL for in-memory cache
        const expiry = this.memoryCacheTTL.get(key);
        if (expiry && Date.now() > expiry) {
          this.memoryCache.delete(key);
          this.memoryCacheTTL.delete(key);
          return null;
        }
        const value = this.memoryCache.get(key);
        return value ? JSON.parse(value) : null;
      }
    } catch (error) {
      console.error(`Cache get error for ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Delete a specific key from cache
   * @param {string} key Cache key
   */
  async del(key) {
    try {
      if (this.isRedisConnected && this.redisClient) {
        await this.redisClient.del(key);
      } else {
        this.memoryCache.delete(key);
        this.memoryCacheTTL.delete(key);
      }
    } catch (error) {
      console.error(`Cache delete error for ${key}:`, error.message);
    }
  }

  /**
   * Clear all cache entries matching a pattern
   * @param {string} pattern Glob pattern (e.g., 'attendance:*')
   */
  async clearPattern(pattern) {
    try {
      if (this.isRedisConnected && this.redisClient) {
        const keys = await this.redisClient.keys(pattern);
        if (keys.length > 0) {
          await this.redisClient.del(keys);
        }
      } else {
        // Simple pattern matching for in-memory cache
        const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
        for (const key of this.memoryCache.keys()) {
          if (regex.test(key)) {
            this.memoryCache.delete(key);
            this.memoryCacheTTL.delete(key);
          }
        }
      }
    } catch (error) {
      console.error(`Cache clear pattern error ${pattern}:`, error.message);
    }
  }
}

const cacheServiceInstance = new CacheService();
// Start initialization in the background — don't block server startup
cacheServiceInstance.initialize();

module.exports = cacheServiceInstance;
