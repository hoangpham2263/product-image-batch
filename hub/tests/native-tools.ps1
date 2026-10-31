param([ValidateSet('grok','social')][string]$Tool)
$ErrorActionPreference='Stop'
$hub=Split-Path $PSScriptRoot -Parent
$env:TOOLS_HUB_MENU='return'
if($Tool -eq 'grok'){
    . (Join-Path $hub '../apps/grok-video-prompt/src/gui.ps1') -BuildOnly
    try {
        foreach($seconds in @('6','10','15')){
            Set-GrokDuration $seconds
            if($styles.Items.Count -ne 10){throw "Missing styles for $seconds"}
            if($seconds -eq '10' -and -not $styles.Items[0].name.Contains('tự nhiên')){throw 'Vietnamese prompt data encoding failed.'}
            $product.Text='Bàn thử nghiệm'
            if(-not $output.Text.Contains('Bàn thử nghiệm') -or $output.Text.Contains('[SẢN PHẨM]')){throw 'Product replacement failed.'}
            $styles.SelectedIndex=9
            if($state.code -ne $styles.SelectedItem.code){throw 'Style selection lost.'}
        }
        if($shell.Menu.Text -ne '← Menu'){throw 'Native menu missing.'}
        'PASS: Grok native controls, all 30 styles, duration/style switching and product replacement.'
    } finally {$form.Dispose();$videoTimer.Dispose();$client.Dispose();$hostMedia.Dispose()}
} else {
    . (Join-Path $hub '../apps/fb-content/src/gui.ps1') -BuildOnly
    try {
        $row=[pscustomobject]@{id='test';name='Bàn';brand='GRENHEIM';link='https://example.test/p';points="Gỗ tự nhiên`nChân vòm";tags='go ban tra';sources=@(@{path='test.png';scenes=3})}
        foreach($toneId in @('story','short','sale')){foreach($platform in $script:SocialPlatforms){
            $post=Get-SocialPost $row $platform.id $toneId
            if(-not $post.Contains('Bàn') -or -not $post.Contains('Gỗ tự nhiên')){throw 'Draft content missing.'}
            if($platform.id -eq 'facebook' -and -not $post.Contains($row.link)){throw 'Facebook link missing.'}
            if($platform.id -in @('instagram','tiktok') -and $post.Contains($row.link)){throw 'Bio platform contains raw link.'}
            if($platform.id -eq 'threads' -and $post.Contains('#ban')){throw 'Threads hashtag limit failed.'}
        }}
        $state.rows=@($row);Update-SocialRows
        if($rows.Items.Count -ne 1){throw 'Native product rows failed.'}
        'PASS: Content MXH native controls and composition across 4 platforms / 3 tones.'
    } finally {$form.Dispose();$platformTimer.Dispose()}
}
