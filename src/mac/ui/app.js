// macOS window for Product Review Batch. Layout, texts and behaviour follow the Windows window
// (src/ui/main-window.ps1 and the dialogs next to it) control by control; the work itself runs in
// PowerShell through server.mjs.
"use strict";

// ---------- helpers ----------
const api = async (cmd, args = {}) => {
  const r = await fetch("/api/rpc", { method: "POST", body: JSON.stringify({ cmd, args }) });
  const body = await r.json();
  if (!r.ok) throw new Error(body.error || `HTTP ${r.status}`);
  return body.result;
};
// PowerShell unrolls one-item arrays; lists always come back as arrays here.
const list = (v) => (Array.isArray(v) ? v : v == null ? [] : [v]);
const fileUrl = (p) => `/file?path=${encodeURIComponent(p)}&t=${Date.now()}`;

function el(tag, cls = "", props = {}) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  for (const [k, v] of Object.entries(props)) {
    if (k === "text") e.textContent = v;
    else if (k === "style") Object.assign(e.style, v);
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else e[k] = v;
  }
  return e;
}
// left, top, width, height (px), plus right/bottom for anchored edges, like WinForms Location/Size/Anchor.
function at(e, l, t, w, h, anchor = {}) {
  const s = e.style;
  if (anchor.right != null) { s.right = anchor.right + "px"; if (anchor.left !== false) s.left = l + "px"; else s.width = w + "px"; }
  else { s.left = l + "px"; if (w != null) s.width = w + "px"; }
  if (anchor.bottom != null) { s.bottom = anchor.bottom + "px"; if (anchor.top !== false) s.top = t + "px"; else s.height = h + "px"; }
  else { s.top = t + "px"; if (h != null) s.height = h + "px"; }
  if (anchor.right != null && anchor.left !== false) s.removeProperty("width");
  if (anchor.bottom != null && anchor.top !== false) s.removeProperty("height");
  return e;
}
const label = (text, cls = "") => el("div", "label " + cls, { text });
const button = (text, primary = false) => el("button", "btn" + (primary ? " primary" : ""), { text, type: "button" });
function picture(cls = "") {
  const p = el("div", "pic " + cls);
  const img = el("img");
  img.hidden = true;
  p.append(img);
  p.set = (path, emptyText = "") => {
    p.querySelector(".empty")?.remove();
    p.classList.toggle("has", !!path);
    img.hidden = !path;
    if (path) { img.src = fileUrl(path); img.onerror = () => { img.hidden = true; }; }
    else if (emptyText) p.append(el("div", "empty", { text: emptyText }));
  };
  // A small × on hover removes the shown image (Add-RemoveOverlay).
  p.onRemove = (fn) => { const x = el("div", "x", { text: "×" }); x.addEventListener("click", (e) => { e.stopPropagation(); fn(); }); p.append(x); };
  return p;
}
function numeric(min, max, value) {
  const box = el("div", "num");
  const input = el("input", "", { value: String(value) });
  const spin = el("div", "spin");
  const up = el("button", "up", { type: "button" }), down = el("button", "down", { type: "button" });
  spin.append(up, down);
  box.append(input, spin);
  const clamp = (v) => Math.max(box.min, Math.min(box.max, Number.isFinite(v) ? Math.round(v) : box.min));
  Object.assign(box, { min, max });
  Object.defineProperty(box, "value", { get: () => clamp(Number(input.value)), set: (v) => { input.value = String(clamp(v)); } });
  Object.defineProperty(box, "enabled", { set: (on) => { input.disabled = !on; up.disabled = !on; down.disabled = !on; box.classList.toggle("disabled", !on); } });
  up.onclick = () => { box.value = box.value + 1; };
  down.onclick = () => { box.value = box.value - 1; };
  input.onblur = () => { box.value = Number(input.value); };
  return box;
}
function combo(items = []) {
  const s = el("select", "combo");
  s.setItems = (values, labels = values) => { s.replaceChildren(...values.map((v, i) => new Option(labels[i], v))); };
  s.setItems(items);
  return s;
}
function checkbox(text) {
  const wrap = el("label", "check");
  const input = el("input", "", { type: "checkbox" });
  wrap.append(input, document.createTextNode(text));
  wrap.input = input;
  return wrap;
}
// Pick image files from disk; each one is uploaded so PowerShell gets a real file path.
async function upload(file) {
  const r = await fetch(`/api/upload?name=${encodeURIComponent(file.name || "clipboard.png")}`, { method: "POST", body: file });
  const body = await r.json();
  if (!r.ok) throw new Error(body.error);
  return body.path;
}
function pickFiles(accept, multiple) {
  return new Promise((resolve) => {
    const input = el("input", "", { type: "file", accept, multiple });
    input.onchange = () => resolve([...input.files]);
    input.click();
  });
}
const imageFiles = (items) => [...items].filter((f) => /^image\/(png|jpeg)$/.test(f.type));

// Errors in this window are logged on the Mac side (workspace/logs/app-errors.log) and go out with Gửi log.
const reportError = (message, stack) => fetch("/api/client-error", { method: "POST", body: JSON.stringify({ message: String(message || ""), stack: String(stack || "") }) }).catch(() => {});
addEventListener("error", (e) => reportError(e.message, e.error?.stack || `${e.filename}:${e.lineno}:${e.colno}`));
addEventListener("unhandledrejection", (e) => reportError(e.reason?.message || e.reason, e.reason?.stack));

// ---------- child windows ----------
const stack = [];
function openWindow(title, w, h, { white = false } = {}) {
  const modal = el("div", "modal");
  const win = el("div", "window");
  const bar = el("div", "titlebar");
  const close = el("button", "close", { text: "✕", type: "button" });
  bar.append(el("div", "t", { text: title }), close);
  const body = el("div", "wbody" + (white ? " white" : ""));
  body.style.width = w + "px";
  body.style.height = h + "px";
  win.append(bar, body);
  modal.append(win);
  document.body.append(modal);
  const place = () => {
    win.style.left = Math.max(0, Math.round((innerWidth - win.offsetWidth) / 2)) + "px";
    win.style.top = Math.max(0, Math.round((innerHeight - win.offsetHeight) / 2)) + "px";
  };
  place();
  const view = { body, win, onClose: null, closed: false, cancel: null };
  view.close = () => {
    if (view.closed) return;
    view.closed = true;
    modal.remove();
    stack.splice(stack.indexOf(view), 1);
    view.onClose?.();
  };
  close.onclick = () => (view.cancel || view.close)();
  stack.push(view);
  return view;
}
addEventListener("keydown", (e) => {
  const top = stack.at(-1);
  if (e.key === "Escape" && top) { e.preventDefault(); (top.cancel || top.close)(); }
});
// ContextMenuStrip shown under a button: [{ text, disabled, onClick }]; a click elsewhere closes it.
function dropMenu(anchor, items) {
  const menu = el("div", "menu");
  const done = () => { menu.remove(); removeEventListener("mousedown", outside, true); removeEventListener("keydown", escape, true); };
  const outside = (e) => { if (!menu.contains(e.target)) done(); };
  const escape = (e) => { if (e.key === "Escape") { e.preventDefault(); e.stopImmediatePropagation(); done(); } };
  for (const item of items) {
    const row = el("div", item.disabled ? "off" : "", { text: item.text });
    if (!item.disabled) row.onclick = () => { done(); item.onClick(); };
    menu.append(row);
  }
  const r = anchor.getBoundingClientRect();
  Object.assign(menu.style, { left: r.left + "px", top: r.bottom + "px" });
  document.body.append(menu);
  addEventListener("mousedown", outside, true);
  addEventListener("keydown", escape, true);
}
// MessageBox.Show: resolves "OK", "Yes" or "No".
function messageBox(text, title = "", buttons = ["OK"]) {
  return new Promise((resolve) => {
    const view = openWindow(title, 0, 0);
    view.win.classList.add("msg");
    view.body.style.width = view.body.style.height = "";
    const bar = el("div", "bar");
    const names = { OK: "OK", Yes: "Yes", No: "No" };
    let answer = buttons.includes("No") ? "No" : "OK";
    for (const b of buttons) {
      const btn = el("button", "btn", { text: names[b], type: "button" });
      btn.onclick = () => { answer = b; view.close(); };
      bar.append(btn);
    }
    view.body.append(el("div", "txt", { text }), bar);
    view.onClose = () => resolve(answer);
    view.win.style.minWidth = "180px";
    view.win.style.left = Math.round((innerWidth - view.win.offsetWidth) / 2) + "px";
    view.win.style.top = Math.round((innerHeight - view.win.offsetHeight) / 2) + "px";
    bar.firstChild.focus();
  });
}

