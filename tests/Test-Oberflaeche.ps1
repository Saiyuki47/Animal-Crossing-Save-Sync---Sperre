<#
================================================================================
  Test-Oberflaeche.ps1 - startet das echte Programm und spielt eine Sitzung
================================================================================

  Nur unter Windows. Laeuft vollstaendig in einem Temp-Ordner mit eigenen
  Einstellungen (APPDATA umgelenkt) und einem lokalen "Server" statt GitHub.

  Ablauf:
    1. Programm starten, warten bis der Status geprueft ist
    2. per UI Automation auf "Spielen starten" klicken
       - als "Spiel" dient ein Starter, der Dolphin startet und sich sofort
         selbst beendet (die Sitzung muss trotzdem offen bleiben)
    3. Spielstand aendern ("im Spiel speichern"), Ersatz-Dolphin schliessen
    4. pruefen: Sperre frei, neuer Spielstand und Spielzeit auf dem Server
    5. Programm schliessen, pruefen: keine Fehler auf stderr

  Nach jedem Schritt entsteht ein Bildschirmfoto in -Ausgabe, dazu das
  Protokoll des Programms. Exitcode 0 = alles gut.

  Aufruf:
    powershell -ExecutionPolicy Bypass -File .\tests\Test-Oberflaeche.ps1
#>
param(
    [string]$Ausgabe = (Join-Path $env:TEMP 'acss-oberflaeche')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes

$skript = Join-Path (Split-Path -Parent $PSScriptRoot) 'AC-SaveSync.ps1'
New-Item -ItemType Directory -Path $Ausgabe -Force | Out-Null
$wurzel = Join-Path $env:TEMP ('acss-ui-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $wurzel -Force | Out-Null

function Schritt { param([string]$t) Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function G {
    # git ohne Fehlerdatensaetze; bricht bei Fehler ab.
    # Bewusst ohne param-Block: sonst deutet PowerShell "-A" o. ae. als
    # eigenen Parameter statt als Git-Schalter.
    $A = @($args)
    $alt = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & git @A 2>&1
    $code = $LASTEXITCODE; $ErrorActionPreference = $alt
    $text = (@($out | ForEach-Object { "$_" }) -join "`n")
    if ($code -ne 0) { throw "git $($A -join ' ') ist gescheitert: $text" }
    return $text
}

# --- Bildschirmfotos ---------------------------------------------------------
$script:bildNr = 0
function Save-Bild {
    param([string]$Name)
    $script:bildNr++
    $datei = Join-Path $Ausgabe ("{0:D2}-{1}.png" -f $script:bildNr, $Name)
    try {
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save($datei, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "   Bildschirmfoto: $datei"
        # Mit ACSS_BILD_INS_LOG=1 zusaetzlich verkleinert als Text ins Log -
        # fuer alle, die an die hochgeladenen Dateien nicht herankommen.
        if ($env:ACSS_BILD_INS_LOG -eq '1') {
            $breite = [math]::Min(800, $bmp.Width)
            $hoehe = [int]($bmp.Height * $breite / $bmp.Width)
            $klein = New-Object System.Drawing.Bitmap($bmp, $breite, $hoehe)
            $ms = New-Object IO.MemoryStream
            $klein.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $b64 = [Convert]::ToBase64String($ms.ToArray())
            Write-Host ("BILD-ANFANG {0}" -f $Name)
            for ($i = 0; $i -lt $b64.Length; $i += 2000) { Write-Host ("BILD " + $b64.Substring($i, [math]::Min(2000, $b64.Length - $i))) }
            Write-Host "BILD-ENDE"
            $klein.Dispose(); $ms.Dispose()
        }
        $g.Dispose(); $bmp.Dispose()
    }
    catch { Write-Host "   (Bildschirmfoto nicht moeglich: $($_.Exception.Message))" -ForegroundColor DarkYellow }
}

# --- Fenster finden und bedienen (UI Automation) -----------------------------
$UIA = [System.Windows.Automation.AutomationElement]
function Get-ProgrammFenster {
    $bed = New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $script:app.Id)
    return @($UIA::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $bed))
}
function Get-Hauptfenster {
    return (Get-ProgrammFenster | Where-Object { $_.Current.Name -like '*Save-Sync*' } | Select-Object -First 1)
}
function Get-Element {
    param([string]$Name)
    $f = Get-Hauptfenster
    if (-not $f) { return $null }
    $bed = New-Object System.Windows.Automation.PropertyCondition($UIA::NameProperty, $Name)
    return $f.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $bed)
}
function Get-StatusText {
    $f = Get-Hauptfenster
    if (-not $f) { return '' }
    $bed = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    foreach ($e in $f.FindAll([System.Windows.Automation.TreeScope]::Descendants, $bed)) {
        $n = $e.Current.Name
        if ($n -match '^(FREI|DU spielst|GESPERRT|ABGELAUFENE|Status unbekannt|Wird geprueft|Noch nicht geprueft|Noch kein Repo|ACHTUNG|SPERRE VERLOREN)') { return $n }
    }
    return ''
}
# Schreibt alle Elemente des Hauptfensters ins Log - zur Fehlersuche, wenn
# ein Element nicht gefunden wird.
function Write-Elementbaum {
    $f = Get-Hauptfenster
    if (-not $f) { Write-Host "   (kein Hauptfenster)"; return }
    Write-Host "   Elemente im Hauptfenster:"
    foreach ($e in $f.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        $c = $e.Current
        Write-Host ("     {0,-22} name='{1}' id='{2}' klasse='{3}'" -f $c.ControlType.ProgrammaticName, $c.Name, $c.AutomationId, $c.ClassName)
    }
}

function Invoke-Knopf {
    param([string]$Name)
    $k = Get-Element $Name
    if (-not $k) { Stop-MitFehler "Knopf '$Name' nicht gefunden" }
    $k.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Host "   geklickt: $Name"
}

# --- Protokoll des Programms -------------------------------------------------
function Get-AppProtokoll {
    $ordner = Join-Path $script:appdata 'AC-SaveSync\logs'
    $d = Get-ChildItem -LiteralPath $ordner -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $d) { return '' }
    try { return [IO.File]::ReadAllText($d.FullName, [Text.UTF8Encoding]::new($false)) } catch { return '' }
}
function Wait-Protokoll {
    param([string]$Muster, [int]$Sekunden = 60)
    $ende = (Get-Date).AddSeconds($Sekunden)
    while ((Get-Date) -lt $ende) {
        if ((Get-AppProtokoll) -match $Muster) { Write-Host "   im Protokoll: $Muster"; return }
        if ($script:app.HasExited) { Stop-MitFehler "Das Programm hat sich unerwartet beendet" }
        $fremd = @(Get-ProgrammFenster | Where-Object { $_.Current.Name -notlike '*Save-Sync*' })
        if ($fremd.Count) {
            Stop-MitFehler ("Unerwartetes Fenster offen: '{0}'" -f (($fremd | ForEach-Object { $_.Current.Name }) -join "', '"))
        }
        Start-Sleep -Milliseconds 500
    }
    Stop-MitFehler "Nach $Sekunden s nicht im Protokoll: $Muster"
}

