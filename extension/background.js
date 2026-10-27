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
  if (platform === "flow") throw new Error("Mở một dự án Google Flow (flow.google.com/project/...) rồi chạy lại.");
  const tab = await chrome.tabs.create({ url: site.start, active: false });
  await waitForLoad(tab.id);
  return tab;
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
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "needs-click" && _sender.tab) {
    // Flow needs one real click on "Bắt đầu tạo": bring that tab to the front.
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
