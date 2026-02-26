'use strict';

const { query } = require('../config/database');

class User {
  /**
   * Get all users with optional pagination
   * @param {{ limit: number, offset: number }} opts
   */
  static async findAll({ limit = 50, offset = 0 } = {}) {
    const { rows } = await query(
      'SELECT id, username, email, full_name, created_at, updated_at FROM users ORDER BY id ASC LIMIT $1 OFFSET $2',
      [limit, offset]
    );
    return rows;
  }

  /**
   * Get a single user by ID
   * @param {number} id
   */
  static async findById(id) {
    const { rows } = await query(
      'SELECT id, username, email, full_name, created_at, updated_at FROM users WHERE id = $1',
      [id]
    );
    return rows[0] || null;
  }

  /**
   * Create a new user
   * @param {{ username: string, email: string, full_name?: string }} data
   */
  static async create({ username, email, full_name }) {
    const { rows } = await query(
      `INSERT INTO users (username, email, full_name)
       VALUES ($1, $2, $3)
       RETURNING id, username, email, full_name, created_at, updated_at`,
      [username, email, full_name || null]
    );
    return rows[0];
  }

  /**
   * Update an existing user
   * @param {number} id
   * @param {{ username?: string, email?: string, full_name?: string }} data
   */
  static async update(id, data) {
    const fields = [];
    const values = [];
    let idx = 1;

    if (data.username !== undefined) { fields.push(`username = $${idx++}`); values.push(data.username); }
    if (data.email !== undefined) { fields.push(`email = $${idx++}`); values.push(data.email); }
    if (data.full_name !== undefined) { fields.push(`full_name = $${idx++}`); values.push(data.full_name); }

    if (fields.length === 0) return null;

    fields.push(`updated_at = CURRENT_TIMESTAMP`);
    values.push(id);

    const { rows } = await query(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${idx} RETURNING id, username, email, full_name, created_at, updated_at`,
      values
    );
    return rows[0] || null;
  }

  /**
   * Delete a user by ID
   * @param {number} id
   */
  static async delete(id) {
    const { rowCount } = await query('DELETE FROM users WHERE id = $1', [id]);
    return rowCount > 0;
  }

  /**
   * Count total users
   */
  static async count() {
    const { rows } = await query('SELECT COUNT(*) AS total FROM users');
    return parseInt(rows[0].total, 10);
  }
}

module.exports = User;