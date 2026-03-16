const http = require('http');

const PORT = process.env.PORT || 3000;

// Health status flags (could be replaced with real health checks)
let appReady = true;
let appAlive = true;

function getHealthResponse() {
  return {
    status: appAlive && appReady ? 'ok' : 'unhealthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    checks: {
      alive: appAlive,
      ready: appReady,
    },
  };
}

const server = http.createServer((req, res) => {
  const url = req.url.toLowerCase();

  if (url === '/health' || url === '/healthz' || url === '/readiness') {
    const health = getHealthResponse();
    const code = health.status === 'ok' ? 200 : 503;

    res.writeHead(code, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    });
    return res.end(JSON.stringify(health));
  }

  if (url === '/set-ready' && req.method === 'POST') {
    appReady = true;
    return res.end('ready=true');
  }

  if (url === '/set-not-ready' && req.method === 'POST') {
    appReady = false;
    return res.end('ready=false');
  }

  if (url === '/set-unhealthy' && req.method === 'POST') {
    appAlive = false;
    return res.end('alive=false');
  }

  if (url === '/set-healthy' && req.method === 'POST') {
    appAlive = true;
    return res.end('alive=true');
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`Health-check server listening on port ${PORT}`);
  console.log('GET /health  /healthz  /readiness');
  console.log('POST /set-ready /set-not-ready /set-healthy /set-unhealthy');
});

// Graceful shutdown handling
process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down...');
  server.close(() => process.exit(0));
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => process.exit(0));
});
