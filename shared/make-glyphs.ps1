# Builds the BAVtrix glyph set: shared/glyphs.json plus the generated Swift and Kotlin sources.
#
# Every glyph is a few straight strokes on a 5 x 7 grid (x 0..4, y 0..6, y grows downwards).
# The digits, letters and symbols below are drawn by hand in a plain angular stroke style.
# The "pseudo-kana" shapes are invented: they come from a seeded random generator (rules: bars,
# verticals or diagonals hanging from the bars, optional hooks and ticks that touch the shape), so
# the result is identical on every run and does not copy any existing typeface.
#
#   powershell -File shared\make-glyphs.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
$cols = 5; $rows = 7

# --- hand drawn glyphs: id => "polyline; polyline; ..." with "x,y x,y ..." ---
$hand = [ordered]@{
  'd0'='0,0 4,0 4,6 0,6 0,0;1,5 3,1'
  'd1'='1,1 2,0 2,6;0,6 4,6'
  'd2'='0,1 1,0 3,0 4,1 4,2 0,6 4,6'
  'd3'='0,0 4,0 4,6 0,6;1,3 4,3'
  'd4'='3,0 0,4 4,4;3,2 3,6'
  'd5'='4,0 0,0 0,3 3,3 4,4 4,5 3,6 0,6'
  'd6'='4,0 1,0 0,1 0,6 4,6 4,3 0,3'
  'd7'='0,0 4,0 1,6;1,3 3,3'
  'd8'='0,0 4,0 4,6 0,6 0,0;0,3 4,3'
  'd9'='4,6 4,0 0,0 0,3 4,3'
  'lA'='0,6 2,0 4,6;1,4 3,4'
  'lB'='0,0 0,6 3,6 4,5 4,4 3,3 0,3;0,0 3,0 4,1 4,2 3,3'
  'lD'='0,0 0,6 3,6 4,5 4,1 3,0 0,0'
  'lE'='4,0 0,0 0,6 4,6;0,3 3,3'
  'lF'='4,0 0,0 0,6;0,3 3,3'
  'lG'='4,1 3,0 1,0 0,1 0,5 1,6 4,6 4,3 2,3'
  'lH'='0,0 0,6;4,0 4,6;0,3 4,3'
  'lK'='0,0 0,6;4,0 0,3 4,6'
  'lL'='0,0 0,6 4,6'
  'lM'='0,6 0,0 2,3 4,0 4,6'
  'lN'='0,6 0,0 4,6 4,0'
  'lP'='0,6 0,0 3,0 4,1 4,2 3,3 0,3'
  'lR'='0,6 0,0 3,0 4,1 4,2 3,3 0,3;2,3 4,6'
  'lT'='0,0 4,0;2,0 2,6'
  'lU'='0,0 0,5 1,6 3,6 4,5 4,0'
  'lV'='0,0 2,6 4,0'
  'lW'='0,0 1,6 2,3 3,6 4,0'
  'lX'='0,0 4,6;4,0 0,6'
  'lY'='0,0 2,3 4,0;2,3 2,6'
  'lZ'='0,0 4,0 0,6 4,6'
  'sPlus'='2,1 2,5;0,3 4,3'
  'sMinus'='0,3 4,3'
  'sEq'='0,2 4,2;0,4 4,4'
  'sLt'='4,0 0,3 4,6'
  'sGt'='0,0 4,3 0,6'
  'sColon'='2,1 2,2;2,4 2,5'
  'sStar'='2,0 2,6;0,2 4,4;4,2 0,4'
  'sSlash'='4,0 0,6'
  'sBar'='2,0 2,6'
  'sCorner'='0,0 4,0 4,6'
}
$mirroredLetters = 'lB','lF','lG','lK','lM','lN','lP','lR','lY','lZ','sLt','sGt','sCorner'

# A shape is a List of strokes; a stroke is a List of [x, y] int arrays. (Plain PowerShell arrays
# would be flattened when a glyph has a single stroke, so lists are used throughout.)
function NewList { New-Object 'System.Collections.Generic.List[object]' }
function Pt([int]$x, [int]$y) { , ([int[]]@($x, $y)) }

