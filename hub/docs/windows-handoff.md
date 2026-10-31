# Windows: cùng giao diện với macOS

Windows và macOS dùng chung một giao diện: các trang web của hub và của tool, do cùng máy chủ Node phục vụ. Không có giao diện Windows riêng.

## Cách chạy

- `start-app.cmd` chạy `hub/launch.ps1` (Windows PowerShell 5.1, ẩn). Chưa có Node.js thì hỏi rồi chạy `hub/setup/setup-install.ps1`.
- Launcher chạy `node hub/picker.mjs` (nhiều tool) hoặc máy chủ của tool duy nhất, ẩn, cổng tính như Node (`HUB_PICKER_PORT` / `PR_PORT`), log ở `workspace/logs/server.log`.
- Cửa sổ app là WinForms + WebView2 (`hub/webview2/`: SDK `Microsoft.Web.WebView2` 1.0.4191.47, bản net462 và `WebView2Loader.dll` x64/x86/arm64). Launcher chép SDK sang `workspace/webview2/sdk` rồi nạp từ đó, để cập nhật thay được file trong `hub/webview2` khi cửa sổ đang mở. Dữ liệu WebView2 ở `workspace/webview2/data`.
- Trang của menu và máy chủ tool (`http://127.0.0.1:<cổng>/`) mở trong cửa sổ; link ngoài mở trình duyệt mặc định. Máy không có WebView2 Runtime thì mở trang bằng trình duyệt mặc định.
- Đóng cửa sổ: đang chạy thì hỏi trước, rồi `POST /api/quit` cho menu; menu gọi `/api/quit` của từng máy chủ tool.
- Khác biệt hệ điều hành gom ở `hub/platform.mjs`: PowerShell (`powershell.exe -ExecutionPolicy Bypass`, vào/ra UTF-8), PATH, dừng tiến trình (`taskkill /T`, lọc dòng lệnh), hộp chọn file (`OpenFileDialog`), không tự mở cửa sổ Chrome.

## Còn làm

- Chạy thử trên máy Windows thật: mở menu, mở từng tool, Cấu hình, Cập nhật, chọn ảnh, chạy và Dừng một lượt Product Review, đóng cửa sổ khi đang chạy. Chưa kiểm tra được từ máy Mac.
- WinForms của Product Review (`apps/product-review/src/gui.ps1`) còn giữ làm dự phòng; bỏ khi bản web chạy ổn trên Windows.
