require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');

const authRouter    = require('./routes/auth');
const healthRouter  = require('./routes/health');
const usersRouter   = require('./routes/users');
const statsRouter   = require('./routes/stats');

const app  = express();
const PORT = process.env.API_PORT || 5000;

const MONGO_URI =
  process.env.MONGO_URI ||
  `mongodb://${process.env.MONGO_INITDB_ROOT_USERNAME}:${process.env.MONGO_INITDB_ROOT_PASSWORD}` +
  `@mongo1:27017,mongo2:27018/${process.env.MONGO_DB_NAME}` +
  `?authSource=admin&replicaSet=rs0&readPreference=primaryPreferred`;

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

app.use('/health',    healthRouter);
app.use('/api/auth',  authRouter);
app.use('/api/users', usersRouter);
app.use('/api/stats', statsRouter);

app.get('/', (req, res) => {
  res.json({
    message: 'MERN Stack API',
    version: '1.0.0',
    endpoints: {
      health:    '/health',
      auth:      '/api/auth  (POST /register, POST /login)',
      users:     '/api/users',
      stats:     '/api/stats',
    },
  });
});

app.use((req, res) => {
  res.status(404).json({ success: false, error: `Route ${req.url} not found` });
});

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

async function start() {
  try {
    await mongoose.connect(MONGO_URI, {
      serverSelectionTimeoutMS: 10000,
      connectTimeoutMS:         10000,
    });
    console.log('  MongoDB connected');
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`  API running on http://0.0.0.0:${PORT}`);
      console.log(`    NODE_ENV : ${process.env.NODE_ENV || 'development'}`);
    });
  } catch (err) {
    console.error('Failed to connect to MongoDB:', err.message);
    setTimeout(start, 5000);  
  }
}

start();
