# Hướng dẫn và bài học của dự án

Áp dụng cho repository Product Image Batch. Đọc trước khi sửa workflow, prompt, giao diện hoặc dữ liệu mẫu. Yêu cầu mới nhất của người dùng có ưu tiên cao nhất; cập nhật quy tắc cũ khi yêu cầu thay đổi, không giữ chỉ dẫn mâu thuẫn.

## 1. Workflow hiện tại

1. Nhận URL và ảnh tham khảo gắn riêng cho từng sản phẩm; kiểm tra link trùng, ảnh thiếu và file/hash trước khi gọi AI.
2. Tải ảnh sản phẩm từ URL và nhận diện sản phẩm từ ảnh thực tế. Ảnh gắn theo URL được dùng trực tiếp; chỉ tự tìm trong kho và kiểm tra FIT khi người dùng bật fallback.
3. Lưu snapshot đầu vào và nguồn vào kết quả của lượt đang chạy. Đọc các bài học còn bật, khớp URL hoặc danh mục từ mục Bài học đã lưu bên dưới; áp dụng yêu cầu sửa hiện tại sau cùng.
4. Tạo một ảnh hoàn chỉnh, kiểm tra PNG đọc được rồi xuất nguyên file AI tạo. Không chấm chất lượng bằng AI sau tạo, không tự sửa hoặc lặp tạo để cải thiện thẩm mỹ.
5. Viết review mẫu từ nguồn tham khảo đúng danh mục, xuất ảnh và CSV. Giữ URL chưa hoàn tất để thử lại. Có ảnh xuất chưa có nghĩa người dùng đã duyệt.
6. Người dùng xem kết quả và yêu cầu sửa khi cần. Làm lại dùng snapshot đầu vào đã kiểm tra hash, lưu batch mới; chỉ người dùng xác nhận mới đánh dấu `accepted`.

Chỉ tự thử lại lỗi kết nối/timeout khi chưa nhận đủ file, tối đa 3 lượt gửi với cùng đầu vào. Phải xác nhận tiến trình cũ đã dừng, tìm ảnh đã lưu trước khi gửi lại; có ảnh thì xuất, không tạo trùng. Lỗi đăng nhập, hết hạn mức hoặc đầu vào sai không tự thử lại. Không chạy lại ảnh hay test khi người dùng đã yêu cầu bỏ qua.

## 2. Đúng sản phẩm và từng chi tiết

- Ảnh sản phẩm quyết định thiết kế, cấu tạo, vật liệu, màu, vân và các thành phần bán kèm. Đọc ảnh đầu vào hiện tại, không chỉ suy luận từ tên hoặc handle.
- Chú ý chi tiết, không chỉ giống tổng thể. Với áo: hình cổ, mép viền, thứ tự màu, số/độ rộng sọc, đường may, nút, nẹp, mảng phối và vị trí logo. Với nội thất: hình dáng, cạnh, độ dày, vân, chân đỡ, lưng/mặt ghế và tỉ lệ. Đưa đặc điểm nhìn thấy cụ thể vào yêu cầu tạo ngay từ đầu.
- Không thêm/bớt hoặc đơn giản hóa chi tiết để ảnh trông đẹp hơn. Không lấy thiết kế sản phẩm từ áo của người mẫu hay đồ trong phòng tham khảo. Góc nhìn và ánh sáng có thể đổi cách hiển thị, không đổi cấu tạo.
- Xác định bàn riêng hay cả bộ từ nguồn; không mặc định có ghế bán kèm hoặc luôn có 12 ghế. Ghi nhận giới hạn của ảnh nguồn; không bịa chi tiết bị che khuất.
- Không hứa giữ chính xác 100% hình dáng/vân chỉ vì prompt có yêu cầu. Khi được yêu cầu kiểm tra ảnh, đối chiếu thực tế và nêu rõ phần chưa xác minh.

## 3. Bối cảnh tự nhiên và ghế đi kèm

