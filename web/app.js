// Product Image Batch web app (macOS and Windows). Talks to bridge/app.mjs on 127.0.0.1.
const $ = (id) => document.getElementById(id);
const state = { urls: [], running: false, total: 0, done: 0, current: 0, stages: {}, editing: null, pendingImage: null };
const OPTIONS_KEY = "pib-options";

const CAUSES = {
  PRODUCT_TIMEOUT: "trang hoặc ảnh phản hồi quá chậm sau 3 lần thử. Link được giữ lại để chạy lại.",
  PRODUCT_NETWORK: "chưa kết nối được trang hoặc ảnh sau 3 lần thử. Kiểm tra mạng rồi chạy lại.",
  PRODUCT_ACCESS: "trang hoặc ảnh yêu cầu đăng nhập hoặc đang chặn truy cập. Vui lòng dùng link công khai.",
  PRODUCT_NOT_FOUND: "không tìm thấy trang hoặc ảnh sản phẩm. Vui lòng kiểm tra link.",
  MISSING_DATA: "thiếu ảnh mẫu cho loại sản phẩm này. Đã ghi vào missing-data trong kết quả.",
  PRODUCT_DOWNLOAD: "chưa tải được trang hoặc ảnh. Link được giữ lại để thử lại.",
  BRIDGE: "chưa kết nối được tab ChatGPT/Flow. Mở Chrome có extension product-image-bridge, đăng nhập rồi chạy lại.",
  STORE_LOCKED: "cửa hàng đang bật mật khẩu. Mở khoá cửa hàng rồi chạy lại.",
  AUTH: "chưa đăng nhập ChatGPT/Codex. Bấm Kiểm tra ChatGPT.",
  QUOTA: "đã hết hạn mức. Thử lại sau giờ đặt lại.",
  NETWORK: "mất kết nối Internet hoặc AI. Kiểm tra mạng rồi chạy lại.",
  AI_TIMEOUT: "AI phản hồi quá lâu. Link được giữ lại để chạy lại.",
  BUSY: "dịch vụ đang bận, thử lại sau.",
};

