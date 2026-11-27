import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./dsh.ps1', import.meta.url));
const runtime = path.resolve(process.argv[2] || path.join(path.dirname(script), '../../.dsh-manager'));
const direct = process.argv.includes('--direct-network');
fs.mkdirSync(runtime, { recursive: true });
const disabled = path.join(runtime, 'watchdog.disabled');
const paused = path.join(runtime, 'service.paused');
const logFile = path.join(runtime, 'watchdog.log');
const pipe = '\\\\.\\pipe\\dsh-watchdog-' + createHash('sha256').update(runtime.toLowerCase()).digest('hex').slice(0, 24);
const server = net.createServer(socket => socket.end());
let child;
let timer;
let stopping = false;
let failures = 0;
let servicePid;
function log(message) {
  try {
    if (fs.existsSync(logFile) && fs.statSync(logFile).size > 1024 * 1024) fs.renameSync(logFile, logFile + '.old');
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] ${message}\n`);
  } catch (error) { console.error(`Watchdog log: ${error.code}`); }
}
function stop() {
  stopping = true;
  clearTimeout(timer);
  child?.kill();
  server.close();
}
function check() {
  if (stopping) return;
  if (fs.existsSync(disabled)) { stop(); return; }
  if (fs.existsSync(paused)) { timer = setTimeout(check, 15000); return; }
  const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script,
    'start', '-RuntimeDirectory', runtime, '-Supervised'];
  if (direct) args.push('-DirectNetwork');
  // The manager owns service output; never copy its authentication URL to watchdog logs.
  child = spawn(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'), args,
    { windowsHide: true, stdio: 'ignore' });
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    child?.kill();
  }, 100000);
  child.on('error', error => log(`Manager launch failed: ${error.code}`));
  child.on('close', (code, signal) => {
    clearTimeout(timeout);
    child = undefined;
    if (stopping) return;
    failures = code === 0 ? 0 : failures + 1;
    if (code !== 0) log(`Manager ${timedOut ? 'timed out' : `failed (${signal || code})`}; retrying. See service.log.err.`);
    else {
      try {
        const pid = fs.readFileSync(path.join(runtime, 'service.pid'), 'utf8').trim();
        if (pid !== servicePid) log(`DSH service PID: ${pid}${servicePid ? ` (previously ${servicePid})` : ''}.`);
        servicePid = pid;
      } catch (error) {
        if (error.code !== 'ENOENT') log(`Unable to read DSH PID: ${error.code}.`);
      }
    }
    timer = setTimeout(check, Math.min(60000, 15000 * 2 ** Math.min(failures, 2)));
  });
}
server.on('error', error => {
  if (error.code !== 'EADDRINUSE') { log(`Watchdog lock failed: ${error.code}`); process.exitCode = 1; }
});
server.listen(pipe, () => {
  log(`Watchdog started (${process.pid}).`);
  check();
});
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
