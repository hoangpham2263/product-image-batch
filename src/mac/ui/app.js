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
  close.onclick = () => view.close();
  stack.push(view);
  return view;
}
addEventListener("keydown", (e) => {
  const top = stack.at(-1);
  if (e.key === "Escape" && top) { e.preventDefault(); (top.cancel || top.close)(); }
});
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
const run = { active: false, since: 0, total: 0, done: 0, index: 0, stages: new Map(), jobRows: [], stage: "", stopped: false, failure: false, started: 0, feedback: "", resultFolder: "", anim: 0 };

function buildMain() {
  const c = ui.client;
  // Header (Dock Top, 64).
  const header = at(el("div", "panel"), 0, 0, null, 64, { right: 0 });
  header.append(at(label("Product Review Batch", ""), 20, 20, null, 24));
  header.firstChild.style.fontSize = "17.33px";
  ui.btnUpdate = at(button("Cập nhật"), null, 18, 100, 28, { right: 24, left: false });
  header.append(ui.btnUpdate);

  // Link sản phẩm & ảnh đi kèm (20,78 820x344, Top/Left/Right).
  const cardList = at(el("div", "card"), 20, 78, null, 344, { right: 264 });
  cardList.append(at(label("Link sản phẩm & ảnh đi kèm"), 14, 10, null, 20));
  const editor = at(el("div", "panel"), 14, 36, null, 296, { right: 14 });
  ui.btnAdd = at(button("+ Thêm sản phẩm", true), 0, 0, 160, 34);
  ui.btnBulk = at(button("Thêm nhiều link"), 172, 0, 150, 34);
  ui.flow = at(el("div", "flow"), 0, 44, null, null, { right: 0, bottom: 34 });
  Object.assign(ui.flow.style, { background: "#fff", border: "1px solid #000", padding: "10px 10px 6px 10px" });
  ui.fallback = at(checkbox("Tự tìm trong kho ảnh cho dòng chưa có ảnh"), 0, null, 330, 26, { bottom: 3, top: false });
  ui.fallback.classList.add("muted");
  ui.library = at(combo(["drive", "local"]), 340, null, 170, 24, { bottom: 6, top: false });
  ui.library.setItems(["drive", "local"], ["Kho trên Drive", "Kho trên máy"]);
  editor.append(ui.btnAdd, ui.btnBulk, ui.flow, ui.fallback, ui.library);
  cardList.append(editor);

  // Thao tác (856,78 224x344, Top/Right).
  const cardActions = at(el("div", "card"), null, 78, 224, 344, { right: 24, left: false });
  cardActions.append(at(label("Thao tác"), 14, 10, null, 20));
  const names = [["btnSave", "Lưu danh sách"], ["btnOut", "Mở kết quả"], ["btnReview", "Duyệt & xuất file"], ["btnFeedback", "Kiểm tra ảnh / Làm lại"], ["btnSetup", "Kiểm tra ChatGPT"], ["btnDrive", "Google Drive"]];
  names.forEach(([key, text], i) => { ui[key] = at(button(text), 14, 36 + i * 37, 196, 32); cardActions.append(ui[key]); });

  // Run row (20,434 1060x62).
  const cardRun = at(el("div", "card"), 20, 434, null, 62, { right: 24 });
  ui.btnRun = at(button("Bắt đầu", true), 14, 11, 160, 40);
  ui.btnStop = at(button("Dừng"), 186, 11, 100, 40);
  ui.btnStop.disabled = true;
  ui.lblStatus = at(label("", "muted"), 302, 18, 220, 26);
  ui.lblStatus.style.lineHeight = "26px";
  ui.lblPer = at(label("Ảnh từ kho/SP:", "muted"), null, 19, 110, 24, { right: 228, left: false });
  ui.numPer = at(numeric(1, 1, 1), null, 16, 64, 24, { right: 162, left: false });
  ui.lblThr = at(label("Luồng:", "muted"), null, 19, 56, 24, { right: 88, left: false });
  ui.numThr = at(numeric(1, 4, 1), null, 16, 64, 24, { right: 22, left: false });
  for (const l of [ui.lblPer, ui.lblThr]) l.style.lineHeight = "24px";
  cardRun.append(ui.btnRun, ui.btnStop, ui.lblStatus, ui.lblPer, ui.numPer, ui.lblThr, ui.numThr);

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
function rowStatus(row) {
  const scenes = row.info?.scenes || [];
  if (scenes.length && scenes[0].ok) return { text: scenes.length > 1 ? `● ${scenes.length} ảnh` : "● Đã có ảnh", color: "var(--ok)", image: scenes[0].file };
  if (scenes.length) return { text: "Không đọc được ảnh, hãy gắn lại.", color: "var(--error)", image: "" };
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
    remove.onclick = (e) => { e.stopPropagation(); if (run.active) return; state.rows.splice(state.rows.indexOf(row), 1); renderRows(); updateStatus(); };
    // Drop images straight onto the row thumbnail.
    pic.addEventListener("dragover", (e) => e.preventDefault());
    pic.addEventListener("drop", async (e) => {
      e.preventDefault(); e.stopPropagation();
      try {
        const files = imageFiles(e.dataTransfer.files);
        if (!files.length) return;
        const root = await api("draftOpen");
        await api("draftAttach", { root, url: row.url.trim(), paths: await Promise.all(files.map(upload)) });
        row.info = await api("draftSave", { root, url: row.url.trim(), others: [], group: state.group });
        renderRows();
      } catch (err) { row.stage = { text: err.message, color: "var(--error)" }; renderRows(); row.stage = null; }
    });
    return card;
  }));
}

