<#
================================================================================
  Start-Tests.ps1 - fuehrt alle Tests aus
================================================================================

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tests\Start-Tests.ps1
    pwsh -File ./tests/Start-Tests.ps1              (auch unter Linux)

  Laeuft ohne Nachinstallieren. Braucht nur git im PATH. Unter Windows
  kommen die Tests mit robocopy, gesperrten Dateien und Prozessen dazu.
  Alles passiert in einem eigenen Temp-Ordner; euer echtes Repo, eure
  Einstellungen und euer Spielstand werden nicht angefasst.

  Rueckgabe (Exitcode): 0 = alles gruen, 1 = mindestens ein Fehler.
#>
param(
    # Nur Testdateien, deren Name dieses Muster enthaelt (z. B. "Sperre")
    [string]$Filter = ''
)

. (Join-Path $PSScriptRoot 'Testrahmen.ps1')

Write-Host ("AC-SaveSync Tests - PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $(if ($script:AufWindows) { 'Windows' } else { 'kein Windows' }))
Write-Host ("git: {0}" -f (& git --version))

# Git braucht fuer Commits Name und E-Mail - im Test-Temp-Ordner reicht eine
# Angabe fuer diesen Prozess, die globale Konfiguration bleibt unberuehrt.
$env:GIT_AUTHOR_NAME = 'Test'; $env:GIT_AUTHOR_EMAIL = 'test@test'
$env:GIT_COMMITTER_NAME = 'Test'; $env:GIT_COMMITTER_EMAIL = 'test@test'
$env:GIT_TERMINAL_PROMPT = '0'

$script:Ast = Import-AcssFunktionen
# Import-AcssFunktionen bringt auch das echte Write-Log mit - fuer die Tests
# wieder auf das Mitschreiben umstellen.
function script:Write-Log { param([string]$msg) [void]$script:Protokoll.Add($msg) }

$dateien = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' | Sort-Object Name |
Where-Object { -not $Filter -or $_.Name -like "*$Filter*" }
foreach ($d in $dateien) {
    Write-Host ""
    Write-Host ("== {0}" -f $d.BaseName) -ForegroundColor Cyan
    . $d.FullName
}

Stop-TestProzesse
try { Remove-Item -LiteralPath $script:TestWurzel -Recurse -Force -ErrorAction SilentlyContinue }
catch { Write-Verbose "Temp-Ordner bleibt liegen: $($_.Exception.Message)" }
if ($script:AufWindows -and (Test-Path -LiteralPath $script:TestSchluessel)) {
    Remove-Item -LiteralPath $script:TestSchluessel -Recurse -Force -ErrorAction SilentlyContinue
}

$ok = @($script:Ergebnisse | Where-Object Status -eq 'ok').Count
$fehl = @($script:Ergebnisse | Where-Object Status -eq 'FEHLER')
$weg = @($script:Ergebnisse | Where-Object Status -eq 'uebersprungen').Count
Write-Host ""
Write-Host ("Ergebnis: {0} ok, {1} Fehler, {2} uebersprungen" -f $ok, $fehl.Count, $weg) -ForegroundColor $(if ($fehl.Count) { 'Red' } else { 'Green' })
foreach ($f in $fehl) { Write-Host ("  FEHLER: {0}`n          {1}" -f $f.Name, $f.Grund) -ForegroundColor Red }
if ($fehl.Count) { exit 1 }
exit 0
