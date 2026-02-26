'use strict';

const { validationResult } = require('express-validator');
const User = require('../models/user');
const logger = require('../config/logger');

/**
 * GET /api/users
 * List all users with pagination
 */
exports.listUsers = async (req, res, next) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
    const offset = parseInt(req.query.offset || '0', 10);

    const [users, total] = await Promise.all([
      User.findAll({ limit, offset }),
      User.count(),
    ]);

    res.json({ status: 'success', data: users, meta: { total, limit, offset } });
  } catch (err) {
    next(err);
  }
};

/**
 * GET /api/users/:id
 * Get a single user by ID
 */
exports.getUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ status: 'error', errors: errors.array() });
    }

    const user = await User.findById(parseInt(req.params.id, 10));
    if (!user) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    res.json({ status: 'success', data: user });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/users
 * Create a new user
 */
exports.createUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(422).json({ status: 'error', message: 'Validation failed', errors: errors.array() });
    }

    const { username, email, full_name } = req.body;
    const user = await User.create({ username, email, full_name });
    logger.info(`User created: id=${user.id} username=${user.username}`);
    res.status(201).json({ status: 'success', data: user });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ status: 'error', message: 'Username or email already exists' });
    }
    next(err);
  }
};

/**
 * PUT /api/users/:id
 * Update a user
 */
exports.updateUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(422).json({ status: 'error', message: 'Validation failed', errors: errors.array() });
    }

    const id = parseInt(req.params.id, 10);
    const updated = await User.update(id, req.body);
    if (!updated) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    logger.info(`User updated: id=${id}`);
    res.json({ status: 'success', data: updated });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ status: 'error', message: 'Username or email already exists' });
    }
    next(err);
  }
};

/**
 * DELETE /api/users/:id
 * Delete a user
 */
exports.deleteUser = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ status: 'error', errors: errors.array() });
    }

    const id = parseInt(req.params.id, 10);
    const deleted = await User.delete(id);
    if (!deleted) {
      return res.status(404).json({ status: 'error', message: 'User not found' });
    }
    logger.info(`User deleted: id=${id}`);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
};