// Busy-LED-server.js
// Starts immediately, proactively starts adb server, auto-detects device (max 3 attempts),
// always updates logical state on /set, supports /force and /confirm, CORS enabled,
// logs stdout/stderr and exit codes, and does not wait on stdin/readline.

const http = require('http');
const { execFile, spawn } = require('child_process');

let ledState = 'off'; // server logical state returned by GET /state

// Configuration via env
const ADB_PATH = process.env.ADB_PATH || 'adb';
let ADB_SERIAL = process.env.ADB_SERIAL || ''; // empty = auto-detect when needed
const SEND_TIMEOUT_MS = parseInt(process.env.SEND_TIMEOUT_MS || '5000', 10);
const DETECT_MAX_ATTEMPTS = parseInt(process.env.DETECT_MAX_ATTEMPTS || '3', 10);
const DETECT_RETRY_DELAY_MS = parseInt(process.env.DETECT_RETRY_DELAY_MS || '700', 10);
const PORT = parseInt(process.env.PORT || '3000', 10);

// ---- Helpers ----
function buildAdbArgs(action, serial) {
  const args = [];
  if (serial) args.push('-s', serial);
  args.push(...action.split(' '));
  return args;
}

function runCmdDetailed(adbPath, action, timeout = SEND_TIMEOUT_MS, serial = '') {
  return new Promise((resolve, reject) => {
    const args = buildAdbArgs(action, serial);
    execFile(adbPath, args, { timeout }, (err, stdout, stderr) => {
      const result = {
        ok: !err,
        code: err && typeof err.code === 'number' ? err.code : 0,
        signal: err && err.signal ? err.signal : null,
        stdout: stdout ? stdout.toString().trim() : '',
        stderr: stderr ? stderr.toString().trim() : '',
        errorMessage: err ? err.message : null
      };
      return result.ok ? resolve(result) : reject(result);
    });
  });
}

function runCmdSpawn(adbPath, action, serial = '') {
  return new Promise((resolve, reject) => {
    const args = buildAdbArgs(action, serial);
    const child = spawn(adbPath, args);
    let stdout = '', stderr = '';
    child.stdout.on('data', d => { stdout += d.toString(); console.log('[ADB STREAM STDOUT]', d.toString().trim()); });
    child.stderr.on('data', d => { stderr += d.toString(); console.log('[ADB STREAM STDERR]', d.toString().trim()); });
    child.on('error', err => reject({ ok: false, errorMessage: err.message, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.on('close', code => {
      const ok = code === 0;
      const result = { ok, code, stdout: stdout.trim(), stderr: stderr.trim() };
      return ok ? resolve(result) : reject(result);
    });
  });
}

// Auto-detect primary serial with limited retries
async function autoDetectSerial(maxAttempts = DETECT_MAX_ATTEMPTS, delayMs = DETECT_RETRY_DELAY_MS) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const res = await runCmdDetailed(ADB_PATH, 'devices -l', SEND_TIMEOUT_MS, '');
      if (res.stdout) {
        const lines = res.stdout.split('\n').map(l => l.trim()).filter(Boolean);
        for (const line of lines) {
          if (/^\s*List of devices attached/.test(line)) continue;
          if (/\bdevice\b/.test(line)) {
            const parts = line.split(/\s+/);
            const serial = parts[0];
            console.log(`[ADB] autoDetectSerial found device on attempt ${attempt}: ${serial}`);
            return serial;
          }
        }
      }
      console.log(`[ADB] autoDetectSerial attempt ${attempt} found no device`);
    } catch (e) {
      console.log(`[ADB] autoDetectSerial attempt ${attempt} error:`, e && e.errorMessage ? e.errorMessage : e);
    }
    if (attempt < maxAttempts) await new Promise(r => setTimeout(r, delayMs));
  }
  console.log('[ADB] autoDetectSerial exhausted attempts, no device found');
  return null;
}

// Ensure adb daemon is running on startup (best-effort)
async function ensureAdbServerRunning() {
  try {
    console.log('[INIT] Starting adb server (adb start-server)...');
    const res = await runCmdDetailed(ADB_PATH, 'start-server', 5000, '');
    console.log('[INIT] adb start-server result code:', res.code, 'stdout:', res.stdout || '<no stdout>');
    return true;
  } catch (e) {
    console.warn('[INIT] adb start-server failed or returned non-zero:', e && e.errorMessage ? e.errorMessage : e);
    return false;
  }
}

