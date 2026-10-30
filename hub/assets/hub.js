// Cập nhật for every page the Tools Hub menu serves on macOS (the menu and web tools): a button at the top right,
// where Product Review has its own, green with the version once a newer one is out. It checks and installs through
// the menu server (hub/picker.mjs). Pages opened as files (Windows) have no server to ask, so no button.
(() => {
  if (!location.protocol.startsWith("http")) return;
  const header = document.querySelector("header");
  if (!header) return;
  const btn = Object.assign(document.createElement("button"), { type: "button", className: "btn update", textContent: "Cập nhật" });
  header.append(btn);
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
})();