// Translate workflow log lines into short messages; raw diagnostics stay in the batch logs.
function toEvent(line) {
  const index = Number(line.match(/\(#(\d+)\)\s*$/)?.[1] || state.current);
  let m;
  if ((m = line.match(/^Starting: (\d+) URLs/))) return { kind: "start", total: +m[1], text: `Bắt đầu xử lý ${m[1]} sản phẩm.` };
  if ((m = line.match(/^\[(\d+)\/(\d+)\] /))) return { kind: "item", index: +m[1], stage: "Đang chuẩn bị" };
  if ((m = line.match(/^Missing data: (\d+)/))) return { kind: "info", cls: "warn", text: `Có ${m[1]} sản phẩm thiếu ảnh mẫu. Gửi missing-data.csv và thư mục missing-data trong kết quả để bổ sung.` };
  if (/^\s*\[CLASSIFY\]/.test(line)) return { kind: "stage", index, stage: "Đang nhận diện sản phẩm" };
  if (/^\s*\[SELECT\] Subject/.test(line)) return { kind: "stage", index, stage: "Đang chọn người mẫu" };
  if (/^\s*\[SELECT\] Scene/.test(line)) return { kind: "stage", index, stage: "Đang chọn bối cảnh" };
  if (/^\s*\[IMAGE-BACKEND\] flow/.test(line)) return { kind: "stage", index, stage: "Chờ bấm Bắt đầu tạo trong tab Flow", text: `Sản phẩm ${index}: mở tab Google Flow và bấm nút Bắt đầu tạo đang viền vàng.` };
  if (/^\s*\[IMAGE\]/.test(line)) return { kind: "stage", index, stage: "Đang tạo ảnh", text: `Sản phẩm ${index}: đang tạo ảnh.` };
  if ((m = line.match(/^\s*\[AI-WAIT\] (\d+)\/(\d+)s/))) return { kind: "stage", index, stage: `Đang chờ AI ${m[1]}/${m[2]} giây` };
  if (/^\s*\[REVIEW\]/.test(line)) return { kind: "stage", index, stage: "Đang viết đánh giá" };
  if (/^\s*\[DRIVE\]/.test(line)) return { kind: "stage", index, stage: "Đã lưu lên Google Drive" };
  if (/^\s*\[(RETRY|IMAGE-RETRY|DOWNLOAD-RETRY|AI-CONNECTION)\]/.test(line)) return { kind: "stage", index, stage: "Đang tự thử lại" };
  if (/^\s*\[METADATA\]/.test(line)) return { kind: "stage", index, stage: "Đang lưu kết quả" };
  if (/^\s*\[OK\]/.test(line)) { const i = Number(line.match(/\[ITEM (\d+)\]/)?.[1] || index); return { kind: "done", index: i, cls: "ok", text: `Sản phẩm ${i} đã hoàn tất.` }; }
  if ((m = line.match(/^WARNING:\s*(?:\[ITEM (\d+)\]\s*)?Failed;/))) {
    const i = Number(m[1] || index);
    const cause = line.match(/\[CAUSE:([A-Z_]+)\]/)?.[1];
    return { kind: "failed", index: i, cls: "warn", text: `Sản phẩm ${i}: ${CAUSES[cause] || "chưa hoàn tất. Link được giữ lại để thử lại."}` };
  }
  if (/^ERROR:|^Batch incomplete|is not recognized|not found/i.test(line)) return { kind: "info", cls: "warn", text: line.replace(/^ERROR:\s*/, "").slice(0, 300) };
  return null;
}

function toast(text) {
  const el = $("toast");
  el.textContent = text;
  el.classList.add("show");
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.classList.remove("show"), 2400);
}

async function api(path, init = {}) {
  const res = await fetch(path, init);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `Lỗi ${res.status}`);
  return body;
}

function message(text, cls = "") {
  const li = document.createElement("li");
  li.textContent = text;
  if (cls) li.className = cls;
  $("messages").prepend(li);
}

const options = () => ({ backend: $("backend").value, photosPerImage: +$("perImage").value, threads: +$("threads").value });
function saveOptions() { try { localStorage.setItem(OPTIONS_KEY, JSON.stringify(options())); } catch {} }
function loadOptions() {
  try {
    const o = JSON.parse(localStorage.getItem(OPTIONS_KEY) || "{}");
    if (o.backend) $("backend").value = o.backend;
    if (o.photosPerImage) $("perImage").value = o.photosPerImage;
    if (o.threads) $("threads").value = o.threads;
  } catch {}
}

function apply(s) {
  state.urls = s.urls;
  state.fallback = s.fallback;
  $("fallback").checked = s.fallback;
  if (!$("sourceGroup").options.length) $("sourceGroup").replaceChildren(...s.groups.map((g) => new Option(g, g)));
  $("sourceGroup").value = s.sourceGroup;
  setRunning(s.running);
  renderQueue();
}

function renderQueue() {
  const missing = state.urls.filter((u) => !u.reference).length;
  $("queueTitle").textContent = `Sản phẩm (${state.urls.length})`;
  $("queueStatus").textContent = missing && !state.fallback ? `${missing} link chưa gắn ảnh` : "";
  $("queueEmpty").hidden = state.urls.length > 0;
  $("queue").replaceChildren(...state.urls.map((item, i) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "row";
    const thumb = item.reference ? Object.assign(document.createElement("img"), { src: `/api/reference?url=${encodeURIComponent(item.url)}&v=${item.reference.sha256.slice(0, 8)}`, alt: "" })
      : Object.assign(document.createElement("span"), { className: "noimg", textContent: "+" });
    const url = Object.assign(document.createElement("span"), { className: "row-url", textContent: item.url });
    const stage = state.stages[i + 1];
    const tag = document.createElement("span");
    tag.className = "tag " + (stage ? (stage === "Đã xong" ? "ok" : stage === "Chưa hoàn tất" ? "warn" : "run") : item.reference ? "ok" : state.fallback ? "" : "warn");
    tag.textContent = stage || (item.reference ? "Có ảnh" : state.fallback ? "Dùng kho" : "Chưa có ảnh");
    row.append(thumb, url, tag);
    row.onclick = () => openItem(item.url);
    row.disabled = state.running;
    return row;
  }));
}

