require('dotenv').config();
const express = require('express');
const cors = require('cors');

const healthRouter = require('./routes/health');
const usersRouter = require('./routes/users');
const statsRouter = require('./routes/stats');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

app.use('/health', healthRouter);
app.use('/api/users', usersRouter);
app.use('/api/stats', statsRouter);

// Root info endpoint
app.get('/', (req, res) => {
  res.json({
    message: '3-Tier App API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      users: '/api/users',
      stats: '/api/stats',
    },
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ success: false, error: `Route ${req.url} not found` });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`  Backend API running on http://0.0.0.0:${PORT}`);
  console.log(`    NODE_ENV  : ${process.env.NODE_ENV || 'development'}`);
  console.log(`    DB URL    : ${process.env.DATABASE_URL ? '(set)' : '(not set)'}`);
});
