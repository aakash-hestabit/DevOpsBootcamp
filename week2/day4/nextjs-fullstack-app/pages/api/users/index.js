import { query } from '../../../lib/db';

export default async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'GET') {
    try {
      const limit = Math.min(parseInt(req.query.limit || '50', 10), 500);
      const offset = Math.max(parseInt(req.query.offset || '0', 10), 0);

      const { rows } = await query(
        'SELECT * FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2',
        [limit, offset]
      );

      const countResult = await query('SELECT COUNT(*) as count FROM users');
      const total = parseInt(countResult.rows[0].count, 10);

      return res.status(200).json({
        status: 'success',
        data: rows,
        total,
        limit,
        offset,
      });
    } catch (err) {
      console.error('[GET /api/users]', err.message);
      return res.status(500).json({ error: 'Failed to fetch users', message: err.message });
    }
  }

  if (req.method === 'POST') {
    try {
      const { username, email, full_name } = req.body;

      if (!username || !email) {
        return res.status(400).json({ error: 'username and email are required' });
      }

      const { rows } = await query(
        'INSERT INTO users (username, email, full_name) VALUES ($1, $2, $3) RETURNING *',
        [username, email, full_name || null]
      );

      return res.status(201).json({
        status: 'success',
        data: rows[0],
      });
    } catch (err) {
      console.error('[POST /api/users]', err.message);

      if (err.code === '23505') {
        return res.status(409).json({
          error: 'Duplicate entry',
          message: 'Username or email already exists',
        });
      }

      return res.status(500).json({ error: 'Failed to create user', message: err.message });
    }
  }

  return res.status(405).json({ error: 'Method not allowed' });
}