// macOS app: serves the window (src/mac/ui) on localhost and runs the same PowerShell code as the
// Windows app. Application calls go to one long-lived pwsh (rpc.ps1); a run is run-images.ps1.
import { createServer } from "node:http";
import { spawn, execFile } from "node:child_process";
import { createInterface } from "node:readline";
import { writeFile, mkdir, copyFile, rm, stat, appendFile } from "node:fs/promises";
import { createReadStream, existsSync } from "node:fs";
import { join, dirname, extname, resolve, sep } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..", "..");
const PORT = Number(process.env.PRB_PORT || 47831);
const workspace = join(root, "workspace");
const logs = join(workspace, "logs");
const uploads = join(workspace, "temp", "mac-uploads");
// pwsh from PATH or the usual install places (Homebrew, dotnet tool, Microsoft pkg).
const PWSH = process.env.PRB_PWSH || [
  ...(process.env.PATH || "").split(":").map((d) => join(d, "pwsh")),
  "/opt/homebrew/bin/pwsh", "/usr/local/bin/pwsh", join(homedir(), ".dotnet", "tools", "pwsh"), "/usr/local/microsoft/powershell/7/pwsh",
].find((p) => existsSync(p)) || "pwsh";
// Node, npm and codex live in Homebrew or the npm prefix; Finder-launched apps miss them in PATH.
const extraPath = ["/opt/homebrew/bin", "/usr/local/bin", join(homedir(), ".npm-global", "bin"), join(homedir(), ".dotnet", "tools")];
const toolEnv = { ...process.env, PATH: [...new Set([...(process.env.PATH || "").split(":"), ...extraPath, dirname(process.execPath)])].filter(Boolean).join(":") };
const findTool = (name) => toolEnv.PATH.split(":").map((d) => join(d, name)).find((p) => existsSync(p));
const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".ico": "image/x-icon" };

// ----- PowerShell application calls -----
let rpcProc = null;
const waiting = new Map();
function startRpc() {
  rpcProc = spawn(PWSH, ["-NoProfile", "-File", join(here, "rpc.ps1")], { cwd: root, env: toolEnv, stdio: ["pipe", "pipe", "pipe"] });
  createInterface({ input: rpcProc.stdout }).on("line", (line) => {
    if (!line.startsWith("@@RPC ")) return;
    const answer = JSON.parse(line.slice(6));
    const job = waiting.get(answer.id);
    if (!job) return;
    waiting.delete(answer.id);
    answer.ok ? job.resolve(answer.result) : job.reject(new Error(answer.error));
  });
  rpcProc.stderr.on("data", (d) => process.stderr.write(d));
  rpcProc.on("exit", () => {
    for (const job of waiting.values()) job.reject(new Error("PowerShell đã dừng."));
    waiting.clear();
    rpcProc = null;
  });
}
function rpc(cmd, args = {}) {
  if (!rpcProc) startRpc();
  const id = randomUUID();
  return new Promise((resolve, reject) => {
    waiting.set(id, { resolve, reject });
    rpcProc.stdin.write(JSON.stringify({ id, cmd, args }) + "\n");
  });
}

