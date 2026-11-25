import { spawn } from 'node:child_process';
import fs from 'node:fs';

const [logFile, command, ...args] = process.argv.slice(2);
if (!logFile || !command) throw new Error('Expected log path, command and arguments.');
const log = fs.createWriteStream(logFile, { flags: 'a' });
const started = Date.now();
let lastOutput = started;
function write(value) {
  process.stdout.write(value);
  log.write(value);
}
// cmd.exe is required for pnpm.cmd. Reject shell syntax in caller-provided arguments.
function quote(value) {
  if (/["\r\n%&|<>^!]/.test(value)) throw new Error('Unsupported shell character in command argument.');
  return `"${value}"`;
}
write(`\n[${new Date().toISOString()}] ${command} ${args.join(' ')}\nLog: ${logFile}\n`);
const child = spawn(process.env.ComSpec || 'cmd.exe',
  ['/d', '/s', '/c', `"${[command, ...args].map(quote).join(' ')}"`],
  { windowsHide: true, windowsVerbatimArguments: true, stdio: ['ignore', 'pipe', 'pipe'] });
for (const stream of [child.stdout, child.stderr]) {
  stream.on('data', data => { lastOutput = Date.now(); write(data); });
}
const heartbeat = setInterval(() => {
  write(`[running] PID ${child.pid}; elapsed ${Math.floor((Date.now() - started) / 1000)}s; no output for ${Math.floor((Date.now() - lastOutput) / 1000)}s\n`);
}, 15000);
child.on('error', error => write(`[launch failed] ${error.message}\n`));
child.on('close', (code, signal) => {
  clearInterval(heartbeat);
  write(`[finished] exit=${code}; signal=${signal || 'none'}; elapsed ${Math.floor((Date.now() - started) / 1000)}s\n`);
  log.end();
  process.exitCode = code ?? 1;
});
