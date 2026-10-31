// Router: keeps a WebSocket to the local bridge and forwards each job to the matching tab.
// The job is submitted inside the signed-in tab, so the page itself handles its own anti-abuse checks.
const BRIDGE_URL = "ws://127.0.0.1:8765";
const SITES = {
  chatgpt: { match: "https://chatgpt.com/*", start: "https://chatgpt.com/" },
  flow: { match: "https://flow.google.com/project/*", start: "https://flow.google.com/" },
};

let socket = null;

function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) return;
  socket = new WebSocket(BRIDGE_URL);
  socket.onopen = () => {
    socket.send(JSON.stringify({ type: "hello", version: chrome.runtime.getManifest().version }));
    chrome.storage.session.set({ connected: true });
  };
  socket.onclose = () => { socket = null; chrome.storage.session.set({ connected: false }); };
  socket.onerror = () => {};
  socket.onmessage = (event) => {
    let job;
    try { job = JSON.parse(event.data); } catch { return; }
    if (job.type === "generate") runJob(job);
    // After an update the app asks for this, so the new files load without a click in chrome://extensions.
    if (job.type === "reload") chrome.runtime.reload();
  };
}

function reply(message) {
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
}

async function findTab(platform) {
  const site = SITES[platform];
  if (!site) throw new Error(`Nền tảng không hỗ trợ: ${platform}`);
  const tabs = await chrome.tabs.query({ url: site.match });
  if (tabs.length) return tabs.sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0))[0];
  if (platform === "flow") return newFlowProject();
  const tab = await chrome.tabs.create({ url: site.start, active: false });
  await waitForLoad(tab.id);
  return tab;
}

// No Flow project open: open Flow's home and press its new-project button, then use that project.
async function newFlowProject() {
  const [home] = await chrome.tabs.query({ url: "https://flow.google.com/*" });
  const tab = home || await chrome.tabs.create({ url: "https://flow.google.com/", active: true });
  if (!home) await waitForLoad(tab.id);
  const ask = () => chrome.tabs.sendMessage(tab.id, { type: "new-project" });
  // A tab open from before the extension (re)loaded has no content script: reload it once.
  const at = await ask().catch(async () => { await chrome.tabs.reload(tab.id); await waitForLoad(tab.id); return ask(); }).catch(() => null);
  if (!at?.ok) throw new Error(at?.error || "Không mở được Google Flow. Mở Cấu hình, bấm Mở ở dòng Chrome của tool rồi đăng nhập Google.");
  await trustedClick(tab, at.x, at.y);
  for (let i = 0; i < 60; i++) {
    const now = await chrome.tabs.get(tab.id);
    if (/^https:\/\/flow\.google\.com\/project\//.test(now.url || "") && now.status === "complete") return now;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("Google Flow chưa tạo được dự án mới.");
}

function waitForLoad(tabId) {
  return new Promise((resolve) => {
    const listener = (id, info) => {
      if (id === tabId && info.status === "complete") { chrome.tabs.onUpdated.removeListener(listener); resolve(); }
    };
    chrome.tabs.onUpdated.addListener(listener);
  });
}

async function runJob(job) {
  const progress = (stage) => reply({ type: "progress", id: job.id, stage });
  try {
    const tab = await findTab(job.platform);
    if (job.platform === "chatgpt") {
      // Every job starts in a fresh conversation so earlier images are never reused.
      await chrome.tabs.update(tab.id, { url: SITES.chatgpt.start });
      await waitForLoad(tab.id);
    }
    progress("submitting");
    let result;
    try {
      result = await chrome.tabs.sendMessage(tab.id, { type: "generate", job });
    } catch {
      // Tabs opened before the extension was installed have no content script yet.
      await chrome.tabs.reload(tab.id);
      await waitForLoad(tab.id);
      result = await chrome.tabs.sendMessage(tab.id, { type: "generate", job });
    }
    if (!result || !result.ok) throw new Error(result?.error || "Tab không trả kết quả.");
    if (result.url && !result.data) {
      // Signed Flow links are fetched here, where the host permission applies.
      const response = await fetch(result.url, { credentials: "include" });
      if (!response.ok) throw new Error(`Tải ảnh Flow lỗi ${response.status}`);
      const blob = await response.blob();
      result = { mime: blob.type, data: await toBase64(blob), source: result.source };
    }
    reply({ type: "result", id: job.id, ok: true, ...result });
  } catch (error) {
    reply({ type: "result", id: job.id, ok: false, error: String(error.message || error) });
  }
}

async function toBase64(blob) {
  const buffer = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let i = 0; i < buffer.length; i += 0x8000) binary += String.fromCharCode(...buffer.subarray(i, i + 0x8000));
  return btoa(binary);
}

// MV3 workers sleep; an alarm wakes the worker to reconnect to the bridge.
chrome.alarms.create("bridge", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
// A real left click at (x, y) in the tab's viewport, sent through the debugger so the page sees a trusted event.
// Chrome shows its "debugging this browser" bar while attached, for this moment only. The window is left as it is
// (the tools' own Chrome runs with none).
async function trustedClick(tab, x, y) {
  await chrome.tabs.update(tab.id, { active: true });
  const target = { tabId: tab.id };
  await chrome.debugger.attach(target, "1.3");
  try {
    const mouse = (type, extra = {}) => chrome.debugger.sendCommand(target, "Input.dispatchMouseEvent", { type, x, y, button: "left", ...extra });
    await mouse("mouseMoved", { button: "none" });
    await mouse("mousePressed", { buttons: 1, clickCount: 1 });
    await mouse("mouseReleased", { buttons: 0, clickCount: 1 });
  } finally {
    await chrome.debugger.detach(target).catch(() => {});
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "click" && _sender.tab) {
    trustedClick(_sender.tab, message.x, message.y).then(() => sendResponse({ ok: true }), (error) => sendResponse({ ok: false, error: String(error.message || error) }));
    return true;
  }
  if (message?.type === "needs-click" && _sender.tab) {
    // The automatic click did not start Flow: bring that tab to the front for the user's click.
    chrome.tabs.update(_sender.tab.id, { active: true });
    chrome.windows.update(_sender.tab.windowId, { focused: true });
    reply({ type: "progress", id: "flow", stage: "waiting for the Flow click" });
    return;
  }
  if (message?.type === "status") {
    connect();
    sendResponse({ connected: !!socket && socket.readyState === WebSocket.OPEN });
  }
});
connect();
