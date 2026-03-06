const express = require('express');
const router = express.Router();
const { query } = require('../db');

router.get('/', async (req, res) => {
  try {
    const result = await query(
      'SELECT id, name, email, role, created_at FROM users ORDER BY created_at DESC'
    );
    res.json({ success: true, data: result.rows, count: result.rowCount });
  } catch (err) {
    console.error('GET /api/users error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const result = await query('SELECT id, name, email, role, created_at FROM users WHERE id = $1', [
      req.params.id,
    ]);
    if (result.rowCount === 0)
      return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('GET /api/users/:id error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/', async (req, res) => {
  const { name, email, role = 'user' } = req.body;
  if (!name || !email)
    return res.status(400).json({ success: false, error: 'name and email are required' });
  try {
    const result = await query(
      'INSERT INTO users (name, email, role) VALUES ($1, $2, $3) RETURNING id, name, email, role, created_at',
      [name, email, role]
    );
    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    if (err.code === '23505')
      return res.status(409).json({ success: false, error: 'Email already exists' });
    console.error('POST /api/users error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { name, email, role } = req.body;
  try {
    const result = await query(
      'UPDATE users SET name = COALESCE($1, name), email = COALESCE($2, email), role = COALESCE($3, role) WHERE id = $4 RETURNING id, name, email, role, created_at',
      [name, email, role, req.params.id]
    );
    if (result.rowCount === 0)
      return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    console.error('PUT /api/users/:id error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const result = await query('DELETE FROM users WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0)
      return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, message: 'User deleted successfully' });
  } catch (err) {
    console.error('DELETE /api/users/:id error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
