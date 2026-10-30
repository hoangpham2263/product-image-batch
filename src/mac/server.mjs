// Kept for installs from before Tools Hub: after updating, the old server restarts this file. It tidies the old
// layout (hub/launch.ps1 -Migrate), then runs Product Review's server on the port the open window still uses.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const pwsh = ["/opt/homebrew/bin/pwsh", "/usr/local/bin/pwsh", `${process.env.HOME}/.dotnet/tools/pwsh`, "pwsh"].find((p) => p === "pwsh" || existsSync(p));
try { execFileSync(pwsh, ["-NoProfile", "-File", resolve(root, "hub", "launch.ps1"), "-Migrate"], { stdio: "inherit", timeout: 120000 }); } catch {}
// The old server asks its successor to wait for the port (PRB_WAIT_PORT, its name before the rename).
if (process.env.PRB_WAIT_PORT) process.env.PR_WAIT_PORT = "1";
process.env.PR_PORT ||= String(47000 + (parseInt(createHash("sha1").update(root).digest("hex").slice(0, 6), 16) % 1000));
await import("../../apps/product-review/src/mac/server.mjs");
