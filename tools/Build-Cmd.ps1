<#
================================================================================
  Build-Cmd.ps1 - macht aus AC-SaveSync.ps1 eine doppelklickbare AC-SaveSync.cmd
================================================================================

  Warum?
  ------
  Eine .ps1-Datei oeffnet beim Doppelklick nur den Editor. Eine .cmd-Datei wird
  dagegen sofort ausgefuehrt. Dieses Skript klebt deshalb einen kleinen
  Batch-Kopf vor das PowerShell-Skript:

      Kopf (Batch)  ->  startet powershell.exe
      Marker-Zeile  ->  ab hier faengt der PowerShell-Teil an
      Rumpf (PS1)   ->  unveraenderter Inhalt von AC-SaveSync.ps1

  Der Batch-Kopf endet mit "exit /b". cmd.exe liest die Datei zeilenweise und
  hoert dort auf - der PowerShell-Rumpf darunter wird von cmd nie gelesen und
  kann daher beliebige Zeichen enthalten. PowerShell liest die Datei erneut
  ein, schneidet alles bis zur Marker-Zeile ab und fuehrt nur den Rest aus.

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tools\Build-Cmd.ps1
#>
[CmdletBinding()]
param(
    # Quelle: das eigentliche PowerShell-Skript (Standard: AC-SaveSync.ps1 im Projektordner)
    [string]$Source,

    # Ziel: die doppelklickbare Datei
    [string]$Output,

    # Konsolenfenster sichtbar lassen - nur zum Suchen von Fehlern.
    # Normalfall: versteckt, damit nur die GUI erscheint.
    [switch]$ShowConsole
)

$ErrorActionPreference = 'Stop'

# Projektordner = eine Ebene ueber tools\
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $root
if (-not $Source) { $Source = Join-Path $root 'AC-SaveSync.ps1' }
if (-not $Output) { $Output = Join-Path $root 'AC-SaveSync.cmd' }

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Quelldatei nicht gefunden: $Source"
}

# Die Marker-Zeile trennt Batch-Kopf und PowerShell-Rumpf.
$marker = '@@AC-SAVESYNC-POWERSHELL-BODY@@'

# Der Bootstrap darf KEINE doppelten Anfuehrungszeichen enthalten - er steht im
# Batch-Kopf selbst in doppelten Anfuehrungszeichen. Deshalb ueberall ' statt ".
# Den Marker setzt er zur Laufzeit zusammen ('...POWERSHELL-' + 'BODY@@'), damit
# er nicht sich selbst findet: im Kopf steht der Suchbegriff ja ebenfalls.
$psCommand = @(
    'try{'
    '$f=$env:ACSS_SELF;'
    '$raw=Get-Content -LiteralPath $f -Raw -Encoding UTF8;'
    "`$m=[char]10 + '@@AC-SAVESYNC-POWERSHELL-' + 'BODY@@';"
    '$i=$raw.IndexOf($m);'
    'if($i -lt 0){throw ''Markerzeile nicht gefunden - Datei beschaedigt?''};'
    # $PSScriptRoot/$PSCommandPath muessen IM Scriptblock gesetzt werden, sonst
    # sind sie dort leer. Der Prolog haengt ohne Zeilenumbruch vorne dran,
    # damit die Zeilennummern in Fehlermeldungen zur .ps1 passen.
    '$pre=''$PSCommandPath=$env:ACSS_SELF; $PSScriptRoot=Split-Path -Parent $env:ACSS_SELF; '';'
    '$body=$pre+$raw.Substring($i+$m.Length).TrimStart([char]13,[char]10);'
    '& ([scriptblock]::Create($body))'
    '}catch{'
    # Ohne Konsole waere ein Fehler sonst unsichtbar - daher zusaetzlich ein Dialog.
    '$e=$_|Out-String;'
    'Write-Host $e;'
    'try{Add-Type -AssemblyName System.Windows.Forms;'
    '[void][Windows.Forms.MessageBox]::Show($e,''AC-SaveSync - Fehler'',''OK'',''Error'')}catch{};'
    'exit 1}'
) -join ' '

# Versteckt (Standard): "start" oeffnet eine EIGENE Konsole fuer PowerShell, und
# -WindowStyle Hidden laesst Windows sie gar nicht erst sichtbar anlegen - es
# blitzt also nichts auf. Das Fenster des Doppelklicks schliesst sich sofort.
# Sichtbar (-ShowConsole): PowerShell laeuft in der vorhandenen Konsole, und bei
# einem Fehler bleibt das Fenster mit "pause" stehen.
$runner = if ($ShowConsole) {
    @"
powershell -NoProfile -ExecutionPolicy Bypass -Sta -Command "$psCommand"
set "ACSS_RC=%ERRORLEVEL%"
if not "%ACSS_RC%"=="0" (
  echo.
  echo [Fehler] Beendet mit Code %ACSS_RC%.
  pause
)
endlocal & exit /b %ACSS_RC%
"@
} else {
    @"
start "AC-SaveSync" powershell -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -Command "$psCommand"
endlocal & exit /b 0
"@
}

$header = @"
@echo off
rem ===========================================================================
rem  Animal Crossing Save-Sync + Sperre - Starter
rem  Diese Datei ist gleichzeitig Starter UND Skript: unterhalb der
rem  Markerzeile steht der komplette PowerShell-Code.
rem  Nicht mit einem Editor speichern, der die Zeilenenden aendert.
rem ===========================================================================
setlocal EnableExtensions
set "ACSS_SELF=%~f0"
$runner
$marker
"@

$body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Source), [Text.UTF8Encoding]::new($false))

# Alles auf CRLF normalisieren - cmd.exe verlangt CRLF im Batch-Kopf.
$content = ($header + "`n" + $body) -replace "`r`n", "`n" -replace "`n", "`r`n"

# UTF-8 OHNE BOM schreiben: ein BOM wuerde cmd.exe die erste Zeile zerlegen.
[IO.File]::WriteAllText($Output, $content, [Text.UTF8Encoding]::new($false))

Write-Host ("Erzeugt: {0} ({1:N0} Bytes)" -f $Output, (Get-Item -LiteralPath $Output).Length)
