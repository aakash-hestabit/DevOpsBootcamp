const express = require('express');
const router = express.Router();
const { testConnection } = require('../db');

router.get('/', async (req, res) => {
  const uptime = process.uptime();
  const timestamp = new Date().toISOString();

  let dbStatus = 'disconnected';
  let dbError = null;

  try {
    await testConnection();
    dbStatus = 'connected';
  } catch (err) {
    dbError = err.message;
  }

  const status = dbStatus === 'connected' ? 'healthy' : 'degraded';

  res.status(dbStatus === 'connected' ? 200 : 503).json({
    status,
    timestamp,
    uptime: `${Math.floor(uptime)}s`,
    environment: process.env.NODE_ENV || 'development',
    version: process.env.npm_package_version || '1.0.0',
    services: {
      api: 'up',
      database: dbStatus,
      ...(dbError && { dbError }),
    },
  });
});

module.exports = router;
