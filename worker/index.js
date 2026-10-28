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

const FOLDER_MIME = "application/vnd.google-apps.folder";
async function createFolder(env, name, parent) {
  const r = await drive(env, "/drive/v3/files?fields=id", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ name, mimeType: FOLDER_MIME, ...(parent ? { parents: [parent] } : {}) }),
  });
  return (await r.json()).id;
}

async function folder(env, name, parent) {
  const key = `folder:${parent || "root"}:${name}`;
  const saved = await env.STORE.get(key);
  if (saved) return saved;
  const id = await createFolder(env, name, parent);
  await env.STORE.put(key, id);
  return id;
}

// drive.file scope: this lists only files the Worker created, never the rest of the Drive.
async function listChildren(env, parent, extra = "") {
  const files = [];
  let pageToken = "";
  do {
    const q = new URLSearchParams({
      q: `'${parent}' in parents and trashed = false${extra ? ` and ${extra}` : ""}`,
      fields: "nextPageToken, files(id, name, mimeType, size, md5Checksum, createdTime)", pageSize: "1000",
      ...(pageToken ? { pageToken } : {}),
    });
    const page = await (await drive(env, `/drive/v3/files?${q}`)).json();
    files.push(...(page.files || []));
    pageToken = page.nextPageToken;
  } while (pageToken);
  return files;
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

// One KV key per image (img:<id>, item copied into metadata for listing), so parallel
// uploads never overwrite each other. LIST_KEY is the older single-array format, still read.
const readLegacy = async (env) => (await env.STORE.get(LIST_KEY, "json")) || [];
const writeLegacy = (env, list) => env.STORE.put(LIST_KEY, JSON.stringify(list));
const putItem = (env, item) => env.STORE.put(`img:${item.id}`, JSON.stringify(item), { metadata: item });
async function getItem(env, id) {
  return (await env.STORE.get(`img:${id}`, "json")) || (await readLegacy(env)).find((i) => i.id === id) || null;
}
async function readList(env) {
  const items = [];
  let cursor;
  do {
    const page = await env.STORE.list({ prefix: "img:", cursor });
    for (const key of page.keys) items.push(key.metadata || (await env.STORE.get(key.name, "json")));
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  const seen = new Set(items.map((i) => i.id));
  return [...items, ...(await readLegacy(env)).filter((i) => !seen.has(i.id))].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}
async function removeItem(env, id) {
  await env.STORE.delete(`img:${id}`);
  const legacy = await readLegacy(env);
  if (legacy.some((i) => i.id === id)) await writeLegacy(env, legacy.filter((i) => i.id !== id));
}
const publicUrl = (origin, item) => `${origin}/img/${item.id}.png`;

// ---------- Source library ----------
// Sample photos for the app live in "<FOLDER_NAME>/Nguồn ảnh/<group>/". Drive is the only index:
// the app downloads one group at a time and compares md5 to fetch only new or changed files.
const SOURCE_FOLDER = "Nguồn ảnh";
const GROUP_RE = /^[\p{L}\p{N}][\p{L}\p{N} -]{0,59}$/u;
const SOURCE_TYPES = ["image/jpeg", "image/png", "image/webp"];
const quote = (value) => value.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
export const cleanFileName = (value) => String(value || "").replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").replace(/^\.+/, "").slice(0, 120);
const sourceRoot = async (env) => folder(env, SOURCE_FOLDER, await folder(env, FOLDER_NAME));
const sourceUrl = (origin, file) => `${origin}/src/${file.id}`;
async function groupFolder(env, name) {
  const found = await listChildren(env, await sourceRoot(env), `mimeType = '${FOLDER_MIME}' and name = '${quote(name)}'`);
  return found[0]?.id || null;
}
const sourceFile = (origin, f) => ({ id: f.id, name: f.name, size: Number(f.size || 0), md5: f.md5Checksum, createdAt: f.createdTime, url: sourceUrl(origin, f) });

// ---------- Support logs ----------
// "Gửi log" in the app uploads one zip here; the management page lists and downloads them.
const LOGS_FOLDER = "Logs";
const logsRoot = async (env) => folder(env, LOGS_FOLDER, await folder(env, FOLDER_NAME));
async function handleLogs(req, env, url, id) {
  const root = await logsRoot(env);
  if (!id && req.method === "GET") {
    const files = await listChildren(env, root);
    return json({ logs: files.map((f) => ({ id: f.id, name: f.name, size: Number(f.size || 0), createdAt: f.createdTime })).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))) }, 200, { "cache-control": "no-store" });
  }
  if (!id && req.method === "POST") {
    const bytes = await req.arrayBuffer();
    if (!bytes.byteLength || bytes.byteLength > 50 * 1024 * 1024) return json({ error: "File log rỗng hoặc quá 50MB." }, 400);
    const name = cleanFileName(url.searchParams.get("name")) || `log-${Date.now()}.zip`;
    const fileId = await uploadFile(env, name.endsWith(".zip") ? name : `${name}.zip`, "application/zip", bytes, root);
    return json({ id: fileId, name }, 201);
  }
  if (!id || !/^[\w-]+$/.test(id)) return json({ error: "Not found" }, 404);
  const meta = await (await drive(env, `/drive/v3/files/${id}?fields=parents,name`)).json();
  if (!(meta.parents || []).includes(root)) return json({ error: "Không tìm thấy log." }, 404);
  if (req.method === "DELETE") {
    await drive(env, `/drive/v3/files/${id}`, { method: "DELETE" });
    return json({ ok: true });
  }
  if (req.method === "GET") {
    const r = await drive(env, `/drive/v3/files/${id}?alt=media`);
    return new Response(r.body, { headers: { "content-type": "application/zip", "content-disposition": `attachment; filename="${String(meta.name).replace(/"/g, "")}"`, "cache-control": "no-store" } });
  }
  return json({ error: "Not found" }, 404);
}

