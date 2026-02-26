'use strict';

const morgan = require('morgan');
const logger = require('../config/logger');

// Morgan stream writes to winston
const stream = {
  write: (message) => logger.http(message.trim()),
};

// Skip logging in test environment
const skip = () => process.env.NODE_ENV === 'test';

const requestLogger = morgan(
  ':remote-addr :method :url :status :res[content-length] - :response-time ms',
  { stream, skip }
);

module.exports = requestLogger;