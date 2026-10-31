# Windows look shared by the Tools Hub menu and every tool's window: Product Review's colours and buttons.
$script:Ui=@{
    Ink=[Drawing.Color]::FromArgb(30,30,30); Muted=[Drawing.Color]::FromArgb(96,96,96); Line=[Drawing.Color]::FromArgb(172,172,172)
    Accent=[Drawing.Color]::FromArgb(40,140,80); AccentDark=[Drawing.Color]::FromArgb(32,118,66); Surface=[Drawing.Color]::White
    Page=[Drawing.SystemColors]::Control; Hover=[Drawing.Color]::FromArgb(230,238,248)
    Ok=[Drawing.Color]::DarkGreen; Warn=[Drawing.Color]::FromArgb(176,96,0); Error=[Drawing.Color]::Firebrick
}
# Flat, single-pixel borders as in v1; never fall back to the raised classic Windows button.
function Set-FlatButton($Button,[switch]$Primary) {
    $ui=$script:Ui
    if($Primary){$Button.FlatStyle='Flat';$Button.UseVisualStyleBackColor=$false;$Button.BackColor=$ui.Accent;$Button.ForeColor=[Drawing.Color]::White;$Button.FlatAppearance.BorderSize=0;$Button.FlatAppearance.MouseOverBackColor=$ui.AccentDark}
    # Back from green: the system colours again, not the white text it had.
    else{$Button.FlatStyle='Flat';$Button.ForeColor=$ui.Ink;$Button.BackColor=$ui.Page;$Button.UseVisualStyleBackColor=$false;$Button.FlatAppearance.BorderSize=1;$Button.FlatAppearance.BorderColor=$ui.Line;$Button.FlatAppearance.MouseOverBackColor=$ui.Hover;$Button.FlatAppearance.MouseDownBackColor=[Drawing.Color]::FromArgb(215,225,235)}
}

# Hover stays in WinForms rather than dispatching PowerShell for every child enter/leave.
if (-not ('ToolsHub.ToolCard' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
namespace ToolsHub {
    public class ToolCard : Panel {
        public bool Hovered { get; private set; }
        public ToolCard() {
            DoubleBuffered = true;
            ResizeRedraw = true;
        }
        protected override void OnControlAdded(ControlEventArgs e) {
            base.OnControlAdded(e);
            e.Control.MouseEnter += UpdateHover;
            e.Control.MouseLeave += UpdateHover;
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); UpdateHover(this,e); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); UpdateHover(this,e); }
        private void UpdateHover(object sender, EventArgs e) {
            bool next = ClientRectangle.Contains(PointToClient(Cursor.Position));
            if (next == Hovered) return;
            Hovered = next;
            Invalidate(new Rectangle(0,0,Width,1));
            Invalidate(new Rectangle(0,Height-1,Width,1));
            Invalidate(new Rectangle(0,0,1,Height));
            Invalidate(new Rectangle(Width-1,0,1,Height));
        }
    }
}
'@
}
# Chevron: one thin rounded mark for every dropdown (lists and menu buttons), drawn the same as on macOS.
function New-ChevronImage([Drawing.Color]$Color) {
    $bitmap=New-Object Drawing.Bitmap(12,8);$g=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $g.SmoothingMode='AntiAlias';$pen=New-Object Drawing.Pen($Color,1.5)
        $pen.StartCap='Round';$pen.EndCap='Round';$pen.LineJoin='Round'
        try{$g.DrawLines($pen,[Drawing.PointF[]]@((New-Object Drawing.PointF(2,2)),(New-Object Drawing.PointF(6,6)),(New-Object Drawing.PointF(10,2))))}finally{$pen.Dispose()}
    }finally{$g.Dispose()}
    return $bitmap
}
# A list ComboBox draws the system arrow; a small cover in the combo's own colours shows the chevron instead
# and opens the list like the arrow did. Call it once the combo is on its form (its height follows the font).
function Set-ComboChevron($Combo) {
    $ink=New-ChevronImage ([Drawing.Color]::FromArgb(68,68,68));$dim=New-ChevronImage ([Drawing.Color]::FromArgb(160,160,160))
    $normal=[Drawing.Color]::FromArgb(225,225,225);$hover=[Drawing.Color]::FromArgb(229,241,251);$off=[Drawing.Color]::FromArgb(204,204,204)
    $cover=New-Object Windows.Forms.Label -Property @{Name='Chevron';ImageAlign='MiddleCenter';Image=$ink;BackColor=$normal}
    $place={$cover.Bounds=New-Object Drawing.Rectangle(($Combo.Width-21),1,20,($Combo.Height-2))}.GetNewClosure()
    # PowerShell names ignore case: the colour is $hover, so the [bool] $IsHot never stands in for it.
    $look={param([bool]$IsHot)$cover.Image=$(if($Combo.Enabled){$ink}else{$dim});$cover.BackColor=$(if(-not $Combo.Enabled){$off}elseif($IsHot){$hover}else{$normal})}.GetNewClosure()
    $Combo.Controls.Add($cover);& $place;& $look $false
    $Combo.Add_SizeChanged($place);$Combo.Add_EnabledChanged({& $look $false}.GetNewClosure())
    $Combo.Add_MouseEnter({& $look $true}.GetNewClosure());$Combo.Add_MouseLeave({& $look $false}.GetNewClosure())
    $cover.Add_MouseDown({if($Combo.Enabled){[void]$Combo.Focus();$Combo.DroppedDown=-not $Combo.DroppedDown}}.GetNewClosure())
}
# Menu buttons (Tải về máy) carry the same chevron at the right; a disabled button greys it itself.
function Set-MenuButtonChevron($Button) {
    $Button.Image=New-ChevronImage ([Drawing.Color]::FromArgb(68,68,68));$Button.ImageAlign='MiddleRight';$Button.Padding='0,0,8,0'
}
