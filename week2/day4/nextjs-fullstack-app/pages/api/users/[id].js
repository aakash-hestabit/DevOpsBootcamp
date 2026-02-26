import { query } from '../../../lib/db';

export default async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  const id = parseInt(req.query.id, 10);

  if (isNaN(id) || id < 1) {
    return res.status(400).json({ error: 'Invalid user ID' });
  }

  if (req.method === 'GET') {
    try {
      const { rows } = await query('SELECT * FROM users WHERE id = $1', [id]);

      if (!rows[0]) {
        return res.status(404).json({ error: 'User not found' });
      }

      return res.status(200).json({
        status: 'success',
        data: rows[0],
      });
    } catch (err) {
      console.error('[GET /api/users/:id]', err.message);
      return res.status(500).json({ error: 'Failed to fetch user', message: err.message });
    }
  }

  if (req.method === 'PUT') {
    try {
      const { username, email, full_name } = req.body;

      if (!username && !email && !full_name) {
        return res.status(400).json({ error: 'At least one field is required' });
      }

      const updates = [];
      const values = [];
      let paramIndex = 1;

      if (username) {
        updates.push(`username = $${paramIndex++}`);
        values.push(username);
      }
      if (email) {
        updates.push(`email = $${paramIndex++}`);
        values.push(email);
      }
      if (full_name) {
        updates.push(`full_name = $${paramIndex++}`);
        values.push(full_name);
      }

      updates.push(`updated_at = CURRENT_TIMESTAMP`);
      values.push(id);

      const { rows } = await query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
        values
      );

      if (!rows[0]) {
        return res.status(404).json({ error: 'User not found' });
      }

      return res.status(200).json({
        status: 'success',
        data: rows[0],
      });
    } catch (err) {
      console.error('[PUT /api/users/:id]', err.message);

      if (err.code === '23505') {
        return res.status(409).json({ error: 'Duplicate entry', message: 'Username or email already exists' });
      }

      return res.status(500).json({ error: 'Failed to update user', message: err.message });
    }
  }

  if (req.method === 'DELETE') {
    try {
      const { rowCount } = await query('DELETE FROM users WHERE id = $1', [id]);

      if (rowCount === 0) {
        return res.status(404).json({ error: 'User not found' });
      }

      return res.status(200).json({
        status: 'success',
        message: 'User deleted successfully',
      });
    } catch (err) {
      console.error('[DELETE /api/users/:id]', err.message);
      return res.status(500).json({ error: 'Failed to delete user', message: err.message });
    }
  }

  return res.status(405).json({ error: 'Method not allowed' });
}