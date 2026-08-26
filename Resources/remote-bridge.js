#!/usr/bin/env node
'use strict';

const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const listenPort = Number(process.env.DSH_REMOTE_PORT || 3081);
const targetHost = process.env.DSH_TARGET_HOST || '127.0.0.1';
const targetPort = Number(process.env.DSH_TARGET_PORT || 3080);
const token = process.env.DSH_REMOTE_TOKEN || '';
const remoteDir = process.env.DSH_REMOTE_DIR || process.cwd();
const statusFile = path.join(remoteDir, 'status.json');
const commandFile = path.join(remoteDir, 'command.json');
const cookieName = 'dsh_remote_session';

if (!token || token.length < 16) {
  console.error('DSH remote bridge requires a strong token');
  process.exit(2);
}
fs.mkdirSync(remoteDir, { recursive: true, mode: 0o700 });

const safeEqual = (a, b) => {
  const aa = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb);
};

function cookies(req) {
  return Object.fromEntries((req.headers.cookie || '').split(';').map(v => {
    const i = v.indexOf('=');
    if (i < 0) return ['', ''];
    try {
      return [v.slice(0, i).trim(), decodeURIComponent(v.slice(i + 1))];
    } catch {
      return ['', ''];
    }
  }).filter(([k]) => k));
}

function upstreamCookies(req) {
  return (req.headers.cookie || '').split(';')
    .map(v => v.trim())
    .filter(v => v && !v.startsWith(`${cookieName}=`))
    .join('; ');
}

function authed(req) {
  return safeEqual(cookies(req)[cookieName] || '', token);
}

function send(res, code, body, type = 'text/plain; charset=utf-8', headers = {}) {
  const data = Buffer.from(body);
  res.writeHead(code, {
    'Content-Type': type,
    'Content-Length': data.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'SAMEORIGIN',
    'Referrer-Policy': 'no-referrer',
    ...headers,
  });
  res.end(data);
}

function pairPage(message = '') {
  const note = message ? `<p class="error">${message}</p>` : '<p>输入电脑上显示的配对密钥</p>';
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#090b10"><title>连接 DSH Desktop</title><style>${css()}</style></head><body><main class="card pair"><div class="logo">DS</div><h1>连接 DSH Desktop</h1>${note}<form method="POST" action="/__remote/pair"><input name="token" autocomplete="one-time-code" autocapitalize="off" spellcheck="false" placeholder="配对密钥" required autofocus><button>连接电脑</button></form><small>手机与电脑需在同一局域网，或已通过 Tailscale 互联。</small></main></body></html>`;
}

