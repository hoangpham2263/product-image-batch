import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { cleanName } from "./index.js";

// In-memory KV, edge cache and Google endpoints.
function setup() {
  const kv = new Map([["refresh_token", "r"]]);
  const env = {
    ADMIN_PASSWORD: "secret", GOOGLE_CLIENT_ID: "id", GOOGLE_CLIENT_SECRET: "s",
    STORE: {
      get: async (k, type) => (kv.has(k) ? (type === "json" ? JSON.parse(kv.get(k)) : kv.get(k)) : null),
      put: async (k, v) => kv.set(k, v),
      delete: async (k) => kv.delete(k),
    },
  };
  const files = new Map();
  globalThis.caches = { default: { match: async () => null, put: async () => {}, delete: async () => {} } };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "a", expires_in: 3600 });
    if (url.includes("/drive/v3/files?fields=id")) return Response.json({ id: `folder-${files.size}` });
    if (url.includes("/upload/drive/v3/files")) {
      // Keep only the media part of the multipart/related body, as Drive does.
      const body = new Uint8Array(await new Response(init.body).arrayBuffer());
      const text = new TextDecoder("latin1").decode(body);
      const start = text.indexOf("\r\n\r\n", text.indexOf("content-type:", text.indexOf("--", 2))) + 4;
      const end = text.lastIndexOf("\r\n--");
      const id = `file-${files.size}`;
      files.set(id, body.slice(start, end));
      return Response.json({ id });
    }
    const media = url.match(/files\/([\w-]+)\?alt=media/);
    if (media) return new Response(files.get(media[1]));
    if (init.method === "DELETE") { files.delete(url.split("/files/")[1]); return new Response(null, { status: 204 }); }
    throw new Error(`unexpected ${url}`);
  };
  const ctx = { waitUntil: () => {} };
  const call = (path, init = {}) => worker.fetch(new Request(`https://api.test${path}`, init), env, ctx);
  return { call, files };
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
