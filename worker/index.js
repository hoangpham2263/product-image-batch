// Product Images API — stores generated images in a private Google Drive folder and serves
// them through stable public links for the review CSV. Same pattern as memories-api:
// refresh token in KV, drive.file scope, admin password header for writes.
const ORIGINS = ["https://hoangpham.is-a.dev", "http://localhost:8000"];
const SCOPE = "openid email https://www.googleapis.com/auth/drive.file";
const OWNER_EMAILS = ["quochoang.idx@gmail.com", "hoangpham2263@gmail.com"];
const FOLDER_NAME = "Product Image Batch";
const LIST_KEY = "images";
const STATUSES = ["awaiting_review", "accepted", "rejected"];

const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", ...headers } });

function cors(req) {
  const origin = req.headers.get("origin") || "";
  return {
    "access-control-allow-origin": ORIGINS.includes(origin) ? origin : ORIGINS[0],
    "access-control-allow-methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "access-control-allow-headers": "content-type, x-admin-key",
    vary: "origin",
  };
}

export function sameKey(a = "", b = "") {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
const isAdmin = (req, env) => !!env.ADMIN_PASSWORD && sameKey(req.headers.get("x-admin-key") || "", env.ADMIN_PASSWORD);

// Batch ids and file names come from the local app; keep them to safe characters.
export const cleanName = (value, fallback) => String(value || "").replace(/[^\w.-]/g, "_").replace(/^\.+/, "").slice(0, 120) || fallback;

// ---------- Google Drive ----------
async function accessToken(env) {
  const cached = await env.STORE.get("access_token", "json");
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const refresh = await env.STORE.get("refresh_token");
  if (!refresh) throw new Error("Chưa kết nối Google Drive.");
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, refresh_token: refresh, grant_type: "refresh_token" }),
  });
  const t = await r.json();
  if (!t.access_token) throw new Error("Google từ chối làm mới phiên: " + (t.error || r.status));
  await env.STORE.put("access_token", JSON.stringify({ token: t.access_token, exp: Date.now() + t.expires_in * 1000 }));
  return t.access_token;
}

async function drive(env, path, init = {}) {
  const token = await accessToken(env);
  const r = await fetch(`https://www.googleapis.com${path}`, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${token}` } });
  if (!r.ok && r.status !== 204) throw new Error(`Drive ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return r;
}

async function folder(env, name, parent) {
  const key = `folder:${parent || "root"}:${name}`;
  const saved = await env.STORE.get(key);
  if (saved) return saved;
  const r = await drive(env, "/drive/v3/files?fields=id", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name, mimeType: "application/vnd.google-apps.folder", ...(parent ? { parents: [parent] } : {}) }),
  });
  const { id } = await r.json();
  await env.STORE.put(key, id);
  return id;
}

async function uploadFile(env, name, mime, bytes, parent) {
  const boundary = "pib" + crypto.randomUUID();
  const head = `--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify({ name, parents: [parent] })}\r\n--${boundary}\r\ncontent-type: ${mime}\r\n\r\n`;
  const r = await drive(env, "/upload/drive/v3/files?uploadType=multipart&fields=id", {
    method: "POST",
    headers: { "content-type": `multipart/related; boundary=${boundary}` },
    body: new Blob([head, bytes, `\r\n--${boundary}--`]),
  });
  return (await r.json()).id;
}

const readList = async (env) => (await env.STORE.get(LIST_KEY, "json")) || [];
const writeList = (env, list) => env.STORE.put(LIST_KEY, JSON.stringify(list));
const publicUrl = (origin, item) => `${origin}/img/${item.id}.png`;

