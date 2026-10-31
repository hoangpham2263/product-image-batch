// What the Node servers (hub/picker.mjs, each tool's src/mac/server.mjs) do differently on macOS and Windows: the
// same pages and servers run on both; on Windows the window is hub/launch.ps1's WebView2 app window.
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { homedir } from "node:os";

export const onWindows = process.platform === "win32";

// Node, npm and codex: Homebrew or the npm prefix on macOS (Finder-launched apps miss them in PATH), the Node
// installer's folder and %APPDATA%\npm on Windows.
const extraPath = onWindows
  ? [join(process.env.ProgramFiles || "C:\\Program Files", "nodejs"), join(process.env.APPDATA || join(homedir(), "AppData", "Roaming"), "npm")]
  : ["/opt/homebrew/bin", "/usr/local/bin", join(homedir(), ".npm-global", "bin"), join(homedir(), ".dotnet", "tools")];
export const toolEnv = { ...process.env, PATH: [...new Set([...(process.env.PATH || "").split(delimiter), ...extraPath, dirname(process.execPath)])].filter(Boolean).join(delimiter) };
export const findTool = (name, env = toolEnv) => String(env.PATH || env.Path || "").split(delimiter).filter(Boolean)
  .flatMap((d) => (onWindows ? [".cmd", ".exe", ""] : [""]).map((ext) => join(d, name + ext))).find((p) => existsSync(p));
// npm and codex are .cmd files on Windows, which Node only starts through the shell.
export function runTool(cmd, args, options, done) {
  if (onWindows && /\.cmd$/i.test(cmd)) return execFile(`"${cmd}"`, args, { ...options, shell: true }, done);
  return execFile(cmd, args, options, done);
}

// Windows PowerShell 5.1 is on every Windows; pwsh 7 on macOS.
export const PWSH = process.env.PR_PWSH || (onWindows ? "powershell.exe"
  : [...(process.env.PATH || "").split(delimiter).map((d) => join(d, "pwsh")), "/opt/homebrew/bin/pwsh", "/usr/local/bin/pwsh",
    join(homedir(), ".dotnet", "tools", "pwsh"), "/usr/local/microsoft/powershell/7/pwsh"].find((p) => existsSync(p)) || "pwsh");
// Arguments for a PowerShell command, and for a script with its parameters ("-Name", value, …). On Windows both run
// past the execution policy and talk UTF-8 on stdin/stdout (5.1 uses the console code page otherwise).
const utf8 = "[Console]::InputEncoding=[Console]::OutputEncoding=New-Object Text.UTF8Encoding $false; ";
const quote = (s) => `'${String(s).replace(/'/g, "''")}'`;
export const psCommand = (command) => (onWindows ? ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", utf8 + command] : ["-NoProfile", "-Command", command]);
export const psFile = (file, args = []) => (onWindows
  ? psCommand(`& ${quote(file)} ${args.map((a) => (/^-[A-Za-z]+$/.test(a) ? a : quote(a))).join(" ")}; exit $LASTEXITCODE`)
  : ["-NoProfile", "-File", file, ...args]);

// Stop every process whose command line has this text (a tool's server, the menu), as pkill -f does.
export function killMatching(text, done = () => {}) {
  if (!onWindows) return execFile("pkill", ["-f", text], () => done());
  execFile(PWSH, psCommand(`Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains(${quote(text)}) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`), { windowsHide: true }, () => done());
}
// Stop a process and everything it started (Dừng: run-images.ps1, codex and their children). On macOS the process
// was started detached, so it leads its own group.
export function killTree(proc) {
  if (onWindows) return execFile("taskkill", ["/PID", String(proc.pid), "/T", "/F"], { windowsHide: true }, () => {});
  try { process.kill(-proc.pid, "SIGKILL"); } catch { try { proc.kill("SIGKILL"); } catch {} }
}

// A window of its own on macOS: Chrome in app mode (no tabs or address bar), else the default browser. On Windows the
// app window (hub/launch.ps1) shows the pages, so nothing opens here.
export function appWindow(url, size = "1120,840") {
  if (onWindows) return;
  execFile("open", ["-na", "Google Chrome", "--args", `--app=${url}`, `--window-size=${size}`], (err) => { if (err) execFile("open", [url]); });
}

// The system file dialog: real paths, opened at folder. filter is "images" or "table" (CSV or ZIP / RAR / 7Z).
export function chooseFiles({ folder = "", table = false }, done) {
  const lines = (err, stdout) => done(err ? [] : String(stdout).split(/\r?\n/).map((p) => p.trim()).filter(Boolean));
  if (onWindows) {
    const filter = table ? "Bảng nhập|*.csv;*.zip;*.rar;*.7z" : "Ảnh|*.png;*.jpg;*.jpeg";
    const script = `Add-Type -AssemblyName System.Windows.Forms; $d=New-Object Windows.Forms.OpenFileDialog; $d.Multiselect=$true; $d.Title=${quote(table ? "Chọn bảng nhập" : "Chọn ảnh")}; $d.Filter=${quote(filter)}; `
      + `if(${quote(folder)} -and (Test-Path -LiteralPath ${quote(folder)})){$d.InitialDirectory=${quote(folder)}}; `
      + `$owner=New-Object Windows.Forms.Form -Property @{TopMost=$true;ShowInTaskbar=$false;Opacity=0}; $owner.Show(); `
      + `if($d.ShowDialog($owner) -eq 'OK'){$d.FileNames}; $owner.Dispose()`;
    return execFile(PWSH, ["-STA", ...psCommand(script)], { windowsHide: true }, lines);
  }
  const at = folder && existsSync(folder) ? ` default location (POSIX file ${JSON.stringify(folder)})` : "";
  const what = table ? `"Chọn bảng nhập" of type {"csv", "zip", "rar", "7z"}` : `"Chọn ảnh" of type {"public.png", "public.jpeg"}`;
  const script = `set picked to choose file with prompt ${what} with multiple selections allowed${at}
set out to ""
repeat with f in picked
set out to out & POSIX path of f & linefeed
end repeat
return out`;
  execFile("osascript", ["-e", script], lines);
}
