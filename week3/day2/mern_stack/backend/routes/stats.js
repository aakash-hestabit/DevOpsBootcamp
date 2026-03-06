const express = require('express');
const User    = require('../models/User');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const [totalUsers, roleBreakdown, recentUsers] = await Promise.all([
      User.countDocuments(),
      User.aggregate([{ $group: { _id: '$role', count: { $sum: 1 } } }, { $sort: { count: -1 } }]),
      User.find().sort({ createdAt: -1 }).limit(5),
    ]);

    res.json({
      success: true,
      data: {
        totalUsers,
        roleBreakdown: roleBreakdown.map((r) => ({ role: r._id, count: r.count })),
        recentUsers,
        serverTime:   new Date().toISOString(),
        nodeVersion:  process.version,
        memoryUsage:  process.memoryUsage(),
        uptime:       `${Math.floor(process.uptime())}s`,
      },
    });
  } catch (err) {
    console.error('GET /api/stats error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
