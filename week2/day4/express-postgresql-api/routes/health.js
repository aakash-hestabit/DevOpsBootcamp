'use strict';

const express = require('express');
const router = express.Router();
const { testConnection, getPoolStats } = require('../config/database');

/**
 * @openapi
 * /api/health:
 *   get:
 *     tags: [Health]
 *     summary: Service health check
 *     description: Returns the health status of the API, database connection, and pool statistics
 *     responses:
 *       200:
 *         description: Service is healthy
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/HealthResponse'
 *       503:
 *         description: Service unhealthy
 */
router.get('/', async (req, res) => {
  const dbConnected = await testConnection();
  const poolStats = getPoolStats();

  const health = {
    status: dbConnected ? 'healthy' : 'unhealthy',
    timestamp: new Date().toISOString(),
    uptime: Math.floor(process.uptime()),
    database: {
      status: dbConnected ? 'connected' : 'disconnected',
      pool: poolStats,
    },
    environment: process.env.NODE_ENV || 'development',
    version: process.env.APP_VERSION || '1.0.0',
  };

  res.status(dbConnected ? 200 : 503).json(health);
});

module.exports = router;