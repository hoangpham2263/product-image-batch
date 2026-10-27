# Hướng dẫn và bài học của dự án

Áp dụng cho toàn bộ repository Product Image Batch. Đọc file này trước khi sửa workflow, prompt, dữ liệu mẫu hoặc bước kiểm tra. Yêu cầu mới nhất của người dùng được ưu tiên; khi yêu cầu thay đổi, cập nhật bài học liên quan thay vì giữ các quy tắc mâu thuẫn.

## Luồng hiện tại (yêu cầu mới nhất)

- Tạo một kết quả rồi xuất cho người dùng review. Không chạy AI QA sau tạo ảnh, không tự sửa ảnh theo đánh giá AI và không tự lặp preview để cải thiện ảnh. Chỉ sửa khi người dùng yêu cầu.
- Giao diện dùng bố cục cũ: danh sách sản phẩm bên trái, các nút thao tác xếp dọc bên phải, Bắt đầu/Dừng bên dưới danh sách; giữ popup thêm/sửa và mỗi sản phẩm một dòng nhỏ, hạn chế chữ đậm.
- Ảnh người dùng gắn được dùng trực tiếp sau kiểm tra file/hash, không chấm FIT bằng AI. Kho tự tìm chỉ dùng khi bật fallback rõ ràng.
- Xuất nguyên file PNG do AI tạo, giữ nguyên nội dung và byte của ảnh. Chỉ kiểm tra file ảnh có đọc được. Có ảnh xuất nghĩa là chờ người dùng xem, không phải chất lượng đã được AI/người dùng chấp nhận.
- Tối đa 3 lượt gửi chỉ dành cho lỗi kết nối/timeout khi chưa nhận đủ file; đã có ảnh thì xuất trực tiếp, không tạo lại vì nhận xét thẩm mỹ.
- Những mục QA bên dưới là lịch sử lỗi và tiêu chí để soạn prompt/đối chiếu khi người dùng yêu cầu, không kích hoạt vòng AI QA trong luồng hiện tại.

## Mục tiêu đã thống nhất

- Lấy đúng sản phẩm từ URL và đặt vào ảnh phòng có sẵn cho tự nhiên.
- Với nội thất, ảnh phòng là nền để chỉnh sửa cục bộ, không phải gợi ý để AI vẽ lại một phòng khác.
- Ưu tiên đúng sản phẩm và ảnh trông thật. Ảnh đẹp hơn nhưng sai sản phẩm hoặc đổi phòng là kết quả lỗi.

## 1. Phân biệt ảnh sản phẩm và ảnh phòng

- Ảnh sản phẩm gốc quyết định kiểu dáng, vật liệu, màu, vân, chân, lưng ghế, mặt ghế và các thành phần được bán kèm.
- Chú ý chi tiết, không chỉ giống tổng thể: trước khi tạo phải quan sát các phần nhìn thấy trong ảnh sản phẩm và đưa đặc điểm cụ thể vào yêu cầu tạo ảnh. Với áo, chú ý hình cổ, mép viền, thứ tự màu, số/độ rộng sọc, đường may, nút, nẹp, mảng phối và vị trí logo; với sản phẩm khác, áp dụng cùng nguyên tắc cho cấu tạo riêng của nó. Chi tiết nhỏ vẫn là thiết kế sản phẩm, không được tự đơn giản hóa, thêm bớt hoặc lấy từ ảnh người/phòng tham khảo. Phần bị che không được coi là đã xác minh. Ví dụ viền cổ dưới đây minh họa nguyên tắc này, không giới hạn bài học ở một đường viền. Đây là yêu cầu đọc ảnh và soạn prompt kỹ từ đầu, không thêm vòng AI QA hay tự tạo lại.
- Ảnh phòng chỉ quyết định không gian, góc máy, phối cảnh và ánh sáng sẵn có. Không lấy kiểu bàn hoặc ghế trong phòng để thay chi tiết sản phẩm.
- Đối chiếu ảnh thực tế đã tải từ URL và bản sao trong `refs/<mã-SP>/`, không chỉ suy luận từ tên hoặc handle.
- Xác định sản phẩm là bàn riêng hay cả bộ bàn ghế từ nguồn. Không mặc định mọi bàn đều kèm ghế, hoặc mọi ảnh đều cần 12 ghế.
- Nếu nguồn ghi số lượng nhưng ảnh chỉ thể hiện một phần, ghi nhận giới hạn đó; không tự đoán các chi tiết khuất như thể đã xác minh.
- Bài học viền cổ áo (27/10/2026): mẫu polo xanh `work-polo-shirt-logo-shoulder-block` có viền trắng sát mép ngoài cổ; ảnh tạo đã thêm dải xanh mỏng ra ngoài viền trắng. Khi tạo áo phải giữ đúng vị trí, thứ tự màu, số sọc và độ rộng tương đối của viền cổ/tay theo ảnh sản phẩm; không lấy viền từ áo người mẫu hoặc tự thêm đường màu. Đối chiếu cận hai bên cổ với `02-product.jpg` đã lưu trong refs; chỉ kết luận phần nhìn thấy, không coi đổi góc/ánh sáng là lý do đổi cấu trúc viền. Không áp thiết kế viền trắng này cho mẫu áo khác. Đã xác minh sai khác ở ảnh hiện tại; chưa tạo lại để chứng minh lỗi đã hết.

