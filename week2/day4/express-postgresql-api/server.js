'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const swaggerUi = require('swagger-ui-express');

const logger = require('./config/logger');
const requestLogger = require('./middleware/requestLogger');
const { errorHandler, notFoundHandler } = require('./middleware/errorHandler');
const swaggerSpec = require('./docs/swagger');
const healthRouter = require('./routes/health');
const usersRouter = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// Security Middleware 
app.use(helmet());

app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10),
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { status: 'error', message: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

// Core Middleware 
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(requestLogger);

// API Documentation 
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
  customSiteTitle: 'Express PostgreSQL API Docs',
}));
app.get('/api-docs.json', (req, res) => res.json(swaggerSpec));

// Routes 
app.use('/api/health', healthRouter);
app.use('/api/users', usersRouter);

// Error Handling 
app.use(notFoundHandler);
app.use(errorHandler);

// Start Server 
const server = app.listen(PORT, () => {
  logger.info(`Express API running on port ${PORT} in ${process.env.NODE_ENV || 'development'} mode`);
  logger.info(`API Docs: http://localhost:${PORT}/api-docs`);
});

// Graceful Shutdown 
const shutdown = (signal) => {
  logger.info(`${signal} received — shutting down gracefully`);
  server.close(() => {
    logger.info('HTTP server closed');
    const { pool } = require('./config/database');
    pool.end(() => {
      logger.info('Database pool closed');
      process.exit(0);
    });
  });
  setTimeout(() => { logger.error('Forced shutdown after timeout'); process.exit(1); }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => { logger.error(`Uncaught exception: ${err.message}`, { stack: err.stack }); process.exit(1); });
process.on('unhandledRejection', (reason) => { logger.error(`Unhandled rejection: ${reason}`); process.exit(1); });

module.exports = app;