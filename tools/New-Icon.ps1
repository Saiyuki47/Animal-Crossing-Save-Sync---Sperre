<#
================================================================================
  New-Icon.ps1 - zeichnet das Programm-Icon (eigenes Blatt-Motiv)
================================================================================

  Warum selbst zeichnen?
  ----------------------
  Original-Grafiken aus dem Spiel duerfen wir nicht mitliefern. Dieses Motiv
  ist deshalb komplett selbst gezeichnet: ein Blatt auf hellem Grund, in
  Farben, die an das Spiel erinnern - aber nichts davon uebernehmen.

  Ergebnis:
    assets/ac-savesync.ico   - Icon mit allen ueblichen Groessen
    assets/icon-preview.png  - dasselbe als Bild zum Anschauen
  Ausserdem wird der Base64-Text ausgegeben, der in AC-SaveSync.ps1 steckt.

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tools\New-Icon.ps1
#>
[CmdletBinding()]
param([switch]$NurVorschau)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$assets = Join-Path $root 'assets'
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets -Force | Out-Null }

# --------------------------------------------------------------------------
# Das Motiv in 256x256 zeichnen - alles Weitere wird daraus verkleinert.
# --------------------------------------------------------------------------
function New-Motiv {
    param([int]$Kante = 256)

    $bmp = New-Object Drawing.Bitmap($Kante, $Kante, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent)

    $s = $Kante / 256.0        # alles relativ zu 256 rechnen
    function P($x, $y) { New-Object Drawing.PointF(($x * $s), ($y * $s)) }

    # ---- Hintergrund: abgerundetes Quadrat, warmer Verlauf ----------------
    $rand = 10 * $s
    $groesse = $Kante - 2 * $rand
    $radius = 56 * $s
    $pfad = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $pfad.AddArc($rand, $rand, $d, $d, 180, 90)
    $pfad.AddArc(($rand + $groesse - $d), $rand, $d, $d, 270, 90)
    $pfad.AddArc(($rand + $groesse - $d), ($rand + $groesse - $d), $d, $d, 0, 90)
    $pfad.AddArc($rand, ($rand + $groesse - $d), $d, $d, 90, 90)
    $pfad.CloseFigure()

    $verlauf = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.PointF(0, 0)),
        (New-Object Drawing.PointF(0, $Kante)),
        [Drawing.Color]::FromArgb(255, 126, 200, 227),   # heller Himmelblau
        [Drawing.Color]::FromArgb(255, 247, 231, 176))   # sandiges Gelb
    $g.FillPath($verlauf, $pfad)

    # sanfter Rand, damit das Icon auf hellem Hintergrund nicht ausfranst
    $stift = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70, 60, 90, 60), (5 * $s))
    $g.DrawPath($stift, $pfad)

    # ---- Sanfte Huegellinie unten (Insel-Anmutung) -----------------------
    $huegel = New-Object Drawing.Drawing2D.GraphicsPath
    $huegel.AddBezier((P 10 208), (P 80 182), (P 176 220), (P 246 190))
    $huegel.AddLine((P 246 190), (P 246 246))
    $huegel.AddLine((P 246 246), (P 10 246))
    $huegel.CloseFigure()
    $grasBrush = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.PointF(0, (160 * $s))),
        (New-Object Drawing.PointF(0, $Kante)),
        [Drawing.Color]::FromArgb(255, 124, 196, 96),
        [Drawing.Color]::FromArgb(255, 72, 146, 66))
    $altClip = $g.Clip
    $g.SetClip($pfad)
    $g.FillPath($grasBrush, $huegel)
    $g.Clip = $altClip

    # ---- Das Blatt -------------------------------------------------------
    # Zwei gespiegelte Bezierkurven ergeben die klassische Blattform.
    $blatt = New-Object Drawing.Drawing2D.GraphicsPath
    $blatt.AddBezier((P 128 34), (P 218 62), (P 212 150), (P 128 184))
    $blatt.AddBezier((P 128 184), (P 44 150), (P 38 62), (P 128 34))
    $blatt.CloseFigure()

    $blattBrush = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.PointF((50 * $s), (34 * $s))),
        (New-Object Drawing.PointF((210 * $s), (184 * $s))),
        [Drawing.Color]::FromArgb(255, 138, 214, 92),
        [Drawing.Color]::FromArgb(255, 55, 132, 54))
    $g.FillPath($blattBrush, $blatt)
    $blattStift = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 42, 104, 44), (7 * $s))
    $blattStift.LineJoin = 'Round'
    $g.DrawPath($blattStift, $blatt)

    # Mittelrippe
    $rippe = New-Object Drawing.Pen([Drawing.Color]::FromArgb(235, 240, 252, 216), (6 * $s))
    $rippe.StartCap = 'Round'; $rippe.EndCap = 'Round'
    $g.DrawBezier($rippe, (P 128 48), (P 132 100), (P 130 142), (P 128 178))

    # Seitenadern: von der Rippe schraeg nach aussen-unten, wie bei einem
    # echten Blatt. Zu waagerecht gezeichnet sieht es nach Fischgraete aus.
    $ader = New-Object Drawing.Pen([Drawing.Color]::FromArgb(170, 240, 252, 216), (4.5 * $s))
    $ader.StartCap = 'Round'; $ader.EndCap = 'Round'
    $paare = @(
        @(129, 72, 88, 92), @(129, 72, 170, 92),
        @(129, 106, 74, 130), @(129, 106, 184, 130),
        @(129, 140, 90, 160), @(129, 140, 168, 160)
    )
    foreach ($a in $paare) { $g.DrawLine($ader, (P $a[0] $a[1]), (P $a[2] $a[3])) }

    # Stiel
    $stiel = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 122, 84, 48), (9 * $s))
    $stiel.StartCap = 'Round'; $stiel.EndCap = 'Round'
    $g.DrawBezier($stiel, (P 128 180), (P 132 196), (P 126 204), (P 118 212))

    # Kleines Glanzlicht, damit es nicht flach wirkt
    $glanz = New-Object Drawing.Drawing2D.GraphicsPath
    $glanz.AddBezier((P 104 64), (P 142 74), (P 154 102), (P 140 126))
    $glanz.AddBezier((P 140 126), (P 128 98), (P 114 78), (P 104 64))
    $glanz.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(60, 255, 255, 255))), $glanz)

    $g.Dispose()
    return $bmp
}

