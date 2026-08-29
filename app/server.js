/**
 * XQORA Demo Application
 * -----------------------
 * A minimal service that satisfies the project's "Demo Application" requirement:
 *  - Basic frontend / web interface (served from /public)
 *  - Backend / API (simple JSON endpoints under /api)
 *  - Health-check endpoint (/health) used by the deployment automation
 */

const express = require('express');
const os = require('os');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || 'dev';
const START_TIME = Date.now();

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ---- Health check endpoint (used by deploy.sh / rollback.sh) ----
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'UP',
    version: APP_VERSION,
    uptime_seconds: Math.floor((Date.now() - START_TIME) / 1000),
    hostname: os.hostname(),
    timestamp: new Date().toISOString()
  });
});

// ---- Simple API ----
app.get('/api/info', (req, res) => {
  res.json({
    app: 'xqora-demo-app',
    version: APP_VERSION,
    message: 'Hello from the XQORA one-click deployment platform!'
  });
});

let visitCount = 0;
app.get('/api/visits', (req, res) => {
  visitCount += 1;
  res.json({ visits: visitCount });
});

app.get('/api/echo', (req, res) => {
  res.json({ youSent: req.query });
});

app.listen(PORT, () => {
  console.log(`XQORA demo app (v${APP_VERSION}) listening on port ${PORT}`);
});
