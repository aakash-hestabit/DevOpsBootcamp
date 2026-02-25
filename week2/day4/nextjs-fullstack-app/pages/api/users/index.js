import { query } from '../../../lib/db';

export default async function handler(req, res) {
  if (req.method === 'GET') {
    try {
      const { rows } = await query(
        'SELECT id, username, email, full_name, created_at, updated_at FROM users ORDER BY id ASC LIMIT $1 OFFSET $2',
        [parseInt(req.query.limit || '50'), parseInt(req.query.offset || '0')]
      );
      const count = await query('SELECT COUNT(*) AS total FROM users');
      return res.status(200).json({
        status: 'success',
        data: rows,
        meta: { total: parseInt(count.rows[0].total), limit: 50, offset: 0 },
      });
    } catch (err) {
      return res.status(500).json({ status: 'error', message: err.message });
    }
  }

  if (req.method === 'POST') {
    const { username, email, full_name } = req.body;
    if (!username || !email) {
      return res.status(422).json({ status: 'error', message: 'username and email are required' });
    }
    try {
      const { rows } = await query(
        'INSERT INTO users (username, email, full_name) VALUES ($1, $2, $3) RETURNING *',
        [username, email, full_name || null]
      );
      return res.status(201).json({ status: 'success', data: rows[0] });
    } catch (err) {
      if (err.code === '23505') {
        return res.status(409).json({ status: 'error', message: 'Username or email already exists' });
      }
      return res.status(500).json({ status: 'error', message: err.message });
    }
  }

  res.status(405).json({ status: 'error', message: 'Method not allowed' });
}