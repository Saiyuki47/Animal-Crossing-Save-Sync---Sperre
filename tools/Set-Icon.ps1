<#
================================================================================
  Set-Icon.ps1 - uebernimmt icon.ico als Programm-Symbol
================================================================================

  Was es macht
  ------------
  1. liest icon.ico aus dem Projektordner,
  2. schreibt es verlustfrei neu als assets/ac-savesync.ico - diesmal mit
     PNG-komprimierten Bilddaten statt roher Bitmaps (rund ein Zehntel so
     gross, Pixel fuer Pixel identisch),
  3. legt assets/icon-preview.png zum Anschauen an,
  4. traegt das Ergebnis als Base64 in AC-SaveSync.ps1 ein.

  Wenn du das Symbol austauschen willst: einfach icon.ico ersetzen und
  dieses Skript noch einmal laufen lassen.

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tools\Set-Icon.ps1
#>
[CmdletBinding()]
param(
    [string]$Source,
    [switch]$NichtEintragen
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# --- .ico selbst auslesen --------------------------------------------------
# Warum nicht die fertigen Klassen?
#   - System.Drawing.Icon sucht sich die Groesse selbst aus und liefert bei
#     einer 256er-Anfrage gern die 128er zurueck.
#   - Der WPF-Decoder liefert Bitmap-Fassungen mit vormultipliziertem Alpha;
#     beim Zurueckrechnen entstehen Rundungsfehler an weichen Kanten.
# Das Format ist simpel genug, um es direkt zu lesen - und nur so bleibt das
# Bild wirklich Pixel fuer Pixel erhalten.
function Get-IcoFrames {
    param([string]$Pfad)
    $b = [IO.File]::ReadAllBytes($Pfad)
    if ([BitConverter]::ToUInt16($b, 2) -ne 1) { throw "Keine Icon-Datei: $Pfad" }
    $anzahl = [BitConverter]::ToUInt16($b, 4)
    $liste = @()
    for ($i = 0; $i -lt $anzahl; $i++) {
        $o = 6 + 16 * $i
        $kante = if ($b[$o] -eq 0) { 256 } else { [int]$b[$o] }
        $laenge = [BitConverter]::ToUInt32($b, $o + 8)
        $start = [BitConverter]::ToUInt32($b, $o + 12)
        $daten = New-Object byte[] $laenge
        [Array]::Copy($b, $start, $daten, 0, $laenge)
        $liste += , @{ Kante = $kante; Daten = $daten; IstPng = ($daten[0] -eq 0x89) }
    }
    return $liste
}

# Macht aus einem Verzeichniseintrag eine Bitmap.
function ConvertTo-Bitmap {
    param($Frame)
    if ($Frame.IstPng) {
        $ms = New-Object IO.MemoryStream(, $Frame.Daten)
        return (New-Object Drawing.Bitmap($ms))
    }
    # Sonst: BITMAPINFOHEADER, danach BGRA-Zeilen von unten nach oben.
    $d = $Frame.Daten
    $kopf = [BitConverter]::ToUInt32($d, 0)
    $breite = [BitConverter]::ToInt32($d, 4)
    $hoehe = [BitConverter]::ToInt32($d, 8) / 2      # enthaelt Bild + Maske
    $bits = [BitConverter]::ToUInt16($d, 14)
    if ($bits -ne 32) { throw "Nur 32-Bit-Fassungen werden gelesen (hier: $bits Bit)" }

    $bmp = New-Object Drawing.Bitmap($breite, $hoehe, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $sperre = $bmp.LockBits(
        (New-Object Drawing.Rectangle(0, 0, $breite, $hoehe)),
        [Drawing.Imaging.ImageLockMode]::WriteOnly,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $zeile = $breite * 4
    for ($y = 0; $y -lt $hoehe; $y++) {
        # unterste Bildzeile steht in der Datei zuerst
        $quelle = $kopf + ($hoehe - 1 - $y) * $zeile
        $ziel = [IntPtr]::Add($sperre.Scan0, $y * $sperre.Stride)
        [Runtime.InteropServices.Marshal]::Copy($d, $quelle, $ziel, $zeile)
    }
    $bmp.UnlockBits($sperre)
    return $bmp
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $Source) { $Source = Join-Path $root 'icon.ico' }
if (-not (Test-Path -LiteralPath $Source)) { throw "Symboldatei nicht gefunden: $Source" }

$assets = Join-Path $root 'assets'
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets -Force | Out-Null }

# --- groesste vorhandene Fassung herausholen ------------------------------
$frames = Get-IcoFrames $Source
Write-Host ("Gefundene Groessen: {0}" -f (($frames | ForEach-Object { "$($_.Kante)" }) -join ', '))
$beste = $frames | Sort-Object { $_.Kante } -Descending | Select-Object -First 1
$quelle = ConvertTo-Bitmap $beste
Write-Host ("Ausgangsbild: {0}x{1}" -f $quelle.Width, $quelle.Height)

# --- als PNG-ICO neu schreiben --------------------------------------------
# Aufbau einer .ico: Kopf, je ein Verzeichniseintrag pro Groesse, dann die
# Bilddaten. Seit Windows Vista duerfen die Daten PNG sein.
function Write-Ico {
    param([Drawing.Bitmap]$Bild, [int[]]$Groessen, [string]$Pfad)
    $teile = @()
    foreach ($k in $Groessen) {
        $eigenesBild = $true
        if ($k -eq $Bild.Width) {
            # Gleiche Groesse: das Original direkt nehmen. Weder DrawImage noch
            # der Bitmap(Image)-Konstruktor kommen infrage - beide zeichnen neu
            # und verfaelschen dabei weiche Kanten um ein paar Stufen.
            $b = $Bild
            $eigenesBild = $false
        }
        else {
            $b = New-Object Drawing.Bitmap($k, $k, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [Drawing.Graphics]::FromImage($b)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.SmoothingMode = 'AntiAlias'
            $g.PixelOffsetMode = 'HighQuality'
            $g.Clear([Drawing.Color]::Transparent)
            $g.DrawImage($Bild, (New-Object Drawing.Rectangle(0, 0, $k, $k)))
            $g.Dispose()
        }
        $m = New-Object IO.MemoryStream
        $b.Save($m, [Drawing.Imaging.ImageFormat]::Png)
        $teile += , @{ Kante = $k; Daten = $m.ToArray() }
        $m.Dispose()
        if ($eigenesBild) { $b.Dispose() }   # das Original gehoert dem Aufrufer
    }

    $fs = [IO.File]::Create($Pfad)
    $w = New-Object IO.BinaryWriter($fs)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$teile.Count)
    $offset = 6 + 16 * $teile.Count
    foreach ($t in $teile) {
        $byteKante = [byte]$(if ($t.Kante -ge 256) { 0 } else { $t.Kante })  # 256 wird als 0 codiert
        $w.Write($byteKante); $w.Write($byteKante)
        $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$t.Daten.Length); $w.Write([uint32]$offset)
        $offset += $t.Daten.Length
    }
    foreach ($t in $teile) { $w.Write($t.Daten) }
    $w.Flush(); $w.Close(); $fs.Dispose()
}

$ziel = Join-Path $assets 'ac-savesync.ico'
Write-Ico $quelle @(16, 24, 32, 48, 64, 256) $ziel
$quelle.Save((Join-Path $assets 'icon-preview.png'), [Drawing.Imaging.ImageFormat]::Png)

$vorher = (Get-Item -LiteralPath $Source).Length
$nachher = (Get-Item -LiteralPath $ziel).Length
Write-Host ("Neu geschrieben: {0}  ({1:N0} -> {2:N0} Bytes)" -f $ziel, $vorher, $nachher)

# --- ins Skript eintragen --------------------------------------------------
if (-not $NichtEintragen) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ziel))
    $skript = Join-Path $root 'AC-SaveSync.ps1'
    $text = [IO.File]::ReadAllText($skript, [Text.UTF8Encoding]::new($false))
    $muster = '(?<=\$script:IconBase64 = ")[A-Za-z0-9+/=]*(?=")'
    if ($text -notmatch $muster) { throw 'Zeile $script:IconBase64 in AC-SaveSync.ps1 nicht gefunden' }
    $text = [regex]::Replace($text, $muster, $b64)
    # ohne BOM schreiben: er wuerde sonst im Rumpf der .cmd landen
    [IO.File]::WriteAllText($skript, $text, [Text.UTF8Encoding]::new($false))
    Write-Host ("In AC-SaveSync.ps1 eingetragen ({0:N0} Zeichen Base64)." -f $b64.Length)
}

$quelle.Dispose()
