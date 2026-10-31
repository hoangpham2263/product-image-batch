# Exercises the full launcher with each actual native tool, twice. No AI jobs are started.
$ErrorActionPreference='Stop'
$hubScripts=Split-Path $PSScriptRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $hubScripts 'launch.ps1')).Replace('$PSScriptRoot','$hubScripts')
$driver=@'
$navigation=@{Index=0;Phase='open';Started=(Get-Date);ReadyAt=$null;Failure=$null}
$navigationTimer=New-Object Windows.Forms.Timer -Property @{Interval=200}
$navigationTimer.Add_Tick({
    try {
        if(((Get-Date)-$navigation.Started).TotalSeconds -gt 35){throw ('Navigation timeout: '+$navigation.Phase)}
        $activeTool=$tools[($navigation.Index % $tools.Count)]
        if($navigation.Phase -eq 'open'){
            & $openCard $grid.Controls[($navigation.Index % $tools.Count)]
            $navigation.Phase='ready'
        }elseif($navigation.Phase -eq 'ready'){
            if(-not $script:toolProcess){throw ('Tool exited before opening: '+$activeTool.id)}
            $script:toolProcess.Refresh()
            if($script:toolProcess.MainWindowTitle.StartsWith([string]$activeTool.name)){
                if(-not $navigation.ReadyAt){$navigation.ReadyAt=Get-Date}
                if(((Get-Date)-$navigation.ReadyAt).TotalMilliseconds -ge 800){
                    if($form.Visible){throw 'Menu is still visible behind the tool.'}
                    [void]$script:toolProcess.CloseMainWindow();$navigation.Phase='return'
                }
            }
        }elseif(-not $script:toolProcess){
            if(-not $form.Visible -or $form.IsDisposed){throw 'Original menu did not return.'}
            Write-Output ('PASS: native open/close/return '+$activeTool.id)
            $navigation.Index++;$navigation.Phase='open';$navigation.Started=Get-Date;$navigation.ReadyAt=$null
            if($navigation.Index -eq ($tools.Count * 2)){$navigationTimer.Stop();$form.Close()}
        }
    }catch{$navigation.Failure=$_;$navigationTimer.Stop();$form.Close()}
})
$navigationTimer.Start()
[Windows.Forms.Application]::Run($form)
$navigationTimer.Dispose()
if($navigation.Failure){throw $navigation.Failure}
if($navigation.Index -ne ($tools.Count * 2)){throw 'Not all native tools were tested.'}
'@
$source=$source.Replace('[Windows.Forms.Application]::Run($form)',$driver)
& ([scriptblock]::Create($source))
Write-Output 'PASS: all three real native tools opened, hid the original menu and returned to it; two rounds each.'
