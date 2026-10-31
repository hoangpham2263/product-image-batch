# Regression: the real menu callbacks must survive repeated tool/menu round trips.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$hub = Split-Path $PSScriptRoot -Parent
. (Join-Path $hub 'winforms.ps1')
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $hub 'launch.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors | Out-String)}
$source=$ast.Extent.Text
$start=$source.IndexOf('    $script:toolProcess = $null')
$end=$source.IndexOf('    foreach ($item in $tools)', $start)
$cardOf={param($c) while($c -and $c.Name -ne 'toolCard'){$c=$c.Parent}; $c}
$root=Split-Path $hub -Parent; $logDir=$env:TEMP; $form=New-Object Windows.Forms.Form
$card=New-Object ToolsHub.ToolCard -Property @{Name='toolCard'}
$button=New-Object Windows.Forms.Button
$testDir=Join-Path $env:TEMP ('tools-hub-menu-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$state=@{Rounds=0;Waiting=$false;Error=$null;Started=(Get-Date)}
$check=New-Object Windows.Forms.Timer -Property @{Interval=100}
try {
    Set-FlatButton $button -Primary; Set-FlatButton $button
    if($button.FlatStyle -ne 'Flat' -or $button.FlatAppearance.BorderSize -ne 1 -or $button.ForeColor -eq [Drawing.Color]::White){throw 'Button style did not reset to flat v1 style.'}
    # Include spaces in the real child entry path and confirm the inherited menu protocol.
    $entry=Join-Path $testDir 'fake tool.ps1'
    '$env:TOOLS_HUB_MENU | Set-Content -LiteralPath (Join-Path $PSScriptRoot ''menu.txt''); Start-Sleep -Milliseconds 500' | Set-Content -LiteralPath $entry
    $card.Tag=[pscustomobject]@{Root=$testDir;windows='fake tool.ps1';web=$null}
    $form.Controls.Add($card)
    . ([scriptblock]::Create($source.Substring($start,$end-$start)))
    $check.Add_Tick({
        try {
            if(((Get-Date)-$state.Started).TotalSeconds -gt 20){throw 'Menu return timed out.'}
            if(-not $state.Waiting){
                & $openCard $card
                if(-not $script:toolProcess){throw 'Child tool did not start.'}
                $state.Waiting=$true
            } elseif(-not $script:toolProcess){
                if(-not $form.Visible -or $form.IsDisposed){throw 'Original menu did not return alive.'}
                if((Get-Content (Join-Path $testDir 'menu.txt')).Trim() -ne 'return'){throw 'Child lost menu return protocol.'}
                $state.Rounds++; $state.Waiting=$false
                if($state.Rounds -eq 3){$form.Close()}
            }
        } catch {$state.Error=$_; $form.Close()}
    })
    $check.Start()
    [Windows.Forms.Application]::Run($form)
    if($state.Error){throw $state.Error}
    if($state.Rounds -ne 3){throw 'Round trips did not finish.'}
    $productAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $hub '../apps/product-review/src/ui/main-window.ps1'),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors){throw ($parseErrors | Out-String)}
    $menuCall=$productAst.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$btnMenu' -and $n.Member.Value -eq 'Add_Click'},$true)
    $menuClick=[scriptblock]::Create($menuCall.Arguments[0].ScriptBlock.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
    $previousMenu=$env:TOOLS_HUB_MENU
    try {
        function Start-Process { throw 'Managed Menu button must not spawn another launcher.' }
        $env:TOOLS_HUB_MENU='return'
        $root=Split-Path $hub -Parent; $logDir=$env:TEMP; $form=New-Object Windows.Forms.Form
        & $menuClick
        if(-not $form.IsDisposed){throw 'Product Review Menu did not close the tool.'}
    } finally { Remove-Item Function:\Start-Process; $env:TOOLS_HUB_MENU=$previousMenu }
    'PASS: flat button reset, three real child-tool/menu round trips, Product Review return without a duplicate launcher.'
} finally {
    $check.Stop();$check.Dispose()
    if($toolTimer){$toolTimer.Stop();$toolTimer.Dispose()}
    if($script:toolProcess){$script:toolProcess.Dispose()}
    $button.Dispose();$form.Dispose()
    # Only remove this test's newly created, verified temporary directory.
    if((Split-Path $testDir -Parent) -eq $env:TEMP -and (Split-Path $testDir -Leaf) -like 'tools-hub-menu-test-*'){
        Remove-Item -LiteralPath $testDir -Recurse -Force
    }
}