- Ảnh tham khảo cung cấp người, không gian, góc máy và ánh sáng; không thay thế thiết kế sản phẩm.
- Với nội thất, dùng ảnh phòng có sẵn làm nền chỉnh sửa. Giữ canvas, góc máy, tường, sàn, cửa, cửa sổ và đồ không liên quan. Chỉ đổi sản phẩm, vùng nền nhỏ lộ ra khi bỏ đồ cũ và bóng tiếp xúc cần thiết.
- Không có trong ảnh gốc thì không tự thêm để dàn cảnh: giữ mặt bàn trống nếu vốn trống, không mang bát đĩa, cây, sách, người hay đồ trang trí từ ảnh sản phẩm sang phòng. Gợi ý trang trí do AI viết trong context không phải yêu cầu người dùng.
- Nếu bán cả bộ, thay đủ bàn và ghế theo nguồn; không chỉ đổi mặt bàn rồi giữ ghế cũ sai kiểu. Theo yêu cầu người dùng, các chỗ ngồi hiện có ngay quanh bàn cũng cần đồng bộ phong cách và chiều cao sử dụng, kể cả khi chỉ bán bàn; không suy ra chúng được bán kèm.
- Bàn trà thấp cần chỗ ngồi phù hợp, không giữ ghế ăn cao chỉ vì có sẵn. Dùng kiểu ghế được nguồn hiện tại hỗ trợ; không áp ghế gỗ cong/mặt đan của một mẫu cho mọi sản phẩm. Không tự thêm số chỗ ngồi hoặc đổi toàn phòng.
- Giữ chân ghế, thanh nối và phần đỡ nhìn thấy liền mạch, hợp phối cảnh và tiếp xúc sàn. Không để sót đồ cũ giao nhau với sản phẩm mới.
- Màu sản phẩm chưa hòa với phòng mặc định cần chỉnh ánh sáng cục bộ, phơi sáng, cân bằng trắng và bóng; giữ màu vật liệu, lớp hoàn thiện và vân. Không đổi màu gỗ cho giống tủ/ghế hoặc làm nhạt vân, trừ khi người dùng yêu cầu đổi màu rõ ràng.

## 4. Logo và chữ

- Chỉ thay thương hiệu khi logo thực sự in, khắc, thêu hoặc gắn trên sản phẩm; giữ vị trí và cách thể hiện vật lý đó. Không có logo vật lý thì không thêm logo, chữ góc ảnh hoặc biển tên trên tường.
- Watermark, logo cửa hàng góc ảnh và địa chỉ web là lớp phủ, không phải logo sản phẩm. Không biến chúng thành thương hiệu giả hoặc đồ vật trong cảnh; tránh chọn ảnh nền có watermark.
- Thương hiệu giả phải hoàn chỉnh, không giữ chữ hướng dẫn như “put your brand on it”, “your logo”, “your brand” hoặc lời nhắc điền tên.

## 5. Giao diện và kho ảnh

- Danh sách bên trái, nút thao tác bên phải, Bắt đầu/Dừng bên dưới. Thêm/sửa trong popup; lưu xong mỗi sản phẩm một dòng nhỏ có thumbnail/trạng thái, bấm để xem lại đúng link/ảnh. Hạn chế chữ đậm, hỗ trợ danh sách lớn.
- Dán clipboard, chọn file hoặc kéo thả ảnh cho từng URL. Đổi URL không mang ảnh cũ sang. Hủy popup không thay dữ liệu. Lưu snapshot/hash; không dùng ảnh của URL khác hoặc âm thầm thay ảnh chỉ định bằng ảnh trong kho.
- Kho dùng tên tiếng Việt có dấu theo nhóm hàng chung như `Áo`, `Nội thất`; không chia theo website, không gọi kho áo là kho cả quần áo. Giữ nhóm khác để dùng về sau. `source_group` là nhóm thư mục; `category` là mã danh mục chi tiết để chọn ảnh và áp dụng bài học.
- Chuyển kho phải cập nhật đường dẫn, giữ nguồn, hash và lịch sử sử dụng. Kiểm tra inventory thực tế trong catalog, không coi số đếm trong tài liệu là luôn cập nhật.
- Khi bật fallback, chọn đúng danh mục, góc ghép, độ nét và diện tích thay thế tương đương; phòng bàn nhỏ hoặc bàn tiệc quá dài không mặc nhiên hợp sản phẩm khác. Không kéo dài sản phẩm để lấp đồ cũ. Tránh CGI, collage, ảnh cận hoặc bị che vùng ghép.
- Luân phiên ảnh phù hợp theo lịch sử. Có một ảnh đạt thì dừng tìm, không cần đủ số ảnh tối đa. FIT/NOFIT đã lưu chỉ áp dụng khi khớp cả URL sản phẩm và hash ảnh; FIT chỉ nói về bối cảnh, không xác nhận chất lượng kết quả.
- Dữ liệu bổ sung cần file thật, nguồn, SHA256, kích thước và ghi nhận kiểm tra. Phân biệt gallery khách hàng, ảnh nhà sản xuất và ảnh review; không gắn nhãn Judge.me cho nguồn khác.
- Có review chữ không có nghĩa có ảnh phù hợp. Khi cần dùng kho mà không có ảnh đạt, lưu missing-data và giữ URL; không tự tạo phòng thay thế.

