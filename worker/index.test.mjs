import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { cleanName } from "./index.js";

// In-memory KV, edge cache and Google endpoints.
function setup() {
  const kv = new Map([["refresh_token", "r"]]);
  const meta = new Map();
  const env = {
    ADMIN_PASSWORD: "secret", APP_PASSWORD: "app-pass", GOOGLE_CLIENT_ID: "id", GOOGLE_CLIENT_SECRET: "s",
    STORE: {
      get: async (k, type) => (kv.has(k) ? (type === "json" ? JSON.parse(kv.get(k)) : kv.get(k)) : null),
      put: async (k, v, opts) => { kv.set(k, v); if (opts?.metadata) meta.set(k, opts.metadata); },
      delete: async (k) => { kv.delete(k); meta.delete(k); },
      list: async ({ prefix }) => ({ keys: [...kv.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name, metadata: meta.get(name) })), list_complete: true }),
    },
  };
  const files = new Map();
  // Drive metadata for list queries: id -> { name, parents, folder, mime }.
  const nodes = new Map();
  globalThis.caches = { default: { match: async () => null, put: async () => {}, delete: async () => {} } };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "a", expires_in: 3600 });
    if (url.includes("/drive/v3/files?fields=id")) {
      const meta = JSON.parse(init.body);
      const id = `folder-${nodes.size}`;
      nodes.set(id, { name: meta.name, parents: meta.parents || [], folder: true });
      return Response.json({ id });
    }
    if (url.includes("/drive/v3/files?q=")) {
      const q = new URL(url).searchParams.get("q");
      const parent = q.match(/^'([^']+)' in parents/)[1];
      const name = q.match(/name = '((?:[^'\\]|\\.)*)'/)?.[1];
      const list = [...nodes].filter(([, n]) => n.parents.includes(parent) && (!name || n.name === name) &&
        (!q.includes("mimeType = ") || n.folder) && (!q.includes("mimeType != ") || !n.folder));
      return Response.json({ files: list.map(([id, n]) => ({ id, name: n.name, mimeType: n.mime, size: "1", md5Checksum: "m" + id })) });
    }
    const metaOnly = url.match(/files\/([\w-]+)\?fields=parents/);
    if (metaOnly) return Response.json({ parents: nodes.get(metaOnly[1])?.parents || [] });
    if (url.includes("/upload/drive/v3/files")) {
      // Keep only the media part of the multipart/related body, as Drive does.
      const body = new Uint8Array(await new Response(init.body).arrayBuffer());
      const text = new TextDecoder("latin1").decode(body);
      const start = text.indexOf("\r\n\r\n", text.indexOf("content-type:", text.indexOf("--", 2))) + 4;
      const end = text.lastIndexOf("\r\n--");
      const id = `file-${files.size}`;
      const meta = JSON.parse(text.slice(text.indexOf("{"), text.indexOf("}") + 1));
      const mime = text.slice(start - 4).length && text.match(/content-type: (image\/\w+)/)?.[1];
      files.set(id, body.slice(start, end));
      nodes.set(id, { name: meta.name, parents: meta.parents, mime });
      return Response.json({ id });
    }
    const media = url.match(/files\/([\w-]+)\?alt=media/);
    if (media) return new Response(files.get(media[1]), { headers: { "content-type": nodes.get(media[1])?.mime || "image/png" } });
    if (init.method === "DELETE") { const id = url.split("/files/")[1]; files.delete(id); nodes.delete(id); return new Response(null, { status: 204 }); }
    throw new Error(`unexpected ${url}`);
  };
  const ctx = { waitUntil: () => {} };
  const call = (path, init = {}) => worker.fetch(new Request(`https://api.test${path}`, init), env, ctx);
  return { call, files, kv };
}

test("upload stores the image in Drive and serves it from a public link", async () => {
  const { call } = setup();
  const png = new Uint8Array([137, 80, 78, 71]);
  const created = await call("/api/images?batch=2026-10-27_x&name=001-tee.png&product=tee", { method: "POST", headers: { "x-admin-key": "secret" }, body: png });
  assert.equal(created.status, 201);
  const item = await created.json();
  assert.match(item.url, /^https:\/\/api\.test\/img\/\w+\.png$/);
  const image = await call(new URL(item.url).pathname);
  assert.equal(image.status, 200);
  assert.deepEqual(new Uint8Array(await image.arrayBuffer()), png);
});

