function Show-AppHelp([Windows.Forms.Form]$Owner) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Hướng dẫn sử dụng'
    $dialog.ClientSize = New-Object Drawing.Size(640, 390)
    $dialog.MinimumSize = New-Object Drawing.Size(560, 390)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = New-Object Drawing.Font('Segoe UI', 10)
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $text = New-Object Windows.Forms.TextBox -Property @{
        Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'
        BorderStyle = 'None'; BackColor = [Drawing.SystemColors]::Control
        Location = '20,18'; Size = '600,310'; Anchor = 'Top,Bottom,Left,Right'
        TabStop = $false
    }
    $content = @'
CÁCH DÙNG
1. Bấm Thêm sản phẩm: dán link và ảnh trong popup rồi Lưu.
   Danh sách chính hiển thị một dòng nhỏ cho mỗi sản phẩm. Bấm dòng để preview/sửa; Hủy không đổi dữ liệu. Có thể Ctrl+V ảnh, chọn file hoặc kéo ảnh vào popup.
   Thêm nhiều link mở popup nhập hàng loạt, mỗi link một dòng. Bấm từng dòng để gắn ảnh; thumbnail hiện trên đúng sản phẩm.
   Chọn Kho ảnh local trong popup: Áo cho áo, Nội thất cho nội thất; Chọn ảnh mở đúng nhóm, Mở thư mục để xem kho. Các nhóm cũ vẫn giữ để dùng sau.
   Chỉ bật dùng kho data cho link chưa gắn ảnh khi bạn muốn app tự tìm. Ảnh đã gắn được dùng trực tiếp, không chấm bằng AI và không tự đổi ảnh.
2. Chọn tuỳ chọn:
   • Ảnh từ kho/SP: số ảnh tham khảo tối đa khi bật tìm trong kho (mặc định 1).
     Nếu chỉ có một ảnh đạt, app dùng cả người và bối cảnh thật trong ảnh đó.
     Đồ vật như bàn ăn dùng ngay một bối cảnh đạt, không chờ tìm ảnh thứ hai.
   • Luồng: số sản phẩm xử lý cùng lúc; mặc định 1, tối đa 4.
     Khuyên dùng 1–2; nhiều luồng dùng thêm RAM, có thể làm máy chậm và hết hạn mức sớm.
3. Bấm Bắt đầu. Tạo một ảnh rồi xuất để bạn review, không AI QA/tự sửa. Khi xong, bấm Mở kết quả để lấy ảnh và CSV.
   Mỗi lần chạy là một thư mục: images/, refs/, logs/ và loox_import.csv.
   Mỗi lượt AI chờ tối đa 3 phút; riêng tạo ảnh tối đa 8 phút.
   Nếu mất kết nối không phục hồi trong 60 giây, app dừng tiến trình cũ. Ảnh đã lưu được kiểm tra trước; nếu chưa có ảnh thì tự thử tiếp, tối đa 3 lượt gửi do lỗi kết nối khi chưa nhận đủ file. Hết lượt vẫn lỗi thì giữ link.
4. Bấm Kiểm tra ảnh / Làm lại: chọn ảnh, so với sản phẩm gốc và ghi cụ thể chỗ sai.
   Lưu và làm lại dùng đúng sản phẩm/phòng đã lưu; bản cũ giữ nguyên, kết quả ở thư mục mới.
   Có thể lưu bài học cho riêng sản phẩm (mặc định) hoặc cả danh mục.
   Tab Bài học & lịch sử cho xem lỗi, mở kết quả mới, chạy lại lượt lỗi và bật/tắt bài học.
   Khi đã xem ảnh mới đúng yêu cầu, chọn phản hồi tương ứng và bấm Ảnh mới đã đúng.

APP LÀM ĐƯỢC GÌ?
Tạo ảnh sản phẩm và review mẫu, xuất file CSV.

ĐIỀU KIỆN CHẠY
• Windows 10/11, có Internet; cài đặt theo setup.txt.
• ChatGPT Plus/Pro hoặc gói có quyền dùng Codex CLI và tạo ảnh.
• Đã đăng nhập trên máy này và còn hạn mức sử dụng.
'@
    $text.Lines = @($content -split '\r?\n')
    $close = New-Object Windows.Forms.Button -Property @{
        Text = 'Đóng'; DialogResult = 'OK'; Location = '520,344'
        Size = '100,30'; Anchor = 'Bottom,Right'
    }
    $dialog.Controls.AddRange(@($text, $close))
    $dialog.AcceptButton = $close
    $dialog.CancelButton = $close
    try { [void]$dialog.ShowDialog($Owner) } finally { $dialog.Dispose() }
}
