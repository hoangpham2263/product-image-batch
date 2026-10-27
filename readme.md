# Product Image Batch

Ứng dụng Windows tạo ảnh sản phẩm trong bối cảnh tham khảo và nội dung review mẫu, sau đó xuất CSV.

Nhấp đúp **[start-app.cmd](start-app.cmd)** ở thư mục gốc để mở giao diện. Bấm **Hướng dẫn** trong app để xem cách dùng. Máy mới xem [setup.txt](setup.txt).

Đăng nhập ChatGPT qua Codex, tài khoản có quyền tạo ảnh và còn hạn mức. Nút **Kiểm tra ChatGPT** kiểm tra cài đặt, đăng nhập và hạn mức Codex còn lại kèm giờ đặt lại (GMT+7); **Xóa thông báo** chỉ dọn khung thông báo, giữ nguyên kết quả và file chẩn đoán.

Hạn mức được đọc trực tiếp từ Codex, không tạo lượt AI. Nếu dịch vụ chưa trả số liệu, app báo chưa lấy được; tài khoản API chưa hỗ trợ xem số dư. Phần trăm Codex không quy đổi thành số ảnh còn tạo được.

Luồng xử lý: mặc định 1, tối đa 4. Khuyên dùng 1–2; tăng luồng dùng nhiều RAM và hạn mức hơn, có thể làm máy chậm.

Mỗi lượt AI có giới hạn chờ: 3 phút cho nhận diện/kiểm tra/viết chữ, 8 phút cho tạo ảnh. App hiển thị thời gian chờ và lỗi mất kết nối; nếu luồng kết nối không phục hồi trong 60 giây thì dừng tiến trình của lượt đó. Sau khi xác nhận đã dừng, app kiểm tra ảnh đã lưu trước khi tạo lại. Ảnh được tạo một lần rồi xuất cho bạn review, không AI QA hoặc tự sửa. Tối đa 3 lượt gửi chỉ dành cho lỗi kết nối khi chưa nhận đủ file, dùng nguyên snapshot đầu vào. Lỗi đăng nhập/hết hạn mức không tự thử lại; hết lượt vẫn lỗi thì giữ URL. Đây là giới hạn từng lượt gọi, không phải tổng thời gian một sản phẩm.

## Workflow

| Bước | Xử lý |
|---|---|
| 1. Nhận URL | Đọc danh sách sản phẩm, giữ hàng đợi để có thể chạy lại phần lỗi. |
| 2. Đọc và nhận diện sản phẩm | Tải ảnh gốc, xác định loại sản phẩm từ ảnh. |
| 3. Chọn ảnh tham khảo | Lấy ảnh trong data/source-photos/ đúng danh mục theo catalog.json, kiểm tra người và bối cảnh có phù hợp. |
| 4. Lưu đầu vào | Sao chép ảnh đã chọn cùng nguồn và SHA256 vào refs/<mã-SP>/. |
| 5. Tạo ảnh | Tạo **một ảnh hoàn chỉnh** theo sản phẩm gốc và bối cảnh tham khảo; giữ hình dáng, màu sắc và hình in. Sản phẩm có logo thì logo được thay đúng chỗ bằng brand giả hợp với sản phẩm và bối cảnh ảnh, mỗi ảnh một tên khác nhau trong batch; không có logo thì không thêm. Không ghép thành nhiều ô. |
| 6. Hoàn tất ảnh | Kiểm tra PNG đọc được rồi xuất nguyên file do AI tạo để người dùng review. |
| 7. Viết review mẫu | Chọn tối đa 3 review tham khảo đúng danh mục từ review-samples.jsonl, xoay vòng mẫu để học cách viết; nội dung mới dựa trên ảnh. Không bắt buộc ngôi thứ nhất, không chép lời khách khác hay thêm trải nghiệm mua hàng. Câu mở đầu kiểu “I like/I love” hoặc chép câu nguồn sẽ được viết lại tối đa một lần; vẫn lỗi thì dừng sản phẩm. |
| 8. Hoàn thiện dữ liệu | Sau khi các luồng ảnh/review kết thúc, máy random tên, sao, email @int và ngày; không gọi Codex cho phần này. |
| 9. Xuất kết quả | Lưu ảnh và CSV; URL thành công được lấy khỏi hàng đợi, URL lỗi được giữ lại. |

### Thư viện ảnh mẫu

Bấm Thêm sản phẩm để mở popup, dán link rồi Ctrl+V ảnh, chọn file hoặc kéo ảnh vào khung preview. Bấm Lưu sản phẩm: danh sách chính chỉ hiện một dòng nhỏ với link, thumbnail và trạng thái. Bấm dòng hoặc Xem / sửa để mở lại đúng sản phẩm. Hủy không đổi dữ liệu. Thêm nhiều link mở ô nhập nhiều dòng; mỗi link được tạo thành một mục để gắn ảnh sau. Đổi URL không mang ảnh cũ sang; link trùng và ảnh thiếu được kiểm tra trước khi chạy AI. Ảnh được sao chép vào `workspace/reference-inputs/`, kiểm tra SHA256 và lưu trong `refs/` của kết quả.

Mặc định không tự lấy data cho link chưa gắn ảnh. Có thể bật **Cho phép dùng kho data cho các link chưa gắn ảnh**; ảnh bạn đã chỉ định mà bị loại vẫn dừng và báo lý do, không tự thay ảnh khác. Dùng CLI với `-ReferenceMapFile <references.json>`. Đây là cách kiểm soát nguồn ảnh và giảm lặp, không phải cam kết chất lượng ghép.

