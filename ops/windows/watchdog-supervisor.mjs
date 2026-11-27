import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync } from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const watchdog = fileURLToPath(new URL('./watchdog.mjs', import.meta.url));
const runtime = path.resolve(process.argv[2] || path.join(path.dirname(watchdog), '../../.dsh-manager'));
const args = [watchdog, runtime, ...process.argv.slice(3)];
const disabled = path.join(runtime, 'watchdog.disabled');
const pipe = '\\\\.\\pipe\\dsh-supervisor-' + createHash('sha256').update(runtime.toLowerCase()).digest('hex').slice(0, 24);
const server = net.createServer(socket => socket.end());
let timer;
let child;
let stopping = false;
let failures = 0;

function log(message) {
  try { appendFileSync(path.join(runtime, 'watchdog.log'), `[${new Date().toISOString()}] Supervisor ${message}\n`); }
  catch (error) { console.error(`Supervisor log: ${error.code}`); }
}

function stop() {
  stopping = true;
  clearTimeout(timer);
  child?.kill();
  server.close();
}

function startWatchdog() {
  if (stopping || existsSync(disabled)) { stop(); return; }
  const startedAt = Date.now();
  child = spawn(process.execPath, args, { windowsHide: true, stdio: 'ignore' });
  child.once('error', error => log(`could not start watchdog: ${error.code}.`));
  child.once('close', (code, signal) => {
    const pid = child.pid;
    child = undefined;
    if (stopping || existsSync(disabled)) { stop(); return; }
    if (Date.now() - startedAt >= 60000) failures = 0;
    const delay = Math.min(60, 2 ** Math.min(++failures, 6));
    log(`observed watchdog PID ${pid ?? 'unknown'} exit (${signal || code}); restarting in ${delay}s.`);
    timer = setTimeout(startWatchdog, delay * 1000);
  });
}

mkdirSync(runtime, { recursive: true });
server.on('error', error => {
  if (error.code !== 'EADDRINUSE') { log(`lock failed: ${error.code}.`); process.exitCode = 1; }
});
server.listen(pipe, () => {
  log(`started (PID ${process.pid}).`);
  startWatchdog();
});
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
