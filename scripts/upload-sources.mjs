// Push local sample photos to the Drive library: one folder per group, new names only.
// Names already on Drive are skipped, so rerunning only uploads what was added.
// Usage (from the repo root): HUB_ADMIN_KEY=<admin password> node scripts/upload-sources.mjs [dir] [drive.json]
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
const [dir = "data/source-photos", configPath = "workspace/drive.json"] = process.argv.slice(2);
const apiUrl = JSON.parse((await readFile(configPath, "utf8")).replace(/^\uFEFF/, "")).apiUrl.replace(/\/\/(product-images-api|product-review-batch-api)\./, "//tools-hub-api.");
// Uploading to the library is a management task: it needs the admin password, not the app password.
const adminKey = process.env.HUB_ADMIN_KEY;
if (!adminKey) { console.error("Đặt mật khẩu admin: HUB_ADMIN_KEY='...' node scripts/upload-sources.mjs"); process.exit(1); }
const api = async (path, init = {}) => {
  for (let attempt = 1; ; attempt++) {
    const r = await fetch(apiUrl.replace(/\/$/, "") + path, { ...init, headers: { ...(init.headers || {}), "x-admin-key": adminKey } });
    if (r.ok || r.status === 409 || attempt === 4 || (r.status >= 400 && r.status < 500 && r.status !== 429)) return r;
    await new Promise((s) => setTimeout(s, attempt * 2000));
  }
};
let total = 0, failed = 0;
for (const group of (await readdir(dir, { withFileTypes: true })).filter((d) => d.isDirectory()).map((d) => d.name.normalize("NFC"))) {
  await api("/api/sources", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: group }) });
  const path = `/api/sources/${encodeURIComponent(group)}`;
  const have = new Set((await (await api(path)).json()).files.map((f) => f.name));
  const queue = (await readdir(join(dir, group))).filter((n) => /\.(jpe?g|png|webp)$/i.test(n) && !have.has(n));
  let done = 0;
  await Promise.all(Array.from({ length: 6 }, async () => {
    for (let name; (name = queue.shift()); ) {
      const r = await api(`${path}?name=${encodeURIComponent(name)}`, { method: "POST", headers: { "content-type": /\.png$/i.test(name) ? "image/png" : /\.webp$/i.test(name) ? "image/webp" : "image/jpeg" }, body: await readFile(join(dir, group, name)) });
      if (!r.ok) { failed++; console.log(`FAIL ${group}/${name} ${r.status}`); }
      if (++done % 50 === 0) console.log(`${group}: ${done}`);
    }
  }));
  total += done;
  console.log(`${group}: xong ${done} (đã có ${have.size})`);
}
console.log(`Tổng ${total}, lỗi ${failed}`);