function setRunning(running) {
  state.running = running;
  $("startBtn").disabled = running;
  $("stopBtn").disabled = !running;
  $("addBtn").disabled = running;
  document.querySelector(".progress").classList.toggle("busy", running && !state.total);
  if (!running) $("runStatus").textContent = state.done || state.total ? `Đã xong ${state.done}/${state.total} sản phẩm` : "Sẵn sàng";
}

function updateProgress() {
  const bar = $("bar");
  document.querySelector(".progress").classList.toggle("busy", state.running && !state.total);
  bar.style.width = state.total ? `${Math.round((state.done / state.total) * 100)}%` : "0";
  const stage = state.stages[state.current];
  if (state.running) $("runStatus").textContent = `${state.done}/${state.total} sản phẩm${stage ? " · " + stage : ""}`;
  renderQueue();
}

function onLine(line) {
  const event = toEvent(line);
  if (!event) return;
  if (event.kind === "start") { state.total = event.total; state.done = 0; state.stages = {}; }
  if (event.index) state.current = event.index;
  if (event.kind === "item" || event.kind === "stage") state.stages[event.index] = event.stage;
  if (event.kind === "done") { state.stages[event.index] = "Đã xong"; state.done++; }
  if (event.kind === "failed") state.stages[event.index] = "Chưa hoàn tất";
  if (event.text) message(event.text, event.cls);
  updateProgress();
}

function listen() {
  const source = new EventSource("/api/events");
  source.onmessage = async (e) => {
    const data = JSON.parse(e.data);
    if (data.type === "snapshot") { data.lines.forEach(onLine); setRunning(data.running); }
    if (data.type === "line") onLine(data.text);
    if (data.type === "status") {
      setRunning(data.running);
      if (!data.running) {
        message(data.exitCode === 0 ? "Hoàn tất. Ảnh và CSV ở mục Kết quả gần nhất." : "Một số sản phẩm chưa hoàn tất. Bấm Bắt đầu để chạy lại các link còn lại.", data.exitCode === 0 ? "ok" : "warn");
        apply(await api("/api/state"));
        loadResults();
      }
    }
  };
}

async function loadResults() {
  const batches = await api("/api/batches");
  const latest = batches.find((b) => b.images.length) || batches[0];
  $("results").hidden = !latest;
  if (!latest) return;
  $("batchName").textContent = latest.id + (latest.missing ? " · có sản phẩm thiếu ảnh mẫu" : "");
  $("csvLink").hidden = !latest.csv;
  if (latest.csv) { $("csvLink").href = latest.csv; $("csvLink").download = "loox_import.csv"; }
  $("openBatchBtn").onclick = () => api("/api/open", { method: "POST", body: JSON.stringify({ batch: latest.id }) });
  $("resultGrid").replaceChildren(...latest.images.map((img) => {
    const a = Object.assign(document.createElement("a"), { href: img.url, target: "_blank", title: img.name });
    a.append(Object.assign(document.createElement("img"), { src: img.url, alt: img.name, loading: "lazy" }));
    return a;
  }));
}

// Add / edit one product: URL plus its reference image.
function openItem(url) {
  state.editing = url || null;
  state.pendingImage = null;
  const item = state.urls.find((u) => u.url === url);
  $("itemTitle").textContent = url ? "Sửa sản phẩm" : "Thêm sản phẩm";
  $("itemUrl").value = url || "";
  $("itemError").hidden = true;
  $("deleteItem").hidden = !url;
  showImage(item?.reference ? `/api/reference?url=${encodeURIComponent(url)}&v=${item.reference.sha256.slice(0, 8)}` : null);
  $("removeRef").hidden = !item?.reference;
  $("itemDlg").showModal();
  if (!url) $("itemUrl").focus();
}

function showImage(src) {
  $("dropImg").hidden = !src;
  $("dropText").hidden = !!src;
  if (src) $("dropImg").src = src;
}

function takeImage(file) {
  if (!file || !["image/png", "image/jpeg"].includes(file.type)) { $("itemError").hidden = false; $("itemError").textContent = "Chọn ảnh PNG hoặc JPEG."; return; }
  state.pendingImage = file;
  $("itemError").hidden = true;
  showImage(URL.createObjectURL(file));
  $("removeRef").hidden = false;
}