async function handleSources(req, env, url, parts) {
  const [rawGroup, fileId] = parts;
  if (!rawGroup) {
    if (req.method === "GET") {
      const folders = await listChildren(env, await sourceRoot(env), `mimeType = '${FOLDER_MIME}'`);
      const groups = await Promise.all(folders.map(async (f) => ({ name: f.name, count: (await listChildren(env, f.id, `mimeType != '${FOLDER_MIME}'`)).length })));
      return json({ groups: groups.sort((a, b) => a.name.localeCompare(b.name, "vi")) }, 200, { "cache-control": "no-store" });
    }
    if (req.method === "POST") {
      const name = String((await req.json().catch(() => ({}))).name || "").trim();
      if (!GROUP_RE.test(name)) return json({ error: "Tên nhóm chỉ gồm chữ, số, dấu cách hoặc gạch ngang." }, 400);
      if (await groupFolder(env, name)) return json({ error: "Nhóm đã có." }, 409);
      await createFolder(env, name, await sourceRoot(env));
      return json({ name, count: 0 }, 201);
    }
    return json({ error: "Not found" }, 404);
  }
  const group = decodeURIComponent(rawGroup);
  if (!GROUP_RE.test(group)) return json({ error: "Tên nhóm không hợp lệ." }, 400);
  const parent = await groupFolder(env, group);
  if (!parent) return json({ error: "Không tìm thấy nhóm." }, 404);

  if (fileId) {
    if (req.method !== "DELETE" || !/^[\w-]+$/.test(fileId)) return json({ error: "Not found" }, 404);
    const meta = await (await drive(env, `/drive/v3/files/${fileId}?fields=parents`)).json();
    if (!(meta.parents || []).includes(parent)) return json({ error: "Ảnh không thuộc nhóm này." }, 404);
    await drive(env, `/drive/v3/files/${fileId}`, { method: "DELETE" });
    return json({ ok: true });
  }
  if (req.method === "GET") {
    const files = await listChildren(env, parent, `mimeType != '${FOLDER_MIME}'`);
    return json({ group, files: files.map((f) => sourceFile(url.origin, f)).sort((a, b) => a.name.localeCompare(b.name)) }, 200, { "cache-control": "no-store" });
  }
  if (req.method === "DELETE") {
    if ((await listChildren(env, parent)).length) return json({ error: "Xoá hết ảnh trong nhóm trước." }, 400);
    await drive(env, `/drive/v3/files/${parent}`, { method: "DELETE" });
    return json({ ok: true });
  }
  if (req.method === "POST") {
    const mime = (req.headers.get("content-type") || "").split(";")[0].trim();
    if (!SOURCE_TYPES.includes(mime)) return json({ error: "Chỉ nhận ảnh JPG, PNG hoặc WebP." }, 400);
    const bytes = await req.arrayBuffer();
    if (!bytes.byteLength || bytes.byteLength > 25 * 1024 * 1024) return json({ error: "Ảnh rỗng hoặc quá 25MB." }, 400);
    // The app matches files by name, so a repeated name gets a numbered suffix instead of a duplicate.
    let name = cleanFileName(url.searchParams.get("name")) || `anh-${Date.now()}.jpg`;
    const taken = new Set((await listChildren(env, parent, `mimeType != '${FOLDER_MIME}'`)).map((f) => f.name));
    const dot = name.lastIndexOf(".");
    const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
    for (let n = 2; taken.has(name); n++) name = `${stem}-${n}${ext}`;
    const id = await uploadFile(env, name, mime, bytes, parent);
    return json(sourceFile(url.origin, { id, name, size: bytes.byteLength, createdTime: new Date().toISOString() }), 201);
  }
  return json({ error: "Not found" }, 404);
}

