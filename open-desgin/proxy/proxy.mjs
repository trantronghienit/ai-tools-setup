import http from 'http';

const DAEMON_HOST = process.env.DAEMON_HOST || 'open-design';
const DAEMON_PORT = parseInt(process.env.DAEMON_PORT || '7456', 10);
const LISTEN_PORT = parseInt(process.env.PORT || '7456', 10);
const TOKEN = process.env.OD_API_TOKEN;

const HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'transfer-encoding', 'te',
  'trailer', 'upgrade', 'proxy-authorization', 'proxy-authenticate',
]);

const server = http.createServer((req, res) => {
  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (!HOP_BY_HOP.has(key.toLowerCase())) {
      headers[key] = value;
    }
  }

  if (req.url?.startsWith('/api/') && TOKEN) {
    headers['authorization'] = `Bearer ${TOKEN}`;
  }

  const opts = {
    hostname: DAEMON_HOST,
    port: DAEMON_PORT,
    path: req.url,
    method: req.method,
    headers,
  };

  const proxyReq = http.request(opts, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    console.error(`proxy error for ${req.url}:`, err.message);
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Bad Gateway');
    }
  });

  req.pipe(proxyReq);
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`auth-proxy listening :${LISTEN_PORT} -> ${DAEMON_HOST}:${DAEMON_PORT}`);
});
