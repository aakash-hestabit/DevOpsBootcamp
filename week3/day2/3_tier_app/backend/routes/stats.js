const express = require('express');
const router = express.Router();
const { query } = require('../db');

router.get('/', async (req, res) => {
  try {
    const [userCount, roleBreakdown, recentUsers] = await Promise.all([
      query('SELECT COUNT(*) AS total FROM users'),
      query('SELECT role, COUNT(*) AS count FROM users GROUP BY role ORDER BY count DESC'),
      query(
        'SELECT id, name, email, role, created_at FROM users ORDER BY created_at DESC LIMIT 5'
      ),
    ]);

    res.json({
      success: true,
      data: {
        totalUsers: parseInt(userCount.rows[0].total, 10),
        roleBreakdown: roleBreakdown.rows,
        recentUsers: recentUsers.rows,
        serverTime: new Date().toISOString(),
        nodeVersion: process.version,
        memoryUsage: process.memoryUsage(),
        uptime: `${Math.floor(process.uptime())}s`,
      },
    });
  } catch (err) {
    console.error('GET /api/stats error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
