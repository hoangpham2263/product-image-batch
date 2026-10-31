// Cấu hình, shared by the Tools Hub menu (hub/picker.mjs) and Product Review's server: the same steps and
// settings as hub/setup/*.ps1, kept once per install in <hub>/workspace/config.
//   POST /api/setup                 the steps (setup-check.ps1 -AsJson)
//   POST /api/setup-step {step}     install: Codex and every tool's browser bridge; login: codex login with a
//                                   one-time code, typed on the sign-in page opened in the tools' own Chrome;
//                                   browser: that Chrome, to sign in to Google Flow, ChatGPT (hub/browser.mjs)
//   GET /api/setup-login            { code } while a sign-in waits for it
//   GET|POST /api/config/ai         Model AI: { settings, models } / save { model, effort }
//   GET|POST|DELETE /api/config/drive   the app password: { drive } / log in { password } / log out
import { execFile, spawn } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { findTool as findIn, runTool, psCommand, psFile, onWindows, killTree } from "../platform.mjs";
import { browserArgs } from "../browser.mjs";
import { createSetupReader } from "./setup-report.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const q = (p) => p.replace(/'/g, "''");

export function createConfigApi({ hubRoot, pwsh, env = process.env }) {
  const readSetup = createSetupReader({ hubRoot, pwsh, args: psFile(join(here, "setup-check.ps1"), ["-AsJson"]), env });
  const findTool = (name) => findIn(name, env);
  const json = (res, status, data) => { res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(data)); };
  const body = (req) => new Promise((done) => { const chunks = []; req.on("data", (c) => chunks.push(c)); req.on("end", () => { try { done(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}")); } catch { done({}); } }); });
  // A PowerShell command over the hub's setup scripts; it prints one JSON line, errors included ({ error }).
  const ps = (script, extraEnv = {}) => new Promise((done) => {
    const command = `$ErrorActionPreference='Stop'; try { ${script} } catch { @{ error = $_.Exception.Message } | ConvertTo-Json -Compress }`;
    execFile(pwsh, psCommand(command), { cwd: hubRoot, env: { ...env, ...extraEnv }, timeout: 120000, windowsHide: true }, (err, stdout) => {
      try { done(JSON.parse(String(stdout).trim().split(/\r?\n/).pop())); } catch { done({ error: "Chưa đọc được cấu hình." }); }
    });
  });
  const load = (file) => `. '${q(join(here, file))}'`;
  const workspace = q(join(hubRoot, "workspace"));
  const openInToolsChrome = (urls, done) => execFile(process.execPath, browserArgs(urls ? "open" : "login", ...(urls || [])), { cwd: hubRoot, env, timeout: 15 * 60000, windowsHide: true }, (err, stdout) => {
    let r = {}; try { r = JSON.parse(String(stdout).trim().split(/\r?\n/).pop()); } catch { r = { error: err?.message || "Không mở được Chrome của tool." }; }
    done(r);
  });
  // codex login opens the system's default browser; with --device-auth it prints a page and a code instead, so the
  // page opens in the tools' own Chrome and Cấu hình shows the code to type there.
  // Đăng nhập again while one waits: that one stops (its answer says so) and a new code comes.
  let loginCode = "", login = null;
  const codexLogin = (codex, done) => {
    if (login) { const old = login; login = null; loginCode = ""; killTree(old.child); old.done({ superseded: true }); }
    const child = spawn(onWindows && /\.cmd$/i.test(codex) ? `"${codex}"` : codex, ["login", "--device-auth"], { cwd: hubRoot, env, windowsHide: true, detached: !onWindows, shell: onWindows && /\.cmd$/i.test(codex) });
    const timer = setTimeout(() => killTree(child), 15 * 60000);
    let out = "", opened = false;
    login = { child, done };
    const current = () => login?.child === child;
    const read = (chunk) => {
      out = (out + chunk).replace(/\x1b\[[0-9;]*m/g, "");
      const url = out.match(/https:\/\/\S+\/device\b\S*/)?.[0], code = out.match(/\b[A-Z0-9]{4,}-[A-Z0-9]{4,}\b/)?.[0];
      if (opened || !url || !code || !current()) return;
      opened = true;
      loginCode = code;
      openInToolsChrome([url], (r) => { if (r.error) { loginCode = ""; killTree(child); done({ error: r.error }); } });
    };
    child.stdout.on("data", read);
    child.stderr.on("data", read);
    child.on("error", (e) => { clearTimeout(timer); if (!current()) return; login = null; loginCode = ""; done({ error: e.message }); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (!current()) return;
      login = null;
      loginCode = "";
      done(code === 0 ? { ok: true } : { error: (out.trim().split(/\r?\n/).pop() || "Chưa đăng nhập được ChatGPT.").slice(0, 300) });
    });
  };

  return async function handle(req, res, path) {
    if (path === "/api/setup" && req.method === "POST") {
      const {status, report} = await readSetup();
      json(res, status, report);
      return true;
    }
    if (path === "/api/setup-login") {
      json(res, 200, { code: loginCode });
      return true;
    }
    if (path === "/api/setup-step" && req.method === "POST") {
      // Cài (Codex via npm, then each tool's browser bridge) or Đăng nhập (opens the browser, waits for the sign-in).
      const { step } = await body(req);
      if (step === "browser") {
        // The first time this downloads Chrome for Testing (about 150 MB) before it opens.
        openInToolsChrome(null, (r) => json(res, r.error ? 500 : 200, r));
        return true;
      }
      const npm = findTool("npm"), codex = findTool("codex");
      if (step === "login") {
        if (!codex) { json(res, 400, { error: "Chưa cài Codex." }); return true; }
        let answered = false;
        codexLogin(codex, (r) => { if (!answered) { answered = true; json(res, r.error ? 500 : 200, r); } });
        return true;
      }
      if (step === "install" && !npm) { json(res, 400, { error: "Chưa có Node.js. Mở lại start-app để cài." }); return true; }
      const [cmd, args] = step === "install" ? [npm, ["install", "-g", "@openai/codex"]] : [codex || "codex", ["login"]];
      runTool(cmd, args, { cwd: hubRoot, timeout: 15 * 60000, env, windowsHide: true }, (err, stdout, stderr) => {
        if (err) return json(res, 500, { error: (String(stderr || stdout).trim().split(/\r?\n/).pop() || err.message).slice(0, 300) });
        if (step !== "install") return json(res, 200, { ok: true });
        const bridges = readdirSync(join(hubRoot, "apps"), { withFileTypes: true }).filter((d) => d.isDirectory())
          .map((d) => join(hubRoot, "apps", d.name, "bridge")).filter((b) => existsSync(join(b, "package.json")));
        const next = () => (bridges.length ? runTool(npm, ["install", "--silent"], { cwd: bridges.shift(), timeout: 10 * 60000, env, windowsHide: true }, next) : json(res, 200, { ok: true }));
        next();
      });
      return true;
    }
    if (path === "/api/config/ai") {
      const saved = req.method === "POST" ? await body(req) : null;
      const script = saved
        ? `${load("ai-settings.ps1")}; Set-AiSettings '${q(hubRoot)}' $env:HUB_AI_MODEL $env:HUB_AI_EFFORT; '{"ok":true}'`
        : `${load("ai-settings.ps1")}; [pscustomobject]@{ settings = (Get-AiSettings '${q(hubRoot)}'); models = @(Get-AiModels) } | ConvertTo-Json -Depth 6 -Compress`;
      const r = await ps(script, saved ? { HUB_AI_MODEL: String(saved.model || ""), HUB_AI_EFFORT: String(saved.effort || "") } : {});
      json(res, r.error ? 400 : 200, r);
      return true;
    }
    if (path === "/api/config/drive") {
      // The password goes to PowerShell in its environment, never on the command line.
      const { password = "" } = req.method === "POST" ? await body(req) : {};
      const action = req.method === "POST" ? `Connect-DriveAccount '${workspace}' $env:HUB_DRIVE_PASSWORD; ` : req.method === "DELETE" ? `Disconnect-DriveAccount '${workspace}'; ` : "";
      const r = await ps(`${load("drive.ps1")}; ${action}@{ drive = (Test-Path -LiteralPath (Get-SharedConfigPath '${workspace}' 'drive.json')) } | ConvertTo-Json -Compress`, { HUB_DRIVE_PASSWORD: String(password) });
      json(res, r.error ? 400 : 200, r);
      return true;
    }
    return false;
  };
}