// ---------- main window ----------
const ui = { client: document.getElementById("client") };
const state = { rows: [], fallback: false, library: "drive", group: "Áo", drive: false, version: "", output: "", codex: false };
const run = { active: false, since: 0, total: 0, done: 0, index: 0, stages: new Map(), jobRows: [], stage: "", stopped: false, failure: false, started: 0, resultFolder: "", anim: 0 };

function buildMain() {
  const c = ui.client;
  // Header (Dock Top, 64).
  const header = at(el("div", "panel"), 0, 0, null, 64, { right: 0 });
  header.append(at(label("Product Review Batch", ""), 20, 19, null, 26));
  header.firstChild.style.fontSize = "17.33px";
  ui.btnUpdate = at(button("Cập nhật"), null, 16, 100, 32, { right: 24, left: false });
  header.append(ui.btnUpdate);

  // Link sản phẩm & ảnh (20,78 820x344, Top/Left/Right).
  const cardList = at(el("div", "card"), 20, 78, null, 344, { right: 264 });
  cardList.append(at(label("Link sản phẩm & ảnh"), 14, 10, null, 20));
  const editor = at(el("div", "panel"), 14, 36, null, 296, { right: 14 });
  ui.btnAdd = at(button("+ Thêm sản phẩm", true), 0, 0, 160, 34);
  ui.btnBulk = at(button("Thêm nhiều link"), 172, 0, 150, 34);
  ui.flow = at(el("div", "flow"), 0, 44, null, null, { right: 0, bottom: 0 });
  Object.assign(ui.flow.style, { background: "#fff", border: "1px solid #000", padding: "10px 10px 6px 10px" });
  editor.append(ui.btnAdd, ui.btnBulk, ui.flow);
  cardList.append(editor);

  // Thao tác (856,78 224x344, Top/Right).
  const cardActions = at(el("div", "card"), null, 78, 224, 344, { right: 24, left: false });
  cardActions.append(at(label("Thao tác"), 14, 10, null, 20));
  // In the order they are used: review the results, open them, then setup and support.
  const names = [["btnReview", "Duyệt & xuất file"], ["btnOut", "Mở kết quả"], ["btnSetup", "Kiểm tra cấu hình"], ["btnLogs", "Gửi log"]];
  names.forEach(([key, text], i) => { ui[key] = at(button(text), 14, 36 + i * 37, 196, 32); cardActions.append(ui[key]); });

  // Run row (20,434 1060x62).
  const cardRun = at(el("div", "card"), 20, 434, null, 62, { right: 24 });
  ui.btnRun = at(button("Bắt đầu", true), 14, 11, 160, 40);
  ui.btnStop = at(button("Dừng"), 186, 11, 100, 40);
  ui.btnStop.disabled = true;
  ui.lblStatus = at(label("", "muted"), 302, 18, 220, 26);
  ui.lblStatus.style.lineHeight = "26px";
  ui.lblThr = at(label("Luồng:", "muted"), null, 19, 56, 24, { right: 88, left: false });
  ui.numThr = at(numeric(1, 4, 1), null, 16, 64, 24, { right: 22, left: false });
  ui.lblThr.style.lineHeight = "24px";
  cardRun.append(ui.btnRun, ui.btnStop, ui.lblStatus, ui.lblThr, ui.numThr);

  // Tiến trình & thông báo (20,508 1060x282, all anchors).
  const cardLog = at(el("div", "card"), 20, 508, null, null, { right: 24, bottom: 10 });
  cardLog.append(at(label("Tiến trình & thông báo"), 14, 10, null, 20));
  ui.bar = at(el("div", "progress"), 14, 36, null, 8, { right: 14 });
  ui.bar.append(el("span"));
  ui.lblProgress = at(label("Thêm sản phẩm và ảnh đi kèm để bắt đầu."), 14, 50, null, 24, { right: 14 });
  ui.lblProgress.style.lineHeight = "24px";
  ui.txtLog = at(el("textarea", "text", { readOnly: true }), 14, 80, null, null, { right: 14, bottom: 12 });
  cardLog.append(ui.bar, ui.lblProgress, ui.txtLog);

  c.append(header, cardList, cardActions, cardRun, cardLog);
}

function appendLog(text) { if (text) { ui.txtLog.value += text + "\n"; ui.txtLog.scrollTop = ui.txtLog.scrollHeight; } }
function setStatus(text, color) { ui.lblStatus.textContent = text; ui.lblStatus.style.color = color || "var(--muted)"; }
function countUrls() { return new Set(state.rows.map((r) => r.url.trim()).filter(Boolean)).size; }
function updateStatus() { if (!run.active) setStatus(`Sẵn sàng • ${countUrls()} sản phẩm`); }
function setBar(value, max, marquee = false) {
  ui.bar.classList.toggle("marquee", marquee);
  ui.bar.firstChild.style.width = marquee ? "" : `${Math.min(100, (value / Math.max(1, max)) * 100)}%`;
}

