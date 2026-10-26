# Product Image Batch

Ứng dụng Windows tạo ảnh sản phẩm trong bối cảnh tham khảo và nội dung review mẫu, sau đó xuất CSV.

Nhấp đúp **[start-app.cmd](start-app.cmd)** ở thư mục gốc để mở giao diện. Bấm **Hướng dẫn** trong app để xem cách dùng. Máy mới xem [setup.txt](setup.txt).

Đăng nhập ChatGPT qua Codex, tài khoản có quyền tạo ảnh và còn hạn mức. Nút **Kiểm tra ChatGPT** kiểm tra cài đặt, đăng nhập và hạn mức Codex còn lại kèm giờ đặt lại (GMT+7); **Xóa thông báo** chỉ dọn khung thông báo, giữ nguyên kết quả và file chẩn đoán.

Hạn mức được đọc trực tiếp từ Codex, không tạo lượt AI. Nếu dịch vụ chưa trả số liệu, app báo chưa lấy được; tài khoản API chưa hỗ trợ xem số dư. Phần trăm Codex không quy đổi thành số ảnh còn tạo được.

Luồng xử lý: mặc định 1, tối đa 4. Khuyên dùng 1–2; tăng luồng dùng nhiều RAM và hạn mức hơn, có thể làm máy chậm.

Mỗi lượt AI có giới hạn chờ: 3 phút cho nhận diện/kiểm tra/viết chữ, 8 phút cho tạo ảnh. App hiển thị thời gian chờ và lỗi mất kết nối; nếu luồng kết nối không phục hồi trong 60 giây thì dừng tiến trình của lượt đó và giữ URL. Lượt tạo ảnh bị gián đoạn không được tự gửi lại để tránh tạo trùng. Đây là giới hạn cho từng lượt gọi, không phải cam kết tổng thời gian cho một sản phẩm.

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

Kho phòng ăn có 46 ảnh, gồm 38 ảnh bổ sung ngày 26/10/2026 từ gallery của The Appel Shop, The Amish Home Gallery, The Amish Home và Dutch Craft Furniture. Nguồn, hash và kết quả kiểm tra bối cảnh lưu trong `data/source-photos/catalog.json` và `data/dining-gallery-expansion.json`. Có 6 ảnh mới đạt kiểm tra bối cảnh với ảnh sản phẩm bộ bàn 12 ghế đang thử. Kết quả này kiểm tra khả năng bố trí, chưa xác nhận chất lượng ảnh ghép cuối cùng. App ưu tiên ảnh đạt cho đúng hash sản phẩm, bỏ qua ảnh đã bị loại cho hash đó; các ảnh phù hợp được luân phiên theo lịch sử sử dụng và vẫn được kiểm tra trước khi ghép.

Ảnh gốc quyết định sản phẩm xuất hiện như thế nào: mặc, cầm, đặt trong không gian hoặc sử dụng xe. Kết quả FIT/NOFIT đã lưu chỉ được dùng khi khớp cả URL sản phẩm và hash ảnh; hai listing dùng chung ảnh có thể bán kích thước hoặc bộ phận khác nhau. Với bàn, phòng cần có footprint đồ cũ tương đương để thay cục bộ, không chỉ đủ diện tích chung. Bát đĩa hoặc bữa ăn do AI gợi ý trong context không phải điều kiện bắt buộc.

Ảnh mẫu nằm trong data/source-photos/<danh-mục>/, mỗi ảnh có bản ghi trong catalog.json (danh mục, nguồn, SHA256). Danh mục cho từng loại sản phẩm khai báo trong data/product-contexts.json (`source_categories`). Ảnh mẫu chỉ cung cấp người, bố cục và bối cảnh; không thay thế chi tiết của sản phẩm gốc.

Số ảnh mẫu/SP là mức tối đa. Nếu chỉ có một ảnh đạt với người và bối cảnh phù hợp, app dùng bối cảnh thật đó; không có ảnh đạt thì xem mục Báo thiếu ảnh mẫu. Thêm loại sản phẩm mới: tạo thư mục ảnh, thêm bản ghi vào catalog.json và khai báo danh mục trong product-contexts.json.

