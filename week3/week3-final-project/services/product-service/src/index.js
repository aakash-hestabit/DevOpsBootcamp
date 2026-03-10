const express = require('express');
const mongoose = require('mongoose');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://product-db:27017/productdb';
const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';
const START = Date.now();

app.use(express.json());

// --- Mongoose model ---
const productSchema = new mongoose.Schema({
  name:        { type: String, required: true },
  description: { type: String, default: '' },
  price:       { type: Number, required: true },
  category:    { type: String, default: 'general' },
  stock:       { type: Number, default: 0 },
}, { timestamps: true });
const Product = mongoose.model('Product', productSchema);

// --- Redis client ---
let redisClient = null;
(async () => {
  try {
    redisClient = createClient({ url: REDIS_URL });
    redisClient.on('error', () => {});
    await redisClient.connect();
    console.log('Redis connected');
  } catch { console.log('Redis unavailable, running without cache'); }
})();

// --- Connect to MongoDB ---
mongoose.connect(MONGO_URI).then(() => {
  console.log('MongoDB connected');
  seedProducts();
}).catch(err => console.error('MongoDB connection error:', err.message));

async function seedProducts() {
  const count = await Product.countDocuments();
  if (count === 0) {
    await Product.insertMany([
      { name: 'Laptop',     description: 'High-performance laptop',  price: 999.99,  category: 'electronics', stock: 50 },
      { name: 'Keyboard',   description: 'Mechanical keyboard',      price: 79.99,   category: 'electronics', stock: 200 },
      { name: 'Backpack',   description: 'Durable travel backpack',  price: 49.99,   category: 'accessories', stock: 150 },
      { name: 'Monitor',    description: '27-inch 4K display',       price: 449.99,  category: 'electronics', stock: 75 },
      { name: 'Mouse',      description: 'Wireless ergonomic mouse', price: 39.99,   category: 'electronics', stock: 300 },
    ]);
    console.log('Seed products inserted');
  }
}

// --- Health ---
app.get('/health', async (req, res) => {
  const mongoStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
  let redisStatus = 'disconnected';
  try { if (redisClient && await redisClient.ping()) redisStatus = 'connected'; } catch {}
  const status = mongoStatus === 'connected' ? 'healthy' : 'degraded';
  res.status(status === 'healthy' ? 200 : 503).json({
    service: 'product-service',
    status,
    uptime: `${Math.floor((Date.now() - START) / 1000)}s`,
    dependencies: { database: mongoStatus, redis: redisStatus },
  });
});

app.get('/', (req, res) => res.json({ service: 'product-service', version: '1.0.0' }));

// --- CRUD ---
app.get('/api/products', async (req, res) => {
  try {
    if (redisClient) {
      const cached = await redisClient.get('products:all');
      if (cached) return res.json({ success: true, data: JSON.parse(cached), source: 'cache' });
    }
    const products = await Product.find().sort({ createdAt: -1 }).lean();
    if (redisClient) await redisClient.setEx('products:all', 30, JSON.stringify(products));
    res.json({ success: true, data: products, count: products.length });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findById(req.params.id).lean();
    if (!product) return res.status(404).json({ success: false, error: 'Product not found' });
    res.json({ success: true, data: product });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/products', async (req, res) => {
  try {
    const product = await Product.create(req.body);
    if (redisClient) await redisClient.del('products:all');
    res.status(201).json({ success: true, data: product });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

app.put('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findByIdAndUpdate(req.params.id, req.body, { new: true, runValidators: true }).lean();
    if (!product) return res.status(404).json({ success: false, error: 'Product not found' });
    if (redisClient) await redisClient.del('products:all');
    res.json({ success: true, data: product });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

app.delete('/api/products/:id', async (req, res) => {
  try {
    const product = await Product.findByIdAndDelete(req.params.id);
    if (!product) return res.status(404).json({ success: false, error: 'Product not found' });
    if (redisClient) await redisClient.del('products:all');
    res.json({ success: true, message: 'Product deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => console.log(`Product service on :${PORT}`));
