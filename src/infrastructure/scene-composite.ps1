# Restore the original room outside the localized furniture edit mask.
Add-Type -AssemblyName System.Drawing
if (-not ('ProductSceneComposite' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class ProductSceneComposite {
    private static Color OpaqueEdge(Color pixel, Color room, int x, int y, int width, int height) {
        if (pixel.A == 255) return pixel;
        if (x != 0 && y != 0 && x != width-1 && y != height-1)
            throw new InvalidOperationException("Edited image has transparency inside the edit region; an incomplete product cannot be exported.");
        return pixel.A == 0 ? room : Color.FromArgb(255,pixel.R,pixel.G,pixel.B);
    }
    public static void NormalizeCanvasEdges(string roomPath, string imagePath, string outputPath) {
        using (var room = new Bitmap(roomPath))
        using (var edit = new Bitmap(imagePath)) {
            if (room.Size != edit.Size) throw new InvalidOperationException("Approved image and archived room dimensions must match.");
            using (var result = new Bitmap(edit.Width,edit.Height,PixelFormat.Format32bppArgb)) {
                for (int y=0;y<edit.Height;y++) for(int x=0;x<edit.Width;x++)
                    result.SetPixel(x,y,OpaqueEdge(edit.GetPixel(x,y),room.GetPixel(x,y),x,y,edit.Width,edit.Height));
                result.Save(outputPath,ImageFormat.Png);
            }
        }
    }
    public static void Merge(string roomPath, string editPath, string maskPath, string outputPath) {
        using (var room = new Bitmap(roomPath))
        using (var edit = new Bitmap(editPath))
        using (var mask = new Bitmap(maskPath)) {
            if (room.Width != edit.Width || room.Height != edit.Height || room.Size != mask.Size)
                throw new InvalidOperationException("Room, edited image and edit mask must have identical pixel dimensions; resizing the room is forbidden.");
            long total = (long)room.Width * room.Height;
            long changed = 0;
            for (int y = 0; y < mask.Height; y++) for (int x = 0; x < mask.Width; x++) {
                Color m = mask.GetPixel(x,y);
                if (m.A != 255 || m.R != m.G || m.R != m.B)
                    throw new InvalidOperationException("Edit mask must be opaque grayscale: black for unchanged room, white for product, gray only for edge/shadow blending.");
                if (m.R > 0) changed++;
            }
            if (changed == 0 || changed > total * 0.85)
                throw new InvalidOperationException("Edit mask must be localized to furniture and contact shadows; empty or near-full-frame masks are rejected.");
            using (var result = new Bitmap(room.Width, room.Height, PixelFormat.Format32bppArgb)) {
                for (int y = 0; y < room.Height; y++) for (int x = 0; x < room.Width; x++) {
                    Color original = room.GetPixel(x,y);
                    int a = mask.GetPixel(x,y).R;
                    if (a == 0) { result.SetPixel(x,y,original); continue; }
                    Color replacement = edit.GetPixel(x,y);
                    if (replacement.A != 255) {
                        // Resampling can introduce a one-pixel canvas fringe even when
                        // all furniture is opaque. Preserve its RGB; never flatten holes
                        // inside the image, where missing furniture could be concealed.
                        replacement = OpaqueEdge(replacement,original,x,y,edit.Width,edit.Height);
                    }
                    result.SetPixel(x,y,Color.FromArgb(255,
                        (replacement.R*a + original.R*(255-a) + 127)/255,
                        (replacement.G*a + original.G*(255-a) + 127)/255,
                        (replacement.B*a + original.B*(255-a) + 127)/255));
                }
                result.Save(outputPath, ImageFormat.Png);
            }
        }
    }
}
'@
}

function Merge-ProductIntoScene($Request, [string]$ItemId, [int]$Attempt) {
    if (-not $Request.SceneBase) { return }
    if (-not (Test-Path -LiteralPath $Request.EditMask)) { throw 'Image technical validation failed: localized edit mask is missing; an unrestricted room redraw cannot be exported.' }
    $raw = Join-Path $script:Batch.Logs "$ItemId-attempt-$Attempt-generated.png"
    Copy-Item -LiteralPath $Request.Output -Destination $raw -Force
    Copy-Item -LiteralPath $Request.EditMask -Destination (Join-Path $script:Batch.Logs "$ItemId-attempt-$Attempt-mask.png") -Force
    $merged = Join-Path $script:Batch.Logs "$ItemId-attempt-$Attempt-composite.png"
    try { [ProductSceneComposite]::Merge($Request.SceneBase, $raw, $Request.EditMask, $merged) }
    catch { throw "Image technical validation failed: room preservation failed. $($_.Exception.Message)" }
    Copy-Item -LiteralPath $merged -Destination $Request.Output -Force
}
