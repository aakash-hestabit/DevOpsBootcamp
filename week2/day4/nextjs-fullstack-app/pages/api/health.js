import { testConnection, getPoolStats } from '../../lib/db';

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ status: 'error', message: 'Method not allowed' });
  }

  const dbConnected = await testConnection();
  const poolStats = getPoolStats();

  const health = {
    status:      dbConnected ? 'healthy' : 'unhealthy',
    timestamp:   new Date().toISOString(),
    uptime:      process.uptime(),
    database:    { status: dbConnected ? 'connected' : 'disconnected', pool: poolStats },
    environment: process.env.NODE_ENV || 'development',
    version:     process.env.npm_package_version || '1.0.0',
  };

  res.status(dbConnected ? 200 : 503).json(health);
}