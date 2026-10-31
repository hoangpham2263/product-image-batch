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

## Còn làm

- Hoàn thiện giao diện, độ khớp bố cục với macOS, responsive/DPI, thumbnail, trạng thái rỗng và popup sửa sản phẩm; hiện mới là bản native cơ bản.
- Kiểm tra video thật, codec, nút phát/tạm dừng và lỗi mạng. MediaElement từng ném NullReferenceException khi Stop chưa có nguồn; đã đổi sang Close có bảo vệ để không chặn đóng cửa sổ. Chưa xác nhận playback video thật.
- Mở rộng test thao tác người dùng thực (popup Lưu/Hủy, kéo thả, clipboard, lưu/mở lại, Cấu hình/Cập nhật). Chưa có bằng chứng parity 100% với macOS.
- Avast trên máy từng cách ly hub/web-server.ps1 (IDP.Generic) và một số entry bị mất. Đã khôi phục file được Git theo dõi, không thay cấu hình bảo vệ. Windows native không còn dùng máy chủ web đó.
- Các file không theo dõi `hub/diagnostic-launch.ps1`, `hub/gui.ps1`, `hub/setup-check.ps1`, `hub/start-app.cmd` là chẩn đoán/bản phục hồi sai vị trí; không thuộc bản bàn giao. Không commit `workspace/`, `data/` không theo dõi hoặc ảnh kho.