$script:seed = [int64]20261119
function NextRand([int]$n) {
  # 32-bit linear congruential generator, high bits used
  $script:seed = ($script:seed * 1664525 + 1013904223) % 4294967296
  return [int](($script:seed -shr 16) % $n)
}
function Clamp([int]$v, [int]$lo, [int]$hi) { [Math]::Max($lo, [Math]::Min($hi, $v)) }

function ParseHand([string]$spec) {
  $strokes = NewList
  foreach ($s in $spec.Split(';')) {
    $stroke = NewList
    foreach ($p in $s.Trim().Split(' ')) { $xy = $p.Split(','); $stroke.Add((Pt ([int]$xy[0]) ([int]$xy[1]))) }
    $strokes.Add($stroke)
  }
  return , $strokes
}

function NewKana {
  $strokes = NewList
  # 1. a top bar (row 0 or 1), not always full width
  $ty = NextRand 2
  $tx0 = NextRand 2; $tx1 = 3 + (NextRand 2)
  $s = NewList; $s.Add((Pt $tx0 $ty)); $s.Add((Pt $tx1 $ty)); $strokes.Add($s)
  # 2. optional middle bar (row 3 or 4)
  $my = -1
  if ((NextRand 2) -eq 0) {
    $my = 3 + (NextRand 2)
    $mx0 = NextRand 3; $mx1 = 2 + (NextRand 3)
    if ($mx1 -le $mx0) { $mx1 = [Math]::Min(4, $mx0 + 2) }
    $s = NewList; $s.Add((Pt $mx0 $my)); $s.Add((Pt $mx1 $my)); $strokes.Add($s)
  }
  # 3. one or two verticals / diagonals hanging from the top bar down to the bottom rows
  $v = 1 + (NextRand 2)
  $usedX = NewList
  for ($i = 0; $i -lt $v; $i++) {
    $sx = $tx0 + (NextRand ($tx1 - $tx0 + 1))
    if ($usedX.Contains($sx)) { $sx = Clamp ($sx + 1) 0 4 }
    $usedX.Add($sx)
    $ex = Clamp ($sx + (NextRand 5) - 2) 0 4
    $ey = 5 + (NextRand 2)
    $s = NewList; $s.Add((Pt $sx $ty)); $s.Add((Pt $ex $ey))
    if ((NextRand 3) -eq 0) {                    # a hook at the bottom
      $hx = Clamp ($ex + (NextRand 2) * 2 - 1) 0 4
      $s.Add((Pt $hx $ey))
    }
    $strokes.Add($s)
  }
  # 4. optional side stroke on the left or right edge
  if ((NextRand 5) -lt 2) {
    $sideX = (NextRand 2) * 4
    $sy0 = 2 + (NextRand 2)
    $s = NewList; $s.Add((Pt $sideX $sy0)); $s.Add((Pt $sideX (4 + (NextRand 3)))); $strokes.Add($s)
  }
  # 5. optional small tick touching the end of the last stroke
  if ((NextRand 5) -lt 2) {
    $last = $strokes[$strokes.Count - 1]; $end = $last[$last.Count - 1]
    $tx = Clamp ($end[0] + (NextRand 2) * 2 - 1) 0 4
    $s = NewList; $s.Add((Pt $end[0] $end[1])); $s.Add((Pt $tx (Clamp ($end[1] - 1) 0 6))); $strokes.Add($s)
  }
  return , $strokes
}
function Key($strokes) { (($strokes | ForEach-Object { ($_ | ForEach-Object { "$($_[0]),$($_[1])" }) -join '>' }) -join '|') }

$glyphs = NewList
foreach ($k in $hand.Keys) {
  $glyphs.Add([pscustomobject]@{ id = $k; mirror = ($mirroredLetters -contains $k); strokes = (ParseHand $hand[$k]) })
}
$seen = @{}
$n = 0
while ($n -lt 40) {
  $st = NewKana
  $key = Key $st
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = $true
  $glyphs.Add([pscustomobject]@{ id = ('k{0:D2}' -f $n); mirror = ((NextRand 2) -eq 1); strokes = $st })
  $n++
}