Kho phòng ăn có 46 ảnh, gồm 38 ảnh bổ sung ngày 26/10/2026 từ gallery của The Appel Shop, The Amish Home Gallery, The Amish Home và Dutch Craft Furniture. Nguồn, hash và kết quả kiểm tra bối cảnh lưu trong `data/source-photos/catalog.json` và `data/dining-gallery-expansion.json`. Có 6 ảnh mới đạt kiểm tra bối cảnh với ảnh sản phẩm bộ bàn 12 ghế đang thử. Kết quả này kiểm tra khả năng bố trí, chưa xác nhận chất lượng ảnh ghép cuối cùng. App ưu tiên ảnh đạt cho đúng hash sản phẩm, bỏ qua ảnh đã bị loại cho hash đó; các ảnh phù hợp được luân phiên theo lịch sử sử dụng và vẫn được kiểm tra trước khi ghép.

Ảnh gốc quyết định sản phẩm xuất hiện như thế nào: mặc, cầm, đặt trong không gian hoặc sử dụng xe. Kết quả FIT/NOFIT đã lưu chỉ được dùng khi khớp cả URL sản phẩm và hash ảnh; hai listing dùng chung ảnh có thể bán kích thước hoặc bộ phận khác nhau. Với bàn, phòng cần có footprint đồ cũ tương đương để thay cục bộ, không chỉ đủ diện tích chung. Bát đĩa hoặc bữa ăn do AI gợi ý trong context không phải điều kiện bắt buộc.

Ảnh mẫu nằm trong data/source-photos/<danh-mục>/, mỗi ảnh có bản ghi trong catalog.json (danh mục, nguồn, SHA256). Danh mục cho từng loại sản phẩm khai báo trong data/product-contexts.json (`source_categories`). Ảnh mẫu chỉ cung cấp người, bố cục và bối cảnh; không thay thế chi tiết của sản phẩm gốc.

Số ảnh mẫu/SP là mức tối đa. Nếu chỉ có một ảnh đạt với người và bối cảnh phù hợp, app dùng bối cảnh thật đó; không có ảnh đạt thì xem mục Báo thiếu ảnh mẫu. Thêm loại sản phẩm mới: tạo thư mục ảnh, thêm bản ghi vào catalog.json và khai báo danh mục trong product-contexts.json.

Với đồ đặt trong không gian như bàn ăn, AI chỉnh sửa trực tiếp ảnh phòng tham khảo để thay sản phẩm, giữ góc máy, ánh sáng và đồ vật không liên quan. App xuất nguyên file PNG do AI tạo để bạn xem và yêu cầu sửa nếu cần.

Phòng vẫn phải đủ chỗ cho toàn bộ sản phẩm thật. App thử tối đa `MaxTries` ảnh cho đồ vật (mặc định 5), dừng tìm ngay khi có một ảnh đạt và không tìm ảnh thứ hai. Đường dẫn ảnh và kết luận được lưu vào `logs/<mã-SP>-p1-fit-<lượt>.json`; ảnh bị loại có lý do cụ thể. Review chữ và ảnh bối cảnh là hai nguồn dữ liệu riêng: có review chữ chưa có nghĩa là đã có ảnh bối cảnh phù hợp.

## Kết quả: mỗi lần chạy là một thư mục

### Phản bác kết quả và lưu bài học

Bấm **Kiểm tra ảnh / Làm lại** để chọn ảnh kết quả và xem cạnh ảnh sản phẩm gốc. Ghi rõ lỗi (ví dụ: “Thay cả ghế nệm bằng đúng ghế gỗ lưng cong của bộ sản phẩm”), rồi bấm **Lưu và làm lại**. App lưu bản sao đầu vào, ảnh bị phản bác và nội dung yêu cầu; lần làm lại giữ đúng sản phẩm/phòng đã lưu, tạo một kết quả mới để bạn review, không chạy AI QA hay tự sửa thêm. AI nhận cả yêu cầu sửa và ảnh lỗi để đối chiếu. Với kết quả cũ chưa lưu context, app nhận diện lại từ ảnh sản phẩm đã lưu, không tải sản phẩm khác.

Tùy chọn **Lưu thành bài học** mặc định áp dụng cho riêng URL sản phẩm; chỉ chọn cả danh mục khi quy tắc thật sự phù hợp với các sản phẩm khác. Bài học nằm tập trung trong phần Saved user lessons của `AGENTS.md` và được đọc trực tiếp vào prompt theo đúng URL/danh mục. App cập nhật riêng phần đó khi lưu hoặc bật/tắt bài học; các hướng dẫn khác được giữ nguyên. `workspace/feedback/<id>/feedback.json` cùng ảnh lỗi và `refs/` là lịch sử lần chạy, không phải nguồn bài học.

Tab **Bài học & lịch sử** hiển thị phản hồi, trạng thái, lỗi và thư mục kết quả. Có thể bật/tắt bài học, chạy lại phản hồi đã lưu hoặc lượt bị lỗi/dừng. Ảnh tạo xong chuyển sang **chờ bạn kiểm tra**; bấm **Ảnh mới đã đúng** sau khi bạn đã xem kết quả. Nếu còn sai, chọn ảnh mới để phản bác tiếp; manifest liên kết phản hồi trước. Bản cũ và hàng đợi URL chính được giữ nguyên khi làm lại.

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
