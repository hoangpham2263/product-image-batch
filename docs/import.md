# Nhập hàng loạt – chuẩn thư mục

Thêm nhiều sản phẩm cùng lúc thay vì gắn ảnh tay từng link. Chuẩn duy nhất: **một thư mục** chứa file `products.csv` và thư mục `images/` đựng toàn bộ ảnh trên máy.

```
product-import/
├── products.csv
└── images/
    ├── dining-table-brown.jpg
    ├── dining-table-black.jpg
    ├── dining-table-review-1.jpg
    ├── dining-table-review-2.jpg
    ├── dining-table-review-3.jpg
    ├── polo-shirt-navy.jpg
    └── polo-shirt-review.jpg
```

Tải **thư mục mẫu** (`product-import-sample.zip`) về, giải nén rồi thay bằng sản phẩm của bạn. Trong app bấm **Nhập hàng loạt**, **kéo thả thư mục `product-import` hoặc file zip của nó** vào hộp (hoặc **Chọn file…** → `products.csv`), rồi bấm **Nhập**.

## products.csv

File CSV (UTF-8, cột cách bằng dấu phẩy). Dòng đầu là tên cột:

| Cột | Bắt buộc | Nội dung |
|---|---|---|
| `product_url` | Có | Link sản phẩm `http(s)://…` |
| `product_image` | Không | Tên file ảnh sản phẩm gốc trong `images/`; bỏ trống thì app đọc ảnh từ trang sản phẩm |
| `review_images` | Nên có | Tên file ảnh review (ảnh bối cảnh) trong `images/`; nhiều ảnh cách nhau bằng dấu phẩy |

```csv
product_url,product_image,review_images
https://shop.com/products/wooden-dining-table,dining-table-brown.jpg,"dining-table-review-1.jpg,dining-table-review-2.jpg"
https://shop.com/products/wooden-dining-table,dining-table-black.jpg,dining-table-review-3.jpg
https://shop.com/products/polo-shirt,polo-shirt-navy.jpg,polo-shirt-review.jpg
```

Dòng 1–2: bàn ăn có hai màu, mỗi màu có ảnh review riêng (tạo 3 ảnh). Dòng 3: áo polo một ảnh gốc, một ảnh review.

- **Mỗi dòng là một ảnh gốc** cùng các ảnh review của nó. Một sản phẩm có nhiều ảnh gốc (nhiều màu) thì viết nhiều dòng cùng `product_url`.
- Mỗi cặp ảnh gốc + ảnh review tạo một ảnh kết quả.
- Chỉ ghi tên file, không ghi `images/`. Chỉ nhận JPG/PNG, tối đa 25 MB.
- Ô có nhiều ảnh được bọc trong dấu nháy kép `"…"`; Excel / Google Sheets tự làm khi lưu CSV.
- Dòng bắt đầu bằng `#` được bỏ qua.

## Kết quả

- App kiểm tra cả bảng trước khi nhập: link sai, cột lạ, thiếu ảnh… được báo theo số dòng, chưa nhập gì.
- Trong lúc nhập có thanh tiến độ; bấm **Hủy** để dừng (ảnh đã gắn vẫn giữ).
- Ảnh nào lỗi thì báo theo dòng và lý do; ảnh khác vẫn nhập. Ảnh gốc lỗi thì bỏ qua các ảnh review của dòng đó, để review không bị gắn nhầm sản phẩm.
- Nhập lại cùng ảnh không bị trùng.

## Dành cho AI tạo bảng

1. Mỗi dòng: `product_url`, `product_image`, `review_images`; ghi đúng tên cột.
2. Ảnh ghi bằng tên file trong `images/`; nhiều ảnh review nối bằng dấu phẩy và bọc cả ô trong `"…"`.
3. Ảnh review phải là ảnh bối cảnh phù hợp với sản phẩm cùng dòng.
