'use strict';
/*
 * 绘声绘色 云函数代理 thf-proxy（腾讯云 CloudBase 云函数，Node.js 18 及以上运行环境）
 * 作用：静态网页通过它调用 DeepSeek（文字）和 MiniMax（图片），密钥只放在云函数的环境变量里。
 * 访问方式：在 CloudBase“HTTP 访问服务”里为本函数添加一条路由，例如 /thf，
 *          然后把 static-site/config.js 里的 THF_API 改成 https://<访问域名>/thf
 * 环境变量：
 *   DEEPSEEK_API_KEY  必填
 *   ARK_API_KEY       火山方舟 API Key（Seedream 4.0 生图，推荐）
 *   MINIMAX_API_KEY   MiniMax 按量付费密钥（可选，与上面二选一或都填）
 *   TENCENT_SECRET_ID / TENCENT_SECRET_KEY  腾讯云语音合成（可选，朗读用）
 *   ACCESS_CODE       建议填写，读者需输入访问码才能生成
 *   ALLOW_ORIGIN      建议填写静态网站的域名，如 https://xxx.tcloudbaseapp.com；不填则允许任何网站调用
 *   DEEPSEEK_MODEL    可选，默认 deepseek-v4-flash
 */
const crypto = require('crypto');

const env = process.env;
const DS_KEY = env.DEEPSEEK_API_KEY || '';
const MM_KEY = env.MINIMAX_API_KEY || '';
const ARK_KEY = env.ARK_API_KEY || '';
const ARK_URL = env.ARK_URL || 'https://ark.cn-beijing.volces.com/api/v3/images/generations';
const TC_ID = env.TENCENT_SECRET_ID || '';
const TC_KEY = env.TENCENT_SECRET_KEY || '';
const TTS_HOST = env.TENCENT_TTS_HOST || 'tts.tencentcloudapi.com';
const TTS_URL = env.TENCENT_TTS_URL || 'https://' + TTS_HOST;
const ACCESS_CODE = env.ACCESS_CODE || '';
const ALLOW_ORIGIN = env.ALLOW_ORIGIN || '*';
const DS_BASE = (env.DEEPSEEK_BASE || 'https://api.deepseek.com').replace(/\/$/, '');
const MM_URL = env.MINIMAX_URL || 'https://api.minimaxi.com/v1/image_generation';
const TEXT_MODEL = env.DEEPSEEK_MODEL || 'deepseek-v4-flash';
const WRITE_MODEL = env.DEEPSEEK_WRITE_MODEL || 'deepseek-v4-pro';
const MODELS = new Set((env.DEEPSEEK_MODELS || 'deepseek-v4-flash,deepseek-v4-pro').split(',').map(s => s.trim()).filter(Boolean));
const TIMEOUT = 280000;
const ROUTES = ['/api/status', '/api/ping', '/api/test', '/api/config', '/api/deepseek/chat/completions', '/api/minimax/image_generation', '/api/seedream/images/generations', '/api/tts'];

