'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const swaggerUi = require('swagger-ui-express');

const logger = require('./config/logger');
const { connect, disconnect } = require('./config/database');
const requestLogger = require('./middleware/requestLogger');
const { errorHandler, notFoundHandler } = require('./middleware/errorHandler');
const swaggerSpec = require('./docs/swagger');
const healthRouter = require('./routes/health');
const usersRouter = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// Security
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10),
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { status: 'error', message: 'Too many requests, please try again later.' },
}));

// Core middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(requestLogger);

// Swagger docs
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
  customSiteTitle: 'Express MongoDB API Docs',
}));
app.get('/api-docs.json', (req, res) => res.json(swaggerSpec));

// Routes
app.use('/api/health', healthRouter);
app.use('/api/users', usersRouter);

// Errors
app.use(notFoundHandler);
app.use(errorHandler);

// Start
const startServer = async () => {
  await connect();
  const server = app.listen(PORT, () => {
    logger.info(`Express MongoDB API running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
    logger.info(`Swagger UI: http://localhost:${PORT}/api-docs`);
  });

  const shutdown = (signal) => {
    logger.info(`${signal} received — shutting down`);
    server.close(async () => {
      await disconnect();
      logger.info('Server closed');
      process.exit(0);
    });
    setTimeout(() => { logger.error('Forced shutdown'); process.exit(1); }, 10000);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
};

process.on('uncaughtException', (err) => { logger.error(`Uncaught: ${err.message}`); process.exit(1); });
process.on('unhandledRejection', (reason) => { logger.error(`Unhandled: ${reason}`); process.exit(1); });

startServer().catch((err) => {
  logger.error(`Failed to start: ${err.message}`);
  process.exit(1);
});

module.exports = app;