function dashboardPage() {
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#090b10"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent"><title>DSH Remote</title><style>${css()}</style></head><body><main class="shell"><header><div><span class="eyebrow">DSH DESKTOP</span><h1>远程控制台</h1></div><span id="dot" class="dot"></span></header><section class="status-card"><span class="label">电脑端状态</span><strong id="state">正在连接…</strong><span id="detail" class="muted"></span></section><div class="actions"><button id="start" onclick="act('start')">▶ 启动</button><button id="restart" onclick="act('restart')">↻ 重启</button><button id="stop" class="danger" onclick="act('stop')">■ 停止</button></div><a id="open" class="primary" href="/">打开完整 DeepSeek Harness <span>→</span></a><p id="feedback" class="feedback"></p><footer>由这台电脑上的 DSH Desktop 安全代理</footer></main><script>
async function refresh(){try{const r=await fetch('/__remote/api/status',{cache:'no-store'});if(!r.ok)throw 0;const s=await r.json();document.getElementById('state').textContent=s.label||s.state;document.getElementById('detail').textContent=s.detail||'';const ready=s.state==='running'||s.state==='externalRunning';document.getElementById('dot').className='dot '+(ready?'ok':s.state==='failed'?'bad':'wait');document.getElementById('open').classList.toggle('disabled',!ready);document.getElementById('start').disabled=!['stopped','failed'].includes(s.state);document.getElementById('restart').disabled=!s.controllable;document.getElementById('stop').disabled=!s.controllable;}catch(e){document.getElementById('state').textContent='电脑连接中断';document.getElementById('dot').className='dot bad';}}async function act(action){const f=document.getElementById('feedback');f.textContent='正在执行…';try{const r=await fetch('/__remote/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action})});const j=await r.json();f.textContent=j.ok?'指令已发送':'操作失败';setTimeout(refresh,500);}catch(e){f.textContent='无法连接电脑';}}refresh();setInterval(refresh,2000);
</script></body></html>`;
}

function css() {
  return `*{box-sizing:border-box}body{margin:0;min-height:100svh;background:radial-gradient(circle at 80% 0,#1b3150 0,transparent 35%),#090b10;color:#f5f7fa;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif;display:grid;place-items:center;padding:max(22px,env(safe-area-inset-top)) 18px max(22px,env(safe-area-inset-bottom))}.shell,.card{width:min(100%,480px)}header{display:flex;justify-content:space-between;align-items:center;margin-bottom:28px}.eyebrow,.label{font-size:11px;letter-spacing:.15em;color:#8491a5}h1{margin:5px 0 0;font-size:30px}.dot{width:13px;height:13px;border-radius:50%;background:#748094;box-shadow:0 0 0 6px #74809422}.dot.ok{background:#35d07f;box-shadow:0 0 0 6px #35d07f22}.dot.bad{background:#ff5d68}.dot.wait{background:#f5ad42}.status-card,.card{background:#141922cc;border:1px solid #ffffff14;border-radius:22px;padding:24px;box-shadow:0 20px 60px #0008;backdrop-filter:blur(20px)}.status-card{display:flex;flex-direction:column;gap:7px}.status-card strong{font-size:24px}.muted,small{color:#8491a5}.actions{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin:16px 0}button,.primary,input{border:0;border-radius:14px;font:inherit}button{padding:15px 8px;background:#1d2634;color:#fff;font-weight:600}button:disabled{opacity:.35}.danger{color:#ff7b84}.primary{display:flex;justify-content:space-between;padding:18px;background:#eaf2ff;color:#0b1729;text-decoration:none;font-weight:700}.primary.disabled{opacity:.35;pointer-events:none}.feedback{text-align:center;color:#8491a5;height:22px}footer{text-align:center;color:#536074;font-size:12px;margin-top:34px}.pair{text-align:center}.logo{display:grid;place-items:center;margin:0 auto 18px;width:58px;height:58px;border-radius:17px;background:#eaf2ff;color:#0b1729;font-weight:900;font-size:20px}.pair h1{font-size:25px}.pair form{display:grid;gap:10px;margin:24px 0}.pair input{padding:16px;background:#090b10;color:#fff;border:1px solid #ffffff22;text-align:center;font-family:ui-monospace,monospace}.pair button{background:#eaf2ff;color:#0b1729}.error{color:#ff7b84}`;
}

function readStatus() {
  try { return fs.readFileSync(statusFile); }
  catch { return Buffer.from(JSON.stringify({ state: 'offline', label: '电脑端未就绪', controllable: false })); }
}

function writeCommand(action) {
  if (!['start', 'stop', 'restart'].includes(action)) return false;
  const tmp = `${commandFile}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ id: crypto.randomUUID(), action, at: Date.now() }), { mode: 0o600 });
  fs.renameSync(tmp, commandFile);
  return true;
}

function proxy(req, res) {
  const headers = { ...req.headers, host: `${targetHost}:${targetPort}` };
  const forwardedCookies = upstreamCookies(req);
  if (forwardedCookies) headers.cookie = forwardedCookies;
  else delete headers.cookie;
  const upstream = http.request({ host: targetHost, port: targetPort, method: req.method, path: req.url, headers }, up => {
    const out = { ...up.headers };
    res.writeHead(up.statusCode || 502, out);
    up.pipe(res);
  });
  upstream.on('error', () => send(res, 503, 'DeepSeek Harness 尚未运行，请返回远程控制台启动。'));
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname === '/__remote/pair' && req.method === 'GET') {
    const supplied = url.searchParams.get('token') || '';
    if (safeEqual(supplied, token)) return send(res, 302, '', 'text/plain', { 'Set-Cookie': `${cookieName}=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000`, Location: '/__remote/' });
    return send(res, 200, pairPage(), 'text/html; charset=utf-8');
  }
  if (url.pathname === '/__remote/pair' && req.method === 'POST') {
    let body = '';
    req.on('data', c => { if (body.length < 4096) body += c; });
    req.on('end', () => {
      const supplied = new URLSearchParams(body).get('token') || '';
      if (!safeEqual(supplied.trim(), token)) return send(res, 403, pairPage('配对密钥不正确'), 'text/html; charset=utf-8');
      send(res, 302, '', 'text/plain', { 'Set-Cookie': `${cookieName}=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=2592000`, Location: '/__remote/' });
    });
    return;
  }
  if (!authed(req)) return send(res, 302, '', 'text/plain', { Location: '/__remote/pair' });
  if (url.pathname === '/__remote/' || url.pathname === '/__remote') return send(res, 200, dashboardPage(), 'text/html; charset=utf-8');
  if (url.pathname === '/__remote/api/status') return send(res, 200, readStatus(), 'application/json; charset=utf-8');
  if (url.pathname === '/__remote/api/action' && req.method === 'POST') {
    let body = '';
    req.on('data', c => { if (body.length < 2048) body += c; });
    req.on('end', () => { try { const ok = writeCommand(JSON.parse(body).action); send(res, ok ? 202 : 400, JSON.stringify({ ok }), 'application/json'); } catch { send(res, 400, JSON.stringify({ ok: false }), 'application/json'); } });
    return;
  }
  proxy(req, res);
});

server.on('upgrade', (req, socket, head) => {
  if (!authed(req)) return socket.destroy();
  const upstream = net.connect(targetPort, targetHost, () => {
    const forwardedCookies = upstreamCookies(req);
    const pairs = Object.entries(req.headers).filter(([k]) => k.toLowerCase() !== 'cookie');
    if (forwardedCookies) pairs.push(['cookie', forwardedCookies]);
    const headers = pairs.map(([k, v]) => `${k}: ${v}`).join('\r\n');
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n${headers}\r\n\r\n`);
    if (head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
});

server.listen(listenPort, '0.0.0.0', () => console.log(`DSH Remote listening on 0.0.0.0:${listenPort}`));