// send keyevent 226 with diagnostics and retry fallback
async function sendToTablet() {
  const action = 'shell input keyevent 226';

  if (!ADB_SERIAL) {
    const detected = await autoDetectSerial();
    if (detected) {
      ADB_SERIAL = detected;
      console.log('[SERVER] Using auto-detected ADB_SERIAL:', ADB_SERIAL);
    } else {
      console.log('[SERVER] No device detected; proceeding without -s (adb default).');
    }
  }

  const fullCmdPreview = `${ADB_PATH} ${buildAdbArgs(action, ADB_SERIAL).join(' ')}`;

  try {
    const res = await runCmdDetailed(ADB_PATH, action, SEND_TIMEOUT_MS, ADB_SERIAL);
    console.log('[ADB] cmd:', fullCmdPreview);
    console.log('[ADB RESULT] code:', res.code, 'stdout:', res.stdout || '<no stdout>', 'stderr:', res.stderr || '<no stderr>');
    return { ok: res.ok, code: res.code, stdout: res.stdout, stderr: res.stderr };
  } catch (first) {
    console.error('[ADB] first attempt failed:', first.errorMessage || first);
    console.error('[ADB] first stdout:', first.stdout || '<no stdout>');
    console.error('[ADB] first stderr:', first.stderr || '<no stderr>');
    console.log('[ADB] Falling back to spawn() and retrying once...');
    try {
      const res2 = await runCmdSpawn(ADB_PATH, action, ADB_SERIAL);
      console.log('[ADB] spawn retry succeeded. code:', res2.code, 'stdout:', res2.stdout || '<no stdout>', 'stderr:', res2.stderr || '<no stderr>');
      return { ok: true, code: res2.code, stdout: res2.stdout, stderr: res2.stderr };
    } catch (second) {
      console.error('[ADB] spawn retry failed. code:', second.code, 'stdout:', second.stdout || '<no stdout>', 'stderr:', second.stderr || '<no stderr>');
      if (process.env.ADB_SERIAL === undefined && ADB_SERIAL) {
        console.log('[SERVER] Clearing auto-detected ADB_SERIAL to allow fresh detection on next request');
        ADB_SERIAL = '';
      }
      return { ok: false, code: second.code, stdout: second.stdout, stderr: second.stderr };
    }
  }
}

// parse JSON body for POST /confirm
function parseRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString();
        if (!raw) return resolve(null);
        const obj = JSON.parse(raw);
        resolve(obj);
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

// ---- HTTP server ----
const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    setCorsHeaders(res);
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  setCorsHeaders(res);

  if (req.method === 'GET' && url.pathname === '/state') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(ledState);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/set') {
    const state = url.searchParams.get('state');
    if (state !== 'on' && state !== 'off') {
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Invalid state — use "on" or "off"');
      return;
    }

    // update logical state immediately for optimistic UI and always attempt send
    const previous = ledState;
    ledState = state;
    if (state !== previous) console.log('[SERVER] LED logical state changed to:', state);
    else console.log('[SERVER] /set requested for same state; updating anyway and attempting send:', state);

    const result = await sendToTablet();
    if (!result.ok) console.error('[SERVER] sendToTablet failed for /set:', result);

    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`State set to ${state}`);
    return;
  }

  if (req.method === 'GET' && url.pathname === '/force') {
    console.log('[SERVER] /force requested — forcing keyevent send');
    if (process.env.ADB_SERIAL === undefined) ADB_SERIAL = ''; // force re-detect next time
    const result = await sendToTablet();
    res.writeHead(result.ok ? 200 : 500, { 'Content-Type': 'text/plain' });
    res.end(result.ok ? 'Forced keyevent sent' : 'Failed to send keyevent');
    return;
  }

  if (req.method === 'POST' && url.pathname === '/confirm') {
    try {
      const body = await parseRequestBody(req);
      if (!body || (body.state !== 'on' && body.state !== 'off')) {
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Invalid body — expected JSON {"state":"on"|"off"}');
        return;
      }
      ledState = body.state;
      console.log('[SERVER] /confirm received — logical state set to:', ledState);
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('Confirmed');
    } catch (e) {
      console.error('[SERVER] /confirm parse error:', e && e.message ? e.message : e);
      res.writeHead(400, { 'Content-Type': 'text/plain' });
      res.end('Bad request');
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found');
});

// ---- Startup sequence (runs immediately, no stdin prompt) ----
(async function startup() {
  console.log('[INIT] Busy LED server starting...');

  // Try to ensure adb daemon running so first sends don't hang waiting for user action
  await ensureAdbServerRunning();

  server.listen(PORT, () => {
    console.log('[SERVER] Listening on port', PORT);
    console.log('[SERVER] Logical state:', ledState);
    if (process.env.ADB_SERIAL) console.log('[SERVER] Using provided ADB_SERIAL:', process.env.ADB_SERIAL);
    if (process.env.ADB_PATH) console.log('[SERVER] Using provided ADB_PATH:', process.env.ADB_PATH);
  });
})();

// ---- Robustness: log uncaught errors and keep process alive ----
process.on('uncaughtException', err => {
  console.error('[UNCAUGHT EXCEPTION]', err && err.stack ? err.stack : err);
});
process.on('unhandledRejection', reason => {
  console.error('[UNHANDLED REJECTION]', reason);
});