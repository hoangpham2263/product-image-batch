# Nhập hàng loạt · Product Review

Thêm nhiều sản phẩm vào Product Review cùng lúc bằng **một thư mục**: file `products.csv` (danh sách sản phẩm) và thư mục `images/` (toàn bộ ảnh). Không cần gắn ảnh tay từng link.

## Làm trong 3 bước

1. **Tải thư mục mẫu** (`product-import-sample.zip`) ở góc trên, giải nén.
2. **Thay bằng sản phẩm của bạn**: chép ảnh vào `images/`, sửa `products.csv` theo hướng dẫn bên dưới.
3. **Nhập vào app**: mở Product Review, bấm **Nhập hàng loạt**, kéo thả thư mục `product-import` (hoặc file nén .zip / .rar / .7z của nó) vào hộp, rồi bấm **Nhập**. Có thể bấm **Chọn file…** và chọn `products.csv` thay cho kéo thả.

## Cấu trúc thư mục

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

- Tên thư mục ngoài cùng đặt tùy ý; bên trong phải có đúng `products.csv` và `images/`.
- Ảnh: JPG hoặc PNG, mỗi ảnh tối đa 25 MB.

## File products.csv

File CSV (UTF-8, các cột cách nhau bằng dấu phẩy). Dòng đầu là tên cột, viết đúng như sau:

| Cột | Bắt buộc | Ghi gì |
|---|---|---|
| `product_url` | Có | Link sản phẩm, bắt đầu bằng `http://` hoặc `https://` |
| `product_image` | Không | Tên file **ảnh gốc** của sản phẩm trong `images/`. Bỏ trống thì app lấy ảnh từ trang sản phẩm |
| `review_images` | Nên có | Tên file **ảnh review** (ảnh bối cảnh) trong `images/`. Nhiều ảnh thì cách nhau bằng dấu phẩy |

Ví dụ (đúng như thư mục mẫu):

```csv
product_url,product_image,review_images
https://shop.com/products/wooden-dining-table,dining-table-brown.jpg,"dining-table-review-1.jpg,dining-table-review-2.jpg"
https://shop.com/products/wooden-dining-table,dining-table-black.jpg,dining-table-review-3.jpg
https://shop.com/products/polo-shirt,polo-shirt-navy.jpg,polo-shirt-review.jpg
```

Bảng trên tạo ra:

| Dòng | Sản phẩm | Ảnh gốc | Ảnh review | Ảnh tạo ra |
|---|---|---|---|---|
| 1 | Bàn ăn | màu nâu | 2 ảnh | 2 |
| 2 | Bàn ăn | màu đen | 1 ảnh | 1 |
| 3 | Áo polo | màu navy | 1 ảnh | 1 |

## Quy tắc cần nhớ

- **Mỗi dòng = một ảnh gốc** và các ảnh review của nó. Sản phẩm có nhiều ảnh gốc (nhiều màu) thì viết nhiều dòng cùng `product_url`.
- **Mỗi cặp ảnh gốc + ảnh review tạo một ảnh kết quả.**
- Chỉ ghi tên file (`polo-shirt-navy.jpg`), không ghi `images/` phía trước.
- Ô có nhiều ảnh phải bọc trong dấu nháy kép `"…"`. Excel và Google Sheets tự làm việc này khi lưu thành CSV.
- Dòng bắt đầu bằng `#` là ghi chú, app bỏ qua.

## App kiểm tra và báo lỗi

- **Trước khi nhập**, app đọc cả bảng: link sai, tên cột lạ, thiếu file ảnh… được báo theo số dòng và chưa nhập gì cả. Sửa xong nhập lại.
- **Trong lúc nhập** có thanh tiến độ; bấm **Hủy** để dừng, ảnh đã gắn vẫn giữ.
- **Ảnh lỗi** được báo theo dòng kèm lý do; các ảnh khác vẫn nhập. Nếu ảnh gốc của một dòng lỗi, app bỏ qua các ảnh review của dòng đó để không gắn nhầm sản phẩm.
- **Nhập lại** cùng ảnh không bị trùng.

## Dành cho AI tạo bảng

1. Ba cột theo thứ tự: `product_url`, `product_image`, `review_images`, viết đúng tên.
2. Ảnh ghi bằng tên file có trong `images/`; nhiều ảnh review nối bằng dấu phẩy và bọc cả ô trong `"…"`.
3. Ảnh review phải là ảnh bối cảnh hợp với sản phẩm cùng dòng.
4. Một sản phẩm nhiều màu: mỗi màu một dòng, cùng `product_url`.
