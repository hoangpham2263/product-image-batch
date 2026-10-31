# Builds each native tool window without showing it and checks it works like its macOS page. Windows PowerShell, STA.
param([ValidateSet('grok','social')][string]$Tool)
$ErrorActionPreference='Stop'
$hub=Split-Path $PSScriptRoot -Parent
$env:TOOLS_HUB_MENU='return'
if($Tool -eq 'grok'){
    . (Join-Path $hub '../apps/grok-video-prompt/src/gui.ps1') -BuildOnly
    try {
        foreach($seconds in $durationIds){
            $state.seconds=$seconds;$state.code='';Update-Grok
            if($list.Items.Count -ne 10){throw "Missing styles for $seconds"}
            if($seconds -eq '10' -and -not ([string]$list.Items[0]).Contains('tự nhiên')){throw 'Vietnamese prompt data encoding failed.'}
            if($list.SelectedIndex -ne 0){throw 'First style not chosen.'}
            $product.Text='Bàn thử nghiệm'
            if(-not $out.Text.Text.Contains('Bàn thử nghiệm') -or $out.Text.Text.Contains('[SẢN PHẨM]')){throw 'Product replacement failed.'}
            $list.SelectedIndex=9
            if($state.code -ne $view.Styles[9].code){throw 'Style selection lost.'}
            $pressed=@($durations.Controls | Where-Object {$_.FlatStyle -eq 'Flat'})
            if($pressed.Count -ne 1 -or $pressed[0].Tag -ne $seconds){throw 'Length button not shown as chosen.'}
        }
        if($shell.Menu.Text -ne '← Menu'){throw 'Native menu missing.'}
        if($sample.Message -ne 'Đang tải video mẫu…'){throw 'Video placeholder missing.'}
        'PASS: Grok native window, every length and style, product replacement, chosen states.'
    } finally {$form.Dispose();$videoTimer.Dispose();$client.Dispose()}
} else {
    . (Join-Path $hub '../apps/fb-content/src/gui.ps1') -BuildOnly
    try {
        $row=@{id='test';name='Bàn';brand='GRENHEIM';link='https://example.test/p';points="Gỗ tự nhiên`nChân vòm";tags='go ban tra';sources=(New-Object Collections.ArrayList)}
        foreach($toneId in @('story','short','sale')){foreach($platform in $script:SocialPlatforms){
            $post=Get-SocialPost $row $platform.id $toneId
            if(-not $post.Contains('Bàn') -or -not $post.Contains('Gỗ tự nhiên')){throw 'Draft content missing.'}
            if($platform.id -eq 'facebook' -and -not $post.Contains($row.link)){throw 'Facebook link missing.'}
            if($platform.id -in @('instagram','tiktok') -and $post.Contains($row.link)){throw 'Bio platform contains raw link.'}
            if($platform.id -eq 'threads' -and $post.Contains('#ban')){throw 'Threads hashtag limit failed.'}
        }}
        $state.rows.Clear();Update-Social
        if($rowsPanel.Visible -or -not $rowsBox.Message){throw 'Empty product list message missing.'}
        [void]$state.rows.Add($row);[void]$row.sources.Add(@{path='missing.png';scenes=3});Update-Social
        if(@($rowsPanel.Controls | Where-Object {$_ -is [ToolsHubNative.Row]}).Count -ne 1){throw 'Native product rows failed.'}
        if($state.current -ne 'test' -or $resultGroup.Heading -ne 'Kết quả · #1 Bàn'){throw 'Current product not shown.'}
        if(@($tiles.Controls).Count -ne 1 -or $tiles.Controls[0].Controls.Count -ne 5){throw 'Original image and its 3 bối cảnh not shown.'}
        $state.platforms=@('facebook','threads');$state.tab='threads';Update-SocialPlatforms;Update-SocialResult
        if(@($tabs.Controls).Count -ne 2 -or -not $out.Text.Text.Contains('Gỗ tự nhiên · Chân vòm')){throw 'Platform tabs or Threads post failed.'}
        if(@($platformGrid.Controls | Where-Object {$_.Pressed}).Count -ne 2){throw 'Platform buttons not shown as chosen.'}
        'PASS: Content MXH native window, rows, results, tabs and posts across 4 platforms / 3 tones.'
    } finally {$form.Dispose()}
}
