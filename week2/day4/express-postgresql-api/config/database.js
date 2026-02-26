'use strict';

const { Pool } = require('pg');
const logger = require('./logger');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'apidb',
  user: process.env.DB_USER || 'apiuser',
  password: process.env.DB_PASSWORD,
  max: parseInt(process.env.DB_POOL_MAX || '20', 10),
  min: parseInt(process.env.DB_POOL_MIN || '5', 10),
  idleTimeoutMillis: parseInt(process.env.DB_POOL_IDLE_TIMEOUT || '30000', 10),
  connectionTimeoutMillis: parseInt(process.env.DB_POOL_CONNECTION_TIMEOUT || '2000', 10),
});

pool.on('connect', () => {
  logger.debug('New client connected to PostgreSQL pool');
});

pool.on('error', (err) => {
  logger.error(`Unexpected error on idle PostgreSQL client: ${err.message}`);
  process.exit(-1);
});

pool.on('remove', () => {
  logger.debug('Client removed from PostgreSQL pool');
});

/**
 * Execute a query with automatic client management
 * @param {string} text - SQL query string
 * @param {Array} params - Query parameters
 * @returns {Promise<import('pg').QueryResult>}
 */
const query = async (text, params = []) => {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    logger.debug(`Query executed in ${duration}ms | rows: ${result.rowCount}`);
    return result;
  } catch (err) {
    logger.error(`Query failed: ${err.message} | query: ${text}`);
    throw err;
  }
};

/**
 * Get pool statistics for health checks
 * @returns {{ total: number, idle: number, active: number }}
 */
const getPoolStats = () => ({
  total: pool.totalCount,
  idle: pool.idleCount,
  active: pool.totalCount - pool.idleCount,
});

/**
 * Test database connectivity
 * @returns {Promise<boolean>}
 */
const testConnection = async () => {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
};

module.exports = { pool, query, getPoolStats, testConnection };