// ----- Batch run (same arguments as New-RunArguments in main-window.ps1) -----
const run = { proc: null, events: [], index: 0, stopped: false, exitCode: null, resultFolder: "", logFile: "", errFile: "", done: false };
async function receive(line) {
  const event = await rpc("event", { line, index: run.index }).catch(() => null);
  if (!event) return;
  if (event.Kind === "Item") run.index = event.Index;
  if (event.Kind === "Output") run.resultFolder = event.Path;
  run.events.push(event);
}
async function startRun({ per = 1, threads = 1 }) {
  if (run.proc) throw new Error("Đang chạy.");
  await mkdir(logs, { recursive: true });
  const stamp = Date.now();
  Object.assign(run, { events: [], index: 0, stopped: false, exitCode: null, resultFolder: "", done: false,
    logFile: join(logs, `image-batch-mac-${stamp}.log`), errFile: join(logs, `image-batch-mac-${stamp}.err.log`) });
  const args = ["-NoProfile", "-File", join(root, "src", "run-images.ps1"), "-PhotosPerImage", String(per), "-ThrottleLimit", String(threads)];
  const map = join(workspace, "reference-inputs", "references.json");
  if (existsSync(map)) args.push("-ReferenceMapFile", map);
  // Own process group, so Dừng stops codex and every other child too.
  const proc = spawn(PWSH, args, { cwd: root, env: toolEnv, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  run.proc = proc;
  let chain = Promise.resolve();
  for (const [stream, file] of [[proc.stdout, run.logFile], [proc.stderr, run.errFile]]) {
    createInterface({ input: stream }).on("line", (line) => {
      chain = chain.then(() => appendFile(file, line + "\n")).then(() => receive(line));
    });
  }
  proc.on("exit", (code) => {
    chain = chain.then(async () => {
      run.exitCode = code;
      // Keep the full run log inside its batch, as the Windows app does.
      if (run.resultFolder && existsSync(run.resultFolder)) {
        const batchLogs = join(run.resultFolder, "logs");
        await mkdir(batchLogs, { recursive: true });
        for (const [from, name] of [[run.logFile, "run.log"], [run.errFile, "run.err.log"]]) {
          if (existsSync(from) && (await stat(from)).size) await copyFile(from, join(batchLogs, name));
          await rm(from, { force: true });
        }
      }
      run.proc = null;
      run.done = true;
    });
  });
}
function stopRun() {
  if (!run.proc) return;
  run.stopped = true;
  try { process.kill(-run.proc.pid, "SIGKILL"); } catch { try { run.proc.kill("SIGKILL"); } catch {} }
}

// ----- HTTP -----
const allowedFile = (p) => {
  const full = resolve(p);
  return [root + sep, resolve(tmpdir()) + sep].some((base) => full.startsWith(base)) && TYPES[extname(full).toLowerCase()]?.startsWith("image/");
};
const body = async (req) => { const chunks = []; for await (const c of req) chunks.push(c); return Buffer.concat(chunks); };
const send = (res, status, data) => { res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }); res.end(JSON.stringify(data)); };