async function saveQueue(urls) {
  apply(await api("/api/queue", { method: "PUT", headers: { "content-type": "application/json" },
    body: JSON.stringify({ urls, fallback: $("fallback").checked, sourceGroup: $("sourceGroup").value }) }));
}

$("itemForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const url = $("itemUrl").value.trim();
  try {
    const urls = state.urls.map((u) => u.url);
    if (state.editing && state.editing !== url) urls.splice(urls.indexOf(state.editing), 1, url);
    else if (!state.editing) { if (urls.includes(url)) throw new Error("Link này đã có trong danh sách."); urls.push(url); }
    await saveQueue(urls);
    if (state.pendingImage) {
      apply(await api(`/api/reference?url=${encodeURIComponent(url)}`, { method: "POST", headers: { "content-type": state.pendingImage.type }, body: state.pendingImage }));
    }
    $("itemDlg").close();
  } catch (e) { $("itemError").hidden = false; $("itemError").textContent = e.message; }
});
$("deleteItem").onclick = async () => { await saveQueue(state.urls.map((u) => u.url).filter((u) => u !== state.editing)); $("itemDlg").close(); };
$("removeRef").onclick = async () => {
  state.pendingImage = null;
  if (state.editing) apply(await api(`/api/reference?url=${encodeURIComponent(state.editing)}`, { method: "DELETE" }));
  showImage(null);
  $("removeRef").hidden = true;
};
document.querySelectorAll("[data-close]").forEach((b) => (b.onclick = () => b.closest("dialog").close()));
$("drop").onclick = () => $("fileInput").click();
$("drop").onkeydown = (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); $("fileInput").click(); } };
$("fileInput").onchange = () => takeImage($("fileInput").files[0]);
$("drop").ondragover = (e) => { e.preventDefault(); $("drop").classList.add("over"); };
$("drop").ondragleave = () => $("drop").classList.remove("over");
$("drop").ondrop = (e) => { e.preventDefault(); $("drop").classList.remove("over"); takeImage(e.dataTransfer.files[0]); };
$("itemDlg").addEventListener("paste", (e) => {
  const file = [...(e.clipboardData?.files || [])].find((f) => f.type.startsWith("image/"));
  if (file) { e.preventDefault(); takeImage(file); }
});

$("addBtn").onclick = () => openItem(null);
$("optionsBtn").onclick = () => $("optionsDlg").showModal();
$("optionsDlg").addEventListener("close", async () => { saveOptions(); await saveQueue(state.urls.map((u) => u.url)); });
$("helpBtn").onclick = () => $("helpDlg").showModal();
$("openBtn").onclick = () => api("/api/open", { method: "POST", body: "{}" });
$("clearBtn").onclick = () => $("messages").replaceChildren();
$("setupBtn").onclick = async () => {
  $("setupList").replaceChildren(Object.assign(document.createElement("li"), { textContent: "Đang kiểm tra…" }));
  $("setupSummary").textContent = "";
  $("setupDlg").showModal();
  try {
    const report = await api("/api/setup");
    $("setupList").replaceChildren(...report.Checks.map((c) => {
      const li = document.createElement("li");
      li.innerHTML = `<span></span><span></span>`;
      li.firstChild.textContent = c.Ok ? "✓" : "!";
      li.firstChild.className = c.Ok ? "" : "danger";
      li.lastChild.textContent = c.Ok || !c.Action ? c.Message : `${c.Message} ${c.Action}`;
      return li;
    }));
    $("setupSummary").textContent = report.Summary || "";
  } catch (e) { $("setupSummary").textContent = e.message; }
};
$("startBtn").onclick = async () => {
  try {
    saveOptions();
    state.total = state.urls.length; state.done = 0; state.stages = {};
    $("messages").replaceChildren();
    await api("/api/run", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(options()) });
    setRunning(true);
    updateProgress();
  } catch (e) { toast(e.message); }
};
$("stopBtn").onclick = () => api("/api/stop", { method: "POST" }).then(() => message("Đã yêu cầu dừng. Các link chưa hoàn tất được giữ lại.", "warn"));

loadOptions();
api("/api/state").then(apply).catch((e) => toast(e.message));
loadResults().catch(() => {});
listen();