// ---------- Routes ----------
async function handle(req, env, ctx) {
  const url = new URL(req.url);
  const path = url.pathname;

  // Wrong password 5 times from one address: locked out for 15 minutes.
  const sentKey = req.headers.get("x-admin-key") || (path === "/oauth/start" ? url.searchParams.get("key") : "");
  if (sentKey) {
    const ip = req.headers.get("cf-connecting-ip") || "unknown";
    const fails = Number(await env.STORE.get(`fail:${ip}`)) || 0;
    if (fails >= 5) return json({ error: "Nhập sai quá nhiều lần, thử lại sau 15 phút." }, 429);
    if (!sameKey(sentKey, env.ADMIN_PASSWORD || "")) ctx.waitUntil(env.STORE.put(`fail:${ip}`, String(fails + 1), { expirationTtl: 900 }));
    else if (fails) ctx.waitUntil(env.STORE.delete(`fail:${ip}`));
  }

  if (path === "/oauth/start") {
    if (!sameKey(url.searchParams.get("key") || "", env.ADMIN_PASSWORD || "")) return new Response("Sai mật khẩu.", { status: 401 });
    const q = new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID, redirect_uri: `${url.origin}/oauth/callback`, response_type: "code",
      scope: SCOPE, access_type: "offline", prompt: "consent select_account",
    });
    return Response.redirect(`https://accounts.google.com/o/oauth2/v2/auth?${q}`, 302);
  }

  if (path === "/oauth/callback") {
    const code = url.searchParams.get("code");
    if (!code) return new Response("Thiếu mã xác thực.", { status: 400 });
    const r = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, redirect_uri: `${url.origin}/oauth/callback`, grant_type: "authorization_code" }),
    });
    const t = await r.json();
    const page = (msg, status = 200) => new Response(`<meta charset=utf-8><p style='font:16px system-ui;padding:24px'>${msg}</p>`, { status, headers: { "content-type": "text/html; charset=utf-8" } });
    const claims = t.id_token ? JSON.parse(atob(t.id_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))) : {};
    if (!OWNER_EMAILS.includes(claims.email)) return page(`Tài khoản ${claims.email || "này"} không có quyền.`, 403);
    if (!t.refresh_token) return page("Google không trả quyền truy cập lâu dài, thử lại.", 400);
    await env.STORE.put("refresh_token", t.refresh_token);
    await env.STORE.put("access_token", JSON.stringify({ token: t.access_token, exp: Date.now() + t.expires_in * 1000 }));
    await env.STORE.put("drive_email", claims.email);
    return page(`Đã kết nối Google Drive (${claims.email}). Bạn có thể đóng tab này.`);
  }

  // Public image link used in the CSV; cached at the edge.
  const img = path.match(/^\/img\/([\w-]+)\.png$/);
  if (img && req.method === "GET") {
    const cache = caches.default;
    const hit = await cache.match(req);
    if (hit) return hit;
    const item = (await readList(env)).find((i) => i.id === img[1]);
    if (!item || item.status === "rejected") return new Response("Không tìm thấy ảnh.", { status: 404 });
    const r = await drive(env, `/drive/v3/files/${item.fileId}?alt=media`);
    const res = new Response(r.body, { headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" } });
    ctx.waitUntil(cache.put(req, res.clone()));
    return res;
  }

  if (path === "/api/status" && req.method === "GET") {
    return json({ connected: !!(await env.STORE.get("refresh_token")), email: isAdmin(req, env) ? await env.STORE.get("drive_email") : undefined });
  }

  // ----- admin only below -----
  if (!path.startsWith("/api/")) return new Response("Not found", { status: 404 });
  if (!isAdmin(req, env)) return json({ error: "Sai mật khẩu quản lý." }, 401);

  if (path === "/api/images" && req.method === "GET") {
    const list = await readList(env);
    return json(list.map((i) => ({ ...i, url: publicUrl(url.origin, i) })), 200, { "cache-control": "no-store" });
  }

  // Upload one PNG: POST /api/images?batch=<batch id>&name=<item id>.png&product=<handle>
  if (path === "/api/images" && req.method === "POST") {
    const bytes = await req.arrayBuffer();
    if (!bytes.byteLength || bytes.byteLength > 25 * 1024 * 1024) return json({ error: "Ảnh rỗng hoặc quá 25MB." }, 400);
    const batch = cleanName(url.searchParams.get("batch"), "batch");
    const name = cleanName(url.searchParams.get("name"), "image.png");
    const root = await folder(env, FOLDER_NAME);
    const fileId = await uploadFile(env, name, "image/png", bytes, await folder(env, batch, root));
    const item = {
      id: crypto.randomUUID().replace(/-/g, ""), fileId, batch, name,
      product: String(url.searchParams.get("product") || "").slice(0, 200),
      size: bytes.byteLength, status: "awaiting_review", createdAt: new Date().toISOString(),
    };
    const list = await readList(env);
    list.unshift(item);
    await writeList(env, list);
    return json({ ...item, url: publicUrl(url.origin, item) }, 201);
  }

  const one = path.match(/^\/api\/images\/(\w+)$/);
  if (one && (req.method === "PATCH" || req.method === "DELETE")) {
    const list = await readList(env);
    const index = list.findIndex((i) => i.id === one[1]);
    if (index < 0) return json({ error: "Không tìm thấy ảnh." }, 404);
    if (req.method === "DELETE") {
      await drive(env, `/drive/v3/files/${list[index].fileId}`, { method: "DELETE" });
      list.splice(index, 1);
      await writeList(env, list);
      return json({ ok: true });
    }
    const { status } = await req.json();
    if (!STATUSES.includes(status)) return json({ error: "Trạng thái không hợp lệ." }, 400);
    list[index] = { ...list[index], status, reviewedAt: new Date().toISOString() };
    await writeList(env, list);
    ctx.waitUntil(caches.default.delete(new Request(publicUrl(url.origin, list[index]))));
    return json({ ...list[index], url: publicUrl(url.origin, list[index]) });
  }

  return json({ error: "Not found" }, 404);
}

export default {
  async fetch(req, env, ctx) {
    if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) });
    let res;
    try {
      res = await handle(req, env, ctx);
    } catch (e) {
      res = json({ error: e.message || "Lỗi máy chủ." }, 500);
    }
    const h = new Headers(res.headers);
    for (const [k, v] of Object.entries(cors(req))) h.set(k, v);
    return new Response(res.body, { status: res.status, headers: h });
  },
};
