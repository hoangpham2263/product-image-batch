# Regression: system buttons, and Product Review's "← Menu" closes its page without opening another menu.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$hub = Split-Path $PSScriptRoot -Parent
. (Join-Path $hub 'winforms.ps1')
$tokens=$null; $parseErrors=$null
$button=New-Object Windows.Forms.Button
try {
    Set-FlatButton $button -Primary; Set-FlatButton $button
    if($button.FlatStyle -ne 'Standard' -or -not $button.UseVisualStyleBackColor -or $button.ForeColor -eq [Drawing.Color]::White){throw 'Button style did not reset to the system button.'}
    $productAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $hub '../apps/product-review/src/ui/main-window.ps1'),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors){throw ($parseErrors | Out-String)}
    $menuCall=$productAst.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$btnMenu' -and $n.Member.Value -eq 'Add_Click'},$true)
    $menuClick=[scriptblock]::Create($menuCall.Arguments[0].ScriptBlock.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
    try {
        function Start-Process { throw 'Managed Menu button must not spawn another launcher.' }
        $form=New-Object Windows.Forms.Form
        & $menuClick
        if(-not $form.IsDisposed){throw 'Product Review Menu did not close the tool.'}
    } finally { Remove-Item Function:\Start-Process }
    'PASS: system button reset, Product Review returns to the menu without a duplicate launcher.'
} finally { $button.Dispose() }