// ----- queue rows (Add-ProductQueueRow / Update-ProductQueueRow) -----
// Link info from PowerShell: products[] (each with scenes[]) plus all scenes flattened.
function normInfo(info) {
  if (!info) return null;
  return { ...info, products: list(info.products).map((p) => ({ ...p, scenes: list(p.scenes) })), scenes: list(info.scenes) };
}
function rowStatus(row) {
  const products = row.info?.products || [], scenes = row.info?.scenes || [];
  const image = products.find((p) => p.ok)?.file || scenes.find((s) => s.ok)?.file || "";
  if (scenes.some((s) => !s.ok) || products.some((p) => p.file && !p.ok)) return { text: "Không đọc được ảnh, hãy gắn lại.", color: "var(--error)", image };
  if (products.some((p) => !p.scenes.length)) return { text: "● Có ảnh gốc chưa có review", color: "var(--warn)", image };
  if (scenes.length) return { text: products.length > 1 ? `● ${products.length} mẫu · ${scenes.length} ảnh` : scenes.length > 1 ? `● ${scenes.length} ảnh` : "● Đã có ảnh", color: "var(--ok)", image };
  return row.url.trim() ? { text: "● Chưa có ảnh", color: "var(--warn)", image: "" } : { text: "Chưa có link", color: "var(--muted)", image: "" };
}
function renderRows() {
  const width = Math.max(700, ui.flow.clientWidth - 40);
  ui.flow.replaceChildren(...state.rows.map((row, i) => {
    const card = el("div", "qrow", { style: { width: width + "px" } });
    const st = row.stage ? { text: row.stage.text, color: row.stage.color } : rowStatus(row);
    const pic = at(picture(), width - 192, 8, 44, 44);
    pic.set(rowStatus(row).image);
    const status = at(label(st.text), width - 340, 19, 140, 24);
    status.style.color = st.color;
    status.style.lineHeight = "24px";
    const open = at(button("Xem / sửa"), width - 136, 12, 90, 34);
    const remove = at(button("×"), width - 40, 12, 32, 34);
    remove.title = "Xóa sản phẩm";
    const url = at(el("div", "text plain", { text: row.url }), 52, 20, width - 397, 22);
    url.style.lineHeight = "20px";
    card.append(at(label("#" + (i + 1), "muted"), 10, 19, 40, 22), url, status, pic, open, remove);
    card.onclick = (e) => { if (!run.active && e.target !== remove) showProductDialog(row); };
    remove.onclick = (e) => { e.stopPropagation(); if (run.active) return; state.rows.splice(state.rows.indexOf(row), 1); renderRows(); updateStatus(); persist(); };
    // Drop images straight onto the row thumbnail.
    pic.addEventListener("dragover", (e) => e.preventDefault());
    pic.addEventListener("drop", async (e) => {
      e.preventDefault(); e.stopPropagation();
      try {
        const files = imageFiles(e.dataTransfer.files);
        if (!files.length) return;
        const root = await api("draftOpen");
        await api("draftAttach", { root, url: row.url.trim(), paths: await Promise.all(files.map(upload)) });
        row.info = normInfo(await api("draftSave", { root, url: row.url.trim(), others: [], group: state.group }));
        renderRows();
      } catch (err) { row.stage = { text: err.message, color: "var(--error)" }; renderRows(); row.stage = null; }
    });
    return card;
  }));
}

async function loadState() {
  Object.assign(state, await api("state"));
  state.rows = list(state.rows).map((info) => ({ url: info.url, info: normInfo(info) }));
  document.title = ("Product Review Batch " + (state.version || "")).trim();
  renderRows();
  updateStatus();
}

// The list saves itself on every change; Bắt đầu checks that every link is ready.
function persist() { saveQueue(false).catch(() => {}); }
async function saveQueue(requireReady = false) {
  return api("queueSave", { urls: state.rows.map((r) => r.url), requireReady });
}

async function updateReviewButton() {
  const pending = run.resultFolder ? await api("pending", { batch: run.resultFolder }).catch(() => 0) : 0;
  ui.btnReview.textContent = pending > 0 ? `Duyệt & xuất file (${pending})` : "Duyệt & xuất file";
  ui.btnReview.classList.toggle("primary", pending > 0);
}

// ----- product dialog: one row per product image, its review images beside it -----
// Small thumbnails only; clicking one opens it large. Each pair becomes one generated image.
function showImagePreview(path, title) {
  const view = openWindow(title, 760, 560);
  const pic = at(picture(), 12, 12, 736, 490);
  pic.style.background = "var(--smoke)";
  pic.set(path);
  const close = at(button("Đóng"), 648, 514, 100, 32);
  close.onclick = view.close;
  view.body.append(pic, close);
  close.focus();
}

// Native macOS file dialog opened at a folder; returns the picked files' real paths.
async function chooseImages(folder) {
  const r = await fetch("/api/choose-images", { method: "POST", body: JSON.stringify({ folder }) }).then((x) => x.json()).catch(() => ({ paths: [] }));
  return list(r.paths);
}