async function loadState() {
  Object.assign(state, await api("state"));
  state.rows = list(state.rows).map((info) => ({ url: info.url, info: { ...info, scenes: list(info.scenes) } }));
  document.title = ("Product Review Batch " + (state.version || "")).trim();
  ui.fallback.input.checked = state.fallback;
  ui.library.value = state.library === "local" ? "local" : "drive";
  ui.library.disabled = !state.fallback;
  for (const e of [ui.lblPer, ui.numPer]) e.hidden = !state.fallback;
  ui.btnDrive.textContent = state.drive ? "Google Drive ✓" : "Google Drive";
  if (!state.codex && !setupAction) setSetupButton("install");
  renderRows();
  updateStatus();
}

async function saveQueue(requireReady = false) {
  return api("queueSave", { urls: state.rows.map((r) => r.url), fallback: ui.fallback.input.checked, library: ui.library.value, group: state.group, requireReady });
}

async function updateReviewButton() {
  const pending = run.resultFolder ? await api("pending", { batch: run.resultFolder }).catch(() => 0) : 0;
  ui.btnReview.textContent = pending > 0 ? `Duyệt & xuất file (${pending})` : "Duyệt & xuất file";
  ui.btnReview.classList.toggle("primary", pending > 0);
}

// ----- product dialog (New-ProductQueueDialog) -----
async function showProductDialog(target = null) {
  let root;
  try { root = await api("draftOpen"); } catch (e) { return appendLog(e.message); }
  const view = openWindow("Ảnh review & ảnh sản phẩm gốc", 1040, 570, { white: true });
  const b = view.body;
  let saved = false;
  view.onClose = () => { if (!saved) api("draftDiscard", { root }).catch(() => {}); };
  const urlBox = at(el("input", "text", { value: target ? target.url : "" }), 20, 42, 1000, 25);
  const status = at(label(""), 20, 482, 680, 30);
  status.style.lineHeight = "30px";
  const preview = at(picture("border"), 20, 112, 680, 230);
  preview.style.background = "rgb(241, 244, 240)";
  preview.tabIndex = 0;
  const thumbs = at(el("div", "flow"), 20, 348, 680, 80);
  Object.assign(thumbs.style, { display: "flex", overflowX: "auto", overflowY: "hidden", background: "#fff" });
  const paste = at(button("Dán ảnh review · Ctrl+V"), 20, 436, 180, 32);
  const choose = at(button("Chọn ảnh review…"), 212, 436, 156, 32);
  const productPreview = at(picture("border"), 720, 112, 300, 310);
  productPreview.tabIndex = 0;
  const chooseProduct = at(button("Chọn ảnh sản phẩm"), 720, 436, 146, 32);
  const pasteProduct = at(button("Dán ảnh sản phẩm"), 874, 436, 146, 32);
  const groups = at(combo(), 132, 78, 216, 24);
  const openFolder = at(button("Mở thư mục"), 360, 78, 140, 28);
  const save = at(button("Lưu sản phẩm"), 760, 526, 144, 32);
  const cancel = at(button("Hủy"), 916, 526, 104, 32);
  b.append(
    at(label("Link sản phẩm (có thể chưa public; gắn ảnh sản phẩm để dùng trực tiếp)"), 20, 16, null, 22),
    urlBox, at(label("Kho ảnh:"), 20, 82, 110, 26), groups, openFolder,
    at(label("Ảnh review"), 560, 82, 140, 26), at(label("Ảnh sản phẩm gốc (quyết định thiết kế)"), 720, 82, 300, 26),
    preview, thumbs, paste, choose, productPreview, chooseProduct, pasteProduct, status, save, cancel,
  );
  view.cancel = view.close;
  cancel.onclick = view.close;
  const fail = (e) => { status.textContent = e.message; status.style.color = "var(--error)"; };

  // Kho ảnh: groups on Drive (or on this Mac when "Kho trên máy" is chosen).
  api("groups", { local: ui.library.value === "local" }).then((g) => {
    g = list(g);
    groups.setItems(g);
    groups.value = g.includes(state.group) ? state.group : g[0] || "";
  }).catch(() => {});
  openFolder.onclick = async () => { try { await api("openPath", { path: await api("sourceDir", { group: groups.value }) }); } catch (e) { fail(e); } };

  let info = { scenes: [], product: "" }, index = 0;
  const refresh = async () => {
    const url = urlBox.value.trim();
    try { info = await api("draftInfo", { root, url }); info.scenes = list(info.scenes); } catch { info = { scenes: [], product: "" }; }
    index = Math.max(0, Math.min(index, info.scenes.length - 1));
    const scene = info.scenes[index];
    preview.set(scene && scene.ok ? scene.file : "", "Dán / kéo ảnh");
    productPreview.set(info.product || "");
    thumbs.replaceChildren(...info.scenes.map((s, i) => {
      const t = picture();
      Object.assign(t.style, { position: "relative", width: "72px", height: "72px", flex: "none", marginRight: "6px", cursor: "pointer", padding: i === index ? "3px" : "1px", background: i === index ? "var(--accent)" : "var(--line)" });
      t.querySelector("img").style.background = "#fff";
      t.set(s.file);
      t.onclick = () => { index = i; refresh(); };
      t.onRemove(async () => { await api("draftRemoveScene", { root, url, index: i }).catch(fail); refresh(); });
      return t;
    }));
    if (info.scenes.length && scene?.ok) { status.textContent = info.scenes.length > 1 ? `● ${info.scenes.length} ảnh` : "● Đã có ảnh"; status.style.color = "var(--ok)"; }
    else if (info.scenes.length) { status.textContent = "Không đọc được ảnh, hãy gắn lại."; status.style.color = "var(--error)"; }
    else { status.textContent = url ? "● Chưa có ảnh" : "Chưa có link"; status.style.color = url ? "var(--warn)" : "var(--muted)"; }
  };
  preview.onRemove(async () => { await api("draftRemoveScene", { root, url: urlBox.value.trim(), index }).catch(fail); refresh(); });
  productPreview.onRemove(async () => { await api("draftRemoveProduct", { root, url: urlBox.value.trim() }).catch(fail); refresh(); });

  const attach = async (files, role = "Scene") => {
    try {
      files = role === "Product" ? files.slice(0, 1) : files;
      const paths = await Promise.all(files.map(upload));
      const url = await api("draftAttach", { root, url: urlBox.value.trim(), paths, role });
      if (url !== urlBox.value.trim()) urlBox.value = url;
      if (role === "Scene") index = Number.MAX_SAFE_INTEGER;
      await refresh();
    } catch (e) { fail(e); }
  };
  // Clipboard: an image attaches, one line of text becomes the link (Paste-ProductQueueRow).
  const pasteFrom = async (items, role) => {
    const files = imageFiles(items.files || []);
    if (files.length) return attach(files, role);
    if (role === "Product") return;
    const text = (items.text || "").trim();
    if (!text) return fail(new Error("Clipboard chưa có link hoặc ảnh."));
    if (text.split(/\r?\n/).length > 1) return fail(new Error("Popup này chỉ nhận một link. Dùng Thêm nhiều link để nhập hàng loạt."));
    urlBox.value = text; refresh();
  };
  const readClipboard = async () => {
    const files = [];
    let text = "";
    try {
      for (const item of await navigator.clipboard.read()) {
        const type = item.types.find((t) => /^image\/(png|jpeg)$/.test(t));
        if (type) files.push(new File([await item.getType(type)], type === "image/png" ? "clipboard.png" : "clipboard.jpg", { type }));
        else if (item.types.includes("text/plain")) text = await (await item.getType("text/plain")).text();
      }
    } catch { text = await navigator.clipboard.readText().catch(() => ""); }
    return { files, text };
  };
  paste.onclick = async () => pasteFrom(await readClipboard(), "Scene");
  pasteProduct.onclick = async () => pasteFrom(await readClipboard(), "Product");
  view.body.addEventListener("paste", (e) => {
    const product = document.activeElement === productPreview;
    const files = [...(e.clipboardData?.files || [])];
    if (document.activeElement === urlBox && !files.length) return;
    e.preventDefault();
    pasteFrom({ files, text: e.clipboardData.getData("text/plain") }, product ? "Product" : "Scene");
  });
  choose.onclick = async () => attach(imageFiles(await pickFiles("image/png,image/jpeg", true)));
  chooseProduct.onclick = async () => attach(imageFiles(await pickFiles("image/png,image/jpeg", false)), "Product");
  for (const zone of [view.body, preview, thumbs, productPreview]) {
    zone.addEventListener("dragover", (e) => e.preventDefault());
    zone.addEventListener("drop", (e) => {
      e.preventDefault(); e.stopPropagation();
      attach(imageFiles(e.dataTransfer.files), zone === productPreview ? "Product" : "Scene");
    });
  }
  preview.onclick = () => urlBox.focus();
  urlBox.oninput = () => { index = 0; refresh(); };
  save.onclick = async () => {
    try {
      const url = urlBox.value.trim();
      const others = state.rows.filter((r) => r !== target).map((r) => r.url.trim());
      const saved_ = await api("draftSave", { root, url, others, group: groups.value || state.group });
      saved = true;
      state.group = groups.value || state.group;
      const entry = { ...saved_, scenes: list(saved_.scenes) };
      if (target) Object.assign(target, { url, info: entry });
      else state.rows.push({ url, info: entry });
      view.close();
      renderRows();
      updateStatus();
      ui.flow.scrollTop = ui.flow.scrollHeight * (target ? 0 : 1);
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
      added.forEach((r, i) => { r.info = infos[i] ? { ...infos[i], scenes: list(infos[i].scenes) } : null; });
      view.close();
      renderRows();
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
  exportBtn.onclick = async () => {
    try { const path = await api("reviewExport", { batch }); await messageBox(`Đã xuất: ${path}`, "Xong"); api("revealPath", { path }); }
    catch (e) { messageBox(e.message, "Chưa xuất được"); }
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
  const original = at(label("Ảnh sản phẩm gốc · chỉ để đối chiếu"), 12, 12, 500, 24);
  const product = at(picture(), 12, 42, 522, 530);
  const result = at(picture(), 546, 42, 522, 530);
  for (const p of [product, result]) p.style.background = "var(--smoke)";
  product.set(item.product);
  result.set(item.image);
  if (!item.product) original.textContent = "Ảnh sản phẩm gốc · không có ảnh đối chiếu";
  const body = at(el("textarea", "text", { readOnly: true, value: item.body }), 12, 584, 1056, 70);
  const state_ = at(label(""), 12, 674, 540, 28);
  const keep = at(button("Giữ đánh giá"), 648, 670, 130, 36), skip = at(button("Bỏ đánh giá"), 790, 670, 130, 36), close = at(button("Đóng"), 932, 670, 136, 36);
  const refresh = () => { state_.textContent = { ok: "Đang giữ đánh giá này", bad: "Đang bỏ đánh giá này khỏi CSV" }[item.decision] || "Chưa chọn giữ hoặc bỏ"; };
  keep.onclick = async () => { await decide("ok"); refresh(); };
  skip.onclick = async () => { await decide("bad"); refresh(); };
  close.onclick = view.close;
  b.append(original, at(label("Ảnh của đánh giá đang chọn"), 548, 12, 500, 24), product, result, body, state_, keep, skip, close);
  refresh();
}

// ----- Kiểm tra ảnh, phản bác và bài học (New-ImageFeedbackDialog) -----
async function showFeedbackDialog() {
  const view = openWindow("Kiểm tra ảnh, phản bác và bài học", 904, 701);
  const result = { feedback: "", approved: "" };
  const tabs = at(el("div", "tabs"), 12, 12, 880, 676);
  const strip = el("div", "tabstrip");
  const tabEdit = el("button", "on", { text: "Kiểm tra & làm lại", type: "button" });
  const tabHistory = el("button", "", { text: "Bài học & lịch sử", type: "button" });
  strip.append(tabEdit, tabHistory);
  const edit = el("div", "tabpage"), history = el("div", "tabpage");
  history.hidden = true;
  tabs.append(strip, edit, history);
  view.body.append(tabs);

  const choices = at(combo(), 12, 12, 708, 24);
  const browse = at(button("Chọn ảnh…"), 730, 10, 124, 30);
  const resultLabel = at(label("Ảnh cần kiểm tra"), 448, 52, 406, 24);
  const productPreview = at(picture(), 12, 78, 410, 240), resultPreview = at(picture(), 448, 78, 406, 240);
  for (const p of [productPreview, resultPreview]) p.style.background = "var(--smoke)";
  const text = at(el("textarea", "text", { maxLength: 4000 }), 12, 358, 842, 106);
  const remember = at(checkbox("Lưu bài học vào AGENTS.md"), 12, 478, 400, 28);
  remember.input.checked = true;
  const scope = at(combo(), 448, 478, 406, 24);
  scope.setItems(["product", "category"], ["Chỉ sản phẩm này", "Cả danh mục sản phẩm"]);
  const save = at(button("Lưu phản hồi"), 12, 522, 160, 36), retry = at(button("Lưu và làm lại"), 184, 522, 180, 36), deliver = at(button("Duyệt ảnh này & bàn giao"), 376, 522, 250, 36);
  const note = at(label("Làm lại dùng đúng ảnh sản phẩm và phòng đã lưu, tạo kết quả mới. Bản cũ được giữ lại."), 12, 570, 842, 48);
  note.style.color = "var(--dim)";
  edit.append(choices, browse, at(label("Sản phẩm gốc"), 12, 52, null, 22), resultLabel, productPreview, resultPreview,
    at(label("Nêu rõ chỗ sai và kết quả cần sửa (ví dụ: thay cả ghế nệm bằng đúng ghế gỗ của sản phẩm)."), 12, 328, 842, 26), text, remember, scope, save, retry, deliver, note);

  let target = null;
  const loadTarget = async () => {
    target = null;
    if (!choices.value) return;
    try {
      target = await api("feedbackTarget", { image: choices.value });
      productPreview.set(target.product); resultPreview.set(target.image); resultLabel.textContent = target.title;
    } catch (e) { resultLabel.textContent = e.message; productPreview.set(""); resultPreview.set(""); }
  };
  choices.onchange = loadTarget;
  browse.onclick = async () => {
    const r = await (await fetch("/api/choose-file", { method: "POST", body: JSON.stringify({ folder: state.output, prompt: "Chọn ảnh trong thư mục images của app" }) })).json();
    if (!r.path) return;
    choices.append(new Option(r.path, r.path));
    choices.value = r.path;
    loadTarget();
  };
  const done = (kind) => { view.close(); return kind; };
  deliver.onclick = () => {
    if (!target) return messageBox("Hãy chọn ảnh cần duyệt có bản lưu đầu vào hợp lệ.");
    result.approved = target.image; done();
  };
  save.onclick = async () => {
    try {
      if (!target) throw new Error("Hãy chọn ảnh có bản lưu đầu vào hợp lệ.");
      await api("feedbackSave", { image: target.image, text: text.value, scope: scope.value, remember: remember.input.checked });
      text.value = "";
      messageBox("Đã lưu phản hồi và lựa chọn bài học. Xem tab Bài học & lịch sử.", "Đã lưu");
    } catch (e) { messageBox(e.message, "Chưa lưu được"); }
  };
  retry.onclick = async () => {
    try {
      if (!target) throw new Error("Hãy chọn ảnh có bản lưu đầu vào hợp lệ.");
      result.feedback = await api("feedbackSave", { image: target.image, text: text.value, scope: scope.value, remember: remember.input.checked });
      done();
    } catch (e) { messageBox(e.message, "Chưa làm lại được"); }
  };

  // Bài học & lịch sử.
  const listBox = at(el("div", "list"), 12, 12, 842, 170);
  const details = at(el("textarea", "text", { readOnly: true }), 12, 194, 842, 300);
  const accept = at(button("Ảnh mới đã đúng"), 12, 516, 180, 36), toggle = at(button("Bật/tắt bài học"), 204, 516, 180, 36), open = at(button("Mở kết quả mới"), 396, 516, 180, 36), resume = at(button("Chạy lại phản hồi này"), 588, 516, 266, 36);
  history.append(listBox, details, accept, toggle, open, resume);
  let selected = "";
  const refreshHistory = async () => {
    selected = ""; details.value = "";
    const rows = list(await api("feedbackHistory").catch(() => []));
    listBox.replaceChildren(...rows.map((r) => {
      const item = el("div", "", { text: r.label });
      item.onclick = async () => {
        for (const x of listBox.children) x.classList.toggle("on", x === item);
        selected = r.path;
        details.value = await api("feedbackDetails", { path: r.path }).catch((e) => e.message);
      };
      return item;
    }));
  };
  const showTab = (h) => { tabEdit.classList.toggle("on", !h); tabHistory.classList.toggle("on", h); edit.hidden = h; history.hidden = !h; if (h) refreshHistory(); };
  tabEdit.onclick = () => showTab(false);
  tabHistory.onclick = () => showTab(true);
  accept.onclick = async () => { if (!selected) return; try { await api("feedbackAccept", { path: selected }); refreshHistory(); } catch (e) { messageBox(e.message); } };
  toggle.onclick = async () => { if (!selected) return; try { await api("feedbackToggle", { path: selected }); refreshHistory(); } catch (e) { messageBox(e.message); } };
  open.onclick = async () => { if (!selected) return; const r = await api("feedbackRecord", { path: selected }); if (r.result_folder) api("openPath", { path: r.result_folder }); };
  resume.onclick = async () => {
    if (!selected) return;
    const r = await api("feedbackRecord", { path: selected });
    if (!["saved", "failed", "stopped"].includes(r.status)) return messageBox("Phản hồi này đang chạy hoặc đã có kết quả. Hãy chọn ảnh mới ở tab Kiểm tra & làm lại để phản bác tiếp.");
    result.feedback = selected; done();
  };

  const photos = list(await api("feedbackChoices").catch(() => []));
  choices.setItems(photos.map((p) => p.image), photos.map((p) => p.label));
  if (photos.length) await loadTarget();
  return new Promise((resolve) => { view.onClose = () => resolve(result); });
}

// ----- Google Drive (Show-DriveLogin) -----
function showDriveDialog() {
  const view = openWindow("Google Drive", 400, 170);
  const info = at(label(""), 20, 18, 360, 40);
  info.style.whiteSpace = "normal";
  const pass = at(el("input", "text", { type: "password" }), 20, 62, 360, 25);
  const err = at(label(""), 20, 94, 360, 22);
  err.style.color = "var(--warn)";
  const ok = at(button("", true), 260, 120, 120, 36);
  view.body.append(info, pass, err, ok);
  if (state.drive) {
    info.textContent = "Đã đăng nhập. Ảnh tạo xong sẽ tự tải lên Drive.";
    pass.hidden = true; ok.textContent = "Đăng xuất";
    ok.onclick = async () => { await api("driveLogout"); view.close(); };
  } else {
    info.textContent = "Nhập mật khẩu quản lý một lần trên máy này để tải ảnh lên Drive.";
    ok.textContent = "Đăng nhập";
    const login = async () => { try { await api("driveLogin", { password: pass.value }); view.close(); } catch (e) { err.textContent = e.message; } };
    ok.onclick = login;
    pass.onkeydown = (e) => { if (e.key === "Enter") login(); };
    pass.focus();
  }
  return new Promise((resolve) => { view.onClose = async () => { Object.assign(state, { drive: (await api("state")).drive }); ui.btnDrive.textContent = state.drive ? "Google Drive ✓" : "Google Drive"; resolve(); }; });
}

// ----- run (Start-GuiBatch, timer ticks) -----
function setRunning(on) {
  run.active = on;
  ui.btnRun.disabled = on; ui.btnStop.disabled = !on;
  for (const b of [ui.btnSave, ui.btnSetup, ui.btnFeedback, ui.btnDrive, ui.btnReview, ui.btnAdd, ui.btnBulk]) b.disabled = on;
  ui.fallback.input.disabled = on;
  ui.library.disabled = on || !ui.fallback.input.checked;
  ui.numPer.enabled = !on; ui.numThr.enabled = !on;
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
async function startBatch({ feedback = "", approved = "" } = {}) {
  if (run.active) return;
  if (!state.drive) return appendLog("Đăng nhập Google Drive trước khi chạy để CSV có link ảnh công khai.");
  if (!feedback && !approved) { try { await saveQueue(true); } catch (e) { return appendLog(e.message); } }
  if (!feedback && !approved && !countUrls()) return messageBox("Vui lòng thêm ít nhất một link sản phẩm.");
  if (!approved && !state.codex) return messageBox('Chưa có công cụ xử lý. Bấm "Kiểm tra ChatGPT" để xem hướng dẫn.');
  ui.txtLog.value = "";
  Object.assign(run, { since: 0, total: feedback || approved ? 1 : countUrls(), done: 0, index: 0, stages: new Map(), jobRows: [], stage: "Đang chuẩn bị", stopped: false, failure: false, started: Date.now(), feedback, resultFolder: "" });
  for (const r of state.rows) r.stage = null;
  await updateReviewButton();
  const r = await fetch("/api/run", { method: "POST", body: JSON.stringify({ per: ui.numPer.value, threads: ui.numThr.value, feedback, approved }) });
  if (!r.ok) {
    const body = await r.json().catch(() => ({}));
    if (feedback) api("feedbackStatus", { path: feedback, status: "failed", folder: "", error: body.error || "" }).catch(() => {});
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
  await loadState();
  const elapsed = Math.floor((Date.now() - run.started) / 1000);
  ui.lblProgress.textContent = `Đã xong ${run.done}/${run.total} ảnh • ${Math.floor(elapsed / 60)} phút ${elapsed % 60} giây`;
  if (r.stopped) { setStatus("Đã dừng", "var(--muted)"); appendLog("Đã dừng. Các link chưa hoàn tất được giữ lại."); }
  else if (r.exitCode === 0 && !run.failure) {
    setStatus("✔ Hoàn tất", "var(--ok)");
    appendLog(run.feedback ? "Đã có ảnh làm lại. Bấm Kiểm tra ảnh / Làm lại để đối chiếu; chỉ đánh dấu đã đúng sau khi bạn xem ảnh." : "Xong. Bấm Duyệt & xuất file để duyệt từng ảnh; file Loox chỉ tạo khi duyệt xong.");
  } else {
    setStatus("! Cần thử lại", "var(--warn)");
    appendLog("Một số sản phẩm chưa hoàn tất. Bạn có thể bấm Bắt đầu để thử lại các link còn lại, hoặc Duyệt & xuất file với các ảnh đã xong.");
  }
  updateReviewButton();
}
// Running animation only in the status label.
setInterval(() => { if (run.active && !run.stopped) { run.anim = (run.anim + 1) % 3; setStatus("Đang chạy " + [".", "..", "..."][run.anim], "var(--accent)"); } }, 350);

// ---------- wiring ----------
let setupAction = "";
function setSetupButton(action) {
  setupAction = action;
  ui.btnSetup.textContent = { install: "Cài Codex", login: "Đăng nhập Codex" }[action] || "Kiểm tra ChatGPT";
  ui.btnSetup.classList.toggle("primary", !!action);
}
function wire() {
  ui.btnAdd.onclick = () => showProductDialog();
  ui.btnBulk.onclick = showBulkDialog;
  ui.fallback.input.onchange = () => {
    const on = ui.fallback.input.checked;
    ui.library.disabled = !on;
    for (const e of [ui.lblPer, ui.numPer]) e.hidden = !on;
  };
  ui.btnDrive.onclick = showDriveDialog;
  ui.btnSave.onclick = async () => { try { await saveQueue(); updateStatus(); appendLog("Đã lưu danh sách link và ảnh đi kèm."); } catch (e) { appendLog(e.message); } };
  ui.btnOut.onclick = () => api("openPath", { path: run.resultFolder || state.output });
  ui.btnReview.onclick = async () => { if (!run.active) { await showReviewDialog(); updateReviewButton(); } };
  ui.btnFeedback.onclick = async () => {
    if (run.active) return;
    const pick = await showFeedbackDialog();
    if (pick.approved) startBatch({ approved: pick.approved });
    else if (pick.feedback) startBatch({ feedback: pick.feedback });
  };
  // Kiểm tra ChatGPT turns into Cài Codex / Đăng nhập Codex when the check finds that step missing.
  ui.btnSetup.onclick = async () => {
    if (setupAction) {
      const step = setupAction;
      ui.btnSetup.disabled = true;
      appendLog(step === "install" ? "Đang cài Codex..." : "Đăng nhập ChatGPT trong trình duyệt vừa mở; xong app tự kiểm tra lại.");
      const r = await (await fetch("/api/setup-step", { method: "POST", body: JSON.stringify({ step }) })).json().catch(() => ({ error: "setup" }));
      if (r.error) appendLog(r.error);
      ui.btnSetup.disabled = false;
      setSetupButton("");
      Object.assign(state, { codex: (await api("state")).codex });
      return ui.btnSetup.onclick();
    }
    ui.btnSetup.disabled = true;
    document.body.style.cursor = "wait";
    ui.txtLog.value = "";
    appendLog("Đang kiểm tra ChatGPT...");
    try {
      const report = await (await fetch("/api/setup", { method: "POST" })).json();
      for (const check of list(report.Checks)) { appendLog(check.Message); if (!check.Ok && check.Action) appendLog(check.Action); }
      appendLog(report.Summary);
      setSetupButton(report.NextAction || "");
    } catch { appendLog("Chưa kiểm tra được ChatGPT. Vui lòng thử lại hoặc xem setup.txt."); }
    finally { ui.btnSetup.disabled = false; document.body.style.cursor = ""; }
  };
  ui.btnUpdate.onclick = async () => {
    if (run.active) return messageBox("Đang xử lý sản phẩm. Chờ chạy xong rồi cập nhật.", "Cập nhật");
    let next;
    document.body.style.cursor = "wait";
    try { next = await api("updateCheck"); }
    catch (e) { document.body.style.cursor = ""; return messageBox(`Không kiểm tra được bản mới: ${e.message}`, "Cập nhật"); }
    document.body.style.cursor = "";
    if (!next) return messageBox("Đang dùng bản mới nhất.", "Cập nhật");
    const name = next === "git" ? "mới" : next;
    if ((await messageBox(`Có bản ${name}. Cập nhật và mở lại app?`, "Cập nhật", ["Yes", "No"])) !== "Yes") return;
    document.body.style.cursor = "wait";
    const r = await fetch("/api/update", { method: "POST" }).catch(() => null);
    if (!r || !r.ok) { document.body.style.cursor = ""; return messageBox("Chưa cập nhật được. Thử lại sau.", "Cập nhật"); }
    // The server restarts on the new files; reload once it answers again.
    const wait = () => fetch("/api/rpc", { method: "POST", body: JSON.stringify({ cmd: "state", args: {} }) }).then((x) => (x.ok ? location.reload() : setTimeout(wait, 500))).catch(() => setTimeout(wait, 500));
    setTimeout(wait, 800);
  };
  ui.btnRun.onclick = () => startBatch();
  ui.btnStop.onclick = async () => { if (run.active) { run.stopped = true; await fetch("/api/stop", { method: "POST" }); setStatus("Đang dừng...", "var(--accent)"); } };
  addEventListener("beforeunload", (e) => { if (run.active) { e.preventDefault(); e.returnValue = ""; } });
  addEventListener("resize", () => renderRows());
}

buildMain();
wire();
loadState().catch((e) => appendLog(e.message));
