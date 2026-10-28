// Local web app shared by macOS and Windows: queue, per-URL reference images, run/stop, results.
// Served by the bridge on 127.0.0.1 only; the workflow itself is src/run-images.ps1.
import { spawn, execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";

const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
  ".csv": "text/csv; charset=utf-8", ".json": "application/json; charset=utf-8", ".txt": "text/plain; charset=utf-8", ".ico": "image/x-icon" };
const IMAGE_TYPES = { "image/png": ".png", "image/jpeg": ".jpg" };
const BACKENDS = ["codex", "chatgpt", "flow"];

export function createApp(root, { spawnImpl = spawn, platform = process.platform } = {}) {
  const paths = {
    web: join(root, "web"),
    workspace: join(root, "workspace"),
    queue: join(root, "workspace", "urls.txt"),
    output: join(root, "workspace", "output"),
    refs: join(root, "workspace", "reference-inputs"),
    map: join(root, "workspace", "reference-inputs", "references.json"),
    photos: join(root, "data", "source-photos"),
  };
  const run = { process: null, lines: [], exitCode: null, startedAt: null, listeners: new Set() };

  const send = (res, status, body, type = "application/json; charset=utf-8") => {
    res.writeHead(status, { "content-type": type, "cache-control": "no-store" });
    res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
  };
  const readBody = async (req) => { const parts = []; for await (const c of req) parts.push(c); return Buffer.concat(parts); };
  const inside = (base, target) => { const full = resolve(base, target); return full === resolve(base) || full.startsWith(resolve(base) + sep) ? full : null; };

  async function readMap() {
    try {
      const map = JSON.parse((await readFile(paths.map, "utf8")).replace(/^﻿/, ""));
      return { schema_version: 1, allow_library_fallback: false, preferred_source_group: "Áo", entries: [], ...map };
    } catch { return { schema_version: 1, allow_library_fallback: false, preferred_source_group: "Áo", entries: [] }; }
  }
  const writeMap = async (map) => { await mkdir(paths.refs, { recursive: true }); await writeFile(paths.map, JSON.stringify(map, null, 2)); };
  async function readQueue() {
    try { return (await readFile(paths.queue, "utf8")).replace(/^﻿/, "").split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#")); }
    catch { return []; }
  }
  const validUrl = (value) => { try { const u = new URL(value); return ["http:", "https:"].includes(u.protocol) && !!u.host; } catch { return false; } };

  async function state() {
    const [urls, map] = await Promise.all([readQueue(), readMap()]);
    let groups = [];
    try { groups = (await readdir(paths.photos, { withFileTypes: true })).filter((d) => d.isDirectory()).map((d) => d.name).sort((a, b) => a.localeCompare(b, "vi")); } catch {}
    return {
      platform,
      urls: urls.map((url) => {
        const entry = map.entries.find((e) => e.product_url === url && e.file && existsSync(e.file));
        const product = map.entries.find((e) => e.product_url === url && e.product_file && existsSync(e.product_file));
        return { url, reference: entry ? { sha256: entry.sha256 } : null, productReference: product ? { sha256: product.product_sha256 } : null };
      }),
      fallback: !!map.allow_library_fallback, sourceGroup: map.preferred_source_group, groups,
      running: !!run.process, exitCode: run.exitCode, startedAt: run.startedAt,
    };
  }

  function emit(message) {
    if (message.type === "line") { run.lines.push(message.text); if (run.lines.length > 400) run.lines.shift(); }
    const data = `data: ${JSON.stringify(message)}\n\n`;
    for (const res of run.listeners) res.write(data);
  }

  function powershell() {
    return platform === "win32" ? { cmd: "powershell.exe", pre: ["-NoProfile", "-ExecutionPolicy", "Bypass"] } : { cmd: "pwsh", pre: ["-NoProfile"] };
  }

  async function startRun(options) {
    if (run.process) throw Object.assign(new Error("Đang chạy."), { status: 409 });
    const urls = await readQueue();
    if (!urls.length) throw Object.assign(new Error("Chưa có link sản phẩm."), { status: 400 });
    const map = await readMap();
    for (const url of urls) {
      const entry = map.entries.find((e) => e.product_url === url);
      if ((new URL(url).hostname === 'local.invalid' && !entry?.product_file) || (entry?.product_file && !existsSync(entry.product_file))) {
        throw Object.assign(new Error('Gắn lại ảnh sản phẩm gốc cho sản phẩm không có link hoặc có ảnh bị thiếu.'), { status: 400 });
      }
    }
    if (!map.allow_library_fallback) {
      const missing = urls.filter((url) => !map.entries.some((e) => e.product_url === url && e.file && existsSync(e.file)));
      if (missing.length) throw Object.assign(new Error(`Chưa gắn ảnh cho ${missing.length} link. Gắn ảnh hoặc bật dùng kho ảnh.`), { status: 400 });
    }
    const per = Math.min(6, Math.max(1, Number(options.photosPerImage) || 2));
    const threads = Math.min(4, Math.max(1, Number(options.threads) || 1));
    const backend = BACKENDS.includes(options.backend) ? options.backend : "codex";
    const { cmd, pre } = powershell();
    const args = [...pre, "-File", join(root, "src", "run-images.ps1"), "-PhotosPerImage", String(per), "-ThrottleLimit", String(threads), "-ImageBackend", backend];
    if (existsSync(paths.map)) args.push("-ReferenceMapFile", paths.map);
    run.lines = []; run.exitCode = null; run.startedAt = new Date().toISOString();
    const child = spawnImpl(cmd, args, { cwd: root, windowsHide: true, detached: platform !== "win32", env: { ...process.env, NO_COLOR: "1" } });
    run.process = child;
    emit({ type: "status", running: true });
    let buffer = "";
    const onData = (chunk) => {
      buffer += chunk.toString("utf8");
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop();
      for (const line of lines) emit({ type: "line", text: line.replace(/\x1b\[[0-9;]*m/g, "") });
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.on("error", (error) => { emit({ type: "line", text: `ERROR: ${error.message}` }); });
    child.on("close", (code) => {
      if (buffer) emit({ type: "line", text: buffer });
      run.process = null; run.exitCode = code;
      emit({ type: "status", running: false, exitCode: code });
    });
  }

  function stopRun() {
    const child = run.process;
    if (!child) return;
    if (platform === "win32") execFile("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true }, () => {});
    else { try { process.kill(-child.pid, "SIGTERM"); } catch { child.kill("SIGTERM"); } }
  }

  async function batches() {
    let dirs = [];
    try { dirs = (await readdir(paths.output, { withFileTypes: true })).filter((d) => d.isDirectory() && !d.name.startsWith("_")).map((d) => d.name).sort().reverse().slice(0, 12); } catch {}
    return Promise.all(dirs.map(async (id) => {
      const dir = join(paths.output, id);
      let images = [];
      try { images = (await readdir(join(dir, "images"))).filter((f) => /\.png$/i.test(f)).sort(); } catch {}
      return { id, images: images.map((name) => ({ name, url: `/output/${encodeURIComponent(id)}/images/${encodeURIComponent(name)}` })),
        csv: existsSync(join(dir, "loox_import.csv")) ? `/output/${encodeURIComponent(id)}/loox_import.csv` : null,
        missing: existsSync(join(dir, "missing-data.csv")) };
    }));
  }

  function openFolder(target) {
    const [cmd, args] = platform === "win32" ? ["explorer.exe", [target]] : platform === "darwin" ? ["open", [target]] : ["xdg-open", [target]];
    execFile(cmd, args, () => {});
  }

  return async function handle(req, res) {
    const url = new URL(req.url, "http://127.0.0.1");
    const path = decodeURIComponent(url.pathname);
    try {
      if (req.method === "GET" && (path === "/" || /^\/(app\.js|style\.css|brand\/[\w.-]+)$/.test(path))) {
        const file = inside(paths.web, path === "/" ? "index.html" : path.slice(1));
        if (!file || !existsSync(file)) return send(res, 404, { error: "not found" });
        return send(res, 200, await readFile(file), MIME[extname(file)] || "application/octet-stream");
      }
      if (path === "/api/state" && req.method === "GET") return send(res, 200, await state());

      if (path === "/api/queue" && req.method === "PUT") {
        const body = JSON.parse((await readBody(req)).toString("utf8"));
        const urls = (body.urls || []).map((u) => String(u).trim()).filter(Boolean);
        const invalid = urls.find((u) => !validUrl(u));
        if (invalid) return send(res, 400, { error: `Link không hợp lệ: ${invalid}` });
        if (new Set(urls).size !== urls.length) return send(res, 400, { error: "Có link bị trùng." });
        await mkdir(paths.workspace, { recursive: true });
        await writeFile(paths.queue, "﻿" + urls.join("\n") + (urls.length ? "\n" : ""));
        const map = await readMap();
        map.entries = map.entries.filter((e) => urls.includes(e.product_url));
        if (typeof body.fallback === "boolean") map.allow_library_fallback = body.fallback;
        if (typeof body.sourceGroup === "string" && body.sourceGroup) map.preferred_source_group = body.sourceGroup;
        await writeMap(map);
        return send(res, 200, await state());
      }

      if (path === "/api/reference") {
        const target = url.searchParams.get("url") || "";
        const role = url.searchParams.get("role") || "scene";
        if (!["scene", "product"].includes(role)) return send(res, 400, { error: "Loại ảnh không hợp lệ." });
        const fileKey = role === "product" ? "product_file" : "file";
        const hashKey = role === "product" ? "product_sha256" : "sha256";
        if (!validUrl(target)) return send(res, 400, { error: "Link không hợp lệ." });
        const map = await readMap();
        if (req.method === "GET") {
          const entry = map.entries.find((e) => e.product_url === target);
          if (!entry?.[fileKey] || !existsSync(entry[fileKey])) return send(res, 404, { error: "Chưa có ảnh." });
          return send(res, 200, await readFile(entry[fileKey]), MIME[extname(entry[fileKey])] || "image/png");
        }
        if (req.method === "DELETE") {
          const entry = map.entries.find((e) => e.product_url === target);
          if (entry) { delete entry[fileKey]; delete entry[hashKey]; }
          map.entries = map.entries.filter((e) => e.file || e.product_file);
          await writeMap(map);
          return send(res, 200, await state());
        }
        if (req.method === "POST") {
          const ext = IMAGE_TYPES[String(req.headers["content-type"] || "").split(";")[0]];
          if (!ext) return send(res, 400, { error: "Chọn ảnh PNG hoặc JPEG." });
          const bytes = await readBody(req);
          if (bytes.length < 100 || bytes.length > 30 * 1024 * 1024) return send(res, 400, { error: "Ảnh rỗng hoặc quá 30MB." });
          await mkdir(paths.refs, { recursive: true });
          const file = join(paths.refs, randomUUID().replace(/-/g, "") + ext);
          await writeFile(file, bytes);
          const entry = map.entries.find((e) => e.product_url === target) || { product_url: target };
          entry[fileKey] = file; entry[hashKey] = createHash("sha256").update(bytes).digest("hex"); entry.origin = "user_reference";
          map.entries = map.entries.filter((e) => e.product_url !== target);
          map.entries.push(entry);
          await writeMap(map);
          return send(res, 200, await state());
        }
      }

      if (path === "/api/run" && req.method === "POST") {
        await startRun(JSON.parse((await readBody(req)).toString("utf8") || "{}"));
        return send(res, 200, { ok: true });
      }
      if (path === "/api/stop" && req.method === "POST") { stopRun(); return send(res, 200, { ok: true }); }

      if (path === "/api/events" && req.method === "GET") {
        res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store", connection: "keep-alive" });
        res.write(`data: ${JSON.stringify({ type: "snapshot", lines: run.lines, running: !!run.process, exitCode: run.exitCode })}\n\n`);
        run.listeners.add(res);
        req.on("close", () => run.listeners.delete(res));
        return;
      }

      if (path === "/api/batches" && req.method === "GET") return send(res, 200, await batches());

      if (path === "/api/open" && req.method === "POST") {
        const body = JSON.parse((await readBody(req)).toString("utf8") || "{}");
        const target = body.batch ? inside(paths.output, body.batch) : paths.output;
        if (!target) return send(res, 400, { error: "Đường dẫn không hợp lệ." });
        await mkdir(target, { recursive: true });
        openFolder(target);
        return send(res, 200, { ok: true });
      }

      if (path === "/api/setup" && req.method === "GET") {
        const { cmd, pre } = powershell();
        const out = await new Promise((done) => execFile(cmd, [...pre, "-File", join(root, "src", "setup-check.ps1"), "-AsJson"], { cwd: root, windowsHide: true, timeout: 120000 },
          (error, stdout) => done(error && !stdout ? JSON.stringify({ Checks: [{ Ok: false, Message: `Chưa chạy được PowerShell (${cmd}).`, Action: platform === "win32" ? "" : "Cài PowerShell 7 (pwsh) rồi mở lại app." }], Summary: "" }) : stdout)));
        return send(res, 200, out.slice(out.indexOf("{")));
      }

      if (path.startsWith("/output/") && req.method === "GET") {
        const file = inside(paths.output, path.slice("/output/".length));
        if (!file || !existsSync(file) || !(await stat(file)).isFile()) return send(res, 404, { error: "not found" });
        return send(res, 200, await readFile(file), MIME[extname(file).toLowerCase()] || "application/octet-stream");
      }
      return false;
    } catch (error) {
      return send(res, error.status || 500, { error: String(error.message || error) });
    }
  };
}