// "Từ kho Drive": nothing loads until a danh mục is chosen, so the window opens at once. Thêm uses the picked
// images directly (downloading only those not on this machine yet); Tải về máy brings the chosen danh mục, or
// every danh mục, over in one go. Either way nothing is fetched twice.
function showDrivePicker() {
  return new Promise((resolve) => {
    const noLogin = "Chưa đăng nhập mật khẩu app. Mở Kiểm tra cấu hình để đăng nhập.";
    const view = openWindow("Chọn ảnh review từ kho Drive", 760, 540);
    const groups = at(combo(), 20, 16, 220, 24);
    const sync = at(button("Tải về máy ▾"), 250, 14, 120, 28);
    const count = at(label("", "muted"), 382, 18, 358, 24);
    const bar = at(el("div", "progress marquee"), 20, 478, 400, 8);
    bar.append(el("span"));
    bar.hidden = true;
    const note = at(label(state.drive ? "" : noLogin), 20, 494, 500, 24);
    note.style.color = "var(--error)";
    // Background loading shows on a thin bar along the top of the grid: running while the Drive listing loads,
    // then filling as the thumbnails arrive.
    const loadBar = at(el("div", "progress"), 20, 46, 720, 4);
    loadBar.append(el("span"));
    loadBar.hidden = true;
    const grid = at(el("div", "flow"), 20, 52, 720, 420);
    Object.assign(grid.style, { background: "#fff", border: "1px solid #000", display: "flex", flexWrap: "wrap", alignContent: "flex-start", gap: "6px", padding: "6px" });
    const add = at(button("Thêm", true), 536, 490, 110, 32), cancel = at(button("Hủy"), 656, 490, 84, 32);
    add.disabled = true;
    sync.disabled = !state.drive;
    view.body.append(groups, sync, count, loadBar, grid, bar, note, add, cancel);
    let files = [], shown = 0, result = [], all = [], syncing = false, loads = 0, listing = false, summary = "";
    const picked = new Map();
    view.onClose = () => resolve(result);
    view.cancel = () => { if (!syncing) view.close(); };
    cancel.onclick = view.cancel;
    const busy = (on) => { syncing = on; sync.disabled = on || !state.drive || !all.length; groups.disabled = on; cancel.disabled = on; bar.hidden = !on; add.disabled = on || !picked.size; };
    // Thumbnails load top to bottom, six at a time, so a big danh mục never loads all at once.
    const thumbs = { queue: [], active: 0, round: 0, total: 0, done: 0 };
    const refreshCount = () => {
      const loading = thumbs.done < thumbs.total, percent = thumbs.total ? Math.round((thumbs.done / thumbs.total) * 100) : 0;
      loadBar.hidden = !groups.value || !(listing || loading);
      loadBar.classList.toggle("marquee", listing && !loading);
      loadBar.firstChild.style.width = listing && !loading ? "" : `${percent}%`;
      if (syncing) return;
      if (!groups.value) { count.textContent = "Chọn danh mục để xem ảnh."; add.disabled = true; return; }
      add.disabled = !picked.size;
      if (loading) { count.textContent = `${picked.size ? `Đã chọn ${picked.size} · ` : ""}Đang tải ảnh ${thumbs.done}/${thumbs.total} (${percent}%)`; return; }
      if (listing) { count.textContent = files.length ? `${files.length} ảnh có trên máy · đang tải danh sách Drive…` : "Đang tải danh sách…"; return; }
      if (summary) { count.textContent = summary; return; }
      const local = files.filter((f) => f.local).length;
      count.textContent = files.length ? `Đã chọn ${picked.size} / ${files.length} ảnh · ${local} ảnh có trên máy` : "Danh mục này chưa có ảnh.";
    };
    const pump = () => {
      while (thumbs.active < 6 && thumbs.queue.length) {
        const [img, src] = thumbs.queue.shift();
        const round = thumbs.round;
        thumbs.active++;
        img.onload = img.onerror = () => { if (round === thumbs.round) { thumbs.active--; thumbs.done++; refreshCount(); pump(); } };
        img.src = src;
      }
    };
    const clearGrid = () => { Object.assign(thumbs, { queue: [], active: 0, total: 0, done: 0 }); thumbs.round++; grid.replaceChildren(); shown = 0; };
    const showMore = () => {
      grid.querySelector(".more")?.remove();
      for (const f of files.slice(shown, shown + 120)) {
        const tile = el("div", "", { style: { width: "100px", height: "100px", padding: "3px", background: picked.has(f.name) ? "var(--accent)" : "var(--smoke)", cursor: "pointer", flex: "none" } });
        const img = el("img", "", { decoding: "async", style: { width: "100%", height: "100%", objectFit: "contain", display: "block" } });
        tile.append(img);
        thumbs.queue.push([img, f.local ? `/file?path=${encodeURIComponent(f.local)}` : f.url]);
        tile.onclick = () => {
          summary = "";
          if (picked.has(f.name)) { picked.delete(f.name); tile.style.background = "var(--smoke)"; }
          else { picked.set(f.name, f); tile.style.background = "var(--accent)"; }
          refreshCount();
        };
        grid.append(tile);
      }
      thumbs.total += Math.min(files.length, shown + 120) - shown;
      shown = Math.min(files.length, shown + 120);
      if (shown < files.length) {
        const more = el("button", "btn more", { text: "Xem thêm", type: "button", style: { position: "static", width: "100px", height: "100px" } });
        more.onclick = showMore;
        grid.append(more);
      }
      pump(); refreshCount();
    };
    // A danh mục shows its local copies at once; the Drive listing loads in the background and, when it brings
    // more (or the local copies are out of date), the grid is redrawn from it, keeping what was picked.
    const load = async () => {
      const token = ++loads;
      clearGrid(); picked.clear(); files = []; listing = false; summary = "";
      note.textContent = state.drive ? "" : noLogin;
      if (!groups.value) return refreshCount();
      const group = groups.value;
      if (state.drive) {
        listing = true; refreshCount();
        files = list(await api("sourceIndexedFiles", { group }).catch(() => []));
        if (token !== loads) return;
        showMore(); refreshCount();
      }
      const next = await api("sourceFiles", { group }).catch(() => ({ Files: files, Error: "Không kết nối được Drive (mạng hoặc mật khẩu app). Đang hiện ảnh có trên máy." }));
      if (token !== loads) return;
      listing = false;
      note.textContent = next.Error || "";
      const nextFiles = list(next.Files);
      if (nextFiles.length !== files.length || nextFiles.some((f) => !f.local) || !state.drive) {
        const keep = new Set(picked.keys());
        picked.clear();
        for (const f of nextFiles) if (keep.has(f.name)) picked.set(f.name, f);
        clearGrid(); files = nextFiles; showMore();
      }
      refreshCount();
    };
    // Tải về máy: one danh mục at a time, so each step shows.
    const runSync = async (names) => {
      if (!names.length) return;
      busy(true); note.textContent = "";
      let total = 0, downloaded = 0, removed = 0;
      const failed = [];
      for (const [i, name] of names.entries()) {
        count.textContent = names.length > 1 ? `Đang tải về máy: ${name} (${i + 1}/${names.length})…` : `Đang tải ${name} về máy…`;
        try { const r = await api("sourceSync", { group: name }); total += r.Total; downloaded += r.Downloaded; removed += r.Removed; }
        catch { failed.push(name); }
      }
      busy(false);
      await load();
      const ok = names.length - failed.length;
      if (ok) { summary = `${names.length > 1 ? `${ok} danh mục` : names[0]} đã có trên máy: ${total} ảnh (vừa tải ${downloaded}, xoá ${removed}).`; refreshCount(); }
      if (failed.length) note.textContent = `Chưa tải được: ${failed.join(", ")}. Kiểm tra mạng rồi thử lại.`;
    };
    sync.onclick = () => dropMenu(sync, [
      { text: "Danh mục đang chọn", disabled: !groups.value, onClick: () => runSync([groups.value]) },
      { text: `Tất cả danh mục (${all.length})`, onClick: () => runSync(all) },
    ]);
    groups.onchange = load;
    add.onclick = async () => {
      const chosen = [...picked.values()];
      const missing = chosen.filter((f) => !f.local);
      busy(true); count.textContent = missing.length ? `Đang tải ${missing.length} ảnh đã chọn…` : "Đang thêm…";
      try {
        const fetched = missing.length ? list(await api("sourcePick", { group: groups.value, files: missing.map(({ name, md5, url }) => ({ name, md5, url })) })) : [];
        result = [...chosen.filter((f) => f.local).map((f) => f.local), ...fetched];
        state.group = groups.value;
        busy(false);
        view.close();
      } catch { count.textContent = "Chưa tải được ảnh đã chọn. Kiểm tra mạng rồi thử lại."; busy(false); }
    };
    api("groups", { local: false }).then((g) => {
      all = list(g);
      groups.setItems(["", ...all], ["Chọn danh mục…", ...all]);
      groups.value = "";
      load();
      if (!all.length) { count.textContent = "Chưa có danh mục nào đang bật."; sync.disabled = true; }
    }).catch(() => { count.textContent = "Chưa tải được danh sách danh mục."; });
  });
}

