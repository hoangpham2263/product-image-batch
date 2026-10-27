// Google Flow: paste references and the prompt into the composer, then return the new image.
// Flow only starts a generation from a real click, so the user presses "Bắt đầu tạo" once;
// everything before and after that click is automatic.
const flowImages = () => new Set([...document.querySelectorAll('img[src*="flow-content.google/image/"]')].map((img) => img.src.split("?")[0]));

async function generateFlow(job) {
  const editor = await waitFor(() => document.querySelector('.ProseMirror[contenteditable="true"]'), 30000, "ô nhập Flow");
  const before = flowImages();
  const files = filesFromJob(job);
  await pasteFiles(editor, files);
  // Uploaded references appear in the project grid as well; record them so they are not mistaken for results.
  if (files.length) {
    await waitFor(() => flowImages().size >= before.size + files.length, 120000, "tải ảnh tham khảo lên Flow");
    flowImages().forEach((src) => before.add(src));
  }
  typePrompt(editor, job.prompt);
  const button = await waitFor(() => document.querySelector("button.generate-icon-button:not([disabled])"), 30000, "nút tạo của Flow");
  button.style.outline = "3px solid #f5b400";
  button.style.outlineOffset = "3px";
  button.scrollIntoView({ block: "center" });
  chrome.runtime.sendMessage({ type: "needs-click", platform: "flow" });

  const src = await waitFor(() => {
    const fresh = [...document.querySelectorAll('img[src*="flow-content.google/image/"]')].find((img) => !before.has(img.src.split("?")[0]) && img.complete && img.naturalWidth > 0);
    return fresh?.src;
  }, (job.timeoutSec || 600) * 1000, "Flow tạo ảnh (bấm Bắt đầu tạo trong tab Flow)");
  button.style.outline = "";
  return { url: src, source: location.href };
}

onJob(generateFlow);
