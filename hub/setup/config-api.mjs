// Cấu hình, shared by the Tools Hub menu (hub/picker.mjs) and Product Review's server: the same steps and
// settings as hub/setup/*.ps1, kept once per install in <hub>/workspace/config.
//   POST /api/setup                 the steps (setup-check.ps1 -AsJson)
//   POST /api/setup-step {step}     install: Codex and every tool's browser bridge; login: codex login
//   GET|POST /api/config/ai         Model AI: { settings, models } / save { model, effort }
//   GET|POST|DELETE /api/config/drive   the app password: { drive } / log in { password } / log out
import { execFile } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { findTool as findIn, runTool, psCommand, psFile } from "../platform.mjs";
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

  return async function handle(req, res, path) {
    if (path === "/api/setup" && req.method === "POST") {
      const {status, report} = await readSetup();
      json(res, status, report);
      return true;
    }
    if (path === "/api/setup-step" && req.method === "POST") {
      // Cài (Codex via npm, then each tool's browser bridge) or Đăng nhập (opens the browser, waits for the sign-in).
      const { step } = await body(req);
      const npm = findTool("npm"), codex = findTool("codex");
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
