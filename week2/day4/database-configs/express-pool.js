// Standalone reference — actual pool is in express-postgresql-api/config/database.js
'use strict';

const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max:      20,                        // max concurrent connections
  min:      5,                         // keep at least 5 connections warm
  idleTimeoutMillis:    30000,         // close idle connections after 30s
  connectionTimeoutMillis: 2000,       // fail fast if pool is exhausted
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle PostgreSQL client:', err.message);
  process.exit(-1);
});

module.exports = pool;