## 6. Review mẫu và báo cáo

- Đưa review tham khảo đúng danh mục vào luồng viết thực tế. Học cách diễn đạt và độ dài, không chép nội dung hoặc trải nghiệm của người khác.
- Không ép mở đầu bằng “I like”, “I love”, “tôi thích”. Không bịa trải nghiệm mua hàng, giao hàng hay sử dụng. Đây là dữ liệu mẫu được tạo, không phải lời chứng thực khách thật.
- Phân biệt thời gian một lượt AI với tổng thời gian sản phẩm; giữ timeout, tiến độ, số lượt thử và lý do lỗi. Không tắt tiến trình không thuộc lượt workflow.
- Báo riêng code đã sửa, kiểm tra offline, ảnh đã tạo thật và ảnh đã xem đối chiếu. Không dùng mock để khẳng định chất lượng ảnh đã đạt. Ghi bài học không có nghĩa lỗi đã được sửa và kiểm chứng.
- Chỉ nói đã cập nhật Git sau commit/push thành công. Kiểm tra diff, giữ thay đổi đang có và không đưa output tạm vào repository.

## 7. Cách ghi bài học

- Quy tắc chung ở các mục trên dành cho người/agent sửa dự án. Các bài học theo URL/danh mục mà luồng tạo ảnh đọc nằm trong khối dữ liệu bên dưới. Không chỉ thêm văn xuôi rồi coi như app đã nhận bài học theo phạm vi.
- Mỗi bài học cần rõ phạm vi, lỗi hoặc yêu cầu thực tế, hành vi đúng và cách đối chiếu với ảnh đầu vào hiện tại. Không lưu riêng câu như “thiếu chân kìa”, “màu chưa hợp” mà thiếu mô tả áp dụng.
- Viết tiếng Việt, tự đủ nghĩa khi clone source mới. Không yêu cầu ảnh, log hoặc batch cũ trong `workspace` để hiểu bài học; đường dẫn lịch sử chỉ là bằng chứng phụ. Ảnh hiện tại không rõ thì ghi nhận chưa xác minh.
- Giữ `id` khi làm rõ bài học cũ để liên kết bật/tắt còn đúng. Cập nhật mục trùng thay vì chép lặp; lỗi riêng của một mẫu không biến thành thiết kế bắt buộc cho cả danh mục. Không tự biến lời AI thành yêu cầu người dùng.
- App lưu nguyên nội dung người dùng nhập vào `requested_change`, không tự biên tập thành bài học. Khi biên tập trong source, giữ đúng ý người dùng, không thêm yêu cầu mới; không tự đổi trạng thái ảnh thành đã duyệt.
- `workspace/feedback/<id>/feedback.json` giữ phản hồi/lịch sử và snapshot cục bộ; không phải nguồn bài học đi theo Git. Khi bật lại bài học từ phản hồi cũ, app có thể lưu lại nội dung phản hồi đó; cần dùng mô tả đủ ngữ cảnh ngay từ lúc nhập.

## 8. Vị trí cần đọc khi sửa

- `src/application/agent-lessons.ps1`: đọc và ghi khối bài học trong file này.
- `src/application/image-feedback.ps1`: lọc bài học theo URL/danh mục và ghép yêu cầu sửa hiện tại.
- `src/workflow/steps/02-select-references.ps1`: chọn ảnh tham khảo và lịch sử dùng kho.
- `src/workflow/steps/03-create-image.ps1`: vai trò ảnh đầu vào và yêu cầu tạo ảnh.
- `src/workflow/steps/04-complete-image.ps1`, `src/infrastructure/image-output.ps1`: xuất PNG và phục hồi lỗi kết nối.
- `src/application/reference-archive.ps1`: snapshot, nguồn và hash đầu vào.
- `data/source-photos/catalog.json`: inventory và thông tin nguồn ảnh.
- `tests/run.ps1`: chạy suite liên quan bằng Windows PowerShell khi được phép.
- `workspace/output/`: kết quả và log cục bộ, Git bỏ qua.

