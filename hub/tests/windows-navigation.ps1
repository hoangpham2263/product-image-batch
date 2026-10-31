# The real menu with each real tool, twice: the tool opens as a page in the menu's window (no new process or
# window), the menu page hides, and the tool's "← Menu" brings the menu back. No AI jobs are started.
$ErrorActionPreference='Stop'
$hubScripts=Split-Path $PSScriptRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $hubScripts 'launch.ps1')).Replace('$PSScriptRoot','$hubScripts')
$driver=@'
$navigation=@{Index=0;Phase='open';Started=(Get-Date);Failure=$null;Windows=@([Diagnostics.Process]::GetCurrentProcess().Id)}
$navigationTimer=New-Object Windows.Forms.Timer -Property @{Interval=300}
$navigationTimer.Add_Tick({
    try {
        if(((Get-Date)-$navigation.Started).TotalSeconds -gt 60){throw ('Navigation timeout: '+$navigation.Phase)}
        $activeTool=$tools[($navigation.Index % $tools.Count)]
        if($navigation.Phase -eq 'open'){
            $navigation.Phase='busy'
            & $openCard $grid.Controls[($navigation.Index % $tools.Count)]
            if(-not $script:page){throw ('Tool page did not open: '+$activeTool.id)}
            if($menuPage.Visible){throw 'Menu page still visible under the tool.'}
            if($script:page.TopLevel -or $script:page.Parent -ne $form){throw 'Tool is not a page of the menu window.'}
            if(-not $form.Text.StartsWith([string]$activeTool.name)){throw ('Window title not the tool: '+$form.Text)}
            $navigation.Phase='return'
        }elseif($navigation.Phase -eq 'return'){
            $navigation.Phase='busy'
            $script:page.Close()
            if($script:page){throw ('Tool page did not close: '+$activeTool.id)}
            if(-not $menuPage.Visible -or -not $form.Visible){throw 'Menu did not come back.'}
            Write-Output ('PASS: page open/return '+$activeTool.id)
            $navigation.Index++;$navigation.Phase='open';$navigation.Started=Get-Date
            if($navigation.Index -eq ($tools.Count * 2)){$navigationTimer.Stop();$form.Close()}
        }
    }catch{$navigation.Failure=$_;$navigationTimer.Stop();$form.Close()}
})
$navigationTimer.Start()
[Windows.Forms.Application]::Run($form)
$navigationTimer.Dispose()
if($navigation.Failure){throw $navigation.Failure}
if($navigation.Index -ne ($tools.Count * 2)){throw 'Not all tools were tested.'}
'@
$source=$source.Replace('try { [Windows.Forms.Application]::Run($form) }','try { & ([scriptblock]::Create($driver)) }')
& ([scriptblock]::Create($source))
Write-Output 'PASS: every tool opened as a page of the one menu window and returned to the menu; two rounds each.'