async function showProductDialog(target = null) {
  let root;
  try { root = await api("draftOpen"); } catch (e) { return appendLog(e.message); }
  const view = openWindow("Ảnh sản phẩm gốc & ảnh review", 760, 430, { white: true });
  const b = view.body;
  let saved = false;
  view.onClose = () => { document.removeEventListener("paste", onPaste); if (!saved) api("draftDiscard", { root }).catch(() => {}); };
  const urlBox = at(el("input", "text", { value: target ? target.url : "" }), 20, 40, 720, 25);
  const rowsBox = at(el("div", "flow"), 20, 100, 720, 250);
  Object.assign(rowsBox.style, { background: "#fff", border: "1px solid #000" });
  const status = at(label(""), 20, 358, 500, 26);
  status.style.lineHeight = "26px";
  const save = at(button("Lưu sản phẩm"), 516, 388, 120, 30);
  const cancel = at(button("Hủy"), 646, 388, 94, 30);
  b.append(
    at(label("Link sản phẩm"), 20, 16, null, 22), urlBox,
    at(label("Ảnh gốc", "muted"), 26, 76, 70, 22), at(label("Ảnh review của ảnh gốc đó", "muted"), 110, 76, 300, 22),
    rowsBox, status, save, cancel,
  );
  view.cancel = view.close;
  cancel.onclick = view.close;
  const fail = (e) => { status.textContent = e.message; status.style.color = "var(--error)"; };


  // Paste and drop go to the row last used; -1 means "a new product image".
  let products = [], active = -1;
  const attach = async (files, productIndex) => {
    files = imageFiles(files);
    if (!files.length) return;
    try { await attachPaths(await Promise.all(files.map(upload)), productIndex); } catch (e) { fail(e); }
  };
  const attachPaths = async (paths, productIndex) => {
    try {
      if (!paths.length) return;
      const role = productIndex < 0 ? "Product" : "Scene";
      const url = await api("draftAttach", { root, url: urlBox.value.trim(), paths, role, productIndex });
      if (url !== urlBox.value.trim()) urlBox.value = url;
      if (role === "Product") active = Number.MAX_SAFE_INTEGER;
      await refresh();
    } catch (e) { fail(e); }
  };
  const thumb = (path, ok, onRemove, title) => {
    const t = picture();
    Object.assign(t.style, { position: "relative", width: "56px", height: "56px", flex: "none", border: "1px solid var(--line)", background: "var(--smoke)", cursor: "pointer" });
    t.set(ok ? path : "");
    t.title = title;
    t.onclick = () => ok && showImagePreview(path, title);
    t.onRemove(onRemove);
    return t;
  };
  const addTile = (text, onPick) => {
    const tile = el("button", "btn", { type: "button", text });
    Object.assign(tile.style, { position: "static", width: "56px", height: "56px", flex: "none", fontSize: text === "+" ? "20px" : "12px", color: "var(--muted)", borderStyle: "dashed", padding: "0", whiteSpace: "normal" });
    tile.onclick = onPick;
    return tile;
  };
  const refresh = async () => {
    const url = urlBox.value.trim();
    try {
      const info = await api("draftInfo", { root, url });
      products = list(info.products).map((p) => ({ ...p, scenes: list(p.scenes) }));
    } catch { products = []; }
    if (active >= products.length) active = products.length - 1;
    const rows = products.map((p, i) => {
      // Product image, arrow, then its reviews; many reviews wrap onto more lines so the add tiles stay visible.
      const row = el("div", "", { style: { display: "flex", alignItems: "flex-start", gap: "6px", padding: "6px", borderBottom: "1px solid var(--line)" } });
      if (i === active) row.style.background = "var(--hover)";
      const product = p.file
        ? thumb(p.file, p.ok, async () => { await api("draftRemoveProduct", { root, url, productIndex: i }).catch(fail); refresh(); }, `Ảnh gốc #${i + 1}`)
        : el("div", "label muted", { text: "Ảnh từ link", style: { position: "static", width: "56px", whiteSpace: "normal", fontSize: "11px" } });
      const arrow = el("div", "label muted", { text: "→", style: { position: "static", width: "16px", height: "56px", lineHeight: "56px", textAlign: "center", flex: "none" } });
      product.style.flex = "none";
      const reviews = el("div", "", { style: { display: "flex", flexWrap: "wrap", gap: "6px", flex: "1", minWidth: "0" } });
      row.append(product, arrow, reviews);
      reviews.append(...p.scenes.map((s, k) => thumb(s.file, s.ok, async () => {
        await api("draftRemoveScene", { root, url, productIndex: i, index: k }).catch(fail); refresh();
      }, `Ảnh review ${k + 1} · ảnh gốc #${i + 1}`)), addTile("+ Máy", async () => { active = i; attachPaths(await chooseImages(await api("reviewFolder", { group: state.group }).catch(() => "")), i); }),
        addTile("+ Drive", async () => { active = i; attachPaths(await showDrivePicker(), i); }),
        addTile("Dán", () => { active = i; pasteButton(i); }));
      // The row under the pointer receives pasted images.
      const select = () => { if (active !== i) { active = i; for (const [n, r] of [...rowsBox.children].entries()) r.style.background = n === i ? "var(--hover)" : ""; } };
      row.addEventListener("click", select);
      row.addEventListener("mouseenter", select);
      row.addEventListener("dragover", (e) => e.preventDefault());
      row.addEventListener("drop", (e) => { e.preventDefault(); e.stopPropagation(); active = i; attach(e.dataTransfer.files, i); });
      return row;
    });
    const addRow = el("div", "", { style: { display: "flex", alignItems: "center", gap: "8px", padding: "6px" } });
    addRow.append(addTile("+", async () => attachPaths(await chooseImages(""), -1)), addTile("Dán", () => pasteButton(-1)), el("div", "label muted", { text: "Thêm ảnh gốc", style: { position: "static" } }));
    addRow.addEventListener("mouseenter", () => { active = -1; for (const r of rowsBox.children) r.style.background = ""; });
    addRow.addEventListener("dragover", (e) => e.preventDefault());
    addRow.addEventListener("drop", (e) => { e.preventDefault(); e.stopPropagation(); attach(e.dataTransfer.files, -1); });
    rowsBox.replaceChildren(...rows, addRow);
    const reviews = products.reduce((n, p) => n + p.scenes.length, 0);
    const missing = products.filter((p) => !p.scenes.length).length;
    if (!url) { status.textContent = "Chưa có link"; status.style.color = "var(--muted)"; }
    else if (!products.length) { status.textContent = "● Chưa có ảnh"; status.style.color = "var(--warn)"; }
    else if (missing) { status.textContent = `● ${missing} ảnh gốc chưa có ảnh review`; status.style.color = "var(--warn)"; }
    else { status.textContent = `● ${products.length} ảnh gốc · ${reviews} ảnh review → ${reviews} ảnh kết quả`; status.style.color = "var(--ok)"; }
  };
  // Clipboard: an image goes to the active row (or becomes a product image when none); text in the link box stays text.
  // Nút Dán: images from the clipboard (the browser asks once for clipboard access).
  const pasteButton = async (productIndex) => {
    const files = [];
    try {
      for (const item of await navigator.clipboard.read()) {
        const type = item.types.find((t) => /^image\/(png|jpeg)$/.test(t));
        if (type) files.push(new File([await item.getType(type)], type === "image/png" ? "clipboard.png" : "clipboard.jpg", { type }));
      }
    } catch {}
    if (!files.length) return fail(new Error("Clipboard chưa có ảnh."));
    attach(files, productIndex);
  };
  // Cmd/Ctrl+V anywhere while this popup is on top, even before anything in it has focus.
  const onPaste = (e) => {
    if (stack.at(-1) !== view) return;
    const files = imageFiles(e.clipboardData?.files || []);
    if (!files.length) return;
    e.preventDefault();
    attach(files, products.length && active >= 0 ? Math.min(active, products.length - 1) : -1);
  };
  document.addEventListener("paste", onPaste);
  rowsBox.addEventListener("dragover", (e) => e.preventDefault());
  rowsBox.addEventListener("drop", (e) => { e.preventDefault(); attach(e.dataTransfer.files, -1); });
  urlBox.oninput = () => { active = -1; refresh(); };
  save.onclick = async () => {
    try {
      const url = urlBox.value.trim();
      const others = state.rows.filter((r) => r !== target).map((r) => r.url.trim());
      const entry = normInfo(await api("draftSave", { root, url, others, group: state.group }));
      saved = true;
      if (target) Object.assign(target, { url, info: entry });
      else state.rows.push({ url, info: entry });
      view.close();
      renderRows();
      updateStatus();
      persist();
      if (!target) ui.flow.scrollTop = ui.flow.scrollHeight;
    } catch (e) { fail(e); }
  };
  await refresh();
  urlBox.focus();
}