function reply(code, body) {
  return {
    statusCode: code,
    isBase64Encoded: false,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': ALLOW_ORIGIN,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-App-Token, X-Access-Code',
      'Access-Control-Max-Age': '86400',
      'Vary': 'Origin'
    },
    body: typeof body === 'string' ? body : JSON.stringify(body)
  };
}
function header(event, name) {
  const h = event.headers || {};
  const k = Object.keys(h).find(x => x.toLowerCase() === name);
  return k ? String(h[k]) : '';
}
function codeOk(event) {
  if (!ACCESS_CODE) return true;
  let c = header(event, 'x-access-code');
  try { c = decodeURIComponent(c); } catch (e) { /* 保持原样 */ }
  const a = Buffer.from(c), b = Buffer.from(ACCESS_CODE);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function readBody(event) {
  let b = event.body;
  if (b == null) return '';
  if (typeof b === 'object') return JSON.stringify(b);
  b = String(b);
  if (event.isBase64Encoded === true || event.isBase64Encoded === 'true') b = Buffer.from(b, 'base64').toString('utf8');
  return b;
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

// 腾讯云 API 3.0 签名（TC3-HMAC-SHA256），与赛珍珠讲解机器人使用的算法一致
function tc3Headers(secretId, secretKey, host, service, action, version, payload) {
  const ts = Math.floor(Date.now() / 1000);
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

exports.main = async (event) => {
  event = event || {};
  const method = String(event.httpMethod || 'GET').toUpperCase();
  if (method === 'OPTIONS') return reply(204, '');
  const path = String(event.path || '');
  const route = ROUTES.find(r => path === r || path.endsWith(r));
  if (!route) return reply(404, { error: 'not_found', path });

  if (route === '/api/status') {
    return reply(200, { mode: 'web', text: !!DS_KEY, image: !!MM_KEY, ark: !!ARK_KEY, tts: !!(TC_ID && TC_KEY), textModel: TEXT_MODEL, writeModel: WRITE_MODEL, needCode: !!ACCESS_CODE, codeOk: codeOk(event) });
  }
  if (!codeOk(event)) return reply(403, { error: 'bad_code' });
  if (route === '/api/ping') return reply(200, { ok: true });
  if (route === '/api/config') return reply(403, { error: 'web_mode' });
  if (route === '/api/test') {
    if (!DS_KEY) return reply(412, { error: 'no_key' });
    const r = await upstream(DS_BASE + '/models', DS_KEY, null, 'GET');
    return reply(200, { ok: r.code === 200, msg: r.code === 200 ? '' : r.code === 401 ? '密钥无效' : r.code === 502 ? '云函数连不上 DeepSeek' : '接口返回 ' + r.code });
  }
  if (method !== 'POST') return reply(405, { error: 'method' });
  const raw = readBody(event);
  if (raw.length > 6e6) return reply(413, { error: 'too_large' });
  let b;
  try { b = JSON.parse(raw || '{}'); } catch (e) { return reply(400, { error: 'bad_json' }); }

  if (route === '/api/deepseek/chat/completions') {
    if (!DS_KEY) return reply(412, { error: 'no_key' });
    if (!MODELS.has(b.model)) b.model = TEXT_MODEL;
    b.stream = false;
    const r = await upstream(DS_BASE + '/chat/completions', DS_KEY, b);
    return reply(r.code, r.text);
  }
  if (route === '/api/seedream/images/generations') {
    if (!ARK_KEY) return reply(412, { error: 'no_key' });
    if (!/^(doubao|dola)-seedream-[a-z0-9-]+$/.test(String(b.model || ''))) b.model = 'doubao-seedream-5-0-flash-260915';
    delete b.sequential_image_generation;
    b.watermark = false;
    const r = await upstream(ARK_URL, ARK_KEY, b);
    return reply(r.code, r.text);
  }
  if (route === '/api/tts') {
    if (!TC_ID || !TC_KEY) return reply(412, { error: 'no_key' });
    const text = typeof b.text === 'string' ? b.text.trim() : '';
    if (!text || Array.from(text).length > 150) return reply(400, { error: 'bad_text' });
    const voice = Number.isInteger(+b.voice) && +b.voice > 0 ? +b.voice : 403011;
    const speed = Math.max(-2, Math.min(6, Number(b.speed) || 0));
    const payload = JSON.stringify({ Text: text, SessionId: crypto.randomUUID(), VoiceType: voice, Codec: 'mp3', SampleRate: 24000, Speed: speed, Volume: 0, PrimaryLanguage: 1 });
    try {
      const r = await fetch(TTS_URL, { method: 'POST', headers: tc3Headers(TC_ID, TC_KEY, TTS_HOST, 'tts', 'TextToVoice', '2019-08-23', payload), body: payload, signal: AbortSignal.timeout(60000) });
      return reply(r.ok ? 200 : 502, await r.text());
    } catch (e) { return reply(502, { error: 'network' }); }
  }
  if (route === '/api/minimax/image_generation') {
    if (!MM_KEY) return reply(412, { error: 'no_key' });
    b.model = 'image-01';
    b.n = 1;
    const r = await upstream(MM_URL, MM_KEY, b);
    return reply(r.code, r.text);
  }
  return reply(404, { error: 'not_found' });
};
