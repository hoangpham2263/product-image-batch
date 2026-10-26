# Product Image Batch

Ứng dụng Windows tạo ảnh sản phẩm trong bối cảnh tham khảo và nội dung review mẫu, sau đó xuất CSV.

Nhấp đúp **[start-app.cmd](start-app.cmd)** ở thư mục gốc để mở giao diện. Bấm **Hướng dẫn** trong app để xem cách dùng. Máy mới xem [setup.txt](setup.txt).

Đăng nhập ChatGPT qua Codex, tài khoản có quyền tạo ảnh và còn hạn mức. Nút **Kiểm tra ChatGPT** kiểm tra cài đặt, đăng nhập và hạn mức Codex còn lại kèm giờ đặt lại (GMT+7); **Xóa thông báo** chỉ dọn khung thông báo, giữ nguyên kết quả và file chẩn đoán.

Hạn mức được đọc trực tiếp từ Codex, không tạo lượt AI. Nếu dịch vụ chưa trả số liệu, app báo chưa lấy được; tài khoản API chưa hỗ trợ xem số dư. Phần trăm Codex không quy đổi thành số ảnh còn tạo được.

Luồng xử lý: mặc định 1, tối đa 4. Khuyên dùng 1–2; tăng luồng dùng nhiều RAM và hạn mức hơn, có thể làm máy chậm.

## Workflow

| Bước | Xử lý |
|---|---|
| 1. Nhận URL | Đọc danh sách sản phẩm, giữ hàng đợi để có thể chạy lại phần lỗi. |
| 2. Đọc và nhận diện sản phẩm | Tải ảnh gốc, xác định loại sản phẩm từ ảnh. |
| 3. Chọn ảnh tham khảo | Lấy ảnh trong data/source-photos/ đúng danh mục theo catalog.json, kiểm tra người và bối cảnh có phù hợp. |
| 4. Lưu đầu vào | Sao chép ảnh đã chọn cùng nguồn và SHA256 vào refs/<mã-SP>/. |
| 5. Tạo ảnh | Tạo **một ảnh hoàn chỉnh** theo sản phẩm gốc và bối cảnh tham khảo; giữ hình dáng, màu sắc và hình in. Sản phẩm có logo thì logo được thay đúng chỗ bằng brand giả hợp với sản phẩm và bối cảnh ảnh, mỗi ảnh một tên khác nhau trong batch; không có logo thì không thêm. Không ghép thành nhiều ô. |
| 6. Kiểm tra ảnh kết quả | Đối chiếu sản phẩm và ngữ cảnh; nếu chưa đạt thì sửa tối đa một lần. |
| 7. Viết review mẫu | Chọn tối đa 3 review tham khảo đúng danh mục từ review-samples.jsonl, xoay vòng mẫu để học cách viết; nội dung mới dựa trên ảnh. Không bắt buộc ngôi thứ nhất, không chép lời khách khác hay thêm trải nghiệm mua hàng. Câu mở đầu kiểu “I like/I love” hoặc chép câu nguồn sẽ được viết lại tối đa một lần; vẫn lỗi thì dừng sản phẩm. |
| 8. Hoàn thiện dữ liệu | Sau khi các luồng ảnh/review kết thúc, máy random tên, sao, email @int và ngày; không gọi Codex cho phần này. |
| 9. Xuất kết quả | Lưu ảnh và CSV; URL thành công được lấy khỏi hàng đợi, URL lỗi được giữ lại. |

### Thư viện ảnh mẫu

Ảnh gốc quyết định sản phẩm xuất hiện như thế nào: mặc, cầm, đặt trong không gian hoặc sử dụng xe.

Ảnh mẫu nằm trong data/source-photos/<danh-mục>/, mỗi ảnh có bản ghi trong catalog.json (danh mục, nguồn, SHA256). Danh mục cho từng loại sản phẩm khai báo trong data/product-contexts.json (`source_categories`). Ảnh mẫu chỉ cung cấp người, bố cục và bối cảnh; không thay thế chi tiết của sản phẩm gốc.

