# Nhập hàng loạt – chuẩn file

Thêm nhiều sản phẩm cùng lúc thay vì gắn ảnh tay từng link. Trong app bấm **Nhập hàng loạt**, dán bảng hoặc **Chọn file…**, rồi bấm **Nhập**. App tự tải ảnh, gắn đúng sản phẩm và thêm link vào danh sách.

## Bảng nhập

File CSV (UTF-8) hoặc dán thẳng từ Google Sheets / Excel (cột cách bằng tab). Dòng đầu là tên cột:

| Cột | Bắt buộc | Nội dung |
|---|---|---|
| `product_url` | Có | Link sản phẩm `http(s)://…` |
| `product_image` | Không | Ảnh sản phẩm gốc; bỏ trống thì app đọc ảnh từ trang sản phẩm |
| `review_images` | Nên có | Ảnh review (ảnh bối cảnh); nhiều ảnh cách nhau bằng dấu `\|` |

- **Mỗi dòng là một ảnh gốc** cùng các ảnh review của nó. Một sản phẩm có nhiều ảnh gốc (nhiều màu) thì viết nhiều dòng cùng `product_url`.
- Mỗi cặp ảnh gốc + ảnh review tạo một ảnh kết quả.
- Ảnh là link `http(s)` công khai hoặc đường dẫn file trên máy; chỉ nhận JPG/PNG, tối đa 25 MB.
- Link ảnh trong kho Drive (cột `url` khi xem ảnh qua API) dùng được luôn.
- Dòng bắt đầu bằng `#` được bỏ qua. Không có dòng tên cột thì mỗi dòng được hiểu là một link (chỉ thêm link, chưa có ảnh).

## Ví dụ

```csv
product_url,product_image,review_images
https://shop.com/products/ban-an-go,https://cdn.shop.com/ban-an-nau.jpg,https://cdn.shop.com/review-1.jpg|https://cdn.shop.com/review-2.jpg
https://shop.com/products/ban-an-go,https://cdn.shop.com/ban-an-den.jpg,https://cdn.shop.com/review-3.jpg
https://shop.com/products/ao-polo,,https://cdn.shop.com/polo-review.jpg
```

Dòng 1–2: bàn ăn có hai màu, mỗi màu có ảnh review riêng (tạo 3 ảnh). Dòng 3: áo polo lấy ảnh gốc từ trang, một ảnh review.

## Kết quả

- App kiểm tra cả bảng trước khi tải: link sai, cột lạ… được báo theo số dòng, chưa nhập gì.
- Trong lúc nhập có thanh tiến độ; bấm **Hủy** để dừng (ảnh đã gắn vẫn giữ).
- Ảnh nào không tải được thì báo theo dòng và lý do; ảnh khác vẫn nhập. Ảnh gốc lỗi thì bỏ qua các ảnh review của dòng đó, để review không bị gắn nhầm sản phẩm.
- Nhập lại cùng ảnh không bị trùng.

## Dành cho AI tạo bảng

1. Mỗi dòng: `product_url`, `product_image`, `review_images`; ghi đúng tên cột.
2. Nhiều ảnh review trong một ô: nối bằng `|`, không có dấu cách thừa.
3. Ô có dấu phẩy thì bọc trong dấu nháy kép `"…"`.
4. Chỉ dùng link ảnh trực tiếp (mở ra là ảnh JPG/PNG), không dùng link trang web.
5. Ảnh review phải là ảnh bối cảnh phù hợp với sản phẩm cùng dòng.