// ----- Thêm nhiều link -----
function showBulkDialog() {
  const view = openWindow("Thêm nhiều link", 700, 420);
  const text = at(el("textarea", "text"), 16, 66, 668, 258);
  const status = at(label(""), 16, 334, 668, 30);
  status.style.color = "var(--error)";
  const save = at(button("Thêm vào danh sách"), 376, 372, 186, 32);
  const cancel = at(button("Hủy"), 574, 372, 110, 32);
  const hint = at(label("Mỗi dòng một link. Thêm xong, bấm từng dòng trong danh sách để gắn ảnh."), 16, 16, 668, 44);
  hint.style.whiteSpace = "normal";
  view.body.append(hint, text, status, save, cancel);
  cancel.onclick = view.close;
  save.onclick = async () => {
    try {
      if (!text.value.trim()) throw new Error("Nhập ít nhất một link.");
      const urls = list(await api("parseLinks", { text: text.value }));
      const added = [];
      for (const url of urls) {
        if (state.rows.some((r) => r.url.trim() === url)) continue;
        const empty = state.rows.find((r) => !r.url.trim());
        if (empty) { empty.url = url; added.push(empty); } else { const row = { url, info: null }; state.rows.push(row); added.push(row); }
      }
      const infos = list(await api("rows", { urls: added.map((r) => r.url) }));
      added.forEach((r, i) => { r.info = normInfo(infos[i]); });
      view.close();
      renderRows();
      persist();
      updateStatus();
    } catch (e) { status.textContent = e.message; }
  };
  text.focus();
}

// ----- Duyệt kết quả (New-BatchReviewDialog) -----
async function showReviewDialog() {
  const view = openWindow("Duyệt kết quả", 924, 721);
  const b = view.body;
  const batches = at(combo(), 12, 12, 600, 24);
  const hint = at(label("Mỗi dòng một đánh giá. Bấm ảnh để xem lớn; Giữ/Bỏ chỉ áp dụng cho dòng đó.", "muted"), 12, 46, 900, 22);
  const flow = at(el("div", "flow"), 12, 72, null, null, { right: 12, bottom: 69 });
  const status = at(label(""), 12, null, 560, 36, { bottom: 17, top: false });
  status.style.lineHeight = "36px";
  const exportBtn = at(button("Xuất file Loox", true), null, null, 180, 40, { right: 12, left: false, bottom: 17, top: false });
  exportBtn.disabled = true;
  b.append(batches, hint, flow, status, exportBtn);
  let items = [], batch = "";
  const refresh = () => {
    const done = items.filter((i) => i.decision).length, good = items.filter((i) => i.decision === "ok").length;
    status.textContent = `Đã duyệt ${done}/${items.length} đánh giá • Giữ ${good} • Bỏ ${done - good}`;
    exportBtn.disabled = !(items.length > 0 && done === items.length && good > 0);
  };
  const decideFor = (item, paint) => async (value) => {
    const next = item.decision === value ? "" : value;
    await api("reviewDecide", { batch, id: item.id, decision: next });
    item.decision = next;
    paint();
    refresh();
  };
  const load = async () => {
    batch = batches.value;
    items = batch ? list(await api("reviewItems", { batch })) : [];
    const width = Math.max(840, flow.clientWidth - 28);
    flow.replaceChildren(...items.map((item, n) => {
      const row = el("div", "rrow", { style: { width: width + "px" } });
      const thumb = at(picture(), 8, 7, 48, 48);
      thumb.style.background = "var(--smoke)";
      thumb.style.cursor = "pointer";
      thumb.set(item.image);
      const title = at(label(`#${n + 1} · ${item.handle}`), 68, 5, width - 240, 20);
      const bodyText = at(label(item.body, "muted"), 68, 28, width - 240, 24);
      const ok = at(button("Giữ"), width - 152, 17, 64, 28), bad = at(button("Bỏ"), width - 80, 17, 64, 28);
      const paint = () => {
        ok.classList.toggle("primary", item.decision === "ok");
        bad.classList.toggle("flat-error", item.decision === "bad");
        row.classList.toggle("ok", item.decision === "ok");
        row.classList.toggle("bad", item.decision === "bad");
      };
      const decide = decideFor(item, paint);
      ok.onclick = () => decide("ok");
      bad.onclick = () => decide("bad");
      thumb.onclick = () => showReviewPreview(item, decide);
      paint();
      row.append(thumb, title, bodyText, ok, bad);
      return row;
    }));
    refresh();
  };
  batches.onchange = load;
  // Export shows its progress on the button itself; no extra message windows.
  exportBtn.onclick = async () => {
    exportBtn.disabled = true; exportBtn.textContent = "Đang xuất…";
    try {
      await api("reviewExport", { batch });
      exportBtn.textContent = "✓ Đã xuất";
      const option = batches.selectedOptions[0];
      if (option && !option.textContent.endsWith("đã xuất")) option.textContent += "  • đã xuất";
      setTimeout(() => { exportBtn.textContent = "Xuất file Loox"; refresh(); }, 2000);
    } catch (e) { status.textContent = e.message; exportBtn.textContent = "Xuất file Loox"; refresh(); }
  };
  const all = list(await api("reviewBatches"));
  batches.setItems(all.map((x) => x.path), all.map((x) => x.label));
  if (all.some((x) => x.path === run.resultFolder)) batches.value = run.resultFolder;
  if (!all.length) status.textContent = "Chưa có lần chạy nào để duyệt. Lần chạy tạo ra ảnh sẽ hiện ở đây.";
  else await load();
  return new Promise((resolve) => { view.onClose = resolve; });
}

function showReviewPreview(item, decide) {
  const view = openWindow("Xem ảnh đánh giá", 1080, 720);
  const b = view.body;
  // Left: the product photo above the review photo the image was made from; right: the result.
  const original = at(label("Ảnh sản phẩm gốc"), 12, 12, 500, 24);
  const product = at(picture(), 12, 42, 522, 250);
  const sceneLabel = at(label("Ảnh review ban đầu"), 12, 296, 500, 22);
  const scene = at(picture(), 12, 322, 522, 250);
  const result = at(picture(), 546, 42, 522, 530);
  for (const p of [product, scene, result]) p.style.background = "var(--smoke)";
  product.set(item.product);
  scene.set(item.scene);
  result.set(item.image);
  if (!item.product) original.textContent = "Ảnh sản phẩm gốc · không có";
  if (!item.scene) sceneLabel.textContent = "Ảnh review ban đầu · không có";
  const body = at(el("textarea", "text", { readOnly: true, value: item.body }), 12, 584, 1056, 70);
  const state_ = at(label(""), 12, 674, 540, 28);
  // Giữ or Bỏ decides and closes the window, so there is no separate Đóng; Esc closes without deciding.
  const keep = at(button("Giữ đánh giá"), 796, 670, 130, 36), skip = at(button("Bỏ đánh giá"), 938, 670, 130, 36);
  state_.textContent = { ok: "Đang giữ đánh giá này", bad: "Đang bỏ đánh giá này khỏi CSV" }[item.decision] || "Chưa chọn giữ hoặc bỏ";
  keep.onclick = async () => { await decide("ok"); view.close(); };
  skip.onclick = async () => { await decide("bad"); view.close(); };
  b.append(original, at(label("Ảnh kết quả"), 548, 12, 500, 24), product, sceneLabel, scene, result, body, state_, keep, skip);
}

