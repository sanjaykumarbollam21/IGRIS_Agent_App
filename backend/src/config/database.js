// Database configuration using Sequelize
// Falls back to SQLite in development when PostgreSQL is unavailable
require('dotenv').config();
const path = require('path');

const usePostgres = process.env.DB_DIALECT !== 'sqlite';

const postgresConfig = {
  username: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'igris_db',
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  dialect: 'postgres',
  logging: false,
  pool: {
    max: 5,
    min: 0,
    acquire: 30000,
    idle: 10000
  }
};

const sqliteConfig = {
  dialect: 'sqlite',
  storage: path.join(__dirname, '..', '..', 'data', 'igris_dev.sqlite'),
  logging: console.log,
  pool: {
    max: 5,
    min: 0,
    acquire: 30000,
    idle: 10000
  }
};

module.exports = {
  development: usePostgres ? postgresConfig : sqliteConfig,
  test: {
    dialect: 'sqlite',
    storage: ':memory:',
    logging: false,
    pool: {
      max: 5,
      min: 0,
      acquire: 30000,
      idle: 10000
    }
  },
  production: postgresConfig
};