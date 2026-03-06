const express = require('express');
const { Pool }  = require('pg');
const redis     = require('redis');

const app  = express();
const PORT = process.env.APP_PORT || 3000;

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  connectionTimeoutMillis: 3000,
});

const redisClient = redis.createClient({
  socket: { host: process.env.REDIS_HOST, port: Number(process.env.REDIS_PORT) },
});
redisClient.connect().catch(() => {});


app.get('/config', (req, res) => {
  res.json({
    app: {
      name:    process.env.APP_NAME,
      env:     process.env.APP_ENV,
      debug:   process.env.APP_DEBUG,
    },
    db: {
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      name: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: '***',
    },
    redis: {
      host: process.env.REDIS_HOST,
      port: process.env.REDIS_PORT,
    },
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', env: process.env.APP_ENV });
});

app.get('/ready', async (req, res) => {
  const checks = { db: false, redis: false };
  try {
    await pool.query('SELECT 1');
    checks.db = true;
  } catch (_) {}
  try {
    await redisClient.ping();
    checks.redis = true;
  } catch (_) {}

  const ok = checks.db && checks.redis;
  res.status(ok ? 200 : 503).json({ status: ok ? 'ready' : 'not_ready', checks });
});

app.get('/', (req, res) => res.json({ endpoints: ['/config', '/health', '/ready'] }));

app.listen(PORT, () =>
  console.log(`[${process.env.APP_ENV}] ${process.env.APP_NAME} listening on :${PORT}`)
);
