// Static file server with COOP/COEP headers (required by Emscripten pthreads + SharedArrayBuffer)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT ?? 8080);
const ROOT = path.resolve(process.env.WEB_ROOT ?? path.join(__dirname, 'public'));

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.js':   'application/javascript; charset=utf-8',
    '.mjs':  'application/javascript; charset=utf-8',
    '.css':  'text/css; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
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

const server = http.createServer((req, res) => {
    // Required for SharedArrayBuffer / pthreads
    res.setHeader('Cross-Origin-Opener-Policy',  'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');

    let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
    if (urlPath === '/') urlPath = '/index.html';

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
