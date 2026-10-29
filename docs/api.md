# Product Review Batch – API kho ảnh (cho người và AI)

Tài liệu này đủ để một người hoặc một trợ lý AI tự đưa ảnh lên kho Google Drive của app: tạo danh mục, tải ảnh lên (từ file hoặc từ link), xem, xoá, bật/tắt danh mục cho app.

## Cần chuẩn bị

| Giá trị | Bắt buộc | Lấy ở đâu | Ví dụ |
|---|---|---|---|
| Địa chỉ API | Có | Cố định | `https://product-images-api.hoangpham2263.workers.dev` |
| Mật khẩu admin | Có | Mật khẩu đăng nhập trang quản lý; đưa cho AI qua biến môi trường `PRB_ADMIN_KEY`, không dán vào tài liệu | `PRB_ADMIN_KEY=...` |
| Tên danh mục | Có | Trang quản lý → Nguồn ảnh, hoặc `GET /api/sources`; viết đúng dấu tiếng Việt | `Áo`, `Nội thất`, `Đồ bếp` |
| Ảnh | Có | File trên máy (JPG/PNG/WebP, tối đa 25 MB) **hoặc** link ảnh công khai `http(s)://...` | `./anh/polo-001.jpg`, `https://shop.example.com/img/polo.jpg` |
| Tên file trên Drive | Không | Tự đặt; bỏ trống thì lấy tên file hoặc tên trong link | `polo-001.jpg` |
| Bật danh mục cho app | Không | Chỉ khi muốn người dùng app thấy danh mục đó | `true` / `false` |

## Quy tắc chung

- **Đăng nhập:** mọi lệnh có `/api/...` gửi header `x-admin-key: <mật khẩu admin>`.
  - Mật khẩu app (dùng trong app trên máy) chỉ đọc được danh mục đang bật, **không** tải lên hay xoá được (trả `403`).
- **Tên danh mục trong đường dẫn phải mã hoá URL:** `Áo` → `%C3%81o`, `Nội thất` → `N%E1%BB%99i%20th%E1%BA%A5t`. JS: `encodeURIComponent`; Python: `urllib.parse.quote(ten, safe="")`; shell: `jq -rn --arg v "$TEN" '$v|@uri'`.
  - Tên hợp lệ: chữ (có dấu), số, dấu cách, gạch ngang; bắt đầu bằng chữ hoặc số; tối đa 60 ký tự.
- **Giá trị trong query** (`name`, `url`) cũng phải mã hoá URL.
- **Trả về:** JSON. Lỗi có dạng `{ "error": "lý do" }`:

| Mã | Nghĩa |
|---|---|
| `200` / `201` | Thành công / đã tạo |
| `400` | Dữ liệu sai: tên không hợp lệ, không phải ảnh, quá 25 MB, link không tải được, danh mục còn ảnh khi xoá |
| `401` | Sai hoặc thiếu mật khẩu |
| `403` | Mật khẩu app không đủ quyền |
| `404` | Không thấy danh mục hoặc ảnh |
| `409` | Danh mục đã có |
| `500` | Lỗi máy chủ (thử lại sau) |

## Danh mục (nhóm ảnh)

### Xem danh sách danh mục
`GET /api/sources`

| Giá trị | Đặt ở | Bắt buộc | Ví dụ |
|---|---|---|---|
| `x-admin-key` | header | Có | mật khẩu admin |

Trả về:
```json
{ "groups": [ { "name": "Áo", "count": 1217, "enabled": true }, { "name": "Mũ", "count": 140, "enabled": false } ] }
```

| Trường | Nghĩa |
|---|---|
| `name` | Tên danh mục, dùng đúng tên này ở các lệnh khác |
| `count` | Số ảnh trong danh mục |
| `enabled` | `true`: người dùng app thấy danh mục; `false`: đang ẩn |

### Tạo danh mục
`POST /api/sources`

| Giá trị | Đặt ở | Bắt buộc | Ví dụ |
|---|---|---|---|
| `x-admin-key` | header | Có | mật khẩu admin |
| `content-type` | header | Có | `application/json` |
| `name` | body JSON | Có | `{ "name": "Đồ bếp" }` |

