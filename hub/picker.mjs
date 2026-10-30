// macOS tool picker (start-app.command runs it when there is more than one tool): a local page lists apps/*/tool.json
// with each tool's icon; picking one starts its Node server ("mac") or opens its page ("web"), then this server exits.
import { createServer } from "node:http";
import { spawn, execFile } from "node:child_process";
import { readFileSync, readdirSync, existsSync, openSync, mkdirSync } from "node:fs";
import { dirname, join, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const tools = readdirSync(join(root, "apps"), { withFileTypes: true })
  .filter((d) => d.isDirectory() && existsSync(join(root, "apps", d.name, "tool.json")))
  .map((d) => ({ ...JSON.parse(readFileSync(join(root, "apps", d.name, "tool.json"), "utf8")), dir: join(root, "apps", d.name) }))
  .sort((a, b) => a.dir.localeCompare(b.dir));
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const page = () => `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tools Hub</title><link rel="icon" href="/hub/icon.svg"><link rel="stylesheet" href="/hub/tool.css">
<style>.tools{display:grid;gap:12px;grid-template-columns:repeat(auto-fill,minmax(240px,1fr))}.tools form{margin:0}.tools button{display:flex;gap:14px;align-items:center;width:100%;text-align:left;cursor:pointer;font:inherit;color:inherit}.tools img{width:48px;height:48px;flex:none}.tools button:hover{border-color:var(--primary)}</style></head>
<body><main><header><img src="/hub/icon.svg" alt=""><h1>Tools Hub</h1></header><div class="tools">
${tools.map((t) => `<form method="post" action="/open/${esc(t.id)}"><button class="card" type="submit"><img src="/icon/${esc(t.id)}" alt=""><span><span>${esc(t.name)}</span><br><span class="muted small">${esc(t.description)}</span></span></button></form>`).join("")}
</div></main></body></html>`;

function open(tool) {
  if (tool.web) return execFile("open", [join(tool.dir, tool.web)]);
  const logs = join(tool.dir, "workspace", "logs");
  mkdirSync(logs, { recursive: true });
  const out = openSync(join(logs, "mac-server.log"), "a");
  spawn(process.execPath, [join(tool.dir, tool.mac)], { cwd: tool.dir, detached: true, stdio: ["ignore", out, out] }).unref();
}

const TYPES = { ".svg": "image/svg+xml", ".png": "image/png", ".css": "text/css; charset=utf-8" };
const server = createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const send = (code, type, body) => { res.writeHead(code, { "content-type": type }); res.end(body); };
  if (url.pathname === "/") return send(200, "text/html; charset=utf-8", page());
  if (url.pathname === "/hub/icon.svg") return send(200, TYPES[".svg"], readFileSync(join(here, "assets", "icon.svg")));
  if (url.pathname === "/hub/tool.css") return send(200, TYPES[".css"], readFileSync(join(here, "assets", "tool.css")));
  const tool = tools.find((t) => t.id === decodeURIComponent(url.pathname.split("/")[2] || ""));
  if (tool && url.pathname.startsWith("/icon/")) {
    const file = join(tool.dir, tool.icon || "icon.svg");
    return existsSync(file) ? send(200, TYPES[extname(file)] || "application/octet-stream", readFileSync(file)) : send(404, "text/plain", "");
  }
  if (tool && url.pathname.startsWith("/open/") && req.method === "POST") {
    open(tool);
    send(200, "text/html; charset=utf-8", `<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/hub/tool.css"><main><p>Đang mở ${esc(tool.name)}… Có thể đóng tab này.</p></main>`);
    return setTimeout(() => process.exit(0), 500);
  }
  send(404, "text/plain", "");
});
// HUB_PICKER_PORT (tests): a fixed port and no browser window.
const fixed = Number(process.env.HUB_PICKER_PORT) || 0;
server.listen(fixed, "127.0.0.1", () => fixed || execFile("open", [`http://127.0.0.1:${server.address().port}/`]));
// Nobody picked: stop after 10 minutes rather than linger.
setTimeout(() => process.exit(0), 10 * 60000).unref();
