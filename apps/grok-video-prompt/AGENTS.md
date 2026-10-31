# Grok Video Prompt – hướng dẫn

Trang tĩnh `ui/index.html`, mở từ menu Tools Hub. Chọn thời lượng và style, điền tên sản phẩm, copy prompt.

- macOS: trang `ui/index.html`. Windows: cửa sổ WinForms `src/gui.ps1` (không dùng trình duyệt), giao diện như trang và dùng chung khung `hub/native-window.ps1`. Sửa chức năng thì sửa cả hai.
- Windows đọc cùng dữ liệu qua `src/export-prompts.cjs` (Node); không có Node thì chỉ đọc `data/prompts.js`.

- Prompt nằm trong `data/prompts.js`, chia theo thời lượng `6`, `10`, `15`. Mỗi prompt có `code` (chỉ chữ, số, `-`, `_`), `name` và `prompt`. Tên sản phẩm điền vào chỗ `[SẢN PHẨM]`. Người dùng không tự thêm prompt trong trang; prompt mới do AI thêm vào file này.
- `data/demo-prompts.js` là prompt demo để đủ 10 style mỗi thời lượng. Có prompt thật thì xóa file đó và dòng `<script>` gọi nó.
- Video mẫu: mỗi prompt một video, lưu trên Drive ở `Tools Hub/Grok Video Prompt/Video mẫu/<n>s/<code>.mp4` qua worker `tools-hub-api`. Trang đọc danh sách ở `GET /grok/videos`; prompt chưa có video thì hiện khung "chưa được tải lên".
- Tải hoặc thay video (cần mật khẩu admin, MP4/WebM/MOV, tối đa 90MB):

```bash
curl -X PUT -H "x-admin-key: $HUB_ADMIN_KEY" -H "content-type: video/mp4" --data-binary @video.mp4 https://tools-hub-api.hoangpham2263.workers.dev/api/grok-videos/<giây>/<code>
```

  Xóa: cùng đường dẫn với `-X DELETE`. Tải lại cùng `code` sẽ thay video cũ và xóa file cũ trên Drive.
