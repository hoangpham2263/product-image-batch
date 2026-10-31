# Shared native Windows shell. Each tool owns its controls and workspace.
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'winforms.ps1')
. (Join-Path $PSScriptRoot 'setup/setup-dialog.ps1')
. (Join-Path $PSScriptRoot 'update-dialog.ps1')
function New-NativeToolWindow([string]$Title,[string]$ToolRoot) {
    $hubRoot=[IO.Path]::GetFullPath((Join-Path $ToolRoot '../..'))
    $nativeErrorPath=Join-Path $ToolRoot 'workspace/app-errors.log'
    [Windows.Forms.Application]::add_ThreadException({
        param($sender,$eventArgs)
        New-Item -ItemType Directory -Force (Split-Path $nativeErrorPath -Parent) | Out-Null
        [IO.File]::AppendAllText($nativeErrorPath,((Get-Date).ToString('o')+"`r`n"+$eventArgs.Exception.ToString()+"`r`n"))
    }.GetNewClosure())
    $window=New-Object Windows.Forms.Form -Property @{Text=$Title;Size='1120,840';MinimumSize='1040,760';StartPosition='CenterScreen';Font=(New-Object Drawing.Font('Segoe UI',10));BackColor=$script:Ui.Page}
    $header=New-Object Windows.Forms.Panel -Property @{Dock='Top';Height=64}
    $back=New-Object Windows.Forms.Button -Property @{Text='← Menu';Location='20,16';Size='90,32';Visible=[bool]$env:TOOLS_HUB_MENU}
    Set-FlatButton $back
    $back.Add_Click({$window.Close()}.GetNewClosure())
    $titleLabel=New-Object Windows.Forms.Label -Property @{Text=$Title;AutoSize=$true;Location='122,21'}
    $config=New-Object Windows.Forms.Button -Property @{Text='Cấu hình';Size='100,32';Location='872,16';Anchor='Top,Right'}
    $update=New-Object Windows.Forms.Button -Property @{Text='Cập nhật';Size='100,32';Location='980,16';Anchor='Top,Right'}
    $header.Width=$window.ClientSize.Width
    Set-FlatButton $config;Set-FlatButton $update
    $config.Add_Click({Show-HubSetup $window $hubRoot}.GetNewClosure())
    $update.Add_Click({
        $logs=Join-Path $hubRoot 'workspace/logs';New-Item -ItemType Directory -Force $logs | Out-Null
        if(Show-UpdateDialog $window $hubRoot $logs ''){
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $hubRoot 'hub/launch.ps1')+'"'))
            $window.Close()
        }
    }.GetNewClosure())
    $header.Controls.AddRange(@($back,$titleLabel,$config,$update));$window.Controls.Add($header)
    $body=New-Object Windows.Forms.Panel -Property @{Dock='Fill';Padding='20,0,20,20'}
    $window.Controls.Add($body);$body.BringToFront()
    return @{Form=$window;Body=$body;Menu=$back}
}
function New-NativeButton([string]$Text,[switch]$Primary) {
    $button=New-Object Windows.Forms.Button -Property @{Text=$Text;Height=32;Width=130;Margin='0,0,8,8'}
    Set-FlatButton $button -Primary:$Primary
    return $button
}
function Read-NativeState([string]$Path,$Default) {
    try {return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json} catch {return $Default}
}
function Write-NativeState([string]$Path,$State) {
    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}
