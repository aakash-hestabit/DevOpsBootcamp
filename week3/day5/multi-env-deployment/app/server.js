const express = require('express');
const app = express();

const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.NODE_ENV || 'development';
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_PORT = process.env.DB_PORT || 5432;
const DB_NAME = process.env.DB_NAME || 'appdb';

app.use(express.json());

app.use((req, res, next) => {
  if (LOG_LEVEL !== 'silent') {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  }
  next();
});

app.get('/', (req, res) => {
  res.json({
    message: `Hello from the ${ENVIRONMENT} environment!`,
    environment: ENVIRONMENT,
    version: APP_VERSION,
    port: PORT,
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    environment: ENVIRONMENT,
    version: APP_VERSION,
    uptime: process.uptime(),
  });
});

app.get('/config', (req, res) => {
  res.json({
    environment: ENVIRONMENT,
    version: APP_VERSION,
    logLevel: LOG_LEVEL,
    database: {
      host: DB_HOST,
      port: DB_PORT,
      name: DB_NAME,
    },
  });
});

app.listen(PORT, () => {
  console.log(`[${ENVIRONMENT.toUpperCase()}] Server running on port ${PORT} (version ${APP_VERSION})`);
  console.log(`  -> Log level : ${LOG_LEVEL}`);
  console.log(`  -> DB host   : ${DB_HOST}:${DB_PORT}/${DB_NAME}`);
});
