# API kho ảnh – Tools Hub · Product Review

Dùng để tạo danh mục và đưa ảnh lên kho Google Drive của app, từ file trên máy hoặc từ link ảnh.

## Bắt đầu

| Mục | Giá trị |
|---|---|
| Địa chỉ | `https://tools-hub-api.hoangpham2263.workers.dev` |
| Mã truy cập | Header `x-admin-key: <mã>` ở mọi lệnh `/api/...` |
| Mã tạm (nên dùng) | Tạo ở trang quản lý → API → **Tạo mã**. Dạng `prb_tmp_…`, tự hết hạn (1 giờ / 24 giờ / 7 ngày), chỉ xem và thêm ảnh, không xoá được |
| Tên danh mục | Đúng dấu tiếng Việt, mã hoá URL trong đường dẫn: `Nội thất` → `N%E1%BB%99i%20th%E1%BA%A5t` |
| Ảnh | JPG, PNG hoặc WebP, tối đa 25 MB |

## Lệnh dùng với mã tạm

| Lệnh | Việc |
|---|---|
| `GET /api/sources` | Danh sách danh mục: `name`, `count`, `enabled` |
| `POST /api/sources` body `{"name":"Đồ bếp"}` | Tạo danh mục (`409` nếu đã có, cứ làm tiếp) |
| `GET /api/sources/<danh mục>` | Ảnh trong danh mục: `id`, `name`, `size`, `md5`, `url` |
| `POST /api/sources/<danh mục>?name=<tên file>` body là ảnh | Tải một file lên; header `content-type: image/jpeg` (hoặc png/webp) |
| `POST /api/sources/<danh mục>?url=<link ảnh>&name=<tên file>` | Máy chủ tự tải ảnh từ link công khai |

- Trùng tên không ghi đè: ảnh mới thành `ten-2.jpg`. Muốn tránh, xem danh sách trước và bỏ qua tên đã có.
- Giá trị trong query (`name`, `url`) cũng mã hoá URL.

## Ví dụ

```bash
export PRB_KEY='prb_tmp_...'
API=https://tools-hub-api.hoangpham2263.workers.dev
curl -s "$API/api/sources" -H "x-admin-key: $PRB_KEY"
curl -s -X POST "$API/api/sources/%C3%81o?name=polo-001.jpg" -H "x-admin-key: $PRB_KEY" -H 'content-type: image/jpeg' --data-binary @polo-001.jpg
curl -s -X POST "$API/api/sources/%C3%81o?url=$(jq -rn --arg u 'https://shop.example.com/img/polo.jpg' '$u|@uri')" -H "x-admin-key: $PRB_KEY"
```

Tải cả thư mục vào một danh mục, bỏ qua ảnh đã có (Node 18+):
```js
// PRB_KEY='prb_tmp_...' node upload.mjs "Nội thất" ./anh
import { readdir, readFile } from "node:fs/promises";
import { join, extname } from "node:path";
const API = "https://tools-hub-api.hoangpham2263.workers.dev", headers = { "x-admin-key": process.env.PRB_KEY };
const [group, dir] = process.argv.slice(2), g = encodeURIComponent(group);
const types = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };
await fetch(`${API}/api/sources`, { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ name: group }) });
const have = new Set(((await (await fetch(`${API}/api/sources/${g}`, { headers })).json()).files || []).map((f) => f.name));
let ok = 0, skip = 0, fail = 0;
for (const name of await readdir(dir)) {
  const type = types[extname(name).toLowerCase()];
  if (!type) continue;
  if (have.has(name)) { skip++; continue; }
  const r = await fetch(`${API}/api/sources/${g}?name=${encodeURIComponent(name)}`, { method: "POST", headers: { ...headers, "content-type": type }, body: await readFile(join(dir, name)) });
  if (r.ok) ok++; else { fail++; console.log("Lỗi", name, (await r.json()).error); }
}
console.log(`Đã tải ${ok}, bỏ qua ${skip}, lỗi ${fail}`);
```

## Dành cho AI

1. Đọc mã từ biến môi trường `PRB_KEY`; không in ra, không ghi vào file.
2. `GET /api/sources` trước để lấy đúng tên danh mục; chưa có thì tạo.
3. Kiểm tra đuôi file khớp loại ảnh thật (GIF hoặc JPEG mang đuôi `.png` thì đổi lại); `content-type` đúng loại.
4. Chỉ tải ảnh chưa có, vài ảnh song song là đủ; ghi lại ảnh lỗi kèm `error` để thử lại.
5. Báo lại: đã tải, bỏ qua, lỗi. `401` nghĩa là mã sai hoặc hết hạn: xin mã mới.

## Lỗi

`400` dữ liệu sai (tên, loại ảnh, quá 25 MB, link hỏng) · `401` mã sai/hết hạn · `403` mã không đủ quyền · `404` không thấy danh mục/ảnh · `409` đã có · `500` thử lại sau. Nội dung lỗi: `{ "error": "lý do" }`.

## Chỉ mật khẩu admin

| Lệnh | Việc |
|---|---|
| `PATCH /api/sources/<danh mục>` body `{"enabled":true}` | Bật/tắt danh mục trong app (danh mục mới đang tắt) |
| `DELETE /api/sources/<danh mục>/<id ảnh>` | Xoá một ảnh |
| `DELETE /api/sources/<danh mục>` | Xoá danh mục đã hết ảnh |
| `POST /api/temp-keys` body `{"hours":24}` | Tạo mã tạm (1, 24 hoặc 168 giờ) |
| `GET /api/temp-keys` · `DELETE /api/temp-keys[/<id>]` | Xem mã còn hạn (kèm mã để copy lại) · huỷ một hoặc tất cả |
| `GET/PATCH/DELETE /api/images[/<id>]` · `GET/DELETE /api/logs[/<id>]` | Ảnh đã tạo và log người dùng gửi (trang quản lý dùng) |
