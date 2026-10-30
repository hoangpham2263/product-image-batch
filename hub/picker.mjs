// macOS Tools Hub menu (start-app.command runs it when there is more than one tool): one app window lists
// apps/*/tool.json with each tool's icon, and a tool opens in that same window. Web tools are served from here;
// a tool with its own server ("mac", e.g. Product Review) is started and the window moves to it. Each tool shows a
// "← Menu" button back here (?hub=<port>). One menu per install: a second start just opens a window on it.
import { createServer } from "node:http";
import { spawn, execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, existsSync, openSync, mkdirSync, statSync } from "node:fs";
import { dirname, join, resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const portFor = (dir, base) => base + (parseInt(createHash("sha1").update(dir).digest("hex").slice(0, 6), 16) % 1000);
// HUB_PICKER_PORT (tests): a fixed port and no window.
const PORT = Number(process.env.HUB_PICKER_PORT) || portFor(root, 46000);
const tools = readdirSync(join(root, "apps"), { withFileTypes: true })
  .filter((d) => d.isDirectory() && existsSync(join(root, "apps", d.name, "tool.json")))
  .map((d) => ({ ...JSON.parse(readFileSync(join(root, "apps", d.name, "tool.json"), "utf8")), dir: join(root, "apps", d.name) }))
  .sort((a, b) => (a.order ?? 99) - (b.order ?? 99) || a.dir.localeCompare(b.dir));
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const page = () => `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tools Hub</title><link rel="icon" href="/hub/icon.svg"><link rel="stylesheet" href="/hub/tool.css">
<style>.tools{display:grid;gap:8px}.tools form{margin:0}.tools button{display:flex;gap:14px;align-items:center;width:100%;height:64px;padding:0 14px;text-align:left;cursor:pointer;font:inherit;color:inherit}.tools img{width:40px;height:40px;flex:none}.tools .name{display:block}.tools .desc{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.tools span.text{min-width:0}</style></head>
<body><main><header><img src="/hub/icon.svg" alt=""><h1>Tools Hub</h1></header><div class="tools list">
${tools.map((t) => `<form method="post" action="/open/${esc(t.id)}"><button class="card" type="submit"><img src="/icon/${esc(t.id)}" alt=""><span class="text"><span class="name">${esc(t.name)}</span><span class="desc muted">${esc(t.description)}</span></span></button></form>`).join("")}
</div></main></body></html>`;

// Same window as Product Review's (src/mac/server.mjs): a Chrome app window, no tabs or address bar; the default
// browser when Chrome is missing.
function appWindow(url, size = "1120,840") {
  execFile("open", ["-na", "Google Chrome", "--args", `--app=${url}`, `--window-size=${size}`], (err) => { if (err) execFile("open", [url]); });
}

// A tool with its own server: start it without a window of its own (or find it running) and return its address.
async function startServer(tool) {
  const base = portFor(tool.dir, 47000);
  const find = async () => {
    for (let port = base; port <= base + 20; port++) {
      const body = await fetch(`http://127.0.0.1:${port}/api/root`).then((r) => r.json()).catch(() => null);
      if (body?.root === tool.dir) return `http://127.0.0.1:${port}/`;
    }
    return "";
  };
  let url = await find();
  if (url) return url;
  const logs = join(tool.dir, "workspace", "logs");
  mkdirSync(logs, { recursive: true });
  const out = openSync(join(logs, "mac-server.log"), "a");
  spawn(process.execPath, [join(tool.dir, tool.mac), "--no-open"], { cwd: tool.dir, detached: true, stdio: ["ignore", out, out] }).unref();
  for (let i = 0; i < 60 && !url; i++) { await new Promise((r) => setTimeout(r, 250)); url = await find(); }
  return url;
}

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json" };
function sendFile(res, file) {
  if (!existsSync(file) || !statSync(file).isFile()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": TYPES[extname(file)] || "application/octet-stream", "cache-control": "no-store" });
  res.end(readFileSync(file));
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  const parts = url.pathname.split("/").map(decodeURIComponent);
  if (url.pathname === "/") { res.writeHead(200, { "content-type": TYPES[".html"] }); return res.end(page()); }
  if (url.pathname === "/api/root") { res.writeHead(200, { "content-type": TYPES[".json"] }); return res.end(JSON.stringify({ root, hub: true })); }
  // /hub/icon.svg, /hub/tool.css, and /hub/assets/tool.css (web tools link it as ../../../hub/assets/tool.css).
  if (parts[1] === "hub") return sendFile(res, join(here, "assets", parts.at(-1) === "icon.svg" ? "icon.svg" : "tool.css"));
  const tool = tools.find((t) => t.id === parts[2]);
  if (tool && parts[1] === "icon") return sendFile(res, join(tool.dir, tool.icon || "icon.svg"));
  if (tool && parts[1] === "apps") {
    const file = resolve(tool.dir, ...parts.slice(3));
    return file.startsWith(tool.dir + sep) ? sendFile(res, file) : (res.writeHead(404), res.end());
  }
  if (tool && parts[1] === "open" && req.method === "POST") {
    const target = tool.web ? `/apps/${encodeURIComponent(tool.id)}/${tool.web}?hub=${PORT}` : await startServer(tool).then((u) => (u ? `${u}?hub=${PORT}` : ""));
    if (!target) { res.writeHead(500, { "content-type": TYPES[".html"] }); return res.end(`<meta charset="utf-8"><link rel="stylesheet" href="/hub/tool.css"><main><header><h1>Không mở được ${esc(tool.name)}</h1></header><a class="btn" href="/">← Menu</a></main>`); }
    res.writeHead(303, { location: target });
    return res.end();
  }
  res.writeHead(404); res.end();
});
server.once("error", (e) => {
  // Already running for this install: just show its window.
  if (e.code !== "EADDRINUSE") throw e;
  fetch(`http://127.0.0.1:${PORT}/api/root`).then((r) => r.json()).then((b) => { if (b.root === root) appWindow(`http://127.0.0.1:${PORT}/`); process.exit(0); }, () => process.exit(1));
});
server.listen(PORT, "127.0.0.1", () => process.env.HUB_PICKER_PORT || appWindow(`http://127.0.0.1:${PORT}/`));