test("writes need the admin key; review status and delete work", async () => {
  const { call, files } = setup();
  assert.equal((await call("/api/images", { method: "POST", body: "x" })).status, 401);
  assert.equal((await call("/api/images")).status, 401);
  const item = await (await call("/api/images?batch=b&name=a.png", { method: "POST", headers: { "x-admin-key": "secret" }, body: "x" })).json();
  const patched = await call(`/api/images/${item.id}`, { method: "PATCH", headers: { "x-admin-key": "secret", "content-type": "application/json" }, body: JSON.stringify({ status: "rejected" }) });
  assert.equal((await patched.json()).status, "rejected");
  assert.equal((await call(new URL(item.url).pathname)).status, 404, "rejected images are not served");
  await call(`/api/images/${item.id}`, { method: "DELETE", headers: { "x-admin-key": "secret" } });
  assert.equal(files.size, 0);
  assert.deepEqual(await (await call("/api/images", { headers: { "x-admin-key": "secret" } })).json(), []);
});

test("names from the local app are reduced to safe characters", () => {
  assert.equal(cleanName("../../etc/passwd", "x"), "_.._etc_passwd");
  assert.equal(cleanName("", "fallback.png"), "fallback.png");
});

test("wrong passwords never lock an address; existing lock records do not block valid login", async () => {
  const { call, kv } = setup();
  const ip = "192.0.2.1";
  kv.set(`fail:${ip}`, "5");
  const headers = { "cf-connecting-ip": ip };
  for (let n = 0; n < 8; n++) {
    const denied = await call("/api/images", { headers: { ...headers, "x-admin-key": "wrong" } });
    assert.equal(denied.status, 401);
    assert.equal((await denied.json()).error, "Sai mật khẩu.");
  }
  assert.equal((await call("/api/images", { headers: { ...headers, "x-admin-key": "secret" } })).status, 200);
  assert.equal((await call("/oauth/start?key=wrong", { headers })).status, 401);
  assert.equal((await call("/oauth/start?key=secret", { headers })).status, 302);
  assert.equal(kv.get(`fail:${ip}`), "5", "login no longer reads or updates old lock records");
});

test("parallel uploads all stay listed and served; old single-list items still work", async () => {
  const { call, kv } = setup();
  kv.set("images", JSON.stringify([{ id: "old1", fileId: "file-old", batch: "b", name: "o.png", status: "awaiting_review", createdAt: "2020-01-01T00:00:00Z" }]));
  const admin = { "x-admin-key": "secret" };
  const made = await Promise.all([1, 2, 3, 4, 5].map((n) => call(`/api/images?batch=b&name=${n}.png`, { method: "POST", headers: admin, body: String(n) }).then((r) => r.json())));
  const list = await (await call("/api/images", { headers: admin })).json();
  assert.equal(list.length, 6);
  for (const item of made) assert.equal((await call(new URL(item.url).pathname)).status, 200);
  const patched = await call("/api/images/old1", { method: "PATCH", headers: { ...admin, "content-type": "application/json" }, body: JSON.stringify({ status: "accepted" }) });
  const body = await patched.json();
  assert.equal(body.status, "accepted", JSON.stringify(body));
  assert.equal((await (await call("/api/images", { headers: admin })).json()).length, 6);
});

