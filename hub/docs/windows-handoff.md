# Windows native: bàn giao 31/10/2026

Yêu cầu: macOS giữ bản web đang chạy ổn. Windows dùng WinForms native, không mở Edge/Chrome để chạy tool. Cần đồng bộ chức năng và logic, không thay macOS sang native.

## Đã làm

- `hub/launch.ps1`: mở entry `windows` của cả ba tool; chỉ ẩn menu sau khi đúng cửa sổ tool xuất hiện. Giữ message loop của menu, quay lại khi child kết thúc; giữ handle để đọc exit code, ghi lỗi startup. `TOOLS_HUB_MENU=return` ngăn Product Review tự mở thêm menu.
- Card dùng double buffering và hover native; kiểm tra cập nhật của menu chạy nền. Nút phẳng viền mảnh ở `hub/winforms.ps1`.
- `hub/native-window.ps1`: header native dùng chung cho Grok/Content MXH (Menu, Cấu hình, Cập nhật); log lỗi UI vào workspace của tool.
- Grok: WinForms, cùng dữ liệu prompts.js + demo-prompts.js với macOS qua export-prompts.cjs. Chọn 6/10/15s, style, tên sản phẩm, copy và lưu trạng thái. Video dùng WPF MediaElement trong WinForms, không dùng browser.
- Content MXH: WinForms, thêm/sửa/xóa sản phẩm, ảnh và số bối cảnh, chọn nền tảng/giọng văn, copy bài mẫu, lưu trạng thái. Quy tắc soạn bài port từ bản macOS. Tạo ảnh/viết AI chưa có ở cả hai bản; nút Bắt đầu thông báo đúng giới hạn này.

## Kiểm tra

Chạy bằng Windows PowerShell STA:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/native-tools.ps1 -Tool grok
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/native-tools.ps1 -Tool social
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/windows-menu.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/windows-navigation.ps1
```

Đã qua kiểm tra 30 style/thay tên, 4 nền tảng × 3 giọng văn, callback Menu của Product Review, và hai vòng mở/đóng/quay lại của cả ba cửa sổ native thật. Có render xem bố cục Grok/Content MXH. Không chạy AI hoặc kiểm tra xuất bản nội dung thật.

## Cập nhật sau bàn giao (v2.0.37)

- Bỏ hẳn `hub/web-server.ps1`, `Get-HubWebPort` và `?win`: Windows không còn đường web nào.
- `hub/native-window.ps1` viết lại thành bộ điều khiển dùng chung theo `tool.css`: Group (khung xám, tiêu đề trong khung), Box, CardList (.listbox/.card), Toggle (nút nền tảng có logo), Tile, Row (.qrow), seg, toast; header giống Product Review, Cập nhật tự kiểm tra bản mới. Kiểu C# 5, đã biên dịch thử với WinForms.
- Nút thường quay lại nút hệ thống Windows 10 (đúng `.btn`), nút chính màu xanh.
- Grok và Content MXH dựng lại theo đúng bố cục trang macOS (cột phải 400px, nhóm, khoảng cách). Content MXH có hàng sản phẩm như Product Review, nút nền tảng có logo (`apps/fb-content/assets/*.png`), tab bài đăng, ảnh gốc → bối cảnh, hộp Xem / sửa có kéo thả ảnh.
- Lỗi đã sửa: TLS 1.2 cho API video, WebClient đọc UTF-8, Grok không còn bắt buộc Node, xây lại hàng trong lúc đang bấm nút của hàng đó, cập nhật từ trong tool mở lại menu mới (mã thoát 3).
- Chưa chạy được trên Windows từ máy Mac: cần chạy lại các test ở trên trên Windows.

## Còn làm

- Hoàn thiện giao diện, độ khớp bố cục với macOS, responsive/DPI, thumbnail, trạng thái rỗng và popup sửa sản phẩm; hiện mới là bản native cơ bản.
- Kiểm tra video thật, codec, nút phát/tạm dừng và lỗi mạng. MediaElement từng ném NullReferenceException khi Stop chưa có nguồn; đã đổi sang Close có bảo vệ để không chặn đóng cửa sổ. Chưa xác nhận playback video thật.
- Mở rộng test thao tác người dùng thực (popup Lưu/Hủy, kéo thả, clipboard, lưu/mở lại, Cấu hình/Cập nhật). Chưa có bằng chứng parity 100% với macOS.
- Avast trên máy từng cách ly hub/web-server.ps1 (IDP.Generic) và một số entry bị mất. Đã khôi phục file được Git theo dõi, không thay cấu hình bảo vệ. Windows native không còn dùng máy chủ web đó.
- Các file không theo dõi `hub/diagnostic-launch.ps1`, `hub/gui.ps1`, `hub/setup-check.ps1`, `hub/start-app.cmd` là chẩn đoán/bản phục hồi sai vị trí; không thuộc bản bàn giao. Không commit `workspace/`, `data/` không theo dõi hoặc ảnh kho.
