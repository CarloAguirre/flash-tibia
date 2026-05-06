// Static file server with COOP/COEP headers (required by Emscripten pthreads + SharedArrayBuffer)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT ?? 8080);
const ROOT = path.resolve(process.env.WEB_ROOT ?? path.join(__dirname, 'public'));
const LOGIN_PROXY_PREFIX = process.env.LOGIN_PROXY_PREFIX ?? '';
const LOGIN_PROXY_HOST = process.env.LOGIN_PROXY_HOST ?? '';
const LOGIN_PROXY_PORT = Number(process.env.LOGIN_PROXY_PORT ?? 80);
const LOGIN_PROXY_CORS_ORIGIN = process.env.LOGIN_PROXY_CORS_ORIGIN ?? '*';

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.js':   'application/javascript; charset=utf-8',
    '.mjs':  'application/javascript; charset=utf-8',
    '.css':  'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.lzma': 'application/octet-stream',
    '.wasm': 'application/wasm',
    '.data': 'application/octet-stream',
    '.png':  'image/png',
    '.jpg':  'image/jpeg',
    '.svg':  'image/svg+xml',
    '.ico':  'image/x-icon',
    '.dat':  'application/octet-stream',
    '.spr':  'application/octet-stream',
    '.pic':  'application/octet-stream',
    '.otb':  'application/octet-stream',
    '.otbm': 'application/octet-stream',
};

function loginProxyCorsHeaders(req) {
    return {
        'Access-Control-Allow-Origin': LOGIN_PROXY_CORS_ORIGIN,
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': req.headers['access-control-request-headers'] || 'content-type',
        'Access-Control-Max-Age': '86400',
        'Access-Control-Allow-Private-Network': 'true',
        'Vary': 'Origin, Access-Control-Request-Headers',
    };
}

function proxyLogin(req, res, urlPath, rawQuery) {
    if (req.method === 'OPTIONS') {
        res.writeHead(204, loginProxyCorsHeaders(req));
        res.end();
        return;
    }

    const prefix = LOGIN_PROXY_PREFIX.replace(/\/$/, '');
    let proxyPath = urlPath.slice(prefix.length) || '/';
    if (!proxyPath.startsWith('/')) proxyPath = `/${proxyPath}`;

    const headers = { ...req.headers, host: `${LOGIN_PROXY_HOST}:${LOGIN_PROXY_PORT}` };
    const proxyReq = http.request({
        host: LOGIN_PROXY_HOST,
        port: LOGIN_PROXY_PORT,
        method: req.method,
        path: proxyPath + rawQuery,
        headers,
    }, proxyRes => {
        res.writeHead(proxyRes.statusCode ?? 502, { ...proxyRes.headers, ...loginProxyCorsHeaders(req) });
        proxyRes.pipe(res);
    });

    proxyReq.on('error', err => {
        res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(`login proxy error: ${err.message}`);
    });

    req.pipe(proxyReq);
}

const server = http.createServer((req, res) => {
    // Required for SharedArrayBuffer / pthreads
    res.setHeader('Cross-Origin-Opener-Policy',  'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');

    const rawUrl = req.url || '/';
    const queryIndex = rawUrl.indexOf('?');
    const rawQuery = queryIndex >= 0 ? rawUrl.slice(queryIndex) : '';
    let urlPath = decodeURIComponent(rawUrl.split('?')[0]);
    if (urlPath === '/') urlPath = '/index.html';

    if (LOGIN_PROXY_PREFIX && LOGIN_PROXY_HOST && urlPath.startsWith(LOGIN_PROXY_PREFIX)) {
        proxyLogin(req, res, urlPath, rawQuery);
        return;
    }

    const filePath = path.join(ROOT, urlPath);
    if (!filePath.startsWith(ROOT)) { res.writeHead(403); res.end('forbidden'); return; }

    fs.stat(filePath, (err, st) => {
        if (err || !st.isFile()) { res.writeHead(404); res.end('not found'); return; }
        const ext  = path.extname(filePath).toLowerCase();
        const mime = MIME[ext] ?? 'application/octet-stream';
        res.setHeader('Content-Type',   mime);
        res.setHeader('Content-Length', st.size);
        res.setHeader('Cache-Control',  ext === '.html' ? 'no-cache' : 'public, max-age=3600');
        fs.createReadStream(filePath).pipe(res);
    });
});

server.listen(PORT, () => {
    console.log(`tibia-web serving ${ROOT} on http://0.0.0.0:${PORT}`);
});
