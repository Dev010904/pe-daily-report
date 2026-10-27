// Front door of the Daily Report website.
// 1. Never serve the app over plain http (a tampered page could steal a
//    password): always redirect to https.
// 2. Add the security headers to every response.
// 3. Hand out the Android app only to someone who is logged in.
const SUPABASE_URL = 'https://bqwgdlvvtosfspyoqmal.supabase.co';
// Public key (the same one the website itself uses); access is decided by
// the database rules for the login token, not by this key.
const SUPABASE_KEY = 'sb_publishable_BAWkjUDeegmjxR6hGmNOAg_k7-8CgHJ';

const APK_ASSET = '/private-app/pe-daily-report.apk';

const SECURITY_HEADERS = {
  'Content-Security-Policy':
    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; " +
    "img-src 'self' data: blob:; font-src 'self' data: https://fonts.gstatic.com; " +
    `connect-src 'self' ${SUPABASE_URL} wss://bqwgdlvvtosfspyoqmal.supabase.co ` +
    "https://fonts.gstatic.com https://www.gstatic.com; worker-src 'self' blob:; frame-ancestors 'none'; " +
    "base-uri 'self'; form-action 'self'; object-src 'none'",
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'X-Robots-Tag': 'noindex, nofollow',
};

function secure(res) {
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(SECURITY_HEADERS)) out.headers.set(k, v);
  return out;
}

function plain(status, text) {
  return secure(new Response(text, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  }));
}

// True when the token belongs to a Daily Report login (pe_me returns the
// member row only for a valid, current login).
async function isMember(token) {
  if (typeof token !== 'string' || token.length > 4096 ||
      !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) {
    return false;
  }
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/pe_me`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!r.ok) return false;
    const rows = await r.json();
    return Array.isArray(rows) && rows.length === 1;
  } catch {
    return false;
  }
}

async function downloadApp(request, env, url) {
  if (request.method !== 'POST') return plain(405, 'Not allowed');
  // Browsers send their page address; it must be this website. The phone
  // app sends none. Either way a valid login token is still required.
  const origin = request.headers.get('Origin');
  if (origin !== null && origin !== url.origin) return plain(403, 'Not allowed');
  let token = '';
  try {
    const body = await request.json();
    token = body && body.token;
  } catch {
    return plain(400, 'Bad request');
  }
  if (!(await isMember(token))) return plain(401, 'Please log in again.');
  const apk = await env.ASSETS.fetch(new Request(new URL(APK_ASSET, url)));
  if (!apk.ok) return plain(404, 'App file not found.');
  return secure(new Response(apk.body, {
    status: 200,
    headers: {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': 'attachment; filename="PE-Daily-Report.apk"',
      'Cache-Control': 'no-store',
    },
  }));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol !== 'https:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }
    if (url.pathname === '/download/android') return downloadApp(request, env, url);
    // The app file is never served directly, only through the login check
    // (also when the address is disguised with %-codes or capitals).
    let path = url.pathname;
    try {
      for (let i = 0; i < 3; i++) {
        const next = decodeURIComponent(path);
        if (next === path) break;
        path = next;
      }
    } catch {
      return plain(400, 'Bad request');
    }
    if (path.toLowerCase().replace(/\/+/g, '/').includes('/private-app')) {
      return plain(404, 'Not found');
    }

    const out = secure(await env.ASSETS.fetch(request));
    // The app files change on every update; never let a stale login page linger.
    if (url.pathname === '/' || url.pathname.endsWith('.html') ||
        url.pathname === '/version.json') {
      out.headers.set('Cache-Control', 'no-store');
    }
    return out;
  },
};
