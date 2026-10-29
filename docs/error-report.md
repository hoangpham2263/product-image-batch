# Báo cáo lỗi – chuẩn `prb-error-report/1`

**Gửi lỗi** trong app tạo một báo cáo lỗi nhỏ (vài KB), cùng một khuôn mỗi lần để AI đọc và kiểm tra. Không có ảnh, không có mật khẩu app hay tài khoản Codex.

File gửi lên là một zip gồm:

| File | Nội dung |
|---|---|
| `report.json` | Báo cáo đầy đủ theo chuẩn dưới đây |
| `summary.txt` | Tóm tắt vài dòng cho người đọc |
| `analysis.md` | Codex CLI trên máy đọc báo cáo theo chuẩn này và viết nguyên nhân, cách sửa. Không có khi máy chưa có Codex, chưa đăng nhập, mất mạng hoặc quá 2 phút: báo cáo vẫn được gửi |

## report.json

| Trường | Nội dung |
|---|---|
| `format` | Luôn là `prb-error-report/1` |
| `created_at`, `since` | Lúc tạo và mốc bắt đầu: lần gửi trước (lùi 1 giờ), lần đầu là 7 ngày trước |
| `app` | Phiên bản, cách cài, hệ điều hành, máy |
| `tools` | Node, npm, Codex, Git, PowerShell: đường dẫn và phiên bản |
| `setup` | Kết quả **Kiểm tra cấu hình** |
| `config` | Đã lưu mật khẩu app chưa (không có mật khẩu), danh mục, đồng bộ kho ảnh |
| `runs` | Các lần chạy từ mốc `since` (ít nhất lần mới nhất) |
| `errors` | Chỉ lỗi: `{ source, text }` cho lỗi giao diện, `{ source, lines }` cho các dòng lỗi trong log và lần chạy (tối đa 50 dòng mỗi file) |
| `rejected` | Đánh giá đã **Bỏ** chưa báo: `run`, `id`, `product_handle`, `reason` (lý do gõ khi bấm Bỏ), `body`, `decided_at` |
| `skipped` | File không đọc được, nếu có |

## Dành cho AI kiểm tra

1. Đọc `summary.txt`, rồi `report.json`.
2. `setup`: bước nào chưa đạt là nguyên nhân đầu tiên cần sửa.
3. `errors`: gom các lỗi giống nhau, nêu nguồn (`source`) và lỗi xuất hiện nhiều nhất.
4. `rejected`: gom theo `reason` để biết ảnh hay sai ở đâu.
5. Trả lời ngắn: nguyên nhân, cách sửa cho người dùng, và việc cần sửa trong app nếu có.
