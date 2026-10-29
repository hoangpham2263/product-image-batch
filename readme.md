# Product Review Batch

App tạo ảnh review sản phẩm: ghép sản phẩm thật vào ảnh bối cảnh tham khảo, viết nội dung review mẫu, rồi xuất CSV để import vào Loox. Chạy trên Windows và macOS với giao diện giống nhau.

Ảnh và review tạo ra là dữ liệu mẫu, không phải trải nghiệm của khách thật.

## Cài đặt

1. [Tải bản mới nhất](https://github.com/hoangpham2263/product-review-batch/releases/latest/download/product-review-batch.zip) và giải nén.
2. Mở app: `start-app.cmd` (Windows) hoặc `start-app.command` (Mac).
3. Bấm **Kiểm tra cấu hình**, rồi bấm **Cài** / **Đăng nhập** ở bước nào chưa đạt: mật khẩu app, Node.js, Codex, đăng nhập ChatGPT.

Có bản mới thì nút **Cập nhật** chuyển xanh; app chỉ cập nhật khi bạn bấm. `workspace/` và bài học riêng trong `AGENTS.md` được giữ. Máy mới xem [setup.txt](setup.txt).

## Chức năng

- **Thêm sản phẩm:** dán link, gắn ảnh sản phẩm gốc và ảnh review (từ máy, kho Drive hoặc dán Ctrl/Cmd+V). Một link có thể có nhiều ảnh gốc, mỗi ảnh gốc nhiều ảnh review.
- **Nhập hàng loạt:** chọn `nhap.csv` trong thư mục chứa ảnh trên máy; app gắn đúng ảnh cho từng sản phẩm ([chuẩn thư mục](docs/import.md)).
- **Tạo ảnh:** mỗi cặp ảnh gốc + ảnh review cho một ảnh kết quả, giữ đúng sản phẩm; logo thật được thay bằng brand giả, watermark bị xoá.
- **Viết review:** nội dung dựa trên ảnh, học cách viết từ kho review mẫu cùng danh mục; tên, sao, email và ngày được tạo ngẫu nhiên.
- **Duyệt & xuất file:** Giữ/Bỏ từng ảnh, xong thì tạo `loox_import.csv` (chọn **Custom File** khi import vào Loox).
- **Theo dõi:** số token đã dùng và hạn mức ChatGPT hiện trực tiếp khi chạy; chọn model AI và mức suy nghĩ trong Kiểm tra cấu hình.
- **Kho ảnh Drive:** ảnh mẫu chia theo danh mục (Áo, Nội thất…), chọn ảnh trong app hoặc **Tải về máy** chạy nền.
- **Gửi log:** gom log, cấu hình và 10 lần chạy gần nhất thành zip gửi lên Drive; không kèm mật khẩu.

Luồng xử lý mặc định 2, tối đa 4. Link lỗi được giữ lại để chạy tiếp, không tạo lại ảnh đã xong.

## Trang quản lý

[hoangpham.is-a.dev/product-review-batch](https://hoangpham.is-a.dev/product-review-batch/) (đăng nhập bằng mật khẩu admin):

- **Ảnh đã tạo:** lọc, duyệt, copy link, tải danh sách.
- **Nguồn ảnh:** tạo danh mục, tải ảnh lên, bật/tắt danh mục hiện trong app.
- **Log người dùng:** tải về hoặc xoá log app gửi lên.
- **API:** tài liệu cho AI và **mã tạm** có thời hạn để AI tự tải ảnh lên kho ([docs/api.md](docs/api.md)).
- **Nhập hàng loạt:** chuẩn file nhập và file mẫu, xem được không cần đăng nhập.

## Mật khẩu

- **Mật khẩu app:** nhập trong app; tải ảnh kết quả lên, dùng kho ảnh, gửi log.
- **Mật khẩu admin:** chỉ cho trang quản lý; không đưa cho người dùng app.
- **Mã tạm:** tạo ở trang API, chỉ xem và thêm ảnh vào kho, tự hết hạn.

## Kết quả mỗi lần chạy

```
workspace/output/<thời-gian>/
  images/            ảnh kết quả
  refs/              bản sao ảnh đầu vào kèm nguồn và SHA256
  logs/              log AI và lỗi từng sản phẩm
  results.json       kết quả chờ duyệt
  loox_import.csv    có sau khi duyệt xong
  missing-data.csv   (nếu có) sản phẩm thiếu ảnh mẫu
```

Trên Drive, mọi thứ nằm trong `Product Review Batch/`: `Ảnh đã tạo/`, `Nguồn ảnh/`, `Logs/`.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `src/` | Mã nguồn app (PowerShell); `src/mac/` cho giao diện Mac |
| `data/` | Quy tắc, kho review mẫu, danh sách tên, catalog ảnh |
| `worker/` | Cloudflare Worker `product-review-batch-api`: lưu ảnh lên Google Drive |
| `docs/` | Trang quản lý (GitHub Pages) và tài liệu API |
| `bridge/`, `extension/` | Tạo ảnh qua tab ChatGPT / Google Flow trên Chrome (tuỳ chọn) |
| `tools/` | Công cụ chuẩn bị dữ liệu, đẩy ảnh lên kho |
| `tests/` | Kiểm thử offline: `test.cmd` (Windows), `./test.sh` (Mac) |
| `workspace/` | File sinh ra khi chạy, không lên Git |

Chi tiết workflow: [docs/workflow.txt](docs/workflow.txt). Hướng dẫn và bài học cho AI: [AGENTS.md](AGENTS.md).

## Phát hành

```bash
git tag v1.0.x && git push origin v1.0.x
```

GitHub Actions tạo Release; người dùng bấm **Cập nhật** trong app.

## Ghi công

Danh sách tên trong `data/names.txt` dùng Names Corpus 1.3 (Mark Kantrowitz, bổ sung bởi Bill Ross); điều khoản ở [data/names-LICENSE.txt](data/names-LICENSE.txt).