Số ảnh mẫu/SP là mức tối đa. Nếu chỉ có một ảnh đạt với người và bối cảnh phù hợp, app dùng bối cảnh thật đó; không có ảnh đạt thì xem mục Báo thiếu ảnh mẫu. Thêm loại sản phẩm mới: tạo thư mục ảnh, thêm bản ghi vào catalog.json và khai báo danh mục trong product-contexts.json.

Với đồ đặt trong không gian như bàn ăn, ảnh mẫu cung cấp phòng và bố cục, không cần giống mẫu bàn hay số ghế. Phòng vẫn phải đủ chỗ cho toàn bộ sản phẩm thật. App thử tối đa `MaxTries` ảnh cho đồ vật (mặc định 5), lưu đường dẫn ảnh và kết luận vào `logs/<mã-SP>-p1-fit-<lượt>.json`; ảnh bị loại có lý do cụ thể. Review chữ và ảnh bối cảnh là hai nguồn dữ liệu riêng: có review chữ chưa có nghĩa là đã có ảnh bối cảnh phù hợp.

## Kết quả: mỗi lần chạy là một thư mục

```
workspace/output/<thời-gian>/
  images/<mã-SP>.png      ảnh kết quả
  refs/<mã-SP>/           bản sao ảnh đầu vào + manifest.json (vai trò, nguồn, SHA256)
  logs/                   log AI, lỗi từng sản phẩm, run.log, rejected/ (ảnh bị loại)
    <mã-SP>-review-sources.json  các review tham khảo thực tế đã chọn
  loox_import.csv         product_handle, rating, author, email, body, created_at, photo_url, verified_purchase
  urls.input.txt          danh sách URL đầu vào
  urls.completed.txt      URL đã xong
  missing-data.csv        (nếu có) sản phẩm thiếu ảnh mẫu
```

Ảnh và review đầu ra là dữ liệu mẫu được tạo ra, không phải bằng chứng mua hàng hay trải nghiệm của khách thật.

## Báo thiếu ảnh mẫu

Sản phẩm không có ảnh mẫu phù hợp sẽ dừng, giữ link để chạy lại, và được ghi vào batch:

```
workspace/output/<thời-gian>/
  missing-data.csv              danh sách: mã SP, sản phẩm, danh mục, cách trình bày, link
  missing-data/<mã-SP>/
    product.jpg                 ảnh sản phẩm gốc
    info.json                   sản phẩm, danh mục, bối cảnh cần, lý do
```

App hiện thông báo khi chạy xong. Gửi `missing-data.csv` và thư mục `missing-data/` để bổ sung ảnh mẫu vào data/source-photos/.

## Cấu trúc thư mục

| Đường dẫn | Nội dung |
|---|---|
| src/ | Mã nguồn: `workflow/steps/01–07`, `application/`, `domain/`, `infrastructure/`, `ui/` |
| data/ | Dữ liệu base trên Git: `source-photos/` (+ catalog.json), names.txt, *.json quy tắc, `image-style/`, review-samples.jsonl (~2.800 review mẫu: nội dung, danh mục, nguồn) |
| tests/ | Kiểm thử offline, chạy bằng test.cmd |
| workspace/ | Mọi file sinh ra, Git bỏ qua: `output/`, `urls.txt` (hàng đợi), `logs/` (log kiểm tra ChatGPT), `temp/`, `tests/` |

Ảnh mẫu chỉ được đọc, không bị sửa hay di chuyển. Tham số CLI -List và -OutDir cho phép chọn đường dẫn riêng.

## Kiểm tra và tài liệu

Chạy **test.cmd** để kiểm tra cú pháp và các bộ kiểm thử offline, không gọi AI trả phí.

- [Chi tiết workflow và cấu trúc mã nguồn](docs/workflow.txt)