Với đồ đặt trong không gian như bàn ăn, ảnh phòng được dùng làm nền gốc để ghép, không phải cảm hứng để AI vẽ lại. Chỉ vùng thay bàn ghế, phần nền nhỏ bị lộ và bóng tiếp xúc được phép chỉnh. AI phải cung cấp ảnh ghép và mask cùng kích thước ảnh phòng; mã nguồn khôi phục nguyên pixel nền ngoài mask. Thiếu mask, mask gần toàn ảnh hoặc sai kích thước thì không xuất kết quả. Bước kiểm tra nhận cả ảnh phòng gốc và mask để phát hiện việc thay đổi kiến trúc/đồ vật ngoài sản phẩm trong vùng ghép. Không đổi góc máy, ánh sáng hay phong cách của phòng để làm ảnh đẹp hơn.

Phòng vẫn phải đủ chỗ cho toàn bộ sản phẩm thật. App thử tối đa `MaxTries` ảnh cho đồ vật (mặc định 5), dừng tìm ngay khi có một ảnh đạt và không tìm ảnh thứ hai. Đường dẫn ảnh và kết luận được lưu vào `logs/<mã-SP>-p1-fit-<lượt>.json`; ảnh bị loại có lý do cụ thể. Review chữ và ảnh bối cảnh là hai nguồn dữ liệu riêng: có review chữ chưa có nghĩa là đã có ảnh bối cảnh phù hợp.

## Kết quả: mỗi lần chạy là một thư mục

### Phản bác kết quả và lưu bài học

Bấm **Kiểm tra ảnh / Làm lại** để chọn ảnh kết quả và xem cạnh ảnh sản phẩm gốc. Ghi rõ lỗi (ví dụ: “Thay cả ghế nệm bằng đúng ghế gỗ lưng cong của bộ sản phẩm”), rồi bấm **Lưu và làm lại**. App lưu bản sao đầu vào, ảnh bị phản bác và nội dung yêu cầu; lần làm lại giữ đúng sản phẩm/phòng đã lưu, tạo batch mới và vẫn phải qua QA. AI nhận cả yêu cầu sửa và ảnh lỗi để đối chiếu. Với kết quả cũ chưa lưu context, app nhận diện lại từ ảnh sản phẩm đã lưu, không tải sản phẩm khác.

Tùy chọn **Lưu thành bài học** mặc định áp dụng cho riêng URL sản phẩm; chỉ chọn cả danh mục khi quy tắc thật sự phù hợp với các sản phẩm khác. Các bài học được đưa vào prompt tạo ảnh và QA ở lần chạy sau, không phải huấn luyện lại mô hình. Lưu tại `workspace/feedback/<id>/feedback.json` cùng ảnh lỗi và bản sao `refs/`; không tự ghi đè `AGENTS.md`.

Tab **Bài học & lịch sử** hiển thị phản hồi, trạng thái, lỗi và thư mục kết quả. Có thể bật/tắt bài học, chạy lại phản hồi đã lưu hoặc lượt bị lỗi/dừng. AI qua QA chỉ chuyển sang **chờ bạn kiểm tra**; bấm **Ảnh mới đã đúng** sau khi bạn đã xem kết quả. Nếu còn sai, chọn ảnh mới để phản bác tiếp; manifest liên kết phản hồi trước. Bản cũ và hàng đợi URL chính được giữ nguyên khi làm lại.

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

Logo chỉ được thay bằng brand giả khi thực sự in, khắc, thêu hoặc gắn trên sản phẩm. Watermark ảnh, logo góc, dấu cửa hàng và địa chỉ website phải bị xóa hoàn toàn; không đổi thành logo giả hay đưa lên tường. Sản phẩm không có logo vật lý giữ nguyên trạng thái không thương hiệu.

## Kiểm tra và tài liệu

Chạy **test.cmd** để kiểm tra cú pháp và các bộ kiểm thử offline, không gọi AI trả phí.

- [Chi tiết workflow và cấu trúc mã nguồn](docs/workflow.txt)
