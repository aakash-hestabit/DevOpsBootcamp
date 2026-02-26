'use strict';

const morgan = require('morgan');
const logger = require('../config/logger');

const stream = { write: (message) => logger.http(message.trim()) };
const skip = () => process.env.NODE_ENV === 'test';

module.exports = morgan(
  ':remote-addr :method :url :status :res[content-length] - :response-time ms',
  { stream, skip }
);