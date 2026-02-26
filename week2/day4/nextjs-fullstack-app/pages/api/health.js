import { testConnection, getPoolStats } from '../../lib/db';

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const dbConnected = await testConnection();
    const poolStats = getPoolStats();

    res.status(200).json({
      status: dbConnected ? 'healthy' : 'unhealthy',
      database: dbConnected ? 'connected' : 'disconnected',
      pool: poolStats,
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    });
  } catch (err) {
    console.error('[HEALTH] Error:', err.message);
    res.status(503).json({
      status: 'error',
      error: err.message,
      timestamp: new Date().toISOString(),
    });
  }
}