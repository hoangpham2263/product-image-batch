// Google Flow: paste references and the prompt into the composer, press the generate button, then return the new
// image. Flow only starts a generation from a real click: the background clicks it through the debugger (a trusted
// mouse event). When that does not start one, the button is highlighted for the user to press once.
// Flow's own images: flow.google.com/asb/<id> now, flow-content.google/image/<id> before.
const isFlowImage = (img) => /^https:\/\/(flow\.google\.com\/asb\/|flow-content\.google\/image\/)/.test(img.src);
const flowImages = () => new Set([...document.images].filter(isFlowImage).map((img) => img.src.split("?")[0]));

async function generateFlow(job) {
  const composer = () => document.querySelector('.ProseMirror[contenteditable="true"]');
  let editor = await waitFor(composer, 30000, "ô nhập Flow");
  if (flowAgentOn()) throw new Error(FLOW_AGENT);
  const before = flowImages();
  const files = filesFromJob(job);
  // Uploaded references appear in the project grid as well; record them so they are not mistaken for results.
  // A new project sometimes drops the first paste (nothing ever uploads): paste again into the composer it has now.
  for (let paste = 1; paste <= 3; paste++) {
    await pasteFiles(editor, files);
    if (!files.length) break;
    try { await waitFor(() => flowImages().size >= before.size + files.length, paste === 3 ? 120000 : 45000, "tải ảnh tham khảo lên Flow"); break; }
    catch (error) { if (paste === 3) throw error; editor = await waitFor(composer, 30000, "ô nhập Flow"); }
  }
  if (files.length) {
    flowImages().forEach((src) => before.add(src));
    // Flow draws the composer again once a reference is attached.
    editor = await waitFor(composer, 30000, "ô nhập Flow");
  }
  typePrompt(editor, job.prompt);
  const button = await waitFor(() => document.querySelector("button.generate-icon-button:not([disabled])"), 30000, "nút tạo của Flow");
  button.scrollIntoView({ block: "center" });
  await sleep(300);
  // Started once the composer lets go of the prompt or the button turns off.
  const started = () => !editor.innerText.includes(job.prompt.slice(0, 20)) || button.disabled || !button.isConnected;
  const box = button.getBoundingClientRect();
  const clicked = await chrome.runtime.sendMessage({ type: "click", x: box.left + box.width / 2, y: box.top + box.height / 2 }).catch(() => null);
  if (!clicked?.ok || !(await waitFor(started, 15000, "").catch(() => false))) {
    button.style.outline = "3px solid #f5b400";
    button.style.outlineOffset = "3px";
    chrome.runtime.sendMessage({ type: "needs-click", platform: "flow" });
  }

  const src = await waitFor(() => {
    const fresh = [...document.images].find((img) => isFlowImage(img) && !before.has(img.src.split("?")[0]) && img.complete && img.naturalWidth > 0);
    return fresh?.src;
  }, (job.timeoutSec || 600) * 1000, "Flow tạo ảnh (bấm Bắt đầu tạo trong tab Flow)");
  button.style.outline = "";
  return { url: src, source: location.href };
}

onJob(generateFlow);

// An account that has never used Flow first gets a welcome dialog (Tiếp theo / Đăng xuất) over the page; a click on
// Dự án mới then lands on it. Only the user goes through it (Cấu hình → Mở Flow).
const FLOW_WELCOME = "Google Flow của tài khoản đang chọn đang hiện màn hình chào lần đầu. Mở Cấu hình, bấm Mở Flow, bấm Tiếp theo cho xong rồi chạy lại.";
// Flow's agent mode (Tác nhân) answers in a chat and makes video, not the image the run waits for; it is on by default
// for some accounts. Turned off once in Flow, it stays off.
const FLOW_AGENT = "Google Flow của tài khoản đang chọn đang bật Tác nhân, không tạo ảnh. Mở Cấu hình, bấm Mở Flow, vào một dự án, tắt Tác nhân và chọn mô hình ảnh Nano Banana rồi chạy lại.";
const flowAgentOn = () => [...document.querySelectorAll("button")].some((b) => b.getAttribute("aria-pressed") === "true" && (b.classList.contains("agent-mode-chip") || /^(Tác nhân|Agent)$/i.test(b.innerText.trim())));
const flowWelcome = () => [...document.querySelectorAll("[role=dialog]")].some((d) => {
  const texts = [...d.querySelectorAll("button")].map((b) => b.innerText.trim());
  return d.getBoundingClientRect().width > 0 && texts.some((t) => /^(Tiếp theo|Next)$/i.test(t)) && texts.some((t) => /^(Đăng xuất|Sign out)$/i.test(t));
});

// On Flow's home page: where its new-project button is, for the background to click.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "new-project") return;
  const find = () => {
    if (flowWelcome()) throw new Error(FLOW_WELCOME);
    return [...document.querySelectorAll("button")].find((b) => /Dự án mới|New project/i.test(b.innerText) || (b.classList.contains("mat-mdc-fab") && /^add\b/.test(b.innerText.trim())));
  };
  waitFor(find, 30000, "nút Dự án mới của Flow (đã đăng nhập Google chưa?)").then(async (button) => {
    // The dialog can come a moment after the page.
    await sleep(1500);
    if (flowWelcome()) throw new Error(FLOW_WELCOME);
    button.scrollIntoView({ block: "center" });
    const box = button.getBoundingClientRect();
    sendResponse({ ok: true, x: box.left + box.width / 2, y: box.top + box.height / 2 });
  }).catch((error) => sendResponse({ ok: false, error: String(error.message || error) }));
  return true;
});