## 2. Bài học: chỉ đổi mặt bàn, giữ ghế phòng mẫu là sai với sản phẩm cả bộ

Trong lần thử bộ bàn ăn gỗ me tây, kết quả có bàn gỗ nhưng giữ các ghế bọc nệm trắng của phòng. Người dùng đã chỉ ra ảnh gốc có bàn gỗ nguyên tấm, chân gỗ dạng khối và ghế gỗ lưng cong, mặt đan. Mô tả trước đó của trợ lý về ghế cũng không chính xác.

- Với sản phẩm bán cả bộ, phải thay cả bàn và các ghế liên quan bằng đúng bộ từ nguồn.
- Người dùng bổ sung cho bàn ăn/bàn trà: ghế hiện có ngay quanh bàn cũng phải đồng bộ phong cách và tỉ lệ sử dụng với bàn mới, kể cả khi chỉ bán bàn. Lượt bàn trà oval ngày 27/10 vẫn giữ bốn ghế ăn đen cao từ phòng bếp, trong khi ảnh sản phẩm là bàn thấp trong phòng khách. Phải chỉnh các chỗ ngồi liên quan sang kiểu phù hợp với bàn trà và phong cách ảnh sản phẩm; không mặc định dùng ghế gỗ lưng cong/mặt đan của sản phẩm khác. Đây là yêu cầu phối ghế hiện có, không chứng minh ghế bán kèm. Giữ kiến trúc và đồ không liên quan; không tự thêm chỗ ngồi hay chuyển toàn phòng thành phòng khác.
- Khi chỉnh sửa bằng AI, thay đủ thành phần sản phẩm được yêu cầu, không chỉ đổi mặt bàn rồi giữ ghế sai.
- Không tự phối thêm ghế sofa, ghế nệm hoặc kiểu ghế khác khi người dùng yêu cầu giữ sản phẩm gốc.
- QA phải so từng thành phần: hình mặt bàn, độ dày, cạnh, vân, chân đỡ, kiểu lưng và mặt ghế, số lượng theo nguồn. Không chỉ kiểm tra có một bàn gỗ trong phòng.
- Phối cảnh và bóng tiếp xúc có thể điều chỉnh để ghép tự nhiên; không dùng việc đó để biện minh cho việc đổi thiết kế.
- Đây là lỗi đã được người dùng chỉ ra, không phải tính năng phối nội thất theo ý thích. Ghi bài học không có nghĩa lỗi tạo ảnh đã được sửa và kiểm chứng.

## 3. Giữ phòng gốc và giới hạn của cam kết 100%

- Giữ nguyên canvas, góc máy, tường, sàn, cửa, cửa sổ và đồ vật không liên quan.
- Chỉ chỉnh vùng thay sản phẩm, nền nhỏ lộ ra khi bỏ đồ cũ và bóng tiếp xúc cần thiết. Không trang trí thêm hoặc làm lại ánh sáng toàn phòng.
- Người dùng đã chốt: không có trong ảnh gốc thì không tự thêm để làm cảnh “tự nhiên”. Khoảng trống/mặt bàn trống phải giữ trống. Chỉ thêm sản phẩm đích và thành phần người dùng yêu cầu rõ; giữ đồ vốn có trong phòng, không mang bát đĩa/cây/sách/người/đồ trang trí từ ảnh sản phẩm sang phòng. QA phải loại đồ thêm không được yêu cầu, không chỉ coi chúng là “không bắt buộc”.
- Không cam kết AI giữ chính xác 100% hình dáng/vân của sản phẩm chỉ vì prompt yêu cầu. Phải xem ảnh kết quả và nói rõ giới hạn thực tế.