// ---------- Routes ----------
async function handle(req, env, ctx) {
  const url = new URL(req.url);
  const path = url.pathname;

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
    const item = await getItem(env, img[1]);
    if (!item || item.status === "rejected") return new Response("Không tìm thấy ảnh.", { status: 404 });
    const r = await drive(env, `/drive/v3/files/${item.fileId}?alt=media`);
    const res = new Response(r.body, { headers: { "content-type": "image/png", "cache-control": "public, max-age=86400" } });
    ctx.waitUntil(cache.put(req, res.clone()));
    return res;
  }

  // Public source photo link for thumbnails on the management page; ids are unguessable Drive ids.
  const src = path.match(/^\/src\/([\w-]+)$/);
  if (src && req.method === "GET") {
    const cache = caches.default;
    const hit = await cache.match(req);
    if (hit) return hit;
    const r = await drive(env, `/drive/v3/files/${src[1]}?alt=media`);
    const type = r.headers.get("content-type") || "";
    if (!type.startsWith("image/")) return new Response("Không tìm thấy ảnh.", { status: 404 });
    const res = new Response(r.body, { headers: { "content-type": type, "cache-control": "public, max-age=86400" } });
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
    await putItem(env, item);
    return json({ ...item, url: publicUrl(url.origin, item) }, 201);
  }

  const logs = path.match(/^\/api\/logs(?:\/([^/]+))?$/);
  if (logs) return handleLogs(req, env, url, logs[1]);

  const sources = path.match(/^\/api\/sources(?:\/([^/]+)(?:\/([^/]+))?)?$/);
  if (sources) return handleSources(req, env, url, [sources[1], sources[2]]);

  const one = path.match(/^\/api\/images\/(\w+)$/);
  if (one && (req.method === "PATCH" || req.method === "DELETE")) {
    const item = await getItem(env, one[1]);
    if (!item) return json({ error: "Không tìm thấy ảnh." }, 404);
    if (req.method === "DELETE") {
      await drive(env, `/drive/v3/files/${item.fileId}`, { method: "DELETE" });
      await removeItem(env, item.id);
      return json({ ok: true });
    }
    const { status } = await req.json();
    if (!STATUSES.includes(status)) return json({ error: "Trạng thái không hợp lệ." }, 400);
    const updated = { ...item, status, reviewedAt: new Date().toISOString() };
    await removeItem(env, item.id);
    await putItem(env, updated);
    ctx.waitUntil(caches.default.delete(new Request(publicUrl(url.origin, updated))));
    return json({ ...updated, url: publicUrl(url.origin, updated) });
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
