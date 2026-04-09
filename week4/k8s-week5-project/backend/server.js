require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 9000;

// Middleware
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type']
}));
app.use(express.json());

console.log('Starting backend on port:', PORT);
console.log('Environment:', process.env.NODE_ENV || 'development');

// PostgreSQL Connection Pool
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Health Endpoint - Backend is healthy
app.get('/api/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    message: 'Backend is up and running',
    timestamp: new Date().toISOString(),
  });
});

// Ready Endpoint - Check if database is connected
app.get('/api/ready', async (req, res) => {
  try {
    console.log('Attempting database connection...');
    const client = await pool.connect();
    const result = await client.query('SELECT NOW()');
    client.release();

    console.log('✓ Database connection successful');
    res.status(200).json({
      status: 'connected',
      message: 'Database connection successful',
      database: process.env.DB_NAME,
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const errorMsg = error.message || 'Unknown error';
    console.error('✗ Database error:', errorMsg);
    res.status(503).json({
      status: 'disconnected',
      message: `Database unavailable: ${errorMsg}`,
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      database: process.env.DB_NAME,
      timestamp: new Date().toISOString(),
    });
  }
});

// Root endpoint
app.get('/api', (req, res) => {
  res.json({
    message: 'Backend API',
    version: '1.0.0',
    endpoints: {
      health: '/api/health',
      ready: '/api/ready',
    },
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({
    status: 'error',
    message: err.message,
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`Backend server running on port ${PORT}`);
  console.log(`Database: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
});
