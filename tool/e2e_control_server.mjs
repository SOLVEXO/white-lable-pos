// DEV ONLY test-control sidecar for integration_test/real_backend_*. The iOS-simulator app cannot run shell commands, so
// the e2e asks this tiny localhost-only server (127.0.0.1:3199) to do the things a human would do on the dev stack:
// flip the main store's POS plan, stop/start the local API (real "server unreachable"), mint a throwaway owner, read the
// latest dev OTP. It only drives ../solvexo-api/dev (the isolated dev stack) and refuses anything but loopback.
import http from 'node:http';
import { execFile, spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const api = resolve(here, '../../solvexo-api');
const run = resolve(api, 'dev/.run');
const PORT = Number(process.env.E2E_CONTROL_PORT || 3199);
const sh = (cmd, args, opts = {}) => new Promise((ok) => execFile(cmd, args, { cwd: api, maxBuffer: 1 << 24, ...opts }, (err, out, errOut) => ok({ err, out: String(out), errOut: String(errOut) })));
const lastLine = (s) => s.trim().split('\n').filter((l) => l.startsWith('{')).pop();

async function handle(path, q) {
  switch (path) {
    case '/health': return { ok: true };
    case '/expire-plan': case '/restore-plan': {
      const r = await sh('node_modules/.bin/ts-node', ['--transpile-only', 'dev/seed.ts', `--${path.slice(1)}`]);
      if (r.err) throw new Error(r.errOut.slice(-400));
      return { ok: true };
    }
    case '/api/stop': {
      const pidFile = resolve(run, 'api.pid');
      if (!existsSync(pidFile)) return { ok: true, note: 'not running' };
      try { process.kill(Number(readFileSync(pidFile, 'utf8')), 'SIGTERM'); } catch {}
      spawnSync('rm', ['-f', pidFile]);
      for (let i = 0; i < 30; i++) { const r = spawnSync('curl', ['-s', '-m', '1', 'http://127.0.0.1:3102/health/live']); if (r.status !== 0 || !String(r.stdout)) break; await new Promise((s) => setTimeout(s, 300)); }
      return { ok: true };
    }
    case '/api/start': {
      const r = await sh('bash', ['dev/up.sh'], { timeout: 180000 });
      if (r.err) throw new Error(r.errOut.slice(-400));
      return { ok: true };
    }
    case '/throwaway-owner': {
      const r = await sh('node_modules/.bin/ts-node', ['--transpile-only', 'dev/e2e-owner.ts']);
      if (r.err) throw new Error(r.errOut.slice(-400));
      return JSON.parse(lastLine(r.out));
    }
    case '/last-otp': {
      const f = resolve(api, 'dev/.logs/mail.log');
      const lines = existsSync(f) ? readFileSync(f, 'utf8').trim().split('\n').reverse() : [];
      for (const l of lines) { try { const m = JSON.parse(l); if (!q.get('to') || m.to === q.get('to')) return { otp: m.otp }; } catch {} }
      return { otp: null };
    }
    default: return null;
  }
}

http.createServer(async (req, res) => {
  if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress)) { res.writeHead(403).end(); return; }
  const u = new URL(req.url, 'http://x');
  try {
    const out = await handle(u.pathname, u.searchParams);
    if (out === null) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(out));
  } catch (e) { res.writeHead(500, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: String(e.message || e) })); }
}).listen(PORT, '127.0.0.1', () => console.log(`e2e control server on 127.0.0.1:${PORT}`));