async function handle(req, res) {
  const url = new URL(req.url, "http://localhost");
  const path = url.pathname;
  if (path === "/api/rpc" && req.method === "POST") {
    const { cmd, args } = JSON.parse((await body(req)).toString("utf8"));
    try { return send(res, 200, { result: await rpc(cmd, args) }); }
    catch (e) { return send(res, 400, { error: e.message }); }
  }
  if (path === "/api/upload" && req.method === "POST") {
    // Pasted, dropped or picked images become local files the PowerShell code can snapshot.
    const name = (url.searchParams.get("name") || "image.png").replace(/[^\w.-]/g, "_");
    const ext = extname(name).toLowerCase();
    if (![".png", ".jpg", ".jpeg"].includes(ext)) return send(res, 400, { error: "Chọn ảnh PNG hoặc JPEG." });
    await mkdir(uploads, { recursive: true });
    const file = join(uploads, `${randomUUID().replace(/-/g, "")}${ext}`);
    await writeFile(file, await body(req));
    return send(res, 200, { path: file });
  }
  if (path === "/api/run" && req.method === "POST") {
    try { await startRun(JSON.parse((await body(req)).toString("utf8") || "{}")); return send(res, 200, { ok: true }); }
    catch (e) { return send(res, 400, { error: e.message }); }
  }
  if (path === "/api/run" && req.method === "GET") {
    const since = Number(url.searchParams.get("since") || 0);
    return send(res, 200, { running: !!run.proc, done: run.done, exitCode: run.exitCode, stopped: run.stopped, resultFolder: run.resultFolder, events: run.events.slice(since), next: run.events.length });
  }
  if (path === "/api/stop" && req.method === "POST") { stopRun(); return send(res, 200, { ok: true }); }
  if (path === "/api/setup" && req.method === "POST") {
    execFile(PWSH, ["-NoProfile", "-File", join(root, "src", "setup-check.ps1"), "-AsJson"], { cwd: root, env: toolEnv, timeout: 120000 }, (err, stdout) => {
      try { send(res, 200, JSON.parse(stdout)); } catch { send(res, 500, { error: "setup" }); }
    });
    return;
  }
  if (path === "/api/setup-step" && req.method === "POST") {
    // Cài (Codex via npm) or Đăng nhập (opens the browser, waits for the sign-in to finish).
    const { step } = JSON.parse((await body(req)).toString("utf8") || "{}");
    const npm = findTool("npm"), codex = findTool("codex");
    if (step === "install" && !npm) return send(res, 400, { error: "Chưa có Node.js. Mở lại start-app.command để cài." });
    const [cmd, args] = step === "install" ? [npm, ["install", "-g", "@openai/codex"]] : [codex || "codex", ["login"]];
    execFile(cmd, args, { cwd: root, timeout: 15 * 60000, env: toolEnv }, (err, stdout, stderr) => {
      if (err) return send(res, 500, { error: (String(stderr || stdout).trim().split("\n").pop() || err.message).slice(0, 300) });
      send(res, 200, { ok: true });
    });
    return;
  }
  if (path === "/api/update" && req.method === "POST") {
    // Update the files, then start a fresh server on the new code; the page reloads itself.
    execFile(PWSH, ["-NoProfile", "-Command", `. '${join(root, "src", "update.ps1").replace(/'/g, "''")}' -NoRun; Update-App '${root.replace(/'/g, "''")}'`], { cwd: root, env: toolEnv, timeout: 300000 }, (err) => {
      if (err) return send(res, 500, { error: err.message });
      send(res, 200, { ok: true });
      setTimeout(() => {
        spawn(process.execPath, [join(here, "server.mjs"), "--no-open"], { cwd: root, detached: true, stdio: "ignore", env: { ...process.env, PRB_WAIT_PORT: "1" } }).unref();
        rpcProc?.kill();
        process.exit(0);
      }, 300);
    });
    return;
  }
  if (path === "/file") {
    const file = url.searchParams.get("path") || "";
    if (!allowedFile(file) || !existsSync(file)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "content-type": TYPES[extname(file).toLowerCase()], "cache-control": "no-store" });
    return createReadStream(file).pipe(res);
  }
  const rel = path === "/" ? "index.html" : path.slice(1);
  const file = resolve(here, "ui", rel);
  if (!file.startsWith(resolve(here, "ui") + sep) || !existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": TYPES[extname(file).toLowerCase()] || "application/octet-stream", "cache-control": "no-store" });
  createReadStream(file).pipe(res);
}

// Open as its own window (Chrome app mode) when Chrome is installed, else the default browser.
function openWindow() {
  const target = `http://127.0.0.1:${PORT}/`;
  execFile("open", ["-na", "Google Chrome", "--args", `--app=${target}`, "--window-size=1120,840"], (err) => { if (err) execFile("open", [target]); });
}

const server = createServer((req, res) => handle(req, res).catch((e) => send(res, 500, { error: e.message })));
function listen(attempt = 0) {
  server.once("error", (e) => {
    // Already running (or the old server is still closing after an update).
    if (e.code === "EADDRINUSE" && process.env.PRB_WAIT_PORT && attempt < 50) return setTimeout(() => listen(attempt + 1), 200);
    if (e.code === "EADDRINUSE") { if (!process.argv.includes("--no-open")) openWindow(); process.exit(0); }
    throw e;
  });
  server.listen(PORT, "127.0.0.1", () => { if (!process.argv.includes("--no-open")) openWindow(); });
}
startRpc();
listen();
