# Mật khẩu app, from Cấu hình: saved once for every tool (Connect-DriveAccount, the shared drive.json).
function Show-DriveLogin([Windows.Forms.Form]$Owner, [string]$WorkspaceRoot) {
    $dialog = New-Object Windows.Forms.Form -Property @{
        Text = 'Mật khẩu app'; ClientSize = '400,170'; StartPosition = 'CenterParent'
        FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false
        Font = (New-Object Drawing.Font('Segoe UI', 10))
    }
    $connected = Test-Path -LiteralPath (Get-SharedConfigPath $WorkspaceRoot 'drive.json')
    $info = New-Object Windows.Forms.Label -Property @{ Location = '20,18'; Size = '360,40' }
    $pass = New-Object Windows.Forms.TextBox -Property @{ Location = '20,62'; Size = '360,28'; UseSystemPasswordChar = $true }
    $err = New-Object Windows.Forms.Label -Property @{ Location = '20,94'; Size = '360,22'; ForeColor = $script:Ui.Warn }
    $ok = New-Object Windows.Forms.Button -Property @{ Location = '260,120'; Size = '120,36' }
    Set-FlatButton $ok -Primary
    if ($connected) {
        $info.Text = 'Đã đăng nhập trên máy này. Ảnh tạo xong tự tải lên Drive.'
        $pass.Visible = $false; $ok.Text = 'Đăng xuất'
        $ok.Add_Click({ Disconnect-DriveAccount $WorkspaceRoot; $dialog.Close() })
    } else {
        $info.Text = 'Nhập mật khẩu app một lần trên máy này để tải ảnh lên Drive và dùng kho Drive.'
        $ok.Text = 'Đăng nhập'; $dialog.AcceptButton = $ok
        $ok.Add_Click({
            try { Connect-DriveAccount $WorkspaceRoot $pass.Text; $dialog.Close() }
            catch { $err.Text = $_.Exception.Message }
        })
    }
    $dialog.Controls.AddRange(@($info, $pass, $err, $ok))
    [void]$dialog.ShowDialog($Owner)
    return Test-Path -LiteralPath (Get-SharedConfigPath $WorkspaceRoot 'drive.json')
}