<!-- app-lessons:start -->
## Bài học đã lưu

Đây là các bài học đang bật mà app đọc trực tiếp trước khi tạo ảnh. Chỉ áp dụng khi khớp URL sản phẩm (`product`) hoặc mã danh mục (`category`); phản hồi sửa hiện tại được ưu tiên hơn bài học cũ. Nội dung phải tự đủ nghĩa, không cần ảnh hoặc log của lượt cũ.

Khối JSON bên dưới là dữ liệu của app, không phải lịch sử chat. Giữ nguyên tên các trường kỹ thuật để app đọc và bật/tắt được:

- `id`: mã ổn định của bài học, dùng để cập nhật hoặc bật/tắt, không phải đường dẫn ảnh.
- `scope`: `product` cho một URL, `category` cho cả danh mục.
- `product_url`: URL áp dụng khi phạm vi là sản phẩm; để trống khi phạm vi là danh mục.
- `category`: mã danh mục trong catalog, không phải tên thư mục kho ảnh tiếng Việt.
- `requested_change`: bài học bằng tiếng Việt, nêu lỗi/yêu cầu và hành vi đúng; không chỉ chép câu nhận xét thiếu ngữ cảnh.
- `created_at`: thời điểm ghi nhận, dùng sắp thứ tự; không phải trạng thái ảnh đã được duyệt.

Bài học có mặt trong danh sách nghĩa là đang bật. App lấy tối đa 10 bài học khớp, từ cũ đến mới. Tắt bài học trong app sẽ gỡ bản ghi khỏi mục này; lịch sử phản hồi và trạng thái duyệt ảnh được giữ riêng trong workspace.

