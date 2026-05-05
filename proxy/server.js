// Tibia WebSocket <-> TCP proxy.
// Browser (OTClient WASM) connects via WebSocket on the same ports as the
// native TFS TCP listeners (default 7171 login / 7172 game) so the standard
// 8.60 client login form works unchanged ("Server: localhost", "Port: 7171").
//
// The proxy runs ONE WebSocket server per port, each forwarding raw bytes
// to TFS over TCP on the matching port.
//
// Env vars:
//   TFS_HOST     TFS hostname  (default 127.0.0.1)
//   TFS_LOGIN    login port    (default 7171)
//   TFS_GAME     game port     (default 7172)
//   HEALTH_PORT  health http   (default 7979)

import net  from 'node:net';
import http from 'node:http';
import { WebSocketServer } from 'ws';

const TFS_HOST    =        process.env.TFS_HOST    ?? '127.0.0.1';
const TFS_LOGIN   = Number(process.env.TFS_LOGIN   ?? 7171);
const TFS_GAME    = Number(process.env.TFS_GAME    ?? 7172);
const HEALTH_PORT = Number(process.env.HEALTH_PORT ?? 7979);

function startBridge(label, listenPort, upstreamPort) {
    const server = http.createServer((_req, res) => { res.writeHead(404); res.end(); });
    const wss    = new WebSocketServer({ server });

    wss.on('connection', (ws, req) => {
        const id = `${req.socket.remoteAddress}:${req.socket.remotePort} -> ${label}`;
        console.log(`[+] ws open  ${id}`);

        const tcp = net.createConnection({ host: TFS_HOST, port: upstreamPort }, () => {
            console.log(`[>] tcp up  ${TFS_HOST}:${upstreamPort} (${id})`);
        });

        ws.on('message', data => {
            const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
            if (!tcp.destroyed) tcp.write(buf);
        });
        tcp.on('data', chunk => {
            if (ws.readyState === ws.OPEN) ws.send(chunk, { binary: true });
        });

        const close = (origin, err) => {
            if (err) console.log(`[!] ${origin} err  ${id}: ${err.message}`);
            else     console.log(`[-] ${origin} close ${id}`);
            try { ws.close(); }   catch { /* ignore */ }
            try { tcp.destroy(); } catch { /* ignore */ }
        };

        ws.on('close',  ()  => close('ws'));
        ws.on('error',  e   => close('ws', e));
        tcp.on('close', ()  => close('tcp'));
        tcp.on('error', e   => close('tcp', e));
    });

    server.listen(listenPort, () => {
        console.log(`tibia-ws-proxy [${label}] ws://0.0.0.0:${listenPort} -> tcp ${TFS_HOST}:${upstreamPort}`);
    });
}

// Health endpoint
const health = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, tfs: { host: TFS_HOST, login: TFS_LOGIN, game: TFS_GAME } }));
        return;
    }
    res.writeHead(404); res.end('not found');
});
health.listen(HEALTH_PORT, () => console.log(`health http://0.0.0.0:${HEALTH_PORT}/health`));

startBridge('login', TFS_LOGIN, TFS_LOGIN);
startBridge('game',  TFS_GAME,  TFS_GAME);
