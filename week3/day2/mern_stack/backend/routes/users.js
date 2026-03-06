const express = require('express');
const auth    = require('../middleware/auth');
const User    = require('../models/User');

const router = express.Router();

router.get('/', auth, async (req, res) => {
  try {
    const users = await User.find().sort({ createdAt: -1 });
    res.json({ success: true, data: users, count: users.length });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.get('/:id', auth, async (req, res) => {
  try {
    const user = await User.findById(req.params.id);
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, data: user });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/', auth, async (req, res) => {
  const { name, email, role, password = 'Password1!' } = req.body;
  if (!name || !email)
    return res.status(400).json({ success: false, error: 'name and email are required' });
  try {
    const user = await User.create({ name, email, password, role });
    res.status(201).json({ success: true, data: user });
  } catch (err) {
    if (err.code === 11000)
      return res.status(409).json({ success: false, error: 'Email already exists' });
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put('/:id', auth, async (req, res) => {
  const { name, email, role } = req.body;
  try {
    const user = await User.findByIdAndUpdate(
      req.params.id,
      { $set: { ...(name && { name }), ...(email && { email }), ...(role && { role }) } },
      { new: true, runValidators: true }
    );
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, data: user });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.delete('/:id', auth, async (req, res) => {
  try {
    const user = await User.findByIdAndDelete(req.params.id);
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, message: 'User deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