// ----- Kiểm tra cấu hình (Show-SetupDialog): each needed step, with a fix button on the ones not done -----
async function showSetupDialog() {
  const view = openWindow("Kiểm tra cấu hình", 520, 372);
  const titles = ["Mật khẩu app", "Node.js", "Codex", "Đăng nhập ChatGPT", "Hạn mức sử dụng"];
  const rows = titles.map((title, i) => {
    const y = 16 + i * 58;
    const icon = at(label("○"), 20, y, 26, 24);
    icon.style.fontSize = "16px";
    const detail = at(label("", "muted"), 52, y + 22, 330, 32);
    Object.assign(detail.style, { whiteSpace: "normal", lineHeight: "16px", display: "-webkit-box", webkitLineClamp: "2", webkitBoxOrient: "vertical" });
    const fix = at(button("", true), 390, y + 6, 110, 32);
    fix.hidden = true;
    view.body.append(icon, at(label(title), 52, y, 330, 22), detail, fix);
    return { icon, detail, fix };
  });
  const again = at(button("Kiểm tra lại"), 290, 322, 110, 34), close = at(button("Đóng"), 410, 322, 90, 34);
  close.onclick = view.close;
  view.body.append(again, close);
  const icons = { ok: ["✔", "var(--ok)"], fail: ["✖", "var(--error)"], warn: ["!", "var(--warn)"] };
  const check = async () => {
    again.disabled = true;
    for (const row of rows) { row.icon.textContent = "○"; row.icon.style.color = "var(--muted)"; row.detail.textContent = "Đang kiểm tra…"; row.fix.hidden = true; }
    try {
      const steps = list((await (await fetch("/api/setup", { method: "POST" })).json()).Steps);
      steps.forEach((step, i) => {
        const row = rows[i];
        if (!row) return;
        const [mark, color] = icons[step.State] || ["○", "var(--muted)"];
        row.icon.textContent = mark; row.icon.style.color = color;
        row.detail.textContent = step.Detail || "";
        if (step.Action) { row.fix.textContent = step.Action === "install" ? "Cài" : step.Action === "drive" && step.State === "ok" ? "Đổi" : "Đăng nhập"; row.fix.hidden = false; row.fix.classList.toggle("primary", step.State !== "ok"); row.fix.onclick = () => fix(step.Action, row); }
      });
    } catch { rows[0].detail.textContent = "Chưa kiểm tra được. Bấm Kiểm tra lại."; }
    finally { again.disabled = false; }
  };
  // Installing or signing in runs here; the steps are checked again when it finishes.
  const fix = async (action, row) => {
    if (action === "drive") { await showDriveDialog(); return check(); }
    for (const r of rows) r.fix.disabled = true;
    row.detail.textContent = action === "install" ? "Đang cài…" : "Đăng nhập ChatGPT trong trình duyệt vừa mở…";
    const r = await (await fetch("/api/setup-step", { method: "POST", body: JSON.stringify({ step: action }) })).json().catch(() => ({ error: "setup" }));
    for (const x of rows) x.fix.disabled = false;
    Object.assign(state, { codex: (await api("state")).codex });
    await check();
    if (r.error) row.detail.textContent = r.error;
  };
  again.onclick = check;
  check();
}

// ----- Cập nhật (Show-UpdateDialog): check, then download and install with a running bar -----
function showUpdateDialog() {
  const view = openWindow("Cập nhật", 440, 168);
  const status = at(label(""), 20, 20, 400, 44);
  status.style.whiteSpace = "normal";
  const bar = at(el("div", "progress marquee"), 20, 72, 400, 10);
  bar.append(el("span"));
  const go = at(button("Cập nhật", true), 220, 112, 100, 32), close = at(button("Đóng"), 330, 112, 90, 32);
  go.hidden = true;
  close.onclick = () => { if (!close.disabled) view.close(); };
  view.cancel = close.onclick;
  view.body.append(status, bar, go, close);
  const current = state.version || "bản hiện tại";
  let next = "";
  const check = async () => {
    status.textContent = "Đang kiểm tra bản mới…";
    bar.hidden = false; go.hidden = true;
    try { next = await api("updateCheck"); }
    catch { bar.hidden = true; status.textContent = "Không kiểm tra được bản mới. Kiểm tra mạng rồi thử lại."; return; }
    bar.hidden = true;
    if (!next) { status.textContent = `Đang dùng bản mới nhất (${current}).`; return; }
    status.textContent = `Có phiên bản mới ${next} (đang dùng ${current}).`;
    go.hidden = false; go.focus();
  };
  // The server replaces the files, restarts on them, and the page reloads once it answers again.
  go.onclick = async () => {
    status.textContent = `Đang tải và cài phiên bản ${next}…`;
    bar.hidden = false; go.hidden = true; close.disabled = true;
    const r = await fetch("/api/update", { method: "POST" }).catch(() => null);
    if (!r || !r.ok) {
      bar.hidden = true; close.disabled = false; go.textContent = "Thử lại"; go.hidden = false;
      status.textContent = "Chưa cập nhật được. Kiểm tra mạng rồi thử lại.";
      return;
    }
    status.textContent = "Đã cập nhật. Đang mở lại app…";
    const wait = () => fetch("/api/rpc", { method: "POST", body: JSON.stringify({ cmd: "state", args: {} }) })
      .then((x) => (x.ok ? location.reload() : setTimeout(wait, 500))).catch(() => setTimeout(wait, 500));
    setTimeout(wait, 800);
  };
  check();
}

// ----- Google Drive (Show-DriveLogin) -----
function showDriveDialog() {
  const view = openWindow("Mật khẩu app", 400, 170);
  const info = at(label(""), 20, 18, 360, 40);
  info.style.whiteSpace = "normal";
  const pass = at(el("input", "text", { type: "password" }), 20, 62, 360, 25);
  const err = at(label(""), 20, 94, 360, 22);
  err.style.color = "var(--warn)";
  const ok = at(button("", true), 260, 120, 120, 36);
  view.body.append(info, pass, err, ok);
  if (state.drive) {
    info.textContent = "Đã đăng nhập trên máy này. Ảnh tạo xong tự tải lên Drive.";
    pass.hidden = true; ok.textContent = "Đăng xuất";
    ok.onclick = async () => { await api("driveLogout"); view.close(); };
  } else {
    info.textContent = "Nhập mật khẩu app một lần trên máy này để tải ảnh lên Drive và dùng kho Drive.";
    ok.textContent = "Đăng nhập";
    const login = async () => { try { await api("driveLogin", { password: pass.value }); view.close(); } catch (e) { err.textContent = e.message; } };
    ok.onclick = login;
    pass.onkeydown = (e) => { if (e.key === "Enter") login(); };
    pass.focus();
  }
  return new Promise((resolve) => { view.onClose = async () => { Object.assign(state, { drive: (await api("state")).drive }); resolve(); }; });
}

