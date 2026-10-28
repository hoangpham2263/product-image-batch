import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { EventEmitter } from "node:events";
import { mkdtemp, mkdir, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "./app.mjs";

async function start() {
  const root = await mkdtemp(join(tmpdir(), "pib-app-"));
  await mkdir(join(root, "data", "source-photos", "Áo"), { recursive: true });
  const spawned = [];
  const spawnImpl = (cmd, args) => {
    const child = new EventEmitter();
    child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.pid = 1;
    spawned.push({ cmd, args, child });
    return child;
  };
  const app = createApp(root, { spawnImpl, platform: "darwin" });
  const server = createServer(async (req, res) => { if ((await app(req, res)) === false) { res.writeHead(404); res.end(); } });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { root, spawned, server, base: `http://127.0.0.1:${server.address().port}` };
}
const json = (base, path, init) => fetch(base + path, init).then(async (r) => ({ status: r.status, body: await r.json() }));

test("product and scene uploads remain independent for an unpublished listing", async () => {
  const { root, server, base } = await start();
  try {
    const url = 'https://private.test/products/unpublished';
    await json(base, '/api/queue', { method: 'PUT', body: JSON.stringify({ urls: [url] }) });
    const endpoint = `/api/reference?url=${encodeURIComponent(url)}`;
    const upload = (role, bytes) => json(base, endpoint + `&role=${role}`, { method: 'POST', headers: { 'content-type': 'image/png' }, body: bytes });
    let r = await upload('product', Buffer.alloc(200, 1));
    assert.equal(r.status, 200);
    assert.ok(r.body.urls[0].productReference);
    assert.equal(r.body.urls[0].reference, null);
    r = await upload('scene', Buffer.alloc(200, 2));
    assert.ok(r.body.urls[0].productReference && r.body.urls[0].reference);
    const map = JSON.parse(await readFile(join(root, 'workspace', 'reference-inputs', 'references.json'), 'utf8'));
    assert.notEqual(map.entries[0].file, map.entries[0].product_file);
    r = await json(base, endpoint, { method: 'DELETE' });
    assert.ok(r.body.urls[0].productReference);
    assert.equal(r.body.urls[0].reference, null);
    const response = await fetch(base + endpoint + '&role=product');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), Buffer.alloc(200, 1));
  } finally { server.close(); }
});

test("queue and per-URL reference images are stored in the workflow formats", async () => {
  const { root, server, base } = await start();
  const url = "https://shop.test/products/tee";
  let r = await json(base, "/api/queue", { method: "PUT", body: JSON.stringify({ urls: [url], fallback: false }) });
  assert.equal(r.status, 200);
  assert.equal((await readFile(join(root, "workspace", "urls.txt"), "utf8")).replace(/^﻿/, "").trim(), url);
  r = await json(base, "/api/queue", { method: "PUT", body: JSON.stringify({ urls: ["not a url"] }) });
  assert.equal(r.status, 400);
  r = await json(base, `/api/reference?url=${encodeURIComponent(url)}`, { method: "POST", headers: { "content-type": "image/png" }, body: Buffer.alloc(200, 1) });
  assert.equal(r.body.urls[0].reference.sha256.length, 64);
  const map = JSON.parse(await readFile(join(root, "workspace", "reference-inputs", "references.json"), "utf8"));
  assert.equal(map.entries[0].product_url, url);
  assert.equal(map.entries[0].origin, "user_reference");
  server.close();
});

test("start requires references unless library fallback is on, then runs pwsh with the options", async () => {
  const { spawned, server, base } = await start();
  await json(base, "/api/queue", { method: "PUT", body: JSON.stringify({ urls: ["https://shop.test/products/tee"], fallback: false }) });
  let r = await json(base, "/api/run", { method: "POST", body: JSON.stringify({}) });
  assert.equal(r.status, 400);
  await json(base, "/api/queue", { method: "PUT", body: JSON.stringify({ urls: ["https://shop.test/products/tee"], fallback: true }) });
  r = await json(base, "/api/run", { method: "POST", body: JSON.stringify({ backend: "flow", photosPerImage: 9, threads: 2 }) });
  assert.equal(r.status, 200);
  const { cmd, args } = spawned[0];
  assert.equal(cmd, "pwsh");
  assert.deepEqual(args.slice(args.indexOf("-PhotosPerImage")), ["-PhotosPerImage", "6", "-ThrottleLimit", "2", "-ImageBackend", "flow", "-ReferenceMapFile", args.at(-1)]);
  assert.equal((await json(base, "/api/run", { method: "POST", body: "{}" })).status, 409, "a second run must not start");
  spawned[0].child.emit("close", 0);
  server.close();
});

test("output files cannot escape the output folder", async () => {
  const { server, base } = await start();
  assert.equal((await fetch(`${base}/output/..%2F..%2Fetc%2Fpasswd`)).status, 404);
  server.close();
});

test("drive login checks the password with the Worker before saving drive.json", async () => {
  const root = await mkdtemp(join(tmpdir(), "pib-drive-"));
  const fetchImpl = async (_url, init) => ({ status: init.headers["x-admin-key"] === "right" ? 200 : 401, ok: init.headers["x-admin-key"] === "right" });
  const app = createApp(root, { fetchImpl });
  const server = createServer(async (req, res) => { if ((await app(req, res)) === false) { res.writeHead(404); res.end(); } });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await json(base, "/api/drive", { method: "POST", body: JSON.stringify({ password: "wrong" }) })).status, 401);
  assert.equal((await json(base, "/api/drive")).body.connected, false);
  assert.equal((await json(base, "/api/drive", { method: "POST", body: JSON.stringify({ password: "right" }) })).status, 200);
  assert.equal(JSON.parse(await readFile(join(root, "workspace", "drive.json"), "utf8")).adminKey, "right");
  await json(base, "/api/drive", { method: "DELETE" });
  assert.equal((await json(base, "/api/drive")).body.connected, false);
  server.close();
});