# --- shared JSON (one glyph per line, compact) ---
function StrokesJson($g) { '[' + (($g.strokes | ForEach-Object { '[' + (($_ | ForEach-Object { "[$($_[0]),$($_[1])]" }) -join ',') + ']' }) -join ',') + ']' }
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('{')
[void]$sb.AppendLine('  "version": 1,')
[void]$sb.AppendLine("  `"grid`": { `"cols`": $cols, `"rows`": $rows },")
[void]$sb.AppendLine('  "note": "Own glyph set. strokes = polylines of [x,y] grid points (y grows downwards); mirror = drawn flipped left to right.",')
[void]$sb.AppendLine('  "glyphs": [')
for ($i = 0; $i -lt $glyphs.Count; $i++) {
  $g = $glyphs[$i]; $m = if ($g.mirror) { 'true' } else { 'false' }
  $comma = if ($i -lt $glyphs.Count - 1) { ',' } else { '' }
  [void]$sb.AppendLine("    { `"id`": `"$($g.id)`", `"mirror`": $m, `"strokes`": $(StrokesJson $g) }$comma")
}
[void]$sb.AppendLine('  ]')
[void]$sb.AppendLine('}')
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'glyphs.json'), $sb.ToString(), $utf8)

# --- generated sources (flat int arrays: x0,y0,x1,y1,...) ---
function FlatStroke($s) { ($s | ForEach-Object { "$($_[0]),$($_[1])" }) -join ',' }

$swift = New-Object Text.StringBuilder
[void]$swift.AppendLine('// Generated by shared/make-glyphs.ps1 from shared/glyphs.json. Do not edit by hand.')
[void]$swift.AppendLine('')
[void]$swift.AppendLine('/// One glyph: strokes are flat [x0, y0, x1, y1, ...] polylines on the grid.')
[void]$swift.AppendLine('public struct GlyphShape {')
[void]$swift.AppendLine('    public let id: String')
[void]$swift.AppendLine('    public let mirror: Bool')
[void]$swift.AppendLine('    public let strokes: [[Int]]')
[void]$swift.AppendLine('}')
[void]$swift.AppendLine('')
[void]$swift.AppendLine('public enum GlyphData {')
[void]$swift.AppendLine("    public static let cols = $cols")
[void]$swift.AppendLine("    public static let rows = $rows")
[void]$swift.AppendLine('    public static let shapes: [GlyphShape] = [')
foreach ($g in $glyphs) {
  $m = if ($g.mirror) { 'true' } else { 'false' }
  $arr = ($g.strokes | ForEach-Object { '[' + (FlatStroke $_) + ']' }) -join ', '
  [void]$swift.AppendLine("        GlyphShape(id: `"$($g.id)`", mirror: $m, strokes: [$arr]),")
}
[void]$swift.AppendLine('    ]')
[void]$swift.AppendLine('}')
[IO.File]::WriteAllText((Join-Path $root 'apple\BAVtrixCore\Sources\BAVtrixCore\GlyphData.swift'), $swift.ToString(), $utf8)

$kt = New-Object Text.StringBuilder
[void]$kt.AppendLine('// Generated by shared/make-glyphs.ps1 from shared/glyphs.json. Do not edit by hand.')
[void]$kt.AppendLine('package app.bavtrix.core')
[void]$kt.AppendLine('')
[void]$kt.AppendLine('/** One glyph: strokes are flat [x0, y0, x1, y1, ...] polylines on the grid. */')
[void]$kt.AppendLine('class GlyphShape(val id: String, val mirror: Boolean, val strokes: List<IntArray>)')
[void]$kt.AppendLine('')
[void]$kt.AppendLine('object GlyphData {')
[void]$kt.AppendLine("    const val COLS = $cols")
[void]$kt.AppendLine("    const val ROWS = $rows")
[void]$kt.AppendLine('    val shapes: List<GlyphShape> = listOf(')
foreach ($g in $glyphs) {
  $m = if ($g.mirror) { 'true' } else { 'false' }
  $arrs = ($g.strokes | ForEach-Object { 'intArrayOf(' + (FlatStroke $_) + ')' }) -join ', '
  [void]$kt.AppendLine("        GlyphShape(`"$($g.id)`", $m, listOf($arrs)),")
}
[void]$kt.AppendLine('    )')
[void]$kt.AppendLine('}')
[IO.File]::WriteAllText((Join-Path $root 'android\core\src\main\kotlin\app\bavtrix\core\GlyphData.kt'), $kt.ToString(), $utf8)

Write-Output "glyphs: $($glyphs.Count) (hand drawn $($hand.Count), generated $n)"
