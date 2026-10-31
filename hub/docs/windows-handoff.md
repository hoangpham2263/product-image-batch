# Windows: một app WinForms

macOS giữ bản web. Windows là một app WinForms duy nhất, không trình duyệt, không máy chủ web, không mở thêm cửa sổ hay tiến trình cho tool.

## Cách chạy

- `hub/launch.ps1` là cửa sổ duy nhất. Trang menu (`$menuPage`) hiện các tool; bấm tool thì `Open-HubTool` dựng `src/gui.ps1` của tool trong một module riêng (biến không đụng menu hay tool khác), đặt form của tool vào cửa sổ (`TopLevel=$false`) thay cho trang menu.
- `← Menu` trong tool đóng form đó; `Close-HubTool` dừng timer của tool và hiện lại menu. Đóng cửa sổ khi đang mở tool thì tool được đóng trước (lưu trạng thái, hỏi khi đang chạy).
- Tool biết mình là trang qua `$global:ToolsHubHosted`: không `ShowDialog`, không tray, không tự bắt lỗi (menu ghi `workspace/logs/app-errors.log`). Cập nhật từ trong tool thì menu tự mở lại bằng file mới.
- Tool chạy riêng (một tool, hoặc mở thẳng `src/gui.ps1`) vẫn là cửa sổ của nó, không có `← Menu`.
- Grok Video Prompt và Content MXH dựng bằng `hub/native-window.ps1`: header như Product Review và các điều khiển chép `hub/assets/tool.css` (Group, Box, CardList, Toggle, Tile, Row, seg, toast; C# 5).

## Kiểm tra (Windows PowerShell, STA)

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/native-tools.ps1 -Tool grok
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/native-tools.ps1 -Tool social
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/windows-menu.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File hub/tests/windows-navigation.ps1
```

## Còn làm

- Chạy các test trên trên máy Windows thật và so ảnh chụp với trang macOS; chưa kiểm tra được từ máy Mac.
- Tạo ảnh và viết bài bằng AI của Content MXH chưa có ở cả hai bản.