Trả về `201 { "name": "Đồ bếp", "count": 0 }`. Đã có thì `409` (coi như đã có, làm tiếp). Danh mục mới **đang tắt**; bật bằng lệnh dưới khi đã đủ ảnh.

### Bật / tắt danh mục trong app
`PATCH /api/sources/<danh mục>`

| Giá trị | Đặt ở | Bắt buộc | Ví dụ |
|---|---|---|---|
| `<danh mục>` | đường dẫn (mã hoá URL) | Có | `%C4%90%E1%BB%93%20b%E1%BA%BFp` |
| `x-admin-key` | header | Có | mật khẩu admin |
| `content-type` | header | Có | `application/json` |
| `enabled` | body JSON | Có | `{ "enabled": true }` hoặc `{ "enabled": false }` |

Trả về `{ "name": "Đồ bếp", "enabled": true }`.

### Xoá danh mục
`DELETE /api/sources/<danh mục>` — cần `<danh mục>` (đường dẫn) và `x-admin-key` (header). Trả về `{ "ok": true }`. Chỉ xoá được khi đã hết ảnh (`400` nếu còn).

## Ảnh trong danh mục

### Xem ảnh của một danh mục
`GET /api/sources/<danh mục>` — cần `<danh mục>` (đường dẫn) và `x-admin-key` (header).

```json
{ "group": "Áo", "files": [ { "id": "1AbC...", "name": "polo-001.jpg", "size": 182311, "md5": "9f...", "createdAt": "2026-10-29T03:00:00.000Z", "url": "https://product-images-api.hoangpham2263.workers.dev/src/1AbC..." } ] }
```

| Trường | Nghĩa |
|---|---|
| `id` | Mã ảnh, dùng khi xoá ảnh |
| `name` | Tên file; dùng để biết ảnh đã có chưa |
| `size` | Dung lượng (byte) |
| `md5` | Mã kiểm tra nội dung; trùng `md5` là cùng một ảnh |
| `createdAt` | Thời điểm tải lên (UTC) |
| `url` | Link công khai xem ảnh, không cần mật khẩu |

### Tải ảnh lên từ file
`POST /api/sources/<danh mục>?name=<tên file>`

| Giá trị | Đặt ở | Bắt buộc | Ví dụ |
|---|---|---|---|
| `<danh mục>` | đường dẫn (mã hoá URL) | Có | `%C3%81o` |
| `name` | query (mã hoá URL) | Không, nên có | `polo-001.jpg` |
| `x-admin-key` | header | Có | mật khẩu admin |
| `content-type` | header | Có | `image/jpeg`, `image/png` hoặc `image/webp` (đúng loại ảnh) |
| Nội dung ảnh | body (nhị phân, **không** phải form) | Có | `curl --data-binary @polo-001.jpg` |

Trả về `201` với thông tin ảnh (các trường như bảng ở trên).

### Tải ảnh lên từ link (không cần tải về máy trước)
`POST /api/sources/<danh mục>?url=<link ảnh>&name=<tên file>` — không có body.

| Giá trị | Đặt ở | Bắt buộc | Ví dụ |
|---|---|---|---|
| `<danh mục>` | đường dẫn (mã hoá URL) | Có | `%C3%81o` |
| `url` | query (mã hoá URL) | Có | `https%3A%2F%2Fshop.example.com%2Fimg%2Fpolo.jpg` |
| `name` | query (mã hoá URL) | Không | `polo-shop-01.jpg` |
| `x-admin-key` | header | Có | mật khẩu admin |

- Máy chủ tự tải ảnh từ link; link phải mở được công khai và trả về ảnh JPG/PNG/WebP, tối đa 25 MB.
- Không có `name` thì lấy tên cuối link; thiếu đuôi thì tự thêm theo loại ảnh.
- Link không tải được hoặc không phải ảnh → `400` kèm lý do.

**Trùng tên:** ảnh mới không ghi đè, mà được đổi thành `ten-2.jpg`, `ten-3.jpg`… Muốn tránh trùng, xem danh sách (`GET`) trước và bỏ qua tên đã có.

### Xoá một ảnh
`DELETE /api/sources/<danh mục>/<id ảnh>` — cần `<danh mục>`, `<id ảnh>` (lấy từ danh sách ảnh) và `x-admin-key`. Trả về `{ "ok": true }`.

