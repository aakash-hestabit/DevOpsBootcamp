const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const rateLimit = require('express-rate-limit');
const cors = require('cors');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;
const START = Date.now();

const USER_SERVICE_URL    = process.env.USER_SERVICE_URL    || 'http://user-service:8000';
const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL || 'http://product-service:3000';
const ORDER_SERVICE_URL   = process.env.ORDER_SERVICE_URL   || 'http://order-service:8001';

// Middleware
app.use(cors());
app.use(morgan('short'));

// Rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT || '100', 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later' },
});
app.use('/api/', limiter);

// --- Gateway health (aggregates all services) ---
app.get('/health', async (req, res) => {
  const check = async (name, url) => {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 3000);
      const r = await fetch(`${url}/health`, { signal: controller.signal });
      clearTimeout(timeout);
      const data = await r.json();
      return { name, status: data.status || 'unknown', details: data };
    } catch {
      return { name, status: 'unreachable', details: null };
    }
  };

  const results = await Promise.all([
    check('user-service',    USER_SERVICE_URL),
    check('product-service', PRODUCT_SERVICE_URL),
    check('order-service',   ORDER_SERVICE_URL),
  ]);

  const services = {};
  results.forEach(r => { services[r.name] = { status: r.status, details: r.details }; });

  const allHealthy = results.every(r => r.status === 'healthy');
  const anyHealthy = results.some(r => r.status === 'healthy');
  const overall = allHealthy ? 'healthy' : anyHealthy ? 'degraded' : 'unhealthy';

  res.status(overall === 'unhealthy' ? 503 : 200).json({
    service: 'api-gateway',
    status: overall,
    uptime: `${Math.floor((Date.now() - START) / 1000)}s`,
    services,
  });
});

app.get('/', (req, res) => {
  res.json({
    service: 'api-gateway',
    version: '1.0.0',
    routes: {
      users:    '/api/users',
      products: '/api/products',
      orders:   '/api/orders',
      health:   '/health',
    },
  });
});

// --- Proxy routes ---
app.use(createProxyMiddleware({
  target: USER_SERVICE_URL,
  changeOrigin: true,
  pathFilter: '/api/users',
}));

app.use(createProxyMiddleware({
  target: PRODUCT_SERVICE_URL,
  changeOrigin: true,
  pathFilter: '/api/products',
}));

app.use(createProxyMiddleware({
  target: ORDER_SERVICE_URL,
  changeOrigin: true,
  pathFilter: '/api/orders',
}));

// 404
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.url} not found` });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`API Gateway on :${PORT}`);
  console.log(`  User Service    -> ${USER_SERVICE_URL}`);
  console.log(`  Product Service -> ${PRODUCT_SERVICE_URL}`);
  console.log(`  Order Service   -> ${ORDER_SERVICE_URL}`);
});
