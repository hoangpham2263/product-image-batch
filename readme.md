# Product Review Batch

Ứng dụng tạo ảnh sản phẩm trong bối cảnh tham khảo và nội dung review mẫu, sau đó xuất CSV. Chạy trên Windows và macOS.

## Tải về

**[Tải bản mới nhất](https://github.com/hoangpham2263/product-review-batch/releases/latest/download/product-review-batch.zip)** ([các phiên bản](https://github.com/hoangpham2263/product-review-batch/releases)) → giải nén → mở `start-app.cmd`. Không cần git: mỗi lần mở, app tự tải bản phát hành (Release) mới nhất và giữ nguyên `workspace/` (link, ảnh, kết quả, đăng nhập Drive) và `AGENTS.md`.

| | Mở app | Chạy test |
|---|---|---|
| Windows | `start-app.cmd` | `test.cmd` |
| macOS | dòng lệnh: `pwsh src/run-images.ps1` | `./test.sh` |

App là cửa sổ Windows. Trên macOS chạy lõi xử lý bằng dòng lệnh với PowerShell 7 (`brew install --cask powershell` hoặc `dotnet tool install --global PowerShell`) và Codex CLI đã đăng nhập. Ảnh trên Drive được quản lý ở trang web (GitHub Pages). Máy mới xem [setup.txt](setup.txt).

Đăng nhập ChatGPT qua Codex, tài khoản có quyền tạo ảnh và còn hạn mức. Nút **Kiểm tra ChatGPT** kiểm tra cài đặt, đăng nhập và hạn mức Codex còn lại kèm giờ đặt lại (GMT+7); **Xóa thông báo** chỉ dọn khung thông báo, giữ nguyên kết quả và file chẩn đoán.

Hạn mức được đọc trực tiếp từ Codex, không tạo lượt AI. Nếu dịch vụ chưa trả số liệu, app báo chưa lấy được; tài khoản API chưa hỗ trợ xem số dư. Phần trăm Codex không quy đổi thành số ảnh còn tạo được.

Luồng xử lý: mặc định 1, tối đa 4. Khuyên dùng 1–2; tăng luồng dùng nhiều RAM và hạn mức hơn, có thể làm máy chậm.

Mỗi lượt AI có giới hạn chờ: 3 phút cho nhận diện/kiểm tra/viết chữ, 8 phút cho tạo ảnh. App hiển thị thời gian chờ và lỗi mất kết nối; nếu luồng kết nối không phục hồi trong 60 giây thì dừng tiến trình của lượt đó. Sau khi xác nhận đã dừng, app kiểm tra ảnh đã lưu trước khi tạo lại. Ảnh được tạo một lần rồi xuất cho bạn xem. Tối đa 3 lượt gửi chỉ dành cho lỗi kết nối khi chưa nhận đủ file, dùng nguyên snapshot đầu vào. Lỗi đăng nhập/hết hạn mức không tự thử lại; hết lượt vẫn lỗi thì giữ URL. Đây là giới hạn từng lượt gọi, không phải tổng thời gian một sản phẩm.

## Workflow

| Bước | Xử lý |
|---|---|
| 1. Nhận URL | Đọc danh sách sản phẩm, giữ hàng đợi để có thể chạy lại phần lỗi. |
| 2. Đọc và nhận diện sản phẩm | Tải ảnh gốc, xác định loại sản phẩm từ ảnh. |
| 3. Chọn ảnh tham khảo | Dùng ảnh đã gắn theo URL; chỉ tự tìm trong kho đúng danh mục và kiểm tra phù hợp khi bật fallback. |
| 4. Lưu đầu vào | Sao chép ảnh đã chọn cùng nguồn và SHA256 vào refs/<mã-SP>/. |
| 5. Tạo ảnh | Tạo **một ảnh hoàn chỉnh** theo sản phẩm gốc và bối cảnh tham khảo; giữ hình dáng, màu sắc và hình in. Sản phẩm có logo thì logo được thay đúng chỗ bằng brand giả hợp với sản phẩm và bối cảnh ảnh, mỗi ảnh một tên khác nhau trong batch; không có logo thì không thêm. Không ghép thành nhiều ô. |
| 6. Hoàn tất ảnh | Kiểm tra PNG đọc được rồi xuất nguyên file do AI tạo để người dùng review. |
| 7. Viết review mẫu | Chọn tối đa 3 review tham khảo đúng danh mục từ review-samples.jsonl, xoay vòng mẫu để học cách viết; nội dung mới dựa trên ảnh. Không bắt buộc ngôi thứ nhất, không chép lời khách khác hay thêm trải nghiệm mua hàng. Câu mở đầu kiểu “I like/I love” hoặc chép câu nguồn sẽ được viết lại tối đa một lần; vẫn lỗi thì dừng sản phẩm. |
| 8. Hoàn thiện dữ liệu | Sau khi các luồng ảnh/review kết thúc, máy random tên, sao (55% 5 sao / 45% 4 sao), email @int và ngày; không gọi Codex cho phần này. |

Kho `data/names.txt` có 4.000 tên hiển thị với tên riêng không trùng, giữ 965 tên riêng từ kho cũ và các tên đã bổ sung. Nguồn mở rộng: Names Corpus 1.3 của Mark Kantrowitz, bổ sung bởi Bill Ross, phân phối qua NLTK. Chỉ lưu danh sách tên trong `data/names.txt`; gộp tên riêng không trùng từ kho cũ và nguồn bổ sung, không nhân mỗi tên với chữ cái họ A–Z. Tên hiển thị theo dạng tên riêng + chữ cái đầu của họ, ví dụ Josh K.; mỗi tên riêng chỉ xuất hiện một dòng. Đây là dữ liệu mẫu, không phải danh tính khách hàng.
| 9. Lưu kết quả | Lưu ảnh và `results.json` (chưa tạo file Loox); URL thành công được lấy khỏi hàng đợi, URL lỗi được giữ lại. |
| 10. Duyệt & xuất file | Mỗi đánh giá một dòng, chọn Giữ/Bỏ riêng từng dòng. Bấm thumbnail để xem ảnh lớn và ảnh gốc đối chiếu. Chạy xong app không tự mở cửa sổ; nút Duyệt & xuất file chuyển xanh kèm số ảnh chờ duyệt. Duyệt hết mới tạo `loox_import.csv`, chỉ gồm đánh giá được giữ; bỏ một đánh giá không loại các đánh giá khác cùng sản phẩm. |

### Thư viện ảnh mẫu

Ảnh sản phẩm gốc và ảnh review là hai đầu vào riêng. Mỗi ảnh review được xử lý thành một kết quả độc lập với ảnh gốc của cùng sản phẩm. Mỗi lượt tạo mới nhận đúng một ảnh review và một ảnh sản phẩm gốc, không gộp hai ảnh review hay thêm ảnh phong cách thứ ba. Popup có ô **Ảnh review** bên trái và **Ảnh sản phẩm gốc** bên phải. Ảnh review áo gấp/đặt trên bàn được giữ cách trình bày đó, không bắt buộc có người mẫu.

Web chưa public hoặc không tải được sản phẩm: gắn **Ảnh sản phẩm gốc** và **Ảnh bối cảnh để ghép vào** trong popup. Ảnh sản phẩm được dùng trực tiếp, không truy cập link. Bản web cho phép để trống link khi đã gắn ảnh sản phẩm; bản Windows tự tạo mã local khi chọn ảnh sản phẩm trước khi nhập link. Dán ảnh vào ô đã chọn, kéo thả hoặc chọn file PNG/JPEG. Hai ảnh được lưu snapshot/hash riêng; đổi link không mang ảnh cũ sang và Hủy không thay ảnh đã lưu.

Bấm Thêm sản phẩm để mở popup, dán link rồi Ctrl+V ảnh, chọn file hoặc kéo ảnh vào khung preview. Bấm Lưu sản phẩm: danh sách chính chỉ hiện một dòng nhỏ với link, thumbnail và trạng thái. Bấm dòng hoặc Xem / sửa để mở lại đúng sản phẩm. Hủy không đổi dữ liệu. Thêm nhiều link mở ô nhập nhiều dòng; mỗi link được tạo thành một mục để gắn ảnh sau. Đổi URL không mang ảnh cũ sang; link trùng và ảnh thiếu được kiểm tra trước khi chạy AI. Ảnh được sao chép vào `workspace/reference-inputs/`, kiểm tra SHA256 và lưu trong `refs/` của kết quả.

Mặc định không tự lấy data cho link chưa gắn ảnh. Có thể bật **Cho phép dùng kho data cho các link chưa gắn ảnh**; ảnh bạn đã chỉ định mà bị loại vẫn dừng và báo lý do, không tự thay ảnh khác. Dùng CLI với `-ReferenceMapFile <references.json>`. Đây là cách kiểm soát nguồn ảnh và giảm lặp, không phải cam kết chất lượng ghép.

Kho phòng ăn có 46 ảnh, gồm 38 ảnh bổ sung ngày 26/10/2026 từ gallery của The Appel Shop, The Amish Home Gallery, The Amish Home và Dutch Craft Furniture. Nguồn, hash và kết quả kiểm tra bối cảnh lưu trong `data/source-photos/catalog.json` và `data/dining-gallery-expansion.json`. Có 6 ảnh mới đạt kiểm tra bối cảnh với ảnh sản phẩm bộ bàn 12 ghế đang thử. Kết quả này kiểm tra khả năng bố trí, chưa xác nhận chất lượng ảnh ghép cuối cùng. App ưu tiên ảnh đạt cho đúng hash sản phẩm, bỏ qua ảnh đã bị loại cho hash đó; các ảnh phù hợp được luân phiên theo lịch sử sử dụng và vẫn được kiểm tra trước khi ghép.

Ảnh gốc quyết định sản phẩm xuất hiện như thế nào: mặc, cầm, đặt trong không gian hoặc sử dụng xe. Kết quả FIT/NOFIT đã lưu chỉ được dùng khi khớp cả URL sản phẩm và hash ảnh; hai listing dùng chung ảnh có thể bán kích thước hoặc bộ phận khác nhau. Với bàn, phòng cần có footprint đồ cũ tương đương để thay cục bộ, không chỉ đủ diện tích chung. Bát đĩa hoặc bữa ăn do AI gợi ý trong context không phải điều kiện bắt buộc.

Kho chung nằm trong `data/source-photos/<nhóm-hàng>/`, không chia theo website. `Áo` chứa nhóm áo, `Nội thất` chứa nội thất; các ảnh khác giữ trong `Cốc và bình`, `Trang trí nhà cửa`, `Phụ kiện`, `Mũ`, `Đồ bếp`, `Thể thao ngoài trời`, `Đồ thú cưng`, `Quần đùi`, `Đồ lót`, `Đồng phục` để dùng lại sau. Ảnh kho nằm trên Google Drive (`Product Image Batch/Nguồn ảnh/<nhóm>/`), không nằm trong Git: thêm/xoá ảnh và tạo nhóm ở tab **Nguồn ảnh** của trang quản lý. Khi chạy có bật dùng kho ảnh, app chỉ tải nhóm đã chọn về `data/source-photos/<nhóm>/` và chỉ tải lại ảnh mới hoặc đã đổi. 3.111 ảnh cũ được thu về cạnh dài tối đa 1280 px (JPEG); `catalog.json` giữ nguồn, hash mới và tên cũ trong `previous_files`. Có thể thêm ảnh vào `data/source-photos/<nhóm>/` trên máy rồi chạy `node tools/upload-sources.mjs` để đẩy ảnh mới lên Drive (ảnh trùng tên đã có thì bỏ qua). Trong popup, chọn **Kho ảnh** rồi **Chọn ảnh** để mở đúng thư mục, hoặc **Mở thư mục** để xem kho; nhóm đã lưu được nhớ cho lần sau.

Mỗi ảnh có bản ghi trong catalog.json (nhóm lưu trữ `source_group`, danh mục sản phẩm `category`, nguồn, SHA256 và đường dẫn cũ). Nhóm thư mục chỉ giúp chọn file; danh mục chi tiết cho từng loại sản phẩm vẫn khai báo trong data/product-contexts.json (`source_categories`). Ảnh mẫu chỉ cung cấp người, bố cục và bối cảnh; không thay thế chi tiết của sản phẩm gốc.

Mỗi lượt dùng đúng một ảnh review cùng một ảnh sản phẩm gốc. Khi bật tìm trong kho, app dừng sau ảnh review đầu tiên đạt; không có ảnh đạt thì xem mục Báo thiếu ảnh mẫu. Thêm loại sản phẩm mới: tạo thư mục ảnh, thêm bản ghi vào catalog.json và khai báo danh mục trong product-contexts.json.

Với đồ đặt trong không gian như bàn ăn, AI chỉnh sửa trực tiếp ảnh phòng tham khảo để thay sản phẩm, giữ góc máy, ánh sáng và đồ vật không liên quan. App xuất nguyên file PNG do AI tạo để bạn xem và yêu cầu sửa nếu cần.

Phòng vẫn phải đủ chỗ cho toàn bộ sản phẩm thật. App thử tối đa `MaxTries` ảnh cho đồ vật (mặc định 5), dừng tìm ngay khi có một ảnh đạt và không tìm ảnh thứ hai. Đường dẫn ảnh và kết luận được lưu vào `logs/<mã-SP>-p1-fit-<lượt>.json`; ảnh bị loại có lý do cụ thể. Review chữ và ảnh bối cảnh là hai nguồn dữ liệu riêng: có review chữ chưa có nghĩa là đã có ảnh bối cảnh phù hợp.

## Kết quả: mỗi lần chạy là một thư mục

### Phản bác kết quả và lưu bài học

Bấm **Kiểm tra ảnh / Làm lại** để chọn ảnh kết quả và xem cạnh ảnh sản phẩm gốc. Ghi rõ lỗi (ví dụ: “Thay cả ghế nệm bằng đúng ghế gỗ lưng cong của bộ sản phẩm”), rồi bấm **Lưu và làm lại**. App lưu bản sao đầu vào, ảnh bị phản bác và nội dung yêu cầu; lần làm lại giữ đúng sản phẩm/phòng đã lưu, tạo một kết quả mới để bạn xem. AI nhận cả yêu cầu sửa và ảnh lỗi để đối chiếu. Với kết quả cũ chưa lưu context, app nhận diện lại từ ảnh sản phẩm đã lưu, không tải sản phẩm khác.

Tùy chọn **Lưu thành bài học** mặc định áp dụng cho riêng URL sản phẩm; chỉ chọn cả danh mục khi quy tắc thật sự phù hợp với các sản phẩm khác. Bài học nằm tập trung trong phần Saved user lessons của `AGENTS.md` và được đọc trực tiếp vào prompt theo đúng URL/danh mục. App cập nhật riêng phần đó khi lưu hoặc bật/tắt bài học; các hướng dẫn khác được giữ nguyên. `workspace/feedback/<id>/feedback.json` cùng ảnh lỗi và `refs/` là lịch sử lần chạy, không phải nguồn bài học.

Tab **Bài học & lịch sử** hiển thị phản hồi, trạng thái, lỗi và thư mục kết quả. Có thể bật/tắt bài học, chạy lại phản hồi đã lưu hoặc lượt bị lỗi/dừng. Ảnh tạo xong chuyển sang **chờ bạn kiểm tra**; bấm **Ảnh mới đã đúng** sau khi bạn đã xem kết quả. Nếu còn sai, chọn ảnh mới để phản bác tiếp; manifest liên kết phản hồi trước. Bản cũ và hàng đợi URL chính được giữ nguyên khi làm lại.

```
workspace/output/<thời-gian>/
  images/<mã-SP>.png      ảnh kết quả
  refs/<mã-SP>/           bản sao ảnh đầu vào + manifest.json (vai trò, nguồn, SHA256)
  logs/                   log AI, lỗi từng sản phẩm, run.log, rejected/ (ảnh bị loại)
    <mã-SP>-review-sources.json  các review tham khảo thực tế đã chọn
  results.json            kết quả chờ duyệt (review.json: Giữ/Bỏ từng dòng)
  loox_import.csv         chỉ có sau khi duyệt xong: product_handle, rating, author, email, body, created_at, photo_url, verified_purchase
  urls.input.txt          danh sách URL đầu vào
  urls.completed.txt      URL đã xong
  missing-data.csv        (nếu có) sản phẩm thiếu ảnh mẫu
```

CSV Loox dùng header đúng template tải từ Loox, UTF-8 không BOM, ngày `YYYY-MM-DD`, boolean `TRUE`/`FALSE`. Khi import, chọn **Custom File** trong Loox. CSV từ trang quản lý Drive là danh sách ảnh, không thay thế file review này.

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

## Tạo ảnh bằng ChatGPT web hoặc Google Flow

Ngoài Codex CLI, app có thể tạo ảnh trong tab ChatGPT / Google Flow đang đăng nhập trên Chrome:

```
app (PowerShell) → bridge/ (Node, 127.0.0.1:8765) → extension/ (Chrome) → tab ChatGPT / Flow
```

1. Chạy `setup.cmd` (cài `bridge/`).
2. Chrome → `chrome://extensions` → bật Developer mode → **Load unpacked** → chọn thư mục `extension/`.
3. Mở tab ChatGPT và một dự án Google Flow (`flow.google.com/project/...`), đã đăng nhập.
4. Chạy với `-ImageBackend chatgpt` hoặc `-ImageBackend flow` (hoặc đặt biến môi trường `PIB_IMAGE_BACKEND`). App tự bật bridge.

- **ChatGPT:** tự động hoàn toàn: dán ảnh tham khảo, gửi prompt, đọc ảnh mới qua API của trang (`/backend-api/my/recent/image_gen`) và tải PNG gốc.
- **Google Flow:** Flow chỉ nhận cú bấm thật, nên extension dán ảnh, điền prompt, đưa tab lên trước và viền vàng nút **Bắt đầu tạo**; bấm 1 lần, phần còn lại tự động.
- Mỗi lần tạo tính vào hạn mức của tài khoản ChatGPT / Flow đang đăng nhập.

## Lưu ảnh lên Google Drive và quản lý

`worker/` là Cloudflare Worker `product-images-api` (cùng mẫu với memories-api): ảnh nằm trong thư mục Drive riêng `Product Image Batch/<batch>/`, CSV dùng link cố định `https://product-images-api…/img/<id>.png`.

Cài một lần:

1. Google Cloud Console: thêm redirect URI `https://product-images-api.hoangpham2263.workers.dev/oauth/callback` vào OAuth client đang dùng cho memories.
2. Trong `worker/`: `npx wrangler kv namespace create STORE`, dán id vào `wrangler.toml`, rồi `npx wrangler secret put GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `ADMIN_PASSWORD` và `npx wrangler deploy`.
3. Trong app, bấm **Google Drive** và nhập mật khẩu quản lý (mỗi máy một lần). App kiểm tra mật khẩu rồi lưu vào `workspace/drive.json` (không lên Git).
4. Mở trang quản lý `docs/index.html` (GitHub Pages: Settings → Pages → `main` / `docs`), nhập mật khẩu, bấm **Kết nối Drive**.

App kiểm tra đăng nhập/kết nối Drive trước khi tạo ảnh. Mỗi luồng tạo xong ảnh thì tải ảnh đó lên Drive ngay (song song); upload lỗi được thử lại cuối lượt; chỉ ảnh có link HTTPS công khai mới được ghi vào CSV bàn giao. Upload tạm lỗi thử tối đa 3 lượt; vẫn lỗi thì giữ URL và lưu ảnh/nội dung tại `workspace/delivery-pending/`. Bấm Bắt đầu sẽ dùng lại các kết quả đã lưu để tiếp tục upload, không gọi AI tạo lại; với nhiều ảnh cùng link, các ảnh đã thành công cũng được dùng lại đến khi cả link hoàn tất. Không thay upload lỗi bằng đường dẫn local. Trang quản lý: lọc theo batch/trạng thái, duyệt, loại, copy link, xoá và tải danh sách link.

CLI có `-LocalOnly` cho kiểm thử hoặc chủ đích chỉ xuất local; đây không phải chế độ bàn giao ảnh công khai cho Loox. Giao diện desktop luôn yêu cầu Drive.

## Cấu trúc thư mục

| Đường dẫn | Nội dung |
|---|---|
| src/ | Mã nguồn: `workflow/steps/01–07`, `application/`, `domain/`, `infrastructure/`, `ui/` |
| data/ | Dữ liệu base trên Git: `source-photos/catalog.json` (ảnh tải từ Drive theo nhóm), names.txt, *.json quy tắc, `image-style/`, review-samples.jsonl (~2.800 review mẫu: nội dung, danh mục, nguồn) |
| bridge/ | Server local nối workflow với extension |
| extension/ | Tạo ảnh qua tab ChatGPT / Google Flow |
| worker/, docs/ | Lưu ảnh lên Google Drive, trang quản lý ảnh (GitHub Pages) |
| tests/ | Kiểm thử offline, chạy bằng test.cmd |
| workspace/ | Mọi file sinh ra, Git bỏ qua: `output/`, `urls.txt` (hàng đợi), `logs/` (log kiểm tra ChatGPT), `temp/`, `tests/` |

Ảnh mẫu chỉ được đọc, không bị sửa hay di chuyển. Tham số CLI -List và -OutDir cho phép chọn đường dẫn riêng.

Logo chỉ được thay bằng brand giả khi thực sự in, khắc, thêu hoặc gắn trên sản phẩm. Watermark ảnh, logo góc, dấu cửa hàng và địa chỉ website phải bị xóa hoàn toàn; không đổi thành logo giả hay đưa lên tường. Sản phẩm không có logo vật lý giữ nguyên trạng thái không thương hiệu.

## Kiểm tra và tài liệu

Chạy **test.cmd** để kiểm tra cú pháp và các bộ kiểm thử offline, không gọi AI trả phí.

- [Chi tiết workflow và cấu trúc mã nguồn](docs/workflow.txt)

Nguồn bổ sung: https://github.com/nltk/nltk_data/blob/gh-pages/packages/corpora/names.zip

Điều khoản gốc của Names Corpus:

```text
Names Corpus, Version 1.3 (1994-03-29)
Copyright (C) 1991 Mark Kantrowitz
Additions by Bill Ross

This corpus contains 5001 female names and 2943 male names, sorted
alphabetically, one per line.

You may use the lists of names for any purpose, so long as credit is
given in any published work. You may also redistribute the list if you
provide the recipients with a copy of this README file. The lists are
not in the public domain (I retain the copyright on the lists) but are
freely redistributable.  If you have any additions to the lists of
names, I would appreciate receiving them.

Mark Kantrowitz <mkant+@cs.cmu.edu>
http://www-2.cs.cmu.edu/afs/cs/project/ai-repository/ai/areas/nlp/corpora/names/
```

## Phát hành phiên bản

Push code lên `main` chưa làm máy khác cập nhật. Muốn phát hành thì tạo tag:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

GitHub Actions tự tạo Release; trong app bấm **Cập nhật** (góc trên bên phải) để tải bản đó và mở lại app. Số phiên bản hiện trên thanh tiêu đề app.