## 4. Logo và watermark

- Chỉ thay bằng thương hiệu giả khi logo thực sự in, khắc, thêu hoặc gắn trên sản phẩm, và đặt đúng vị trí vật lý đó.
- Sản phẩm không có logo vật lý thì không thêm logo, chữ góc ảnh hoặc biển tên trên tường.
- Watermark, logo cửa hàng ở góc và địa chỉ web là lớp phủ ảnh, không phải thương hiệu gắn trên sản phẩm.
- Không biến watermark thành logo giả. Với ảnh phòng cần giữ nguyên, loại ảnh có watermark trước khi chọn nền.
- Logo giả phải là thiết kế hoàn chỉnh; không có chữ như “put your brand on it”, “your logo” hay hướng dẫn điền tên.

## 5. Kho ảnh mẫu: số lượng chưa đủ để chứng minh phù hợp

- Kho local dùng tên tiếng Việt có dấu cho thư mục nhóm hàng chung, không chia theo website: `Áo` cho áo, `Nội thất` cho nội thất và các nhóm khác theo hàng thực tế. Không gọi kho áo là `clothes` rồi ngầm hiểu có cả quần. Giữ các ảnh thuộc nhóm khác để người dùng dùng sau, không xóa chỉ vì hiện tại hai website chưa bán nhóm đó. `source_group` là nhóm thư mục; giữ `category` chi tiết, nguồn và SHA256 trong catalog để không đổi điều kiện chọn ảnh/bài học. Chuyển thư mục phải đối chiếu hash và giữ lịch sử dùng ảnh.

- Người dùng có thể gắn ảnh riêng theo từng URL bằng dán clipboard, chọn file hoặc kéo thả. Ảnh đã gắn phải được ưu tiên và lưu snapshot/hash; không tự lấy ảnh cho link khác. Nếu ảnh chỉ định bị loại, báo lý do và dừng, không âm thầm thay bằng data. Dùng kho cho URL chưa gắn ảnh chỉ khi người dùng bật fallback rõ ràng. Cách này giảm trùng ảnh do chọn tự động nhưng không bảo đảm AI ghép đúng; vẫn cần kiểm tra tỉ lệ, vùng thay thế và QA.
- Người dùng đã đổi yêu cầu: thêm/sửa link và ảnh trong popup, lưu xong hiển thị một dòng nhỏ có thumbnail và trạng thái; bấm dòng để preview/sửa đúng sản phẩm, không chọn lại link. Hỗ trợ số lượng lớn, hạn chế chữ đậm. Hủy popup không được thay đổi dữ liệu. Đổi URL không được mang ảnh của URL cũ sang. Kiểm tra link trùng/thiếu ảnh trước khi gọi AI để tránh tốn lượt mới phát hiện lỗi nhập.

