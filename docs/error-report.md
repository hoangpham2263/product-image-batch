# File lỗi – chuẩn

Bấm **Gửi lỗi** trong app thì chỉ **một file** được gửi lên trang quản lý: `<ngày>_<giờ>_<phiên bản>_<mac|windows>_<máy>.md`, ví dụ `2026-10-29_22h40m37s_v1.0.46_mac_MacBookPro.md`, vài KB. Không có ảnh, không có mật khẩu app hay tài khoản Codex.

## Cách tạo

1. App gom những gì lỗi từ lần Gửi lỗi trước (lần đầu: 7 ngày): bước **Kiểm tra cấu hình** chưa đạt, lỗi giao diện, các dòng lỗi trong log và lần chạy, đánh giá đã **Bỏ** kèm lý do đã gõ.
2. Codex CLI trên máy đọc dữ liệu đó và viết file theo chuẩn dưới đây (tối đa 2 phút).
3. Máy chưa có Codex, chưa đăng nhập, mất mạng hoặc quá 2 phút: app tự viết file với cùng dữ liệu, dạng danh sách.

## Nội dung file

```
# Lỗi Product Review Batch <phiên bản> · <hệ điều hành> · <máy> · <ngày giờ>

## Tóm tắt
Một hai câu: chuyện gì đang hỏng.

## Nguyên nhân
- Giờ xảy ra (yyyy-MM-dd HH:mm) · từng nguyên nhân, nêu nguồn (bước cấu hình, file log) và số lần lặp.

## Cách sửa cho người dùng
1. Việc người dùng tự làm được, theo thứ tự.

## Đánh giá đã Bỏ
- Gom theo lý do: lý do – số lần – giờ gần nhất – ví dụ.

## Cần sửa trong app
- Việc cho admin / dev, nếu có. Không có thì ghi "Không".
```

## Dành cho AI viết file

1. Bước cấu hình chưa đạt là nguyên nhân đầu tiên cần nêu.
2. Gom lỗi giống nhau, ghi số lần và giờ (trường `at`, dòng log có giờ thì lấy giờ đó); bỏ dòng trùng.
3. Đánh giá đã Bỏ: gom theo lý do để thấy ảnh hay sai ở đâu.
4. Tiếng Việt, ngắn gọn, không chép nguyên log dài; không bịa thông tin không có trong dữ liệu.
