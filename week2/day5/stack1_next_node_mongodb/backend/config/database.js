'use strict';

const mongoose = require('mongoose');
const logger = require('./logger');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/usersdb';

const options = {
  maxPoolSize: parseInt(process.env.MONGODB_POOL_SIZE || '10', 10),
  connectTimeoutMS: parseInt(process.env.MONGODB_CONNECT_TIMEOUT || '5000', 10),
  serverSelectionTimeoutMS: parseInt(process.env.MONGODB_SERVER_SELECTION_TIMEOUT || '5000', 10),
  socketTimeoutMS: 45000,
  family: 4,
};

mongoose.connection.on('connected', () => {
  logger.info(`MongoDB connected: ${mongoose.connection.host}/${mongoose.connection.name}`);
});

mongoose.connection.on('disconnected', () => {
  logger.warn('MongoDB disconnected');
});

mongoose.connection.on('error', (err) => {
  logger.error(`MongoDB connection error: ${err.message}`);
});

const connect = async () => {
  try {
    await mongoose.connect(MONGODB_URI, options);
    logger.info('MongoDB connection pool ready');
  } catch (err) {
    logger.error(`MongoDB initial connection failed: ${err.message}`);
    throw err;
  }
};

const disconnect = async () => {
  await mongoose.disconnect();
  logger.info('MongoDB disconnected gracefully');
};

const testConnection = async () => {
  try {
    const state = mongoose.connection.readyState;
    // 1 = connected
    if (state !== 1) return false;
    await mongoose.connection.db.admin().ping();
    return true;
  } catch {
    return false;
  }
};

const getPoolStats = () => {
  const conn = mongoose.connection;
  return {
    state: ['disconnected', 'connected', 'connecting', 'disconnecting'][conn.readyState] || 'unknown',
    host: conn.host || null,
    name: conn.name || null,
    poolSize: options.maxPoolSize,
  };
};

module.exports = { connect, disconnect, testConnection, getPoolStats };