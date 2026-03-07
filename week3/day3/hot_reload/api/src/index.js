const express = require('express');
const cors    = require('cors');
const fs      = require('fs');
const path    = require('path');

const config = require('../config/app.config');
const app    = express();

app.use(cors());
app.use(express.json());

const logDir  = path.join(__dirname, '../logs');
const logFile = path.join(logDir, 'api.log');

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  try { fs.appendFileSync(logFile, line); } catch (_) {}
}

app.get('/api/message', (req, res) => {
  log('GET /api/message');
  res.json({
    message:   config.message,         
    version:   config.version,
    timestamp: new Date().toISOString(),
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(config.port, () => {
  log(`API v${config.version} running on port ${config.port} [${config.env}]`);
});