# --------------------------------------------------------------------------
# ICO-Datei selbst schreiben.
# .NET kann keine mehrgroessigen Icons erzeugen; das Format ist aber simpel:
# Kopf, je ein Verzeichniseintrag pro Groesse, danach die Bilddaten. Seit
# Windows Vista duerfen die Bilddaten PNG sein - das spart viel Platz.
# --------------------------------------------------------------------------
function Write-Ico {
    param([Drawing.Bitmap]$Quelle, [int[]]$Groessen, [string]$Pfad)

    $pngs = @()
    foreach ($k in $Groessen) {
        $b = New-Object Drawing.Bitmap($k, $k, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($b)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.SmoothingMode = 'AntiAlias'
        $g.PixelOffsetMode = 'HighQuality'
        $g.Clear([Drawing.Color]::Transparent)
        $g.DrawImage($Quelle, (New-Object Drawing.Rectangle(0, 0, $k, $k)))
        $g.Dispose()
        $ms = New-Object IO.MemoryStream
        $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
        $pngs += , @{ Kante = $k; Daten = $ms.ToArray() }
        $ms.Dispose(); $b.Dispose()
    }

    $fs = [IO.File]::Create($Pfad)
    $w = New-Object IO.BinaryWriter($fs)
    $w.Write([uint16]0)                 # reserviert
    $w.Write([uint16]1)                 # Typ 1 = Icon
    $w.Write([uint16]$pngs.Count)

    # 6 Byte Kopf + 16 Byte je Eintrag
    $offset = 6 + 16 * $pngs.Count
    foreach ($p in $pngs) {
        # 256 wird als 0 codiert - das Feld ist nur ein Byte breit
        $w.Write([byte]($(if ($p.Kante -ge 256) { 0 } else { $p.Kante })))
        $w.Write([byte]($(if ($p.Kante -ge 256) { 0 } else { $p.Kante })))
        $w.Write([byte]0)               # Farben in der Palette (0 = keine)
        $w.Write([byte]0)               # reserviert
        $w.Write([uint16]1)             # Farbebenen
        $w.Write([uint16]32)            # Bits pro Pixel
        $w.Write([uint32]$p.Daten.Length)
        $w.Write([uint32]$offset)
        $offset += $p.Daten.Length
    }
    foreach ($p in $pngs) { $w.Write($p.Daten) }
    $w.Flush(); $w.Close(); $fs.Dispose()
}

# --------------------------------------------------------------------------
$motiv = New-Motiv 256
$vorschau = Join-Path $assets 'icon-preview.png'
$motiv.Save($vorschau, [Drawing.Imaging.ImageFormat]::Png)
Write-Host "Vorschau: $vorschau"

if (-not $NurVorschau) {
    $ico = Join-Path $assets 'ac-savesync.ico'
    # 128 bewusst weggelassen: kostet 15 KB und Windows verkleinert die
    # 256er-Fassung bei Bedarf selbst - der Unterschied ist nicht sichtbar.
    Write-Ico $motiv @(16, 24, 32, 48, 64, 256) $ico
    $bytes = [IO.File]::ReadAllBytes($ico)
    Write-Host ("Icon: {0} ({1:N0} Bytes)" -f $ico, $bytes.Length)
    $b64 = [Convert]::ToBase64String($bytes)
    Write-Host ("Base64-Laenge: {0:N0} Zeichen" -f $b64.Length)
    Set-Content -LiteralPath (Join-Path $assets 'icon-base64.txt') -Value $b64 -Encoding ASCII
    Write-Host ("Base64 liegt in: {0}" -f (Join-Path $assets 'icon-base64.txt'))
}
$motiv.Dispose()