- Chọn đúng danh mục, kiểm tra phòng có đủ chỗ cho toàn bộ sản phẩm, góc ghép và mặt sàn có phù hợp, ảnh có đủ nét không.
- Phòng cho bàn nhỏ không tự nhiên phù hợp với bộ bàn lớn. Góc rộng không chứng minh phòng có thêm diện tích.
- Tránh ảnh CGI, collage, ảnh cận chỉ thấy sản phẩm, ảnh có watermark hoặc đồ vật che khuất vùng ghép.
- Luân phiên các ảnh phù hợp theo lịch sử dùng. Không để ưu tiên loại nguồn khiến một ảnh độc chiếm mọi lần chạy.
- Kết quả FIT/NOFIT đã lưu cho một hash ảnh sản phẩm chỉ áp dụng cho đúng hash đó. FIT là đánh giá bối cảnh, chưa chứng minh ảnh ghép cuối cùng thành công.
- Cache FIT/NOFIT phải khớp cả URL sản phẩm và hash ảnh, vì các listing có thể dùng chung ảnh nhưng bán kích thước/bộ phận khác. Không quy lỗi cho cache nếu chưa kiểm tra hash thật. Ở lượt lỗi 14:54 ngày 26/10/2026, hash không khớp cache bộ 12 ghế; AI đã trực tiếp chấm FIT cho phòng bàn tiệc quá dài. Kiểm tra footprint thay thế tương đương, không chỉ phòng đủ rộng; không kéo dài sản phẩm để lấp footprint đồ cũ.
- “Bày cho bữa ăn”, bát đĩa, sách và đồ trang trí do AI gợi ý trong context không phải yêu cầu người dùng. Không loại bàn trống vì thiếu các món đó. Phản hồi người dùng về kiểu ghế vẫn phải được áp dụng, kể cả khi ghế không được xác minh là hàng bán kèm.
- Dữ liệu bổ sung phải có file thật, nguồn, SHA256, kích thước và ghi nhận kiểm tra. Phân biệt ảnh gallery khách hàng, ảnh nhà sản xuất và ảnh review; không gắn nhãn Judge.me khi nguồn không phải Judge.me.
- Có review chữ không có nghĩa đã có ảnh phòng phù hợp. Không có ảnh đạt thì lưu missing-data và giữ URL để thử lại, không tự tạo một phòng thay thế.
- Xem inventory trong catalog; không coi số lượng ghi trong tài liệu là số liệu luôn cập nhật.

## 6. Review mẫu

- Phải đọc và đưa các review tham khảo đúng danh mục vào luồng viết thực tế; chỉ tải về mà không dùng thì chưa hoàn thành.
- Học cách diễn đạt và độ dài, không chép nội dung hoặc trải nghiệm của người khác.
- Không ép mọi câu mở đầu bằng “I like”, “I love”, “tôi thích”. Luân phiên mẫu và kiểm tra câu mở đầu rập khuôn.
- Không bịa trải nghiệm giao hàng, mua hàng hoặc sử dụng. Đầu ra là dữ liệu mẫu được tạo, không phải lời chứng thực của khách thật.

## 7. Thời gian chạy và báo cáo kết quả

- Bài học lỗi màu: đã có lượt QA lần 1 chê bàn đỏ không giống bảng màu của phòng, sửa nhạt rồi QA lần 2 chê mất màu/vân gốc. Tạo ảnh và QA phải dùng cùng tiêu chí: phản hồi màu chưa hòa với phòng mặc định yêu cầu sửa ánh sáng, cân bằng trắng và bóng cục bộ, không phải đổi màu vật liệu. Chỉ đổi stain/màu gỗ khi người dùng yêu cầu rõ. Không bắt các đồ nội thất khác vật liệu có cùng màu, cũng không bắt RGB giống ảnh nguồn dưới ánh sáng khác. Hiển thị lý do QA khi sửa và khi dừng để người dùng không bị yêu cầu thử lại mù.

- Phân biệt thời gian từng lượt AI với tổng thời gian một sản phẩm; không hứa một sản phẩm hoàn tất trong giới hạn của một lượt.
- Có một phòng đạt cho đồ vật thì dừng chọn; không tiếp tục kiểm tra ảnh thứ hai chỉ vì cấu hình số ảnh tối đa là 2.
- Người dùng cho phép tự thử lại khi timeout/mất kết nối: tối đa 3 lượt gửi do lỗi kết nối/timeout, dùng cùng snapshot đầu vào, dừng khi nhận được ảnh. Chỉ thử sau khi xác nhận tiến trình cũ đã dừng; nếu đã có ảnh thì xuất nguyên file cho người dùng review, không tạo trùng ngay. Không thử lại lỗi đăng nhập/hết hạn mức/đầu vào sai. Hiển thị số lượt, giữ timeout và lý do khi hết lượt; không đánh dấu ảnh đã được người dùng duyệt khi chưa có xác nhận.
- Chỉ kết thúc tiến trình thuộc lượt gọi của workflow; không tắt các tiến trình không liên quan.
- Báo riêng: code đã sửa, test offline đã pass, ảnh đã được tạo thật, ảnh đã được xem và đối chiếu. Không dùng test mock để tuyên bố chất lượng ảnh thực tế đã đạt.
- Không nói đã cập nhật Git nếu chưa commit/push thành công. Khi người dùng yêu cầu cập nhật Git, kiểm tra diff để giữ các thay đổi đang có và không đưa output tạm vào repository.

