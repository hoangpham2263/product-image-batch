function Show-AppHelp([Windows.Forms.Form]$Owner) {
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = 'Hướng dẫn sử dụng'
    $dialog.ClientSize = New-Object Drawing.Size(560, 300)
    $dialog.MinimumSize = New-Object Drawing.Size(480, 300)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = New-Object Drawing.Font('Segoe UI', 10)
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $text = New-Object Windows.Forms.TextBox -Property @{
        Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'
        BorderStyle = 'None'; BackColor = [Drawing.SystemColors]::Control
        Location = '20,18'; Size = '520,226'; Anchor = 'Top,Bottom,Left,Right'
        TabStop = $false
    }
    $content = @'
1. Thêm sản phẩm: dán link, gắn một hoặc nhiều ảnh bối cảnh (mỗi ảnh ra một ảnh kết quả), bấm Lưu.
2. Chọn số ảnh mẫu và số luồng (khuyên dùng 1–2 luồng).
3. Bấm Bắt đầu. Xong thì bấm Mở kết quả để lấy ảnh và CSV.
4. Ảnh chưa đúng: bấm Kiểm tra ảnh / Làm lại, ghi chỗ sai rồi Lưu và làm lại.
5. Google Drive: đăng nhập một lần để ảnh tự tải lên Drive.

Link lỗi được giữ lại để chạy lại. Mỗi lần chạy là một thư mục trong kết quả.

Cần: Windows 10/11, Internet, tài khoản ChatGPT có Codex và quyền tạo ảnh (xem setup.txt).
'@
    $text.Lines = @($content -split '\r?\n')
    $close = New-Object Windows.Forms.Button -Property @{
        Text = 'Đóng'; DialogResult = 'OK'; Location = '440,256'
        Size = '100,30'; Anchor = 'Bottom,Right'
    }
    $dialog.Controls.AddRange(@($text, $close))
    $dialog.AcceptButton = $close
    $dialog.CancelButton = $close
    try { [void]$dialog.ShowDialog($Owner) } finally { $dialog.Dispose() }
}
