// Google Flow: paste references and the prompt into the composer, press the generate button, then return the new
// image. Flow only starts a generation from a real click: the background clicks it through the debugger (a trusted
// mouse event). When that does not start one, the button is highlighted for the user to press once.
// Flow's own images: flow.google.com/asb/<id> now, flow-content.google/image/<id> before.
const isFlowImage = (img) => /^https:\/\/(flow\.google\.com\/asb\/|flow-content\.google\/image\/)/.test(img.src);
const flowImages = () => new Set([...document.images].filter(isFlowImage).map((img) => img.src.split("?")[0]));

async function generateFlow(job) {
  const composer = () => document.querySelector('.ProseMirror[contenteditable="true"]');
  let editor = await waitFor(composer, 30000, "ô nhập Flow");
  const before = flowImages();
  const files = filesFromJob(job);
  await pasteFiles(editor, files);
  // Uploaded references appear in the project grid as well; record them so they are not mistaken for results.
  if (files.length) {
    await waitFor(() => flowImages().size >= before.size + files.length, 120000, "tải ảnh tham khảo lên Flow");
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

// On Flow's home page: where its new-project button is, for the background to click.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "new-project") return;
  const find = () => [...document.querySelectorAll("button")].find((b) => /Dự án mới|New project/i.test(b.innerText) || (b.classList.contains("mat-mdc-fab") && /^add\b/.test(b.innerText.trim())));
  waitFor(find, 30000, "nút Dự án mới của Flow (đã đăng nhập Google chưa?)").then((button) => {
    button.scrollIntoView({ block: "center" });
    const box = button.getBoundingClientRect();
    sendResponse({ ok: true, x: box.left + box.width / 2, y: box.top + box.height / 2 });
  }, (error) => sendResponse({ ok: false, error: String(error.message || error) }));
  return true;
});