## Vị trí cần đọc khi sửa

- `src/workflow/steps/02-select-references.ps1`: chọn và kiểm tra phòng.
- `src/workflow/steps/03-create-image.ps1`: yêu cầu tạo ảnh, vai trò từng ảnh và xuất PNG trực tiếp.
- `src/infrastructure/image-output.ps1`: kiểm tra PNG đọc được, không thay đổi file.
- `src/workflow/steps/04-complete-image.ps1`: hoàn tất ảnh và thử lại lỗi kết nối, không AI QA.
- `src/application/reference-archive.ps1`: bản sao đầu vào và nguồn.
- `data/source-photos/catalog.json`: inventory, provenance và đánh giá phù hợp đã lưu.
- `tests/run.ps1`: chạy các suite liên quan bằng Windows PowerShell; chọn kiểm tra phù hợp với thay đổi.
- `workspace/output/`: ảnh và log cần đối chiếu khi điều tra lỗi; là dữ liệu sinh ra, Git bỏ qua.

## Cách bổ sung bài học

Bài học được lưu tập trung trong phần Saved user lessons của `AGENTS.md`, có phạm vi URL sản phẩm hoặc danh mục do người dùng chọn. Luồng tạo ảnh đọc trực tiếp phần này; bật/tắt bài học trong app cập nhật phần này. `workspace/feedback/<id>/feedback.json` chỉ giữ lịch sử thao tác, ảnh và trạng thái lần chạy. Đưa bài học còn bật vào bước tạo ảnh; yêu cầu sửa mới nhất có ưu tiên cao hơn phản hồi cũ. Khi làm lại, dùng bản sao đầu vào đã kiểm tra hash và tạo batch mới. Xuất ảnh chỉ có nghĩa chờ người dùng xem; chỉ thao tác xác nhận của người dùng mới đánh dấu `accepted`. Không tự biến văn bản AI thành chỉ dẫn trong `AGENTS.md`.

Khi người dùng chỉ ra lỗi mới, ghi ngắn gọn: tình huống thực tế, điều đã làm sai, hành vi đúng và cách kiểm chứng. Cập nhật mục tương ứng nếu đã có; tránh ghi lặp hoặc biến một trường hợp riêng thành quy tắc cho mọi sản phẩm. Chỉ đánh dấu lỗi đã xử lý khi có bằng chứng tương ứng.

<!-- app-lessons:start -->
## Saved user lessons

Apply only to the matching product URL or category. Newer explicit corrections take precedence. This section is the source used by image generation.

