const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 3000;
const START = Date.now();

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'healthdb',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'secret',
  connectionTimeoutMillis: 3000,
  idleTimeoutMillis: 5000,
  max: 3,
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status:  'ok',
    service: 'node-api',
    uptime:  `${((Date.now() - START) / 1000).toFixed(1)}s`,
  });
});

app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready', db: 'connected' });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', db: 'disconnected', error: err.message });
  }
});

app.get('/', (req, res) => res.json({ service: 'node-api', endpoints: ['/health', '/ready'] }));

app.listen(PORT, () => console.log(`Node API listening on port ${PORT}`));
