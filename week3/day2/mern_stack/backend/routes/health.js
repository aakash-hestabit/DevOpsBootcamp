const express   = require('express');
const mongoose  = require('mongoose');

const router = express.Router();

router.get('/', async (req, res) => {
  const uptime    = process.uptime();
  const timestamp = new Date().toISOString();

  const dbState   = mongoose.connection.readyState;
  // 0=disconnected, 1=connected, 2=connecting, 3=disconnecting
  const dbStatus  = dbState === 1 ? 'connected' : 'disconnected';
  const status    = dbStatus === 'connected' ? 'healthy' : 'degraded';

  res.status(dbStatus === 'connected' ? 200 : 503).json({
    status,
    timestamp,
    uptime: `${Math.floor(uptime)}s`,
    environment: process.env.NODE_ENV || 'development',
    version: process.env.npm_package_version || '1.0.0',
    services: {
      api:      'up',
      database: dbStatus,
    },
  });
});

module.exports = router;
