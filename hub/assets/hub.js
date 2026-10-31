// Cấu hình and Cập nhật for every page the Tools Hub menu serves, on macOS and Windows (the menu and web tools): buttons
// at the top right, where Product Review has its own; Cập nhật turns green with the version once a newer one is out.
// Both work through the menu server (hub/picker.mjs, hub/setup/config-api.mjs). A page opened as a file has no server
// to ask, so no buttons.
(() => {
  if (!location.protocol.startsWith("http")) return;
  const header = document.querySelector("header");
  if (!header) return;
  const btn = Object.assign(document.createElement("button"), { type: "button", className: "btn update", textContent: "Cập nhật" });
  const config = Object.assign(document.createElement("button"), { type: "button", className: "btn config", textContent: "Cấu hình" });
  header.append(config, btn);
  // The window title carries the installed version, as Product Review's does: "Grok Video Prompt v2.0.21".
  fetch("/api/root").then((r) => r.json()).then((r) => { if (r.version && !document.title.endsWith(r.version)) document.title = `${document.title} ${r.version}`; }).catch(() => {});
  config.onclick = showSetup;
  // The menu says whether Cấu hình is done: every step but the quota (which only reads what is left) must be OK.
  // Cấu hình turns green while something is missing; closing the window checks again.
  const status = document.getElementById("setupStatus");
  const STEP_NAMES = { drive: "mật khẩu app", node: "Node.js", codex: "Codex", login: "đăng nhập ChatGPT" };
  let setupRequest;
  function requestSetup() {
    if (setupRequest) return setupRequest;
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 50000);
    setupRequest = fetch('/api/setup', { method: 'POST', signal: abort.signal, cache: 'no-store' })
      .then(async response => {
        const report = await response.json();
        if (!response.ok) return { error: report.error || 'Không kiểm tra được cấu hình. Bấm Kiểm tra lại.' };
        if (!Array.isArray(report.Steps) || [...Object.keys(STEP_NAMES), 'quota'].some(id => !report.Steps.some(step => step.Id === id))) return { error: 'Kết quả cấu hình chưa đầy đủ. Bấm Kiểm tra lại.' };
        return report;
      })
      .catch(error => ({ error: error.name === 'AbortError' ? 'Kiểm tra cấu hình quá thời gian. Bấm Kiểm tra lại.' : 'Mất kết nối với app. Đóng và mở lại Tools Hub rồi kiểm tra lại.' }))
      .finally(() => { clearTimeout(timer); setupRequest = null; });
    return setupRequest;
  }
  async function refreshStatus() {
    if (!status) return;
    status.className = "setup-status";
    status.innerHTML = `<span class="mark">○</span><span class="text muted">Đang kiểm tra cấu hình…</span>`;
    const report = await requestSetup();
    const steps = [].concat(report?.Steps || []);
    if (!steps.length) { status.innerHTML = `<span class="mark">!</span><span class="text">Chưa kiểm tra được cấu hình. Bấm Cấu hình để xem.</span>`; return; }
    const missing = steps.filter((s) => s.Id in STEP_NAMES && s.State !== "ok" && s.State !== "warn").map((s) => STEP_NAMES[s.Id]);
    const done = !missing.length;
    status.className = `setup-status ${done ? "ok" : "todo"}`;
    status.innerHTML = done
      ? `<span class="mark">✔</span><span class="text">Đã cấu hình đủ. Các công cụ sẵn sàng dùng.</span>`
      : `<span class="mark">✖</span><span class="text">Chưa cấu hình xong: còn thiếu ${missing.join(", ")}. Cấu hình đủ rồi mới dùng được các công cụ.</span><button class="btn primary" type="button">Cấu hình ngay</button>`;
    status.querySelector("button")?.addEventListener("click", showSetup);
    config.classList.toggle("primary", !done);
  }
  refreshStatus();
  let next = "", current = "";
  const show = () => { btn.textContent = next ? `Cập nhật ${next}` : "Cập nhật"; btn.classList.toggle("primary", !!next); };
  const check = () => fetch("/api/update-check").then((r) => (r.ok ? r.json() : Promise.reject())).then((r) => { next = r.next || ""; current = r.current || ""; show(); return true; }).catch(() => false);
  setTimeout(check, 3000);
  setInterval(check, 6 * 3600 * 1000);

  // Same dialog as Product Review's (Show-UpdateDialog): check, then download and install with a running bar.
  btn.onclick = async () => {
    const shade = Object.assign(document.createElement("div"), { className: "shade" });
    shade.innerHTML = `<div class="dialog" role="dialog" aria-label="Cập nhật"><div class="status"></div><div class="bar"><span></span></div><div class="actions"><button class="btn primary" type="button" hidden>Cập nhật</button><button class="btn" type="button">Đóng</button></div></div>`;
    document.body.append(shade);
    const [status, bar, go, close] = [".status", ".bar", ".btn.primary", ".btn:not(.primary)"].map((s) => shade.querySelector(s));
    close.onclick = () => { if (!close.disabled) shade.remove(); };
    status.textContent = "Đang kiểm tra bản mới…";
    if (!(await check())) { bar.hidden = true; status.textContent = "Không kiểm tra được bản mới. Kiểm tra mạng rồi thử lại."; return; }
    bar.hidden = true;
    if (!next) { status.textContent = `Đang dùng bản mới nhất (${current || "bản hiện tại"}).`; return; }
    status.textContent = `Có phiên bản mới ${next} (đang dùng ${current || "bản hiện tại"}).`;
    go.hidden = false; go.focus();
    go.onclick = async () => {
      status.textContent = `Đang tải và cài phiên bản ${next}…`;
      bar.hidden = false; go.hidden = true; close.disabled = true;
      const r = await fetch("/api/update", { method: "POST" }).catch(() => null);
      if (!r || !r.ok) {
        bar.hidden = true; close.disabled = false; go.textContent = "Thử lại"; go.hidden = false;
        status.textContent = "Chưa cập nhật được. Kiểm tra mạng rồi thử lại.";
        return;
      }
      // The menu restarts on the new files; the page reloads once it answers again.
      status.textContent = "Đã cập nhật. Đang mở lại…";
      const wait = () => fetch("/api/root").then((x) => (x.ok ? location.reload() : setTimeout(wait, 500))).catch(() => setTimeout(wait, 500));
      setTimeout(wait, 1200);
    };
  };

  // Each step the tools need (hub/setup/setup-check.ps1), a fix button on the ones not
  // done, then Model AI. Settings are saved once for every tool.
  const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const post = (path, data, method = "POST") => fetch(path, { method, body: data ? JSON.stringify(data) : undefined }).then((r) => r.json()).catch(() => ({ error: "Không kết nối được." }));
  function dialog(cls, html) {
    const shade = Object.assign(document.createElement("div"), { className: "shade" });
    shade.innerHTML = `<div class="dialog ${cls}" role="dialog">${html}</div>`;
    document.body.append(shade);
    return shade;
  }
  function showSetup() {
    const titles = ["Mật khẩu app", "Node.js", "Codex", "Đăng nhập ChatGPT", "Hạn mức sử dụng", "Chrome của tool"];
    const shade = dialog("setup", `${titles.map((t) => `<div class="step"><span class="mark">○</span><span>${t}</span><span class="detail"></span><button class="btn primary" type="button" hidden></button></div>`).join("")}
      <div class="ai"><span>Model AI · model nhẹ, mức thấp tốn ít token hơn</span><select class="model"></select><select class="effort"></select></div>
      <div class="actions"><button class="btn again" type="button">Kiểm tra lại</button><button class="btn close" type="button">Đóng</button></div>`);
    const rows = [...shade.querySelectorAll(".step")].map((row) => ({ mark: row.querySelector(".mark"), detail: row.querySelector(".detail"), fix: row.querySelector("button") }));
    const [again, close, model, effort] = [".again", ".close", ".model", ".effort"].map((x) => shade.querySelector(x));
    close.onclick = () => { shade.remove(); refreshStatus(); };
    const marks = { ok: ["✔", "darkgreen"], fail: ["✖", "firebrick"], warn: ["!", "#b06000"] };
    const check = async () => {
      again.disabled = true;
      for (const r of rows) { r.mark.textContent = "○"; r.mark.style.color = ""; r.detail.textContent = "Đang kiểm tra…"; r.fix.hidden = true; }
      const report = await requestSetup();
      const steps = [].concat(report.Steps || []);
      if (!steps.length) {
        for (const row of rows) {
          row.mark.textContent = "!"; row.mark.style.color = "#b06000";
          row.detail.textContent = report.error || "Chưa kiểm tra được. Bấm Kiểm tra lại.";
        }
      }
      steps.forEach((step) => {
        const r = rows[['drive', 'node', 'codex', 'login', 'quota', 'browser'].indexOf(step.Id)];
        if (!r) return;
        const [mark, color] = marks[step.State] || ["○", ""];
        r.mark.textContent = mark; r.mark.style.color = color; r.detail.textContent = step.Detail || "";
        if (step.Action) {
          r.fix.textContent = step.Action === "install" ? "Cài" : step.Action === "browser" ? "Mở" : step.Action === "drive" && step.State === "ok" ? "Đổi" : "Đăng nhập";
          r.fix.classList.toggle("primary", step.State !== "ok"); r.fix.hidden = false;
          r.fix.onclick = () => fix(step.Action, r);
        }
      });
      again.disabled = false;
    };
    // While Codex signs in (from this window or another): the one-time code to type on the page opened in the tools'
    // Chrome. The buttons work meanwhile; Đăng nhập again starts over with a new code.
    const watchLogin = setInterval(async () => {
      if (!rows[3].detail.isConnected) return clearInterval(watchLogin);
      const { code } = await fetch("/api/setup-login").then((r) => r.json()).catch(() => ({}));
      const detail = rows[3].detail;
      if (!code || (detail.dataset.code === code && detail.querySelector(".copy-code"))) return;
      // Drawn once per code, with Chép mã to paste it on the sign-in page.
      detail.dataset.code = code;
      const copy = document.createElement("button");
      copy.type = "button";
      copy.className = "copy-code";
      copy.textContent = "Chép mã";
      copy.onclick = async () => {
        // The clipboard API needs a focused page; the old copy command covers the rest.
        const done = await navigator.clipboard.writeText(code).then(() => true, () => {
          const box = Object.assign(document.createElement("textarea"), { value: code });
          document.body.append(box);
          box.select();
          const ok = document.execCommand("copy");
          box.remove();
          return ok;
        });
        copy.textContent = done ? "Đã chép" : "Chưa chép được";
        setTimeout(() => { copy.textContent = "Chép mã"; }, 2000);
      };
      detail.replaceChildren(`Mã đăng nhập: ${code} `, copy, ". Dán vào trang đăng nhập vừa mở trong Chrome của tool. Lỗi thì bấm Đăng nhập để lấy mã mới.");
      for (const r of rows) r.fix.disabled = false;
    }, 1000);
    // Installing or signing in runs on this Mac; the steps are checked again when it finishes.
    const fix = async (action, row) => {
      if (action === "drive") { await showDrive(); return check(); }
      for (const r of rows) r.fix.disabled = true;
      row.detail.textContent = action === "install" ? "Đang cài…" : action === "browser" ? "Đang mở Chrome của tool (lần đầu tải về, có thể vài phút)…" : "Đang mở trang đăng nhập ChatGPT trong Chrome của tool…";
      const r = await post("/api/setup-step", { step: action });
      if (r.superseded) return;
      for (const x of rows) x.fix.disabled = false;
      await check();
      if (r.error) row.detail.textContent = r.error;
    };
    again.onclick = check;
    // Model AI: the model and reasoning level Codex uses; empty keeps Codex's own default.
    const effortNames = { low: "Thấp · ít token nhất", medium: "Vừa", high: "Cao", xhigh: "Rất cao", max: "Tối đa", ultra: "Siêu cao" };
    let models = [];
    const fill = (select, values, labels, value) => { select.innerHTML = values.map((v, i) => `<option value="${esc(v)}">${esc(labels[i])}</option>`).join(""); select.value = values.includes(value) ? value : ""; };
    const fillEfforts = (value) => {
      const m = models.find((x) => x.slug === model.value);
      const efforts = ["", ...(m ? [].concat(m.efforts || []) : ["low", "medium", "high"])];
      fill(effort, efforts, efforts.map((e) => (e ? effortNames[e] + (m && e === m.default_effort ? " (mặc định)" : "") : "Mức suy nghĩ mặc định")), value);
    };
    model.onchange = effort.onchange = async () => {
      fillEfforts(effort.value);
      const r = await post("/api/config/ai", { model: model.value, effort: effort.value });
      if (r.error) alert(r.error);
    };
    fetch("/api/config/ai").then((r) => r.json()).then((r) => {
      models = [].concat(r.models || []);
      const saved = r.settings || {};
      if (saved.model && !models.some((m) => m.slug === saved.model)) models.unshift({ slug: saved.model, name: saved.model, efforts: ["low", "medium", "high"], default_effort: "" });
      fill(model, ["", ...models.map((m) => m.slug)], ["Model mặc định của Codex", ...models.map((m) => m.name)], saved.model || "");
      fillEfforts(saved.effort || "");
    }).catch(() => { fill(model, [""], ["Model mặc định của Codex"], ""); fillEfforts(""); });
    check();
  }
  // Mật khẩu app (Show-DriveLogin): log in once on this Mac for every tool, or log out.
  async function showDrive() {
    const { drive } = await fetch("/api/config/drive").then((r) => r.json()).catch(() => ({}));
    const shade = dialog("", `<div class="status">${drive ? "Đã đăng nhập trên máy này. Ảnh tạo xong tự tải lên Drive." : "Nhập mật khẩu app một lần trên máy này để tải ảnh lên Drive và dùng kho Drive."}</div>
      ${drive ? "" : `<input class="pass" type="password" style="width:100%;margin-bottom:6px">`}<div class="err"></div>
      <div class="actions"><button class="btn primary go" type="button">${drive ? "Đăng xuất" : "Đăng nhập"}</button><button class="btn close" type="button">Đóng</button></div>`);
    return new Promise((done) => {
      const end = () => { shade.remove(); done(); };
      const pass = shade.querySelector(".pass"), err = shade.querySelector(".err");
      shade.querySelector(".close").onclick = end;
      const go = async () => {
        const r = drive ? await post("/api/config/drive", null, "DELETE") : await post("/api/config/drive", { password: pass.value });
        if (r.error) err.textContent = r.error; else end();
      };
      shade.querySelector(".go").onclick = go;
      if (pass) { pass.focus(); pass.onkeydown = (e) => { if (e.key === "Enter") go(); }; }
    });
  }
})();
