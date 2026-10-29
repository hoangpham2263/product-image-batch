# The app's star: window and taskbar icon, plus a tray icon (Mở cửa sổ / Thoát) while the app runs,
# matching the menu bar star on macOS.
function New-StarIcon([int]$Size = 32) {
    $bitmap = New-Object Drawing.Bitmap($Size, $Size)
    $g = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.SmoothingMode = 'AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
        $center = $Size / 2; $outer = $Size * 0.48; $inner = $outer * 0.42
        $points = for ($i = 0; $i -lt 10; $i++) {
            $radius = if ($i % 2) { $inner } else { $outer }
            $angle = [Math]::PI / 2 - $i * [Math]::PI / 5
            New-Object Drawing.PointF(([single]($center + $radius * [Math]::Cos($angle))), ([single]($center - $radius * [Math]::Sin($angle) + $Size * 0.04)))
        }
        $brush = New-Object Drawing.SolidBrush($script:Ui.Accent)
        try { $g.FillPolygon($brush, [Drawing.PointF[]]$points) } finally { $brush.Dispose() }
    } finally { $g.Dispose() }
    return [Drawing.Icon]::FromHandle($bitmap.GetHicon())
}

function New-AppTray([Windows.Forms.Form]$Form, [Drawing.Icon]$Icon) {
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $show = { $Form.Show(); if ($Form.WindowState -eq 'Minimized') { $Form.WindowState = 'Normal' }; $Form.Activate() }.GetNewClosure()
    $title = $menu.Items.Add('Product Review Batch'); $title.Enabled = $false
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add('Mở cửa sổ', $null, $show)
    [void]$menu.Items.Add('Thoát', $null, { $Form.Close() }.GetNewClosure())
    $tray = New-Object Windows.Forms.NotifyIcon -Property @{ Icon = $Icon; Text = 'Product Review Batch'; ContextMenuStrip = $menu }
    $tray.Add_DoubleClick($show)
    return $tray
}
