const express = require('express');
const app = express();

const PORT    = process.env.PORT        || 3000;
const COLOR   = process.env.COLOR       || 'unknown';   // "blue" or "green"
const VERSION = process.env.APP_VERSION || '1.0.0';

app.use(express.json());

app.use((req, res, next) => {
  console.log(`[${COLOR.toUpperCase()}] ${new Date().toISOString()} ${req.method} ${req.url}`);
  next();
});

// Root shows which slot is serving traffic
app.get('/', (req, res) => {
  res.json({
    message : `Hello from the ${COLOR.toUpperCase()} deployment!`,
    color   : COLOR,
    version : VERSION,
    port    : PORT,
    timestamp: new Date().toISOString(),
  });
});

// Health check returns {"status":"OK"} so the deploy script can grep for "OK"
app.get('/health', (req, res) => {
  res.json({
    status  : 'OK',
    color   : COLOR,
    version : VERSION,
    uptime  : process.uptime(),
  });
});

// Info endpoint
app.get('/info', (req, res) => {
  res.json({
    color   : COLOR,
    version : VERSION,
    nodeVersion: process.version,
    pid     : process.pid,
  });
});

app.listen(PORT, () => {
  console.log(`[${COLOR.toUpperCase()}] Server v${VERSION} listening on port ${PORT}`);
});
