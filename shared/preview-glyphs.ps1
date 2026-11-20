# Draws a contact sheet of the glyph set (shared/glyphs.json) to a PNG, using the same rules as the
# apps: grid 5 x 7, strokes with square caps and mitred joins, mirrored glyphs flipped left-right.
#   powershell -File shared\preview-glyphs.ps1 -Out sheet.png [-Cell 18]
param([string]$Out = (Join-Path $PSScriptRoot 'glyph-sheet.png'), [int]$Cell = 16)
Add-Type -AssemblyName System.Drawing
$data = Get-Content (Join-Path $PSScriptRoot 'glyphs.json') -Raw | ConvertFrom-Json
$cols = $data.grid.cols; $rows = $data.grid.rows
$perRow = 16
$scale = $Cell                                   # pixels per grid unit
$cw = ($cols + 2) * $scale                       # cell box with margins
$ch = ($rows + 2) * $scale
$n = $data.glyphs.Count
$lines = [Math]::Ceiling($n / $perRow)
$bmp = New-Object Drawing.Bitmap ($perRow * $cw), ($lines * $ch)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([Drawing.Color]::Black)
$pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 57, 255, 136)), ([single]($scale * 0.55))
$pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'; $pen.LineJoin = 'Miter'
for ($i = 0; $i -lt $n; $i++) {
  $gl = $data.glyphs[$i]
  $ox = ($i % $perRow) * $cw + $scale
  $oy = [Math]::Floor($i / $perRow) * $ch + $scale
  foreach ($stroke in $gl.strokes) {
    $pts = @()
    foreach ($p in $stroke) {
      $x = [double]$p[0]; if ($gl.mirror) { $x = ($cols - 1) - $x }
      $pts += New-Object Drawing.PointF ([single]($ox + $x * $scale + $scale / 2)), ([single]($oy + [double]$p[1] * $scale + $scale / 2))
    }
    if ($pts.Count -ge 2) { $g.DrawLines($pen, [Drawing.PointF[]]$pts) }
  }
}
$g.Dispose()
$bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
Write-Output "wrote $Out ($($bmp.Width)x$($bmp.Height))"