```json
[
  {
    "id": "2b459eefc9514ffa999909bbc85d42ea",
    "scope": "product",
    "product_url": "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
    "category": "dining-tables",
    "requested_change": "Lỗi đã gặp: chân ghế bị thiếu trong ảnh ghép bàn ăn. Khi thay bàn và ghế, giữ cấu tạo đầy đủ của những phần ghế nhìn thấy theo ảnh sản phẩm: chân, thanh nối, lưng và mặt ghế phải liền mạch, đúng phối cảnh, có điểm tiếp xúc sàn hợp lý. Không để chân bị cụt, đứt hoặc xuyên vào bàn/sàn. Phần bị che khuất không được tự coi là đã xác minh. Áp dụng với ảnh sản phẩm và ảnh phòng đầu vào hiện tại của URL này.",
    "created_at": "2026-10-26T07:04:24.644366Z"
  },
  {
    "id": "f84798614e0d45a1a9d46ec91a0b33ca",
    "scope": "product",
    "product_url": "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
    "category": "dining-tables",
    "requested_change": "Yêu cầu người dùng: bàn và các ghế ngay quanh bàn phải đồng bộ với phong cách ảnh sản phẩm. Dùng thiết kế ghế được thể hiện trong nguồn hiện tại; không giữ ghế của phòng mẫu nếu sai kiểu, cũng không lấy ghế từ một sản phẩm khác. Nếu bán cả bộ thì giữ đúng ghế của bộ; nếu chỉ bán bàn thì phối lại các ghế hiện có theo yêu cầu này không có nghĩa ghế được bán kèm. Không tự thêm chỗ ngồi.",
    "created_at": "2026-10-26T07:12:01.185526Z"
  },
  {
    "id": "7aeb3fcd590741439c8b449ca7d36cc3",
    "scope": "product",
    "product_url": "https://bangometay.com/p/ban-go-tu-nhien-chan-tang-nguyen-khoi-tu-nhien-2m8x85x6-5cm/",
    "category": "dining-tables",
    "requested_change": "Lỗi đã gặp: màu bàn chưa hòa với ánh sáng của phòng. Điều chỉnh ánh sáng cục bộ, độ phơi sáng, cân bằng trắng và bóng tiếp xúc để ghép tự nhiên; giữ màu vật liệu, lớp hoàn thiện và vân gỗ theo ảnh sản phẩm. Không đổi màu gỗ cho giống tủ/ghế trong phòng, không làm nhạt hoặc xóa vân. Chỉ đổi màu vật liệu khi người dùng yêu cầu rõ; không đổi ánh sáng toàn phòng.",
    "created_at": "2026-10-26T07:36:05.4286701Z"
  },
  {
    "id": "table-seating-dining-tables",
    "scope": "category",
    "product_url": "",
    "category": "dining-tables",
    "requested_change": "Yêu cầu cho bàn ăn: chỉnh các ghế hiện có ngay quanh bàn để phù hợp phong cách sản phẩm và chiều cao sử dụng của bàn ăn. Nếu nguồn bán cả bộ, dùng đúng ghế của bộ. Nếu chỉ bán bàn, yêu cầu phối ghế không có nghĩa ghế bán kèm. Không mặc định ghế nào cũng phải có lưng gỗ cong hoặc mặt đan; chỉ dùng đặc điểm đó khi nguồn hiện tại thể hiện. Không tự thêm chỗ ngồi, đồ trang trí hay đổi kiến trúc; giữ đồ không liên quan.",
    "created_at": "2026-10-27T06:48:09.3468036Z"
  },
  {
    "id": "table-seating-coffee-table",
    "scope": "category",
    "product_url": "",
    "category": "coffee-table",
    "requested_change": "Lỗi đã gặp: thay bàn trà thấp nhưng giữ ghế ăn cao của phòng mẫu, làm sai công năng và tỉ lệ. Chỉnh các chỗ ngồi hiện có ngay quanh bàn sang kiểu, chất liệu và chiều cao phù hợp với bàn trà và ảnh sản phẩm hiện tại. Không mặc định dùng ghế ăn gỗ cong/mặt đan của sản phẩm khác. Đây là yêu cầu phối chỗ ngồi, không chứng minh ghế bán kèm. Không tự thêm chỗ ngồi hoặc chuyển toàn phòng thành không gian khác; giữ kiến trúc và đồ không liên quan.",
    "created_at": "2026-10-27T06:48:09.3592337Z"
  },
  {
    "id": "polo-shoulder-block-collar-edge-20261027",
    "scope": "product",
    "product_url": "https://forteraapparel.com/products/work-polo-shirt-logo-shoulder-block",
    "category": "polo-shirts",
    "requested_change": "Mẫu áp dụng: polo xanh navy phối vai trắng tại URL này. Chi tiết đúng từ phía trong cổ ra ngoài: nền xanh navy → một viền trắng → mép ngoài cổ. Lỗi đã gặp: ảnh tạo thêm một dải xanh mỏng giữa viền trắng và mép ngoài. Giữ viền trắng sát mép ở cả hai bên cổ, đúng số sọc và độ rộng tương đối theo ảnh sản phẩm hiện tại; không lấy cấu trúc cổ từ áo người mẫu trong ảnh bối cảnh. Góc nhìn, nếp gấp và ánh sáng không được đổi thứ tự màu. Nếu ảnh đầu vào không cho thấy rõ thì ghi nhận chưa xác minh, không đoán. Quy tắc viền trắng này chỉ áp dụng cho mẫu này.",
    "created_at": "2026-10-27T16:03:29.9593975+07:00"
  },
  {
    "id": "polo-detail-fidelity-20261027",
    "scope": "category",
    "product_url": "",
    "category": "polo-shirts",
    "requested_change": "Chú ý từng chi tiết áo, không chỉ giống tổng thể. Trước khi tạo, quan sát hình cổ, mép viền, thứ tự màu, số sọc, độ rộng tương đối, đường may, nút, nẹp, mảng phối vai/tay và vị trí logo trong ảnh sản phẩm. Giữ các chi tiết đó theo đúng mẫu hiện tại, chỉ thay thương hiệu theo quy tắc chung. Không thêm/bớt sọc, đơn giản hóa thiết kế hoặc lấy chi tiết áo của người mẫu trong ảnh tham khảo. Phần bị che phải ghi nhận chưa xác minh. Lỗi viền cổ của mẫu shoulder-block là ví dụ về sai chi tiết, không có nghĩa mọi polo đều có cùng viền trắng.",
    "created_at": "2026-10-27T16:04:20.7937109+07:00"
  }
]
```
<!-- app-lessons:end -->