// ----- run (Start-GuiBatch, timer ticks) -----
function setRunning(on) {
  run.active = on;
  ui.btnRun.disabled = on; ui.btnStop.disabled = !on;
  for (const b of [ui.btnSetup, ui.btnLogs, ui.btnReview, ui.btnAdd, ui.btnBulk]) b.disabled = on;
  ui.numThr.enabled = !on;
  ui.flow.style.pointerEvents = on ? "none" : "";
}
function updateRunDisplay() {
  if (!run.active) return;
  const elapsed = Math.floor((Date.now() - run.started) / 1000);
  const time = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  let activity = [...run.stages].filter(([, v]) => !["Đã xong", "Chưa hoàn tất"].includes(v)).sort((a, b) => a[0] - b[0]).map(([k, v]) => `SP ${k}: ${v}`);
  if (run.stage === "Đang lưu kết quả" || !activity.length) activity = [run.stage];
  ui.lblProgress.textContent = `${run.done}/${run.total} ảnh đã xong  •  ${activity.join("  |  ")}  •  ${time}`;
  // Each job's live stage on its queue row (a link with several images runs several jobs).
  for (const [key, value] of run.stages) {
    const i = run.jobRows.length >= key ? run.jobRows[key - 1] - 1 : key - 1;
    const row = state.rows[i];
    if (!row) continue;
    const done = value === "Đã xong";
    row.stage = { text: done ? "✔ Đã xong" : `◔ ${value}`, color: done ? "var(--ok)" : "var(--accent)" };
  }
  renderRows();
}
function receive(event) {
  switch (event.Kind) {
    case "Start": run.total = event.Total; break;
    case "Output": run.resultFolder = event.Path; break;
    case "Rows": run.jobRows = list(event.Rows); break;
    case "Item": run.index = event.Index; run.stages.set(event.Index, event.Stage); break;
    case "Stage": run.stages.set(event.Index, event.Stage); run.stage = event.Stage; break;
    case "Retry": run.stages.set(event.Index, event.Stage); break;
    case "Saving": run.stage = event.Stage; break;
    case "Completed": if (run.stages.get(event.Index) !== "Đã xong") run.done++; run.stages.set(event.Index, event.Stage); break;
    case "Failed": run.stages.set(event.Index, event.Stage); run.failure = true; break;
    case "Warning": run.failure = true; break;
  }
  if (event.Text) appendLog(event.Text);
}
async function startBatch() {
  if (run.active) return;
  if (!state.drive) return appendLog("Nhập mật khẩu app trước khi chạy (Kiểm tra cấu hình).");
  try { await saveQueue(true); } catch (e) { return appendLog(e.message); }
  if (!countUrls()) return messageBox("Vui lòng thêm ít nhất một link sản phẩm.");
  if (!state.codex) return messageBox('Chưa có công cụ xử lý. Bấm "Kiểm tra cấu hình" để xem hướng dẫn.');
  ui.txtLog.value = "";
  Object.assign(run, { since: 0, total: countUrls(), done: 0, index: 0, stages: new Map(), jobRows: [], stage: "Đang chuẩn bị", stopped: false, failure: false, started: Date.now(), resultFolder: "" });
  for (const r of state.rows) r.stage = null;
  await updateReviewButton();
  const r = await fetch("/api/run", { method: "POST", body: JSON.stringify({ per: 1, threads: ui.numThr.value }) });
  if (!r.ok) {
    const body = await r.json().catch(() => ({}));
    return appendLog("Chưa khởi động được lượt xử lý: " + (body.error || r.status));
  }
  setRunning(true);
  setStatus("Đang chạy", "var(--accent)");
  setBar(0, 1, true);
  updateRunDisplay();
  poll();
}
async function poll() {
  if (!run.active) return;
  try {
    const r = await (await fetch(`/api/run?since=${run.since}`)).json();
    for (const event of r.events) receive(event);
    run.since = r.next;
    if (r.resultFolder) run.resultFolder = r.resultFolder;
    updateRunDisplay();
    if (r.done && !r.running) return finish(r);
  } catch {}
  setTimeout(poll, 700);
}
async function finish(r) {
  setRunning(false);
  setBar(run.done, Math.max(1, run.total));
  for (const row of state.rows) row.stage = null;
  // Finished links leave the queue during the run; their images go too, so the list starts clean.
  await api("pruneMap").catch(() => {});
  await loadState();
  const elapsed = Math.floor((Date.now() - run.started) / 1000);
  ui.lblProgress.textContent = `Đã xong ${run.done}/${run.total} ảnh • ${Math.floor(elapsed / 60)} phút ${elapsed % 60} giây`;
  if (r.stopped) { setStatus("Đã dừng", "var(--muted)"); appendLog("Đã dừng. Các link chưa hoàn tất được giữ lại."); }
  else if (r.exitCode === 0 && !run.failure) {
    setStatus("✔ Hoàn tất", "var(--ok)");
    appendLog("Xong. Bấm Duyệt & xuất file để duyệt từng ảnh; file Loox chỉ tạo khi duyệt xong.");
  } else {
    setStatus("! Cần thử lại", "var(--warn)");
    appendLog("Một số sản phẩm chưa hoàn tất. Bạn có thể bấm Bắt đầu để thử lại các link còn lại, hoặc Duyệt & xuất file với các ảnh đã xong.");
    appendLog("Nếu lỗi lặp lại, bấm Gửi log để admin kiểm tra.");
  }
  updateReviewButton();
}
// Running animation only in the status label.
setInterval(() => { if (run.active && !run.stopped) { run.anim = (run.anim + 1) % 3; setStatus("Đang chạy " + [".", "..", "..."][run.anim], "var(--accent)"); } }, 350);

// ---------- wiring ----------
function wire() {
  ui.btnAdd.onclick = () => showProductDialog();
  ui.btnBulk.onclick = showBulkDialog;
  // Gửi log: packs the logs and uploads them for the admin page; progress shows on the button.
  ui.btnLogs.onclick = async () => {
    const rejected = await api("rejectedCount").catch(() => 0);
    const question = "Gửi log cho admin?\n\n" + (rejected ? `Gồm log, cấu hình, các lần chạy gần nhất và ${rejected} ảnh đã Bỏ chưa gửi.` : "Gồm log, cấu hình và các lần chạy gần nhất.") + " Không gửi mật khẩu.";
    if ((await messageBox(question, "Gửi log", ["Yes", "No"])) !== "Yes") return;
    ui.btnLogs.disabled = true; ui.btnLogs.textContent = "Đang gửi…";
    try {
      const r = await api("sendLogs");
      if (r.sent) { ui.btnLogs.textContent = "✓ Đã gửi"; appendLog(`Đã gửi log: ${r.name}${r.samples ? ` (kèm ${r.samples} ảnh đã Bỏ)` : ""}`); }
      else { ui.btnLogs.textContent = "Gửi log"; appendLog(`Chưa gửi được; file log ở: ${r.path}`); api("revealPath", { path: r.path }); }
    } catch { ui.btnLogs.textContent = "Gửi log"; appendLog("Chưa tạo được file log."); }
    setTimeout(() => { ui.btnLogs.textContent = "Gửi log"; ui.btnLogs.disabled = run.active; }, 2500);
  };
  ui.btnOut.onclick = () => api("openPath", { path: run.resultFolder || state.output });
  ui.btnReview.onclick = async () => { if (!run.active) { await showReviewDialog(); updateReviewButton(); } };
  ui.btnSetup.onclick = showSetupDialog;
  ui.btnUpdate.onclick = () => (run.active ? messageBox("Đang xử lý sản phẩm. Chờ chạy xong rồi cập nhật.", "Cập nhật") : showUpdateDialog());

  ui.btnRun.onclick = () => startBatch();
  ui.btnStop.onclick = async () => { if (run.active) { run.stopped = true; await fetch("/api/stop", { method: "POST" }); setStatus("Đang dừng...", "var(--accent)"); } };
  addEventListener("beforeunload", (e) => { if (run.active) { e.preventDefault(); e.returnValue = ""; } });
  addEventListener("resize", () => renderRows());
}

// A newer release shows on the button, green with its version, without updating anything: checked a few
// seconds after the window opens and every 6 hours.
async function checkUpdate() {
  const next = await api("updateCheck").catch(() => null);
  if (next === null) return;
  ui.btnUpdate.textContent = next ? `Cập nhật ${next}` : "Cập nhật";
  ui.btnUpdate.style.width = next ? "150px" : "100px";
  ui.btnUpdate.classList.toggle("primary", !!next);
}

buildMain();
wire();
loadState().catch((e) => appendLog(e.message));
setTimeout(checkUpdate, 3000);
setInterval(checkUpdate, 6 * 3600 * 1000);
