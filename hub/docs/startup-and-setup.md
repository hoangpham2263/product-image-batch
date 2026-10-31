# Khởi động và kiểm tra cấu hình

- Windows chỉ dùng máy chủ khi `/api/root` khớp thư mục, loại dịch vụ và `protocol: 1`, đồng thời `/` tải được HTML. Một máy chủ cũ trả đúng root nhưng không có trang menu không đủ điều kiện.
- Cổng mặc định được tính theo thư mục cài. Nếu cổng bị chiếm, launcher tìm máy chủ đúng đang chạy hoặc cổng trống trong dải kế tiếp, không dừng tiến trình lạ. Địa chỉ đã xác minh được lưu tại `workspace/server-address.json`; không mặc định cứng `46763` trong shortcut.
- Launcher chỉ dừng máy chủ PowerShell cũ khi xác minh đúng root và đúng entry `hub/web-server.ps1` của bản cài. Khởi động Node có hạn chờ, log theo cổng, phát hiện child thoát sớm và thử cổng kế tiếp. Không mở cửa sổ app trước khi menu sẵn sàng.
- Mỗi máy chủ gộp các yêu cầu `/api/setup` đồng thời thành một child PowerShell. Không cache kết quả lâu dài: bấm kiểm tra lại sẽ đọc trạng thái mới.
- Child có hạn chờ 45 giây; client 50 giây. Báo lỗi có mã `SETUP_TIMEOUT`/`SETUP_INVALID_REPORT`, không biến lỗi đọc thành thiếu mật khẩu hoặc hết hạn mức. Một báo cáo đủ 5 bước vẫn hợp lệ nếu script exit 1 vì máy chưa cấu hình xong.
- Hộp thoại luôn kết thúc trạng thái chờ khi lỗi; ghép từng dòng theo Id thay vì vị trí mảng. Không tự đăng nhập, cài lại hoặc đổi mật khẩu khi kiểm tra thất bại.
- Log: `workspace/logs/app-errors.log`, `server-<port>.err.log`, `setup-api-errors.log`. File địa chỉ chỉ chứa root/service/port; không chứa mật khẩu.

Kiểm tra hồi quy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File hub/tests/server-health.ps1
node --test hub/tests/setup-report.test.mjs hub/tests/setup-client.test.mjs
```

Các cơ chế này xử lý các dạng lỗi đã xác định; không bảo đảm mọi lỗi mạng, antivirus hoặc hệ điều hành sẽ không xảy ra. Nếu tái diễn, giữ log để xác định đúng nguyên nhân.
