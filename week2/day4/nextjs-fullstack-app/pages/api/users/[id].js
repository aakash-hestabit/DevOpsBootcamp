import { query } from '../../../lib/db';

export default async function handler(req, res) {
  const id = parseInt(req.query.id);
  if (isNaN(id) || id < 1) {
    return res.status(400).json({ status: 'error', message: 'Invalid user ID' });
  }

  if (req.method === 'GET') {
    try {
      const { rows } = await query('SELECT * FROM users WHERE id = $1', [id]);
      if (!rows[0]) return res.status(404).json({ status: 'error', message: 'User not found' });
      return res.status(200).json({ status: 'success', data: rows[0] });
    } catch (err) {
      return res.status(500).json({ status: 'error', message: err.message });
    }
  }

  if (req.method === 'PUT') {
    const { username, email, full_name } = req.body;
    try {
      const { rows } = await query(
        `UPDATE users SET
           username  = COALESCE($1, username),
           email     = COALESCE($2, email),
           full_name = COALESCE($3, full_name),
           updated_at = CURRENT_TIMESTAMP
         WHERE id = $4 RETURNING *`,
        [username || null, email || null, full_name || null, id]
      );
      if (!rows[0]) return res.status(404).json({ status: 'error', message: 'User not found' });
      return res.status(200).json({ status: 'success', data: rows[0] });
    } catch (err) {
      return res.status(500).json({ status: 'error', message: err.message });
    }
  }

  if (req.method === 'DELETE') {
    try {
      const { rowCount } = await query('DELETE FROM users WHERE id = $1', [id]);
      if (!rowCount) return res.status(404).json({ status: 'error', message: 'User not found' });
      return res.status(200).json({ status: 'success', message: 'User deleted' });
    } catch (err) {
      return res.status(500).json({ status: 'error', message: err.message });
    }
  }

  res.status(405).json({ status: 'error', message: 'Method not allowed' });
}