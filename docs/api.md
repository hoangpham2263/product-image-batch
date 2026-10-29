# Product Review Batch – API kho ảnh (cho người và AI)

Tài liệu này đủ để một người hoặc một trợ lý AI tự đưa ảnh lên kho Google Drive của app: tạo danh mục, tải ảnh lên (từ file hoặc từ link), xem, xoá, bật/tắt danh mục cho app.

## Cơ bản

- **Địa chỉ gốc:** `https://product-images-api.hoangpham2263.workers.dev`
- **Đăng nhập:** gửi header `x-admin-key: <MẬT_KHẨU_ADMIN>` trong mọi lệnh có `/api/...`.
  - Mật khẩu admin là mật khẩu đăng nhập trang quản lý. Không dán mật khẩu vào nơi công khai; khi đưa tài liệu này cho AI, để AI đọc mật khẩu từ biến môi trường `PRB_ADMIN_KEY`.
  - Mật khẩu app (dùng trong app trên máy) chỉ đọc được danh mục đang bật, **không** tải lên hay xoá được.
- **Trả về:** JSON. Lỗi có dạng `{ "error": "lý do" }` với mã HTTP 400 (dữ liệu sai), 401 (sai mật khẩu), 403 (mật khẩu app không đủ quyền), 404 (không thấy), 409 (đã tồn tại), 500 (lỗi máy chủ).
- **Tên danh mục:** đúng như trên trang quản lý, có dấu tiếng Việt, ví dụ `Áo`, `Nội thất`. Chỉ gồm chữ, số, dấu cách, gạch ngang; tối đa 60 ký tự. Khi đặt trong đường dẫn phải mã hoá URL: `Nội thất` → `N%E1%BB%99i%20th%E1%BA%A5t` (`encodeURIComponent` trong JS, `urllib.parse.quote` trong Python, `curl --data-urlencode`/`jq -rR @uri` trong shell).
- **Ảnh nhận:** JPG, PNG, WebP; mỗi ảnh tối đa 25 MB.

## Danh mục (nhóm ảnh)

### Xem danh sách danh mục
`GET /api/sources`

```json
{ "groups": [ { "name": "Áo", "count": 1217, "enabled": true }, { "name": "Mũ", "count": 140, "enabled": false } ] }
```
`enabled`: danh mục có hiện trong app hay không.

### Tạo danh mục
`POST /api/sources` với body JSON `{ "name": "Đồ bếp" }` → `201 { "name": "Đồ bếp", "count": 0 }`. Đã có thì `409`.

Danh mục mới **đang tắt** (app chưa thấy). Bật bằng lệnh dưới khi đã đủ ảnh.

### Bật / tắt danh mục trong app
`PATCH /api/sources/<danh mục>` với body JSON `{ "enabled": true }` (hoặc `false`) → `{ "name": "...", "enabled": true }`.

### Xoá danh mục
`DELETE /api/sources/<danh mục>` → `{ "ok": true }`. Chỉ xoá được khi danh mục đã hết ảnh (`400` nếu còn).

## Ảnh trong danh mục

### Xem ảnh của một danh mục
`GET /api/sources/<danh mục>`

```json
{ "group": "Áo", "files": [ { "id": "1AbC...", "name": "polo-001.jpg", "size": 182311, "md5": "9f...", "createdAt": "2026-10-29T03:00:00.000Z", "url": "https://product-images-api.hoangpham2263.workers.dev/src/1AbC..." } ] }
```
`url` là link công khai xem ảnh (không cần mật khẩu). `md5` dùng để biết ảnh đã có hay chưa.

### Tải ảnh lên từ file
`POST /api/sources/<danh mục>?name=<tên file>`
- Header `content-type`: `image/jpeg`, `image/png` hoặc `image/webp`.
- Body: nội dung file ảnh (nhị phân), không phải form.
- Trả về `201` với thông tin ảnh như trên.

### Tải ảnh lên từ link (không cần tải về máy trước)
`POST /api/sources/<danh mục>?url=<link ảnh>[&name=<tên file>]` — không cần body.
- Máy chủ tự tải ảnh từ link (`http`/`https`, link phải trả về ảnh JPG/PNG/WebP).
- Không có `name` thì lấy tên từ link; thiếu đuôi thì tự thêm theo loại ảnh.
- Link không tải được hoặc không phải ảnh → `400` kèm lý do.

**Trùng tên:** ảnh mới không ghi đè, mà được đổi thành `ten-2.jpg`, `ten-3.jpg`… Muốn tránh trùng, xem danh sách (`GET`) trước và bỏ qua tên đã có.

### Xoá một ảnh
`DELETE /api/sources/<danh mục>/<id ảnh>` → `{ "ok": true }`.

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
