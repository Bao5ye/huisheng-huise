'use strict';
/*
 * 绘声绘色 网页版服务端（零依赖，Node.js 18 及以上）
 * - 提供 public/index.html
 * - 转发 DeepSeek（文字）与 MiniMax（图片）请求，密钥只放在服务器环境变量里
 * - 可选访问码、按 IP 限流、请求体大小限制
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const env = process.env;
const PORT = Number(env.PORT) || 8080;
const DS_KEY = env.DEEPSEEK_API_KEY || '';
const MM_KEY = env.MINIMAX_API_KEY || '';
const ARK_KEY = env.ARK_API_KEY || '';
const ARK_URL = env.ARK_URL || 'https://ark.cn-beijing.volces.com/api/v3/images/generations';
const SD_MODEL_RE = /^(doubao|dola)-seedream-[a-z0-9-]+$/;
const TC_ID = env.TENCENT_SECRET_ID || '';
const TC_KEY = env.TENCENT_SECRET_KEY || '';
const TTS_HOST = env.TENCENT_TTS_HOST || 'tts.tencentcloudapi.com';
const TTS_URL = env.TENCENT_TTS_URL || 'https://' + TTS_HOST;
const ACCESS_CODE = env.ACCESS_CODE || '';
const DS_BASE = (env.DEEPSEEK_BASE || 'https://api.deepseek.com').replace(/\/$/, '');
const MM_URL = env.MINIMAX_URL || 'https://api.minimaxi.com/v1/image_generation';
const TEXT_MODEL = env.DEEPSEEK_MODEL || 'deepseek-v4-flash';
const WRITE_MODEL = env.DEEPSEEK_WRITE_MODEL || 'deepseek-v4-pro';
const MODELS = new Set((env.DEEPSEEK_MODELS || 'deepseek-v4-flash,deepseek-v4-pro').split(',').map(s => s.trim()).filter(Boolean));
const LIMIT = Number(env.RATE_LIMIT_PER_HOUR) || 600;
const TIMEOUT = 300000;

const HTML = fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf8').replace('__THF_TOKEN__', '');

const hits = new Map();
function clientIp(req) {
  return String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress || '';
}
function overLimit(req) {
  const k = clientIp(req), now = Date.now();
  let e = hits.get(k);
  if (!e || now - e.t > 3600e3) { e = { t: now, n: 0 }; hits.set(k, e); }
  e.n++;
  if (hits.size > 5000) for (const [kk, v] of hits) if (now - v.t > 3600e3) hits.delete(kk);
  return e.n > LIMIT;
}
function codeOk(req) {
  if (!ACCESS_CODE) return true;
  let c = String(req.headers['x-access-code'] || '');
  try { c = decodeURIComponent(c); } catch (e) { /* 保持原样 */ }
  const a = Buffer.from(c), b = Buffer.from(ACCESS_CODE);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function send(res, code, type, body) {
  res.writeHead(code, {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'SAMEORIGIN'
  });
  res.end(body);
}
const json = (res, code, obj) => send(res, code, 'application/json; charset=utf-8', JSON.stringify(obj));
function readBody(req, max) {
  return new Promise((resolve, reject) => {
    let n = 0; const chunks = [];
    req.on('data', d => { n += d.length; if (n > max) { reject(new Error('too_large')); req.destroy(); } else chunks.push(d); });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}
async function upstream(url, key, body, method) {
  try {
    const r = await fetch(url, {
      method: method || 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
      body: body == null ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT)
    });
    return { code: r.status, text: await r.text() };
  } catch (e) {
    return { code: 502, text: JSON.stringify({ error: 'network' }) };
  }
}
const status = req => ({ mode: 'web', text: !!DS_KEY, image: !!MM_KEY, ark: !!ARK_KEY, tts: !!(TC_ID && TC_KEY), textModel: TEXT_MODEL, writeModel: WRITE_MODEL, needCode: !!ACCESS_CODE, codeOk: codeOk(req) });

// 腾讯云 API 3.0 签名（TC3-HMAC-SHA256），与赛珍珠讲解机器人使用的算法一致
function tc3Headers(secretId, secretKey, host, service, action, version, payload, ts) {
  ts = ts || Math.floor(Date.now() / 1000);
  const date = new Date(ts * 1000).toISOString().slice(0, 10);
  const ct = 'application/json; charset=utf-8';
  const sha = x => crypto.createHash('sha256').update(x, 'utf8').digest('hex');
  const hmac = (k, m) => crypto.createHmac('sha256', k).update(m, 'utf8').digest();
  const scope = date + '/' + service + '/tc3_request';
  const canonical = 'POST\n/\n\ncontent-type:' + ct + '\nhost:' + host + '\n\ncontent-type;host\n' + sha(payload);
  const toSign = 'TC3-HMAC-SHA256\n' + ts + '\n' + scope + '\n' + sha(canonical);
  const signature = crypto.createHmac('sha256', hmac(hmac(hmac('TC3' + secretKey, date), service), 'tc3_request')).update(toSign, 'utf8').digest('hex');
  return {
    'Content-Type': ct,
    'Authorization': 'TC3-HMAC-SHA256 Credential=' + secretId + '/' + scope + ', SignedHeaders=content-type;host, Signature=' + signature,
    'X-TC-Action': action, 'X-TC-Version': version, 'X-TC-Timestamp': String(ts)
  };
}
async function tts(b) {
  const text = typeof b.text === 'string' ? b.text.trim() : '';
  if (!text || Array.from(text).length > 150) return { code: 400, text: JSON.stringify({ error: 'bad_text' }) };
  const voice = Number.isInteger(+b.voice) && +b.voice > 0 ? +b.voice : 403011;
  const speed = Math.max(-2, Math.min(6, Number(b.speed) || 0));
  const payload = JSON.stringify({ Text: text, SessionId: crypto.randomUUID(), VoiceType: voice, Codec: 'mp3', SampleRate: 24000, Speed: speed, Volume: 0, PrimaryLanguage: 1 });
  try {
    const r = await fetch(TTS_URL, { method: 'POST', headers: tc3Headers(TC_ID, TC_KEY, TTS_HOST, 'tts', 'TextToVoice', '2019-08-23', payload), body: payload, signal: AbortSignal.timeout(60000) });
    return { code: r.ok ? 200 : 502, text: await r.text() };
  } catch (e) { return { code: 502, text: JSON.stringify({ error: 'network' }) }; }
}

const server = http.createServer(async (req, res) => {
  try {
    const p = new URL(req.url, 'http://localhost').pathname;
    if (req.method === 'GET' && (p === '/' || p === '/index.html')) return send(res, 200, 'text/html; charset=utf-8', HTML);
    if (p === '/healthz') return json(res, 200, { ok: true });
    if (p === '/config.js') return send(res, 200, 'application/javascript; charset=utf-8', "window.THF_API = '';");
    if (!p.startsWith('/api/')) return json(res, 404, { error: 'not_found' });
    if (p === '/api/status') return json(res, 200, status(req));
    if (!codeOk(req)) return json(res, 403, { error: 'bad_code' });
    if (p === '/api/ping') return json(res, 200, { ok: true });
    if (overLimit(req)) return json(res, 429, { error: 'rate' });
    if (p === '/api/test') {
      if (!DS_KEY) return json(res, 412, { error: 'no_key' });
      const r = await upstream(DS_BASE + '/models', DS_KEY, null, 'GET');
      return json(res, 200, { ok: r.code === 200, msg: r.code === 200 ? '' : r.code === 401 ? '密钥无效' : r.code === 502 ? '服务器连不上 DeepSeek' : '接口返回 ' + r.code });
    }
    if (p === '/api/config') return json(res, 403, { error: 'web_mode' });
    if (req.method !== 'POST') return json(res, 405, { error: 'method' });
    const raw = await readBody(req, 6e6);
    let b;
    try { b = JSON.parse(raw || '{}'); } catch (e) { return json(res, 400, { error: 'bad_json' }); }
    if (p === '/api/deepseek/chat/completions') {
      if (!DS_KEY) return json(res, 412, { error: 'no_key' });
      if (!MODELS.has(b.model)) b.model = TEXT_MODEL;
      b.stream = false;
      const r = await upstream(DS_BASE + '/chat/completions', DS_KEY, b);
      return send(res, r.code, 'application/json; charset=utf-8', r.text);
    }
    if (p === '/api/seedream/images/generations') {
      if (!ARK_KEY) return json(res, 412, { error: 'no_key' });
      if (!SD_MODEL_RE.test(String(b.model || ''))) b.model = 'doubao-seedream-5-0-flash-260915';
      delete b.sequential_image_generation;
      b.watermark = false;
      const r = await upstream(ARK_URL, ARK_KEY, b);
      return send(res, r.code, 'application/json; charset=utf-8', r.text);
    }
    if (p === '/api/tts') {
      if (!TC_ID || !TC_KEY) return json(res, 412, { error: 'no_key' });
      const r = await tts(b);
      return send(res, r.code, 'application/json; charset=utf-8', r.text);
    }
    if (p === '/api/minimax/image_generation') {
      if (!MM_KEY) return json(res, 412, { error: 'no_key' });
      b.model = 'image-01';
      b.n = 1;
      const r = await upstream(MM_URL, MM_KEY, b);
      return send(res, r.code, 'application/json; charset=utf-8', r.text);
    }
    return json(res, 404, { error: 'not_found' });
  } catch (e) {
    const big = e && e.message === 'too_large';
    if (!res.headersSent) json(res, big ? 413 : 500, { error: big ? 'too_large' : 'server' });
  }
});
server.requestTimeout = TIMEOUT + 30000;
server.listen(PORT, () => {
  console.log('绘声绘色网页版已启动：http://localhost:' + PORT);
  console.log('DeepSeek：' + (DS_KEY ? '已配置' : '未配置') + '；Seedream：' + (ARK_KEY ? '已配置' : '未配置') + '；MiniMax：' + (MM_KEY ? '已配置' : '未配置') + '；腾讯云语音：' + (TC_ID && TC_KEY ? '已配置' : '未配置') + '；访问码：' + (ACCESS_CODE ? '已启用' : '未启用'));
});

module.exports = { tc3Headers };
