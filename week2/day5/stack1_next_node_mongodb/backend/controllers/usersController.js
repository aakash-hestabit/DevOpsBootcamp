'use strict';

const { validationResult } = require('express-validator');
const User = require('../models/user');
const logger = require('../config/logger');

exports.listUsers = async (req, res, next) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
    const offset = parseInt(req.query.offset || '0', 10);
    const { users, total } = await User.findAll({ limit, offset });
    res.json({ status: 'success', data: users, meta: { total, limit, offset } });
  } catch (err) {
    next(err);
  }
};

exports.getUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ status: 'error', errors: errors.array() });

    const user = await User.findById(req.params.id);
    if (!user) return res.status(404).json({ status: 'error', message: 'User not found' });
    res.json({ status: 'success', data: user });
  } catch (err) {
    next(err);
  }
};

exports.createUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ status: 'error', message: 'Validation failed', errors: errors.array() });

    const { username, email, full_name } = req.body;
    const user = await User.create({ username, email, full_name });
    logger.info(`User created: id=${user.id} username=${user.username}`);
    res.status(201).json({ status: 'success', data: user });
  } catch (err) {
    if (err.code === 11000) {
      const field = Object.keys(err.keyValue || {})[0] || 'field';
      return res.status(409).json({ status: 'error', message: `${field} already exists` });
    }
    next(err);
  }
};

exports.updateUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ status: 'error', message: 'Validation failed', errors: errors.array() });

    const updated = await User.update(req.params.id, req.body);
    if (!updated) return res.status(404).json({ status: 'error', message: 'User not found' });
    logger.info(`User updated: id=${req.params.id}`);
    res.json({ status: 'success', data: updated });
  } catch (err) {
    if (err.code === 11000) {
      const field = Object.keys(err.keyValue || {})[0] || 'field';
      return res.status(409).json({ status: 'error', message: `${field} already exists` });
    }
    next(err);
  }
};

exports.deleteUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ status: 'error', errors: errors.array() });

    const deleted = await User.delete(req.params.id);
    if (!deleted) return res.status(404).json({ status: 'error', message: 'User not found' });
    logger.info(`User deleted: id=${req.params.id}`);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
};