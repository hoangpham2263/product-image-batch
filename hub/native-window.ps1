# Shared native Windows frame for the tools that are web pages on macOS (Grok Video Prompt, Content MXH): the same
# window, header and look as their pages (hub/assets/tool.css), drawn with WinForms only, as Product Review's window
# is. No browser, no local server. Each tool owns its controls and workspace.
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
# Windows PowerShell 5.1 starts on old TLS; the API (Cloudflare) needs 1.2.
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'winforms.ps1')
. (Join-Path $PSScriptRoot 'setup/setup-dialog.ps1')
. (Join-Path $PSScriptRoot 'update-dialog.ps1')
$script:NativeFont=New-Object Drawing.Font('Segoe UI',10)

# tool.css in WinForms. Group = .group (grey border, heading inside at 14,10); Box = a white box (pre.out, .listbox,
# the dashed .empty-note); CardList = .listbox of .card buttons; Toggle = a platform button with its logo; Tile = an
# image tile; Row = a product row (.qrow). C# 5, which Windows PowerShell 5.1 compiles.
if (-not ('ToolsHubNative.Group' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;
namespace ToolsHubNative {
    public static class Look {
        public static readonly Color Ink = Color.FromArgb(30, 30, 30);
        public static readonly Color Muted = Color.FromArgb(96, 96, 96);
        public static readonly Color Line = Color.FromArgb(172, 172, 172);
        public static readonly Color Accent = Color.FromArgb(40, 140, 80);
        public static readonly Color Hover = Color.FromArgb(230, 238, 248);
        // A square from the middle of a picture (object-fit: cover), read without keeping the file open.
        public static Bitmap Thumb(string path, int size) {
            byte[] bytes = File.ReadAllBytes(path);
            using (MemoryStream stream = new MemoryStream(bytes))
            using (Image source = Image.FromStream(stream)) {
                Bitmap bitmap = new Bitmap(size, size);
                using (Graphics g = Graphics.FromImage(bitmap)) {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    int side = Math.Min(source.Width, source.Height);
                    Rectangle from = new Rectangle((source.Width - side) / 2, (source.Height - side) / 2, side, side);
                    g.DrawImage(source, new Rectangle(0, 0, size, size), from, GraphicsUnit.Pixel);
                }
                return bitmap;
            }
        }
        // A logo in grey at half strength, for a platform that is off (filter: grayscale(1); opacity: .5).
        public static Bitmap Faded(Image source) {
            Bitmap bitmap = new Bitmap(source.Width, source.Height);
            ColorMatrix matrix = new ColorMatrix(new float[][] {
                new float[] { .299f, .299f, .299f, 0, 0 }, new float[] { .587f, .587f, .587f, 0, 0 },
                new float[] { .114f, .114f, .114f, 0, 0 }, new float[] { 0, 0, 0, .5f, 0 }, new float[] { 0, 0, 0, 0, 1 } });
            using (ImageAttributes attributes = new ImageAttributes())
            using (Graphics g = Graphics.FromImage(bitmap)) {
                attributes.SetColorMatrix(matrix);
                g.DrawImage(source, new Rectangle(0, 0, source.Width, source.Height), 0, 0, source.Width, source.Height, GraphicsUnit.Pixel, attributes);
            }
            return bitmap;
        }
        public static void DrawBorder(Graphics g, Rectangle r, Color color, bool dashed) {
            using (Pen pen = new Pen(color)) {
                if (dashed) pen.DashStyle = DashStyle.Dash;
                g.DrawRectangle(pen, r.X, r.Y, r.Width - 1, r.Height - 1);
            }
        }
    }
    public class Group : Panel {
        string heading = "";
        public Group() { DoubleBuffered = true; ResizeRedraw = true; Padding = new Padding(14, 38, 14, 14); }
        public string Heading { get { return heading; } set { heading = value ?? ""; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            Look.DrawBorder(e.Graphics, ClientRectangle, Look.Line, false);
            if (heading.Length > 0)
                TextRenderer.DrawText(e.Graphics, heading, Font, new Rectangle(14, 10, Math.Max(1, Width - 28), 22), Look.Ink,
                    TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
        }
    }
    public class Box : Panel {
        string message = ""; bool dashed, videoIcon; Color border = Look.Line;
        public Box() { DoubleBuffered = true; ResizeRedraw = true; BackColor = Color.White; }
        public string Message { get { return message; } set { message = value ?? ""; Invalidate(); } }
        public bool Dashed { get { return dashed; } set { dashed = value; Invalidate(); } }
        public bool VideoIcon { get { return videoIcon; } set { videoIcon = value; Invalidate(); } }
        public Color Border { get { return border; } set { border = value; Invalidate(); } }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            Look.DrawBorder(g, ClientRectangle, border, dashed);
            if (message.Length == 0) return;
            TextFormatFlags flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix;
            if (!videoIcon) {
                TextRenderer.DrawText(g, message, Font, new Rectangle(16, 16, Math.Max(1, Width - 32), Math.Max(1, Height - 32)), Look.Muted, flags | TextFormatFlags.VerticalCenter);
                return;
            }
            // The video mark of the macOS page (a screen with a play triangle), 36px, above the text.
            float x = Width / 2f - 18, y = Height / 2f - 46;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(Look.Muted, 1.5f)) {
                pen.LineJoin = LineJoin.Round;
                g.DrawRectangle(pen, x + 4.5f, y + 7.5f, 27f, 21f);
                g.DrawPolygon(pen, new PointF[] { new PointF(x + 15, y + 13.5f), new PointF(x + 22.5f, y + 18), new PointF(x + 15, y + 22.5f) });
            }
            TextRenderer.DrawText(g, message, Font, new Rectangle(16, Height / 2 - 2, Math.Max(1, Width - 32), Math.Max(1, Height / 2 - 14)), Look.Muted, flags);
        }
    }
    public class CardList : ListBox {
        int hover = -1;
        public CardList() {
            DrawMode = DrawMode.OwnerDrawFixed; ItemHeight = 54; IntegralHeight = false; BorderStyle = BorderStyle.None;
            SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            Graphics g = e.Graphics; Rectangle b = e.Bounds;
            using (SolidBrush white = new SolidBrush(Color.White)) g.FillRectangle(white, b);
            if (e.Index < 0 || e.Index >= Items.Count) return;
            bool on = e.Index == SelectedIndex;
            // 46px cards, 8px apart.
            Rectangle card = new Rectangle(b.X, b.Y, b.Width, b.Height - 8);
            using (SolidBrush fill = new SolidBrush(e.Index == hover ? Look.Hover : Color.White)) g.FillRectangle(fill, card);
            Look.DrawBorder(g, card, on ? Look.Accent : Look.Line, false);
            if (on) using (SolidBrush accent = new SolidBrush(Look.Accent)) g.FillRectangle(accent, card.X, card.Y, 3, card.Height);
            TextRenderer.DrawText(g, Convert.ToString(Items[e.Index]), Font, new Rectangle(card.X + 14, card.Y, Math.Max(1, card.Width - 28), card.Height), Look.Ink,
                TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
        protected override void OnSelectedIndexChanged(EventArgs e) { Invalidate(); base.OnSelectedIndexChanged(e); }
        protected override void OnMouseMove(MouseEventArgs e) { base.OnMouseMove(e); SetHover(IndexFromPoint(e.Location)); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); SetHover(-1); }
        void SetHover(int index) {
            if (index == hover) return;
            int old = hover; hover = index; Redraw(old); Redraw(index);
        }
        void Redraw(int index) { if (index >= 0 && index < Items.Count) Invalidate(GetItemRectangle(index)); }
    }
    public class Toggle : Control {
        bool pressed, hot; Image logo, logoOff;
        public Toggle() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.White; Cursor = Cursors.Hand;
        }
        public bool Pressed { get { return pressed; } set { pressed = value; Invalidate(); } }
        public Image Logo { get { return logo; } set { logo = value; Invalidate(); } }
        public Image LogoOff { get { return logoOff; } set { logoOff = value; Invalidate(); } }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); hot = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hot = false; Invalidate(); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e) {
            Graphics g = e.Graphics;
            using (SolidBrush fill = new SolidBrush(hot ? Look.Hover : Color.White)) g.FillRectangle(fill, ClientRectangle);
            Look.DrawBorder(g, ClientRectangle, pressed ? Look.Accent : Look.Line, false);
            if (pressed) using (SolidBrush accent = new SolidBrush(Look.Accent)) g.FillRectangle(accent, 0, Height - 3, Width, 3);
            Image image = pressed || logoOff == null ? logo : logoOff;
            TextFormatFlags flags = TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
            Size text = TextRenderer.MeasureText(g, Text, Font, Size.Empty, flags);
            int x = Math.Max(4, (Width - text.Width - (image != null ? 22 : 0)) / 2);
            if (image != null) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(image, new Rectangle(x, (Height - 16) / 2, 16, 16));
                x += 22;
            }
            TextRenderer.DrawText(g, Text, Font, new Rectangle(x, 0, Math.Max(1, Width - x - 2), Height), Look.Ink, flags | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }
    public class Tile : Panel {
        Image picture; string caption = ""; bool dashed, clickable, hot; Color border = Look.Line;
        public Tile() { DoubleBuffered = true; ResizeRedraw = true; BackColor = Color.White; }
        public Image Picture { get { return picture; } set { picture = value; Invalidate(); } }
        public string Caption { get { return caption; } set { caption = value ?? ""; Invalidate(); } }
        public bool Dashed { get { return dashed; } set { dashed = value; Invalidate(); } }
        public Color Border { get { return border; } set { border = value; Invalidate(); } }
        public bool Clickable { get { return clickable; } set { clickable = value; Cursor = value ? Cursors.Hand : Cursors.Default; } }
        public bool Lit { get { return hot; } set { hot = value; Invalidate(); } }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); if (clickable) Lit = true; }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (clickable) Lit = false; }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            if (hot) using (SolidBrush fill = new SolidBrush(Look.Hover)) g.FillRectangle(fill, ClientRectangle);
            if (picture != null) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(picture, new Rectangle(1, 1, Width - 2, Height - 2));
            } else if (caption.Length > 0) {
                TextRenderer.DrawText(g, caption, Font, new Rectangle(6, 6, Math.Max(1, Width - 12), Math.Max(1, Height - 12)), Look.Muted,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            }
            Look.DrawBorder(g, ClientRectangle, hot ? Look.Accent : border, dashed);
        }
    }
    public class Row : Panel {
        bool current, hot;
        public Row() { DoubleBuffered = true; ResizeRedraw = true; BackColor = Color.White; Cursor = Cursors.Hand; }
        public bool Current { get { return current; } set { current = value; Invalidate(); } }
        protected override void OnControlAdded(ControlEventArgs e) {
            base.OnControlAdded(e);
            e.Control.MouseEnter += Track; e.Control.MouseLeave += Track;
        }
        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); Track(this, e); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); Track(this, e); }
        void Track(object sender, EventArgs e) {
            bool next = ClientRectangle.Contains(PointToClient(Control.MousePosition));
            if (next == hot) return;
            hot = next; BackColor = hot ? Look.Hover : Color.White;
        }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            Look.DrawBorder(e.Graphics, ClientRectangle, current ? Look.Accent : Look.Line, false);
            if (current) using (SolidBrush accent = new SolidBrush(Look.Accent)) e.Graphics.FillRectangle(accent, 0, 0, 3, Height);
        }
    }
}
'@
}

# The window as Product Review's: 1120 x 840, a 64px header with "← Menu" (opened from the menu), the title, Cấu hình
# and Cập nhật (green with the version once a newer one is out) 24px from the right, then the body: 20px left, 24px
# right, 20px at the bottom, 14px under the header.
function New-NativeToolWindow([string]$Title,[string]$ToolRoot) {
    $hubRoot=[IO.Path]::GetFullPath((Join-Path $ToolRoot '../..'))
    $logs=Join-Path $hubRoot 'workspace/logs'
    $errorLog=Join-Path $ToolRoot 'workspace/app-errors.log'
    # An error in a click is written down and shown, not lost behind the hidden console.
    [Windows.Forms.Application]::add_ThreadException({
        param($sender,$eventArgs)
        try {
            New-Item -ItemType Directory -Force (Split-Path $errorLog -Parent) | Out-Null
            [IO.File]::AppendAllText($errorLog,((Get-Date).ToString('o')+"`r`n"+$eventArgs.Exception.ToString()+"`r`n"))
        } catch { }
        [void][Windows.Forms.MessageBox]::Show("Có lỗi: $($eventArgs.Exception.Message)`r`n`r`nChi tiết đã lưu trong workspace/app-errors.log.",$Title,'OK','Warning')
    }.GetNewClosure())
    $versionFile=Join-Path $hubRoot 'workspace/version.txt'
    $version=if(Test-Path -LiteralPath $versionFile){(Get-Content -LiteralPath $versionFile -Raw).Trim()}else{''}
    $form=New-Object Windows.Forms.Form -Property @{Text=("$Title $version").Trim();Size='1120,840';MinimumSize='1040,760';StartPosition='CenterScreen';Font=$script:NativeFont;BackColor=[Drawing.SystemColors]::Control;ForeColor=$script:Ui.Ink}
    $iconPng=Join-Path $ToolRoot 'icon.png'
    if(Test-Path -LiteralPath $iconPng){try{$form.Icon=[Drawing.Icon]::FromHandle((New-Object Drawing.Bitmap($iconPng)).GetHicon())}catch{}}
    # Full width before the buttons are anchored right, as in Product Review.
    $header=New-Object Windows.Forms.Panel -Property @{Name='NativeHeader';Size=(New-Object Drawing.Size($form.ClientSize.Width,64));Dock='Top'}
    $fromHub=[bool]$env:TOOLS_HUB_MENU
    $menu=New-Object Windows.Forms.Button -Property @{Text='← Menu';Location='20,16';Size='90,32';Visible=$fromHub}
    $titleLabel=New-Object Windows.Forms.Label -Property @{Text=$Title;Location=$(if($fromHub){'122,19'}else{'20,19'});AutoSize=$true;Font=(New-Object Drawing.Font('Segoe UI',13));UseMnemonic=$false}
    $update=New-Object Windows.Forms.Button -Property @{Text='Cập nhật';Size='100,32';Anchor='Top,Right'}
    $update.Location=New-Object Drawing.Point(($header.Width-24-100),16)
    $config=New-Object Windows.Forms.Button -Property @{Text='Cấu hình';Size='100,32';Anchor='Top,Right'}
    $config.Location=New-Object Drawing.Point(($update.Left-8-100),16)
    foreach($button in @($menu,$update,$config)){Set-FlatButton $button}
    # Handlers read what they need from Tag: a closure would not see the functions dot-sourced into the tool's script.
    $menu.Add_Click({param($sender) $sender.FindForm().Close()})
    $config.Tag=$hubRoot
    $config.Add_Click({param($sender) Show-HubSetup $sender.FindForm() ([string]$sender.Tag)})
    $check=@{Root=$hubRoot;Logs=$logs;Current=$version;Proc=$null;Out=(Join-Path $logs "update-check-$PID.txt");Button=$update;Config=$config}
    $update.Tag=$check
    $update.Add_Click({
        param($sender)
        $info=$sender.Tag;$owner=$sender.FindForm()
        New-Item -ItemType Directory -Force $info.Logs | Out-Null
        if(Show-UpdateDialog $owner $info.Root $info.Logs $info.Current){$owner.Tag='updated';$owner.Close()}
    })
    # A newer release shows on Cập nhật, checked in the background once the window is up (hub/update.ps1 -Check).
    $checkTimer=New-Object Windows.Forms.Timer -Property @{Interval=500;Tag=$check}
    $checkTimer.Add_Tick({
        param($timer)
        $info=$timer.Tag
        if(-not $info.Proc -or -not $info.Proc.HasExited){return}
        $timer.Stop()
        try {
            $next=Get-Content -LiteralPath $info.Out -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if($info.Proc.ExitCode -eq 0 -and $next -and $next.Trim() -match '^v?\d+\.\d+\.\d+$'){
                $button=$info.Button;$button.Text='Cập nhật '+$next.Trim();$button.Width=150;$button.Left=$button.Parent.ClientSize.Width-24-150
                Set-FlatButton $button -Primary;$info.Config.Left=$button.Left-8-$info.Config.Width
            }
        } catch { } finally { $info.Proc.Dispose();$info.Proc=$null;Remove-Item -LiteralPath $info.Out -Force -ErrorAction SilentlyContinue }
    })
    $header.Tag=$checkTimer
    $form.Add_Shown({
        param($sender)
        # No button starts focused: Windows would draw it with a thick black border.
        $sender.ActiveControl=$null
        $timer=$sender.Controls['NativeHeader'].Tag;$info=$timer.Tag
        try {
            New-Item -ItemType Directory -Force $info.Logs | Out-Null
            $info.Proc=Start-Process powershell.exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $info.Out -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $info.Root 'hub/update.ps1')+'"'),'-Root',('"'+$info.Root+'"'),'-Check')
            [void]$info.Proc.Handle;$timer.Start()
        } catch { }
    })
    $form.Add_FormClosed({param($sender) $timer=$sender.Controls['NativeHeader'].Tag;$timer.Stop();$timer.Dispose()})
    $header.Controls.AddRange(@($menu,$titleLabel,$config,$update))
    $body=New-Object Windows.Forms.Panel -Property @{Dock='Fill';Padding='20,14,24,20'}
    # Toast: the short message at the bottom of the page (.toast), gone after 1.8 s.
    $toast=New-Object Windows.Forms.Label -Property @{Name='NativeToast';AutoSize=$true;Visible=$false;BackColor=$script:Ui.Ink;ForeColor=[Drawing.Color]::White;Padding='14,8,14,8';UseMnemonic=$false}
    $toastTimer=New-Object Windows.Forms.Timer -Property @{Interval=1800;Tag=$toast}
    $toastTimer.Add_Tick({param($timer) $timer.Stop();$timer.Tag.Visible=$false})
    $toast.Tag=$toastTimer
    $form.Controls.AddRange(@($toast,$header,$body))
    $body.BringToFront();$toast.BringToFront()
    $form.Add_FormClosed({param($sender) $sender.Controls['NativeToast'].Tag.Dispose()})
    return @{Form=$form;Body=$body;Menu=$menu;Root=$hubRoot}
}
# Shows the window until it closes. After Cập nhật: back in the menu that opened it, which restarts on exit code 3
# (hub/launch.ps1) with the new files; opened on its own, the tool opens again.
function Show-NativeToolWindow($Shell,[string]$Entry) {
    [void]$Shell.Form.ShowDialog()
    if($Shell.Form.Tag -ne 'updated'){return}
    if($env:TOOLS_HUB_MENU -eq 'return'){exit 3}
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$Entry+'"'))
}
function Show-NativeToast($Form,[string]$Text) {
    $toast=$Form.Controls['NativeToast']
    $toast.Text=$Text;$toast.Size=$toast.PreferredSize
    $toast.Location=New-Object Drawing.Point([int](($Form.ClientSize.Width-$toast.Width)/2),($Form.ClientSize.Height-24-$toast.Height))
    $toast.Visible=$true;$toast.BringToFront();$toast.Tag.Stop();$toast.Tag.Start()
}
# Docked children in reading order (the first one outermost): WinForms docks the last-added first, so each is
# brought to the front in turn.
function Add-NativeStack($Parent,[object[]]$Controls) {
    foreach($control in $Controls){$Parent.Controls.Add($control)}
    foreach($control in $Controls){$control.BringToFront()}
}
function New-NativeGap([string]$Dock,[int]$Size) {
    $gap=New-Object Windows.Forms.Panel -Property @{Dock=$Dock}
    if($Dock -in @('Left','Right')){$gap.Width=$Size}else{$gap.Height=$Size}
    return $gap
}
function New-NativeGroup([string]$Heading,[string]$Dock='Fill',[int]$Size=0) {
    $group=New-Object ToolsHubNative.Group -Property @{Heading=$Heading;Dock=$Dock}
    if($Size){if($Dock -in @('Left','Right')){$group.Width=$Size}else{$group.Height=$Size}}
    # A group without a heading (the run row): 11px above and below, as .run.
    if(-not $Heading){$group.Padding='14,11,14,11'}
    return $group
}
function New-NativeLabel([string]$Text) {
    return New-Object Windows.Forms.Label -Property @{Text=$Text;Dock='Top';Height=20;AutoEllipsis=$true;UseMnemonic=$false}
}
function New-NativeButton([string]$Text,[switch]$Primary) {
    $button=New-Object Windows.Forms.Button -Property @{Text=$Text;Height=32;Width=130;UseMnemonic=$false}
    Set-FlatButton $button -Primary:$Primary
    return $button
}
# .seg: system buttons side by side sharing a border; the pressed one green (Update-NativeSeg). -Fill shares the
# width out evenly (#tones).
function New-NativeSeg([object[]]$Items,[switch]$Fill) {
    $seg=New-Object Windows.Forms.Panel -Property @{Height=32;Dock='Top';Tag=[bool]$Fill}
    foreach($item in $Items){
        $button=New-Object Windows.Forms.Button -Property @{Text=[string]$item.Text;Tag=[string]$item.Id;Height=32;UseMnemonic=$false}
        if($item.Image){$button.Image=$item.Image;$button.TextImageRelation='ImageBeforeText'}
        Set-FlatButton $button
        $seg.Controls.Add($button)
    }
    Set-NativeSegLayout $seg
    $seg.Add_Resize({param($sender) if($sender.Tag){Set-NativeSegLayout $sender}})
    return $seg
}
function Set-NativeSegLayout($Seg) {
    $count=$Seg.Controls.Count;$x=0
    for($i=0;$i -lt $count;$i++){
        $button=$Seg.Controls[$i]
        if($Seg.Tag){$button.Width=[int][Math]::Round(($i+1)*($Seg.ClientSize.Width-1)/$count)-$x+1}
        else{$button.Width=[Windows.Forms.TextRenderer]::MeasureText($button.Text,$script:NativeFont).Width+$(if($button.Image){46}else{32})}
        $button.Location=New-Object Drawing.Point($x,0);$x+=$button.Width-1
    }
}
function Update-NativeSeg($Seg,[string]$Pressed) {
    foreach($button in $Seg.Controls){Set-FlatButton $button -Primary:([string]$button.Tag -eq $Pressed)}
}
# .listbox of .card buttons: a white box with a black border, the cards inside. Items are the cards' text.
function New-NativeCardList {
    $frame=New-Object ToolsHubNative.Box -Property @{Border=[Drawing.Color]::Black;Padding='10,10,10,2';Dock='Fill'}
    $list=New-Object ToolsHubNative.CardList -Property @{Dock='Fill'}
    $frame.Controls.Add($list)
    return @{Frame=$frame;List=$list}
}
# pre.out: white, grey border, Consolas 12.5px.
function New-NativeOutput {
    $frame=New-Object ToolsHubNative.Box -Property @{Padding='12,10,2,10';Dock='Fill'}
    $text=New-Object Windows.Forms.TextBox -Property @{Dock='Fill';Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';WordWrap=$true;BorderStyle='None';BackColor=[Drawing.Color]::White;Font=(New-Object Drawing.Font('Consolas',9.5))}
    $frame.Controls.Add($text)
    return @{Frame=$frame;Text=$text}
}
function Read-NativeState([string]$Path,$Default) {
    try {return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json} catch {return $Default}
}
function Write-NativeState([string]$Path,$State) {
    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}