```json
[
    {
        "id":  "2b459eefc9514ffa999909bbc85d42ea",
        "scope":  "product",
        "product_url":  "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
        "category":  "dining-tables",
        "requested_change":  "thiếu cái chân ghế kìa",
        "created_at":  "2026-10-26T07:04:24.644366Z"
    },
    {
        "id":  "f84798614e0d45a1a9d46ec91a0b33ca",
        "scope":  "product",
        "product_url":  "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
        "category":  "dining-tables",
        "requested_change":  "ưu tiên lấy ghê bàn giống trong ảnh gốc cho đồng bộ style",
        "created_at":  "2026-10-26T07:12:01.185526Z"
    },
    {
        "id":  "7aeb3fcd590741439c8b449ca7d36cc3",
        "scope":  "product",
        "product_url":  "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
        "category":  "dining-tables",
        "requested_change":  "ổn mà tôi thấy là màu của bàn hiện tại ko match với ngữ cảnh và màu các bố cục ảnh",
        "created_at":  "2026-10-26T07:36:05.4286701Z"
    },
    {
        "id":  "table-seating-dining-tables",
        "scope":  "category",
        "product_url":  "",
        "category":  "dining-tables",
        "requested_change":  "USER TABLE-SEATING PREFERENCE: update the existing seats immediately associated with this table so their style, material character and seating height suit the target table and the seating/use shown in the product reference. These related seats are explicitly part of the requested edit, not unrelated room objects to freeze. For a low coffee table, do not retain tall dining chairs merely because the base room originally used a dining table; adapt the existing seating to appropriate low lounge seating consistent with the reference. For a dining table, use dining-height seating. Where a set is sold, preserve its actual chairs; where only the table is sold, this seating styling does not imply chairs are included. Do not reuse curved wooden backs or woven seats from another product unless supported by the current reference. Replace existing related seats only; do not add extra seats, props, a new room, or redesign architecture. Keep unrelated furniture unchanged. A newer explicit user correction overrides this default preference.",
        "created_at":  "2026-10-27T06:48:09.3468036Z"
    },
    {
        "id":  "table-seating-coffee-table",
        "scope":  "category",
        "product_url":  "",
        "category":  "coffee-table",
        "requested_change":  "USER TABLE-SEATING PREFERENCE: update the existing seats immediately associated with this table so their style, material character and seating height suit the target table and the seating/use shown in the product reference. These related seats are explicitly part of the requested edit, not unrelated room objects to freeze. For a low coffee table, do not retain tall dining chairs merely because the base room originally used a dining table; adapt the existing seating to appropriate low lounge seating consistent with the reference. For a dining table, use dining-height seating. Where a set is sold, preserve its actual chairs; where only the table is sold, this seating styling does not imply chairs are included. Do not reuse curved wooden backs or woven seats from another product unless supported by the current reference. Replace existing related seats only; do not add extra seats, props, a new room, or redesign architecture. Keep unrelated furniture unchanged. A newer explicit user correction overrides this default preference.",
        "created_at":  "2026-10-27T06:48:09.3592337Z"
    },
    {
        "id":  "polo-shoulder-block-collar-edge-20261027",
        "scope":  "product",
        "product_url":  "https://forteraapparel.com/products/work-polo-shirt-logo-shoulder-block",
        "category":  "polo-shirts",
        "requested_change":  "Giữ đúng viền cổ theo ảnh sản phẩm gốc của mẫu polo xanh này: sọc trắng chạy sát mép ngoài cổ, không có dải xanh hẹp nằm ra ngoài sọc trắng. Ảnh tạo ngày 27/10/2026 đã thêm dải xanh bên ngoài viền trắng, làm sai thiết kế. Giữ vị trí, thứ tự màu, số sọc và độ rộng tương đối của viền ở cả hai bên cổ; không sao chép cấu trúc viền của áo người trong ảnh tham khảo. Đổi góc nhìn, nếp gấp và ánh sáng không được biến viền trắng sát mép thành sọc trắng nằm lọt trong nền xanh. Đối chiếu phần cổ nhìn thấy với ảnh sản phẩm đã lưu tại refs/001-work-polo-shirt-logo-shoulder-block/02-product.jpg của batch 2026-10-27_15-46-36-685-6ccd8b. Đây là quy tắc riêng mẫu áo này, không ép mẫu khác dùng cùng viền. Chỉ sửa chi tiết người dùng yêu cầu; không tự tạo thêm lượt QA hoặc tạo lại khi chưa được yêu cầu.",
        "created_at":  "2026-10-27T16:03:29.9593975+07:00"
    },
    {
        "id":  "polo-detail-fidelity-20261027",
        "scope":  "category",
        "product_url":  "",
        "category":  "polo-shirts",
        "requested_change":  "Chú ý từng chi tiết áo, không chỉ làm giống tổng thể. Trước khi tạo, quan sát ảnh sản phẩm và giữ chính xác hình cổ, vị trí mép viền, thứ tự màu, số sọc và độ rộng tương đối, đường may, nút, nẹp, mảng phối vai/tay và vị trí logo theo quy tắc thương hiệu hiện có. Không tự thêm/bớt dải màu, đơn giản hóa thiết kế hoặc lấy chi tiết áo người mẫu từ ảnh tham khảo. Mỗi mẫu có thiết kế riêng: không dùng cấu trúc viền của mẫu khác. Chi tiết bị che phải ghi nhận chưa xác minh; góc nhìn và ánh sáng chỉ đổi cách nhìn, không đổi cấu tạo. Lỗi thêm dải xanh ra ngoài viền trắng ở mẫu shoulder-block là ví dụ về sai chi tiết, không phải quy tắc mọi polo đều có viền trắng. Áp dụng khi đọc ảnh và soạn yêu cầu tạo ngay từ đầu; giữ luồng tạo một lần để người dùng review, không thêm AI QA hay tự tạo lại.",
        "created_at":  "2026-10-27T16:04:20.7937109+07:00"
    }
]
```
<!-- app-lessons:end -->