test("source groups are Drive folders: create, upload, list, rename duplicates, delete", async () => {
  const { call } = setup();
  const admin = { "x-admin-key": "secret" };
  assert.equal((await call("/api/sources")).status, 401);
  assert.equal((await call("/api/sources", { method: "POST", headers: admin, body: JSON.stringify({ name: "../x" }) })).status, 400);
  assert.equal((await call("/api/sources", { method: "POST", headers: admin, body: JSON.stringify({ name: "Áo" }) })).status, 201);
  assert.equal((await call("/api/sources", { method: "POST", headers: admin, body: JSON.stringify({ name: "Áo" }) })).status, 409);
  const group = `/api/sources/${encodeURIComponent("Áo")}`;
  assert.equal((await call(`${group}?name=a.txt`, { method: "POST", headers: { ...admin, "content-type": "text/plain" }, body: "x" })).status, 400);
  const first = await (await call(`${group}?name=tee.jpg`, { method: "POST", headers: { ...admin, "content-type": "image/jpeg" }, body: "one" })).json();
  const second = await (await call(`${group}?name=tee.jpg`, { method: "POST", headers: { ...admin, "content-type": "image/jpeg" }, body: "two" })).json();
  assert.equal(second.name, "tee-2.jpg");
  const listed = await (await call(group, { headers: admin })).json();
  assert.deepEqual(listed.files.map((f) => f.name), ["tee-2.jpg", "tee.jpg"]);
  assert.ok(listed.files.every((f) => f.md5));
  const groups = await (await call("/api/sources", { headers: admin })).json();
  assert.deepEqual(groups.groups, [{ name: "Áo", count: 2 }]);
  const image = await call(new URL(first.url).pathname);
  assert.equal(image.headers.get("content-type"), "image/jpeg");
  assert.equal(await image.text(), "one");
  assert.equal((await call(group, { method: "DELETE", headers: admin })).status, 400, "a group with photos is not deleted");
  for (const f of listed.files) assert.equal((await call(`${group}/${f.id}`, { method: "DELETE", headers: admin })).status, 200);
  assert.equal((await call(group, { method: "DELETE", headers: admin })).status, 200);
  assert.deepEqual((await (await call("/api/sources", { headers: admin })).json()).groups, []);
});

test("support logs: upload a zip, list it, download it, delete it", async () => {
  const { call } = setup();
  const admin = { "x-admin-key": "secret" };
  assert.equal((await call("/api/logs")).status, 401);
  const zip = new Uint8Array([80, 75, 3, 4, 1, 2]);
  const created = await (await call("/api/logs?name=2026-10-28_v1.0.9_mac.zip", { method: "POST", headers: admin, body: zip })).json();
  const listed = await (await call("/api/logs", { headers: admin })).json();
  assert.deepEqual(listed.logs.map((l) => l.name), ["2026-10-28_v1.0.9_mac.zip"]);
  const file = await call(`/api/logs/${created.id}`, { headers: admin });
  assert.equal(file.headers.get("content-type"), "application/zip");
  assert.equal((await call(`/api/logs/${created.id}`, { method: "DELETE", headers: admin })).status, 200);
  assert.deepEqual((await (await call("/api/logs", { headers: admin })).json()).logs, []);
});

test("the app password reaches only the app's calls; the admin password reaches everything", async () => {
  const { call } = setup();
  const app = { "x-admin-key": "app-pass" }, admin = { "x-admin-key": "secret" };
  assert.equal((await call("/api/app-check", { headers: app })).status, 200);
  assert.equal((await call("/api/images?batch=b&name=a.png", { method: "POST", headers: app, body: "x" })).status, 201);
  assert.equal((await call("/api/logs?name=a.zip", { method: "POST", headers: app, body: "zip" })).status, 201);
  assert.equal((await call("/api/sources", { headers: app })).status, 200);
  for (const [path, init] of [["/api/images", {}], ["/api/logs", {}], ["/api/sources", { method: "POST", body: "{}" }]]) {
    assert.equal((await call(path, { ...init, headers: app })).status, 403, `app password must not reach ${init.method || "GET"} ${path}`);
  }
  assert.equal((await call("/api/images", { headers: admin })).status, 200);
  assert.equal((await call("/api/app-check", { headers: { "x-admin-key": "wrong" } })).status, 401);
});

test("the app password sends at most 10 logs a day from one address", async () => {
  const { call } = setup();
  const headers = { "x-admin-key": "app-pass", "cf-connecting-ip": "198.51.100.7" };
  for (let n = 0; n < 10; n++) assert.equal((await call(`/api/logs?name=l${n}.zip`, { method: "POST", headers, body: "zip" })).status, 201);
  assert.equal((await call("/api/logs?name=l10.zip", { method: "POST", headers, body: "zip" })).status, 429);
  assert.equal((await call("/api/logs?name=admin.zip", { method: "POST", headers: { "x-admin-key": "secret", "cf-connecting-ip": "198.51.100.7" }, body: "zip" })).status, 201);
});
