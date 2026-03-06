const express = require('express');
const jwt     = require('jsonwebtoken');
const User    = require('../models/User');

const router = express.Router();

const sign = (user) =>
  jwt.sign(
    { id: user._id, email: user.email, role: user.role },
    process.env.JWT_SECRET || 'changeme',
    { expiresIn: '7d' }
  );

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const { name, email, password, role } = req.body;
  if (!name || !email || !password)
    return res.status(400).json({ success: false, error: 'name, email and password are required' });

  try {
    const user  = await User.create({ name, email, password, role });
    const token = sign(user);
    res.status(201).json({ success: true, token, data: user });
  } catch (err) {
    if (err.code === 11000)
      return res.status(409).json({ success: false, error: 'Email already exists' });
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password)
    return res.status(400).json({ success: false, error: 'email and password are required' });

  try {
    const user = await User.findOne({ email }).select('+password');
    if (!user || !(await user.matchPassword(password)))
      return res.status(401).json({ success: false, error: 'Invalid credentials' });

    const token = sign(user);
    res.json({ success: true, token, data: user });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