function Stop-MitFehler {
    param([string]$Text)
    Save-Bild 'fehler'
    try { Write-Elementbaum } catch { }
    throw $Text
}

# --- Aufbau: Server, Repo mit Startstand, Spielstand, Ersatz-Dolphin ---------
Schritt "Testumgebung anlegen: $wurzel"
$server = Join-Path $wurzel 'server.git'
$repo = Join-Path $wurzel 'repo'
$save = Join-Path $wurzel 'Dolphin\Spielstand'
$fake = Join-Path $wurzel 'FakeDolphin'
$script:appdata = Join-Path $wurzel 'appdata'
G init -q --bare -b main $server | Out-Null
G clone -q $server $repo | Out-Null
New-Item -ItemType Directory -Path (Join-Path $repo 'save\data'), (Join-Path $save 'data'), $fake, (Join-Path $script:appdata 'AC-SaveSync') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $repo 'save\data\stadt.bin') -Value 'Server-Stand'
G -C $repo add -A | Out-Null
G -C $repo commit -qm 'Startstand' | Out-Null
G -C $repo push -q origin main | Out-Null
Set-Content -LiteralPath (Join-Path $save 'data\stadt.bin') -Value 'alter Stand auf diesem PC'

$dolphin = Join-Path $fake 'Dolphin.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\PING.EXE') -Destination $dolphin
# Starter, der Dolphin startet und sich sofort selbst beendet
$starter = Join-Path $wurzel 'Starter.cmd'
Set-Content -LiteralPath $starter -Encoding ASCII -Value ("@echo off`r`nstart `"`" /b `"{0}`" -n 600 127.0.0.1`r`n" -f $dolphin)

$cfg = [ordered]@{
    DolphinPath = $dolphin; RepoPath = $repo; GamePath = $starter; SaveFolder = $save; PicsFolder = ''
    PlayerName = 'Tester'; Branch = 'main'; LeaseMinutes = 5; HeartbeatSeconds = 60
}
[IO.File]::WriteAllText((Join-Path $script:appdata 'AC-SaveSync\acsync-config.json'), ($cfg | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

$stdout = Join-Path $Ausgabe 'stdout.txt'
$stderr = Join-Path $Ausgabe 'stderr.txt'
$script:app = $null
$erfolg = $false
try {
    Schritt "Programm starten"
    $env:APPDATA = $script:appdata
    $script:app = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Sta', '-File', "`"$skript`"" `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $ende = (Get-Date).AddSeconds(60)
    while (-not (Get-Hauptfenster) -and (Get-Date) -lt $ende) {
        if ($script:app.HasExited) { Stop-MitFehler "Programm beim Start beendet (Exitcode $($script:app.ExitCode))" }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Get-Hauptfenster)) { Stop-MitFehler "Hauptfenster erscheint nicht" }
    Write-Host ("   Fenster: {0}" -f (Get-Hauptfenster).Current.Name)
    Wait-Protokoll 'Frei - du kannst spielen\.' 90
    # Nach der Statuspruefung sieht das Programm noch nach Updates und der Uhr.
    Wait-Protokoll '(Version [\d.]+ ist aktuell|Update-Pruefung nicht moeglich|Neue Version verfuegbar)' 60
    Start-Sleep -Seconds 3
    Save-Bild 'gestartet'
    $status = Get-StatusText
    Write-Host "   Status: $status"
    if ($status -notmatch '^FREI') { Stop-MitFehler "Status sollte FREI sein, ist: $status" }

    Schritt "Spielen starten"
    Invoke-Knopf 'Spielen starten'
    Wait-Protokoll 'Viel Spass' 90
    Save-Bild 'spielt'
    $status = Get-StatusText
    Write-Host "   Status: $status"
    if ($status -notmatch '^DU spielst') { Stop-MitFehler "Status sollte 'DU spielst' sein, ist: $status" }
    $sperre = G --git-dir $server show main:PLAYING.lock
    if ($sperre -notmatch 'Tester') { Stop-MitFehler "Sperre auf dem Server fehlt: $sperre" }
    Write-Host "   Sperre auf dem Server: ok"
    if ((Get-Content -LiteralPath (Join-Path $save 'data\stadt.bin')) -ne 'Server-Stand') { Stop-MitFehler "Spielstand vom Server nicht in den Dolphin-Ordner geschrieben" }
    Write-Host "   Spielstand vom Server geschrieben: ok"

    Schritt "Starter beendet sich - Sitzung muss offen bleiben"
    Wait-Protokoll 'Dolphin laeuft aber weiter' 45
    Start-Sleep -Seconds 8     # laenger als die Wartezeit der Ende-Erkennung
    if ((Get-AppProtokoll) -match 'Dolphin beendet\.') { Stop-MitFehler "Sitzung wurde beendet, obwohl Dolphin noch laeuft" }
    Write-Host "   Sitzung offen: ok"

    Schritt "Im Spiel speichern und Dolphin schliessen"
    Set-Content -LiteralPath (Join-Path $save 'data\stadt.bin') -Value 'neuer Stand aus der Sitzung'
    Get-Process -Name 'Dolphin' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null; try { $p = $_.Path } catch { }; $p -and $p -like "$fake*"
    } | Stop-Process -Force
    Wait-Protokoll 'Fertig\. Spielstand hochgeladen, Sperre freigegeben\.' 90
    Start-Sleep -Seconds 2
    Save-Bild 'fertig'
    Write-Host ("   Status: {0}" -f (Get-StatusText))

    Schritt "Server pruefen"
    $dateien = G --git-dir $server ls-tree -r --name-only main
    if ($dateien -match 'PLAYING\.lock') { Stop-MitFehler "Sperre ist auf dem Server noch gesetzt" }
    $stand = G --git-dir $server show main:save/data/stadt.bin
    if ($stand -notmatch 'neuer Stand aus der Sitzung') { Stop-MitFehler "Neuer Spielstand fehlt auf dem Server (ist: $stand)" }
    $zeit = G --git-dir $server show main:playtime.json
    if ($zeit -notmatch 'Tester') { Stop-MitFehler "Spielzeit fehlt: $zeit" }
    Write-Host "   Sperre frei, neuer Spielstand und Spielzeit auf dem Server: ok"
    Write-Host ("   Commits: " + ((G --git-dir $server log --format=%s main) -replace "`n", ' | '))

    Schritt "Programm schliessen"
    [void]$script:app.CloseMainWindow()
    if (-not $script:app.WaitForExit(30000)) { Stop-MitFehler "Programm schliesst sich nicht" }
    Write-Host "   geschlossen"
    $fehlertext = if (Test-Path -LiteralPath $stderr) { (Get-Content -LiteralPath $stderr -Raw) } else { '' }
    if ($fehlertext -and $fehlertext.Trim()) { throw "Fehlerausgabe des Programms (stderr):`n$fehlertext" }
    Write-Host "   keine Fehlerausgabe: ok"
    $erfolg = $true
}
finally {
    if ($script:app -and -not $script:app.HasExited) { try { $script:app.Kill() } catch { } }
    Get-Process -Name 'Dolphin' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null; try { $p = $_.Path } catch { }; $p -and $p -like "$fake*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    $log = Get-AppProtokoll
    if ($log) { [IO.File]::WriteAllText((Join-Path $Ausgabe 'programm-protokoll.log'), $log, [Text.UTF8Encoding]::new($false)) }
    Write-Host ""
    Write-Host "== Protokoll des Programms" -ForegroundColor Cyan
    Write-Host $log
    if (Test-Path -LiteralPath $stderr) {
        $e = Get-Content -LiteralPath $stderr -Raw
        if ($e) { Write-Host "== stderr" -ForegroundColor Red; Write-Host $e }
    }
}
if ($erfolg) { Write-Host ""; Write-Host "Oberflaechentest bestanden." -ForegroundColor Green; exit 0 }
exit 1