### Xem ảnh công khai
`GET /src/<id ảnh>` — không cần mật khẩu.

## Ví dụ

Đặt mật khẩu một lần:
```bash
export PRB_ADMIN_KEY='mật khẩu admin'
API=https://product-images-api.hoangpham2263.workers.dev
```

Tạo danh mục rồi bật cho app:
```bash
curl -s -X POST "$API/api/sources" -H "x-admin-key: $PRB_ADMIN_KEY" -H 'content-type: application/json' -d '{"name":"Đồ bếp"}'
curl -s -X PATCH "$API/api/sources/%C4%90%E1%BB%93%20b%E1%BA%BFp" -H "x-admin-key: $PRB_ADMIN_KEY" -H 'content-type: application/json' -d '{"enabled":true}'
```

Tải một file lên:
```bash
curl -s -X POST "$API/api/sources/%C3%81o?name=polo-001.jpg" -H "x-admin-key: $PRB_ADMIN_KEY" -H 'content-type: image/jpeg' --data-binary @polo-001.jpg
```

Tải từ link:
```bash
curl -s -X POST "$API/api/sources/%C3%81o?url=$(jq -rn --arg u 'https://shop.example.com/img/polo blue.jpg' '$u|@uri')" -H "x-admin-key: $PRB_ADMIN_KEY"
```

Tải cả thư mục ảnh vào một danh mục (Node 18+), bỏ qua ảnh đã có cùng tên:
```js
// node upload.mjs "Áo" ./anh
import { readdir, readFile } from "node:fs/promises";
import { join, extname } from "node:path";
const API = "https://product-images-api.hoangpham2263.workers.dev", key = process.env.PRB_ADMIN_KEY;
const [group, dir] = process.argv.slice(2), g = encodeURIComponent(group);
const types = { ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp" };
const have = new Set(((await (await fetch(`${API}/api/sources/${g}`, { headers: { "x-admin-key": key } })).json()).files || []).map((f) => f.name));
for (const name of await readdir(dir)) {
  const type = types[extname(name).toLowerCase()];
  if (!type || have.has(name)) continue;
  const r = await fetch(`${API}/api/sources/${g}?name=${encodeURIComponent(name)}`, { method: "POST", headers: { "x-admin-key": key, "content-type": type }, body: await readFile(join(dir, name)) });
  console.log(r.status, name, r.ok ? "" : (await r.json()).error);
}
```

Trong source (bản git) có sẵn công cụ đẩy cả `data/source-photos/<danh mục>/` lên, chỉ đẩy ảnh chưa có:
```bash
PRB_ADMIN_KEY='mật khẩu admin' node tools/upload-sources.mjs
```

## Ghi chú cho AI làm việc này

1. Đọc mật khẩu từ biến môi trường `PRB_ADMIN_KEY`; không in ra, không ghi vào file.
2. Gọi `GET /api/sources` trước để biết đúng tên danh mục (có dấu). Danh mục chưa có thì tạo bằng `POST /api/sources`.
3. Với mỗi danh mục, `GET /api/sources/<danh mục>` để lấy tên ảnh đã có, rồi chỉ tải ảnh chưa có (tránh `-2`, `-3`).
4. Tải từng ảnh một (hoặc vài ảnh song song), ghi lại ảnh nào lỗi kèm `error` để làm lại.
5. Xong thì bật danh mục cho app bằng `PATCH ... {"enabled": true}` nếu người dùng muốn, và báo lại số ảnh đã tải, đã bỏ qua, bị lỗi.

## API khác (trang quản lý dùng)

| Lệnh | Việc |
|---|---|
| `GET /api/images` | Ảnh app đã tạo (mỗi ảnh có `id`, `batch`, `product`, `status`, `url`) |
| `PATCH /api/images/<id>` body `{ "status": "accepted" \| "rejected" \| "awaiting_review" }` | Đổi trạng thái ảnh đã tạo |
| `DELETE /api/images/<id>` | Xoá ảnh đã tạo |
| `GET /api/logs` | Danh sách file log người dùng gửi |
| `GET /api/logs/<id>` | Tải một file log (zip) |
| `DELETE /api/logs/<id>` | Xoá một file log |
| `GET /api/app-check` | Kiểm tra mật khẩu: trả `{ "ok": true, "role": "admin" \| "app" }` |
