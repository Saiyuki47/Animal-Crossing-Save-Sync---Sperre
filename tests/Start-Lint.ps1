<#
================================================================================
  Start-Lint.ps1 - prueft alle Skripte mit PSScriptAnalyzer
================================================================================

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tests\Start-Lint.ps1

  Die Regeln stehen in PSScriptAnalyzerSettings.psd1 im Projektordner.
  Fehlt PSScriptAnalyzer, wird es fuer den aktuellen Benutzer installiert.
  Rueckgabe (Exitcode): 0 = keine Befunde, 1 = Befunde (oder Fehler).
#>

$ErrorActionPreference = 'Stop'
$wurzel = Split-Path -Parent $PSScriptRoot
$einstellungen = Join-Path $wurzel 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer fehlt - wird fuer diesen Benutzer installiert...'
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
}
Import-Module PSScriptAnalyzer
Write-Host ("PSScriptAnalyzer {0}, PowerShell {1}" -f (Get-Module PSScriptAnalyzer).Version, $PSVersionTable.PSVersion)

$befunde = @(Invoke-ScriptAnalyzer -Path $wurzel -Recurse -Settings $einstellungen)
foreach ($b in $befunde) {
    $datei = $b.ScriptPath.Substring($wurzel.Length).TrimStart('\', '/')
    Write-Host ("{0}:{1}  [{2}] {3}  {4}" -f $datei, $b.Line, $b.Severity, $b.RuleName, $b.Message)
}
if ($befunde.Count) {
    Write-Host ("{0} Befund(e)." -f $befunde.Count) -ForegroundColor Red
    exit 1
}
Write-Host 'Keine Befunde.' -ForegroundColor Green
exit 0
