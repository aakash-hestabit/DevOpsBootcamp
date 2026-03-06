const express = require('express');
const os      = require('os');

const app  = express();
const PORT = process.env.PORT || 3000;
let reqCount = 0;

app.get('/', (req, res) => {
  reqCount++;
  res.json({
    message:   'Hello from replica',
    hostname:  os.hostname(),
    pid:       process.pid,
    requests_served: reqCount,
  });
});

app.get('/health', (_req, res) => res.json({ status: 'ok', hostname: os.hostname() }));

app.listen(PORT, () => console.log(`[${os.hostname()}] API listening on :${PORT}`));
