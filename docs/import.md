# Nhập hàng loạt – chuẩn thư mục

Thêm nhiều sản phẩm cùng lúc thay vì gắn ảnh tay từng link. Chuẩn duy nhất: **một thư mục** chứa file `nhap.csv` và các ảnh trên máy.

```
nhap-hang/
  nhap.csv
  ban-an-nau.jpg
  ban-an-den.jpg
  review-1.jpg
  review-2.jpg
  review-3.jpg
  polo-review.jpg
```

Trong app bấm **Nhập hàng loạt → Chọn file…**, chọn `nhap.csv`, rồi bấm **Nhập**.

## nhap.csv

File CSV (UTF-8, cột cách bằng dấu phẩy). Dòng đầu là tên cột:

| Cột | Bắt buộc | Nội dung |
|---|---|---|
| `product_url` | Có | Link sản phẩm `http(s)://…` |
| `product_image` | Không | Tên file ảnh sản phẩm gốc trong thư mục; bỏ trống thì app đọc ảnh từ trang sản phẩm |
| `review_images` | Nên có | Tên file ảnh review (ảnh bối cảnh); nhiều ảnh cách nhau bằng dấu phẩy |

```csv
product_url,product_image,review_images
https://shop.com/products/ban-an-go,ban-an-nau.jpg,"review-1.jpg,review-2.jpg"
https://shop.com/products/ban-an-go,ban-an-den.jpg,review-3.jpg
https://shop.com/products/ao-polo,,polo-review.jpg
```

Dòng 1–2: bàn ăn có hai màu, mỗi màu có ảnh review riêng (tạo 3 ảnh). Dòng 3: áo polo lấy ảnh gốc từ trang, một ảnh review.

- **Mỗi dòng là một ảnh gốc** cùng các ảnh review của nó. Một sản phẩm có nhiều ảnh gốc (nhiều màu) thì viết nhiều dòng cùng `product_url`.
- Mỗi cặp ảnh gốc + ảnh review tạo một ảnh kết quả.
- Ảnh nằm trong thư mục con thì ghi kèm thư mục, ví dụ `review/review-1.jpg`. Chỉ nhận JPG/PNG, tối đa 25 MB.
- Ô có nhiều ảnh được bọc trong dấu nháy kép `"…"`; Excel / Google Sheets tự làm khi lưu CSV.
- Dòng bắt đầu bằng `#` được bỏ qua.

## Kết quả

- App kiểm tra cả bảng trước khi nhập: link sai, cột lạ, thiếu ảnh… được báo theo số dòng, chưa nhập gì.
- Trong lúc nhập có thanh tiến độ; bấm **Hủy** để dừng (ảnh đã gắn vẫn giữ).
- Ảnh nào lỗi thì báo theo dòng và lý do; ảnh khác vẫn nhập. Ảnh gốc lỗi thì bỏ qua các ảnh review của dòng đó, để review không bị gắn nhầm sản phẩm.
- Nhập lại cùng ảnh không bị trùng.

## Dành cho AI tạo bảng

1. Mỗi dòng: `product_url`, `product_image`, `review_images`; ghi đúng tên cột.
2. Ảnh ghi bằng tên file trong thư mục; nhiều ảnh review nối bằng dấu phẩy và bọc cả ô trong `"…"`.
3. Ảnh review phải là ảnh bối cảnh phù hợp với sản phẩm cùng dòng.
