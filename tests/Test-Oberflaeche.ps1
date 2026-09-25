<#
================================================================================
  Test-Oberflaeche.ps1 - startet das echte Programm und spielt eine Sitzung
================================================================================

  Nur unter Windows. Laeuft vollstaendig in einem Temp-Ordner mit eigenen
  Einstellungen (APPDATA umgelenkt) und einem lokalen "Server" statt GitHub.

  Ablauf:
    1. Programm starten, warten bis der Status geprueft ist
    2. per UI Automation auf "Spielen starten" klicken
       - der Test-Server ist absichtlich langsam (jedes Hochladen dauert
         8 s): waehrenddessen muss das Fenster reagieren und die
         Fortschrittsanzeige "Lade auf den Server hoch" zeigen
       - als "Spiel" dient ein Starter, der Dolphin startet und sich sofort
         selbst beendet (die Sitzung muss trotzdem offen bleiben)
    3. Spielstand aendern ("im Spiel speichern"), Ersatz-Dolphin schliessen
    4. pruefen: Sperre frei, neuer Spielstand und Spielzeit auf dem Server
    5. Spielzeit-Dialog oeffnen, alle drei Reiter fotografieren
       (der Verlauf enthaelt dafuer vorbereitete Sitzungen von Anna und Max)
    6. Ruebenkurs oeffnen, Preise eintragen, speichern - sie muessen samt
       README-Abschnitt auf dem Server ankommen
    7. Programm schliessen, pruefen: keine Fehler auf stderr

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
# Alle Fenster des Programms. Dialoge und Meldungen, die einem Fenster
# gehoeren, haengt UI Automation unter dieses Fenster - nicht unter den
# Desktop. Deshalb werden auch die direkten Unterfenster mitgesucht.
# Nur echte Fenster: Steht der Mauszeiger zufaellig ueber einem Knopf,
# erscheint dessen Kurzhinweis samt Schatten (Klasse "SysShadow", ohne Namen).
# Beides galt sonst als "unerwartetes Fenster", und der Test scheiterte.
function Get-ProgrammFenster {
    $istFenster = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    $bed = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $script:app.Id)), $istFenster)
    $alle = New-Object System.Collections.ArrayList
    foreach ($f in $UIA::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $bed)) {
        [void]$alle.Add($f)
        foreach ($k in $f.FindAll([System.Windows.Automation.TreeScope]::Children, $istFenster)) { [void]$alle.Add($k) }
    }
    return @($alle)
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
# Hinweis: UI Automation meldet die Elemente dieses Programms als "Pane"
# (nicht als Text/Button) - deshalb wird nach Fensterklasse und Text gesucht.
function Get-StatusText {
    $f = Get-Hauptfenster
    if (-not $f) { return '' }
    foreach ($e in $f.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($e.Current.ClassName -notlike '*STATIC*') { continue }
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

# Klickt per BM_CLICK-Nachricht an das Knopf-Fenster. Geht bei jedem
# Win32-Knopf (auch wenn UI Automation kein Invoke anbietet) und wird nur
# eingereiht - oeffnet das Programm dabei ein Meldungsfenster, haengt der
# Test nicht fest, sondern bemerkt es in Wait-Protokoll.
Add-Type -Namespace AcssUi -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr w, string l);
'@

# Reagiert das Fenster? Schickt eine leere Nachricht und wartet hoechstens
# $Millisekunden auf die Antwort. Ein eingefrorenes Fenster antwortet nicht.
function Test-FensterReagiert {
    param([IntPtr]$Hwnd, [int]$Millisekunden = 1500)
    $ergebnis = [IntPtr]::Zero
    $r = [AcssUi.Win]::SendMessageTimeout($Hwnd, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, $Millisekunden, [ref]$ergebnis)   # WM_NULL, SMTO_ABORTIFHUNG
    return ($r -ne [IntPtr]::Zero)
}

# Sucht ein Element in einem beliebigen Fenster (z. B. einem Dialog).
function Find-InFenster {
    param($Fenster, [string]$Name, [string]$Klasse = '')
    foreach ($e in $Fenster.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($Name -and $e.Current.Name -ne $Name) { continue }
        if ($Klasse -and $e.Current.ClassName -notlike "*$Klasse*") { continue }
        return $e
    }
    return $null
}

# Text der Fortschrittsanzeige unten im Hauptfenster (leer, wenn nichts laeuft).
# Bewusst ohne UI Automation: deren Abfragen muss das Programm selbst
# beantworten, und waehrend es beschaeftigt ist, dauert das pro Element etwas.
# Hier genuegt eine Nachricht: Die (einzige) Fortschrittsleiste wird ueber
# ihre Fensterklasse gefunden - ob sie sichtbar ist, weiss Windows selbst -,
# dann wird nur der Text des Labels daneben abgefragt.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace AcssUi {
    public static class Fortschritt {
        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, StringBuilder l, uint flags, uint timeout, out IntPtr result);

        public static string Text(IntPtr haupt) {
            IntPtr balken = IntPtr.Zero;
            EnumChildWindows(haupt, (h, l) => {
                var k = new StringBuilder(256);
                GetClassName(h, k, k.Capacity);
                if (k.ToString().IndexOf("progress", StringComparison.OrdinalIgnoreCase) < 0) return true;
                balken = h;
                return false;
            }, IntPtr.Zero);
            if (balken == IntPtr.Zero || !IsWindowVisible(balken)) return "";
            string text = "";
            EnumChildWindows(GetParent(balken), (h, l) => {
                if (h == balken) return true;
                var sb = new StringBuilder(512);
                IntPtr r;
                // WM_GETTEXT, SMTO_ABORTIFHUNG, hoechstens 1 s
                if (SendMessageTimeout(h, 0x000D, (IntPtr)sb.Capacity, sb, 2, 1000, out r) == IntPtr.Zero) return true;
                if (sb.Length == 0) return true;
                text = sb.ToString();
                return false;
            }, IntPtr.Zero);
            return text;
        }
    }
}
'@
function Get-FortschrittText {
    param([IntPtr]$Hwnd)
    return [AcssUi.Fortschritt]::Text($Hwnd)
}
function Invoke-Knopf {
    param([string]$Name)
    $k = Get-Element $Name
    if (-not $k) { Stop-MitFehler "Knopf '$Name' nicht gefunden" }
    if (-not $k.Current.IsEnabled) { Stop-MitFehler "Knopf '$Name' ist gesperrt" }
    $hwnd = [IntPtr]$k.Current.NativeWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { Stop-MitFehler "Knopf '$Name' hat kein Fenster-Handle" }
    [void][AcssUi.Win]::PostMessage($hwnd, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
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
    try { Write-Elementbaum } catch { Write-Host "   (Elementbaum nicht lesbar: $($_.Exception.Message))" }
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
# Vorbereiteter Verlauf fuer die Spielzeit-Statistik: zwei Wochen lang
# Sitzungen von Anna und Max, so wie das Programm sie selbst schreibt.
function Add-VerlaufsCommit {
    param([datetime]$Zeit, [string]$Betreff)
    $iso = $Zeit.ToString('yyyy-MM-ddTHH:mm:ss') + 'Z'
    $env:GIT_COMMITTER_DATE = $iso; $env:GIT_AUTHOR_DATE = $iso
    try { G -C $repo commit -q --allow-empty -m $Betreff | Out-Null }
    finally { Remove-Item Env:GIT_COMMITTER_DATE, Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue }
}
$heute = [datetime]::UtcNow.Date
for ($i = 14; $i -ge 1; $i--) {
    if ($i -in 5, 9) { continue }                        # Luecken fuer die Serie
    $wer = if ($i % 3 -eq 0) { 'Max' } else { 'Anna' }
    $beginn = $heute.AddDays(-$i).AddHours(16)
    $dauer = 40 + (($i * 17) % 80)                       # 40 bis 119 Minuten
    Add-VerlaufsCommit $beginn "lock: $wer"
    Add-VerlaufsCommit $beginn.AddMinutes([math]::Floor($dauer / 2)) "heartbeat: $wer"
    Add-VerlaufsCommit $beginn.AddMinutes($dauer) "Session beendet + Spielstand ($wer)"
}
G -C $repo push -q origin main | Out-Null
# Langsamer Server: jedes Hochladen dauert 8 s. Ein eingefrorenes Fenster
# fiele dabei sofort auf.
[IO.File]::WriteAllText((Join-Path $server 'hooks\pre-receive'), "#!/bin/sh`nsleep 8`n")
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

    Schritt "Spielen starten - langsamer Server, Fenster muss reagieren"
    $hwnd = [IntPtr](Get-Hauptfenster).Current.NativeWindowHandle
    Invoke-Knopf 'Spielen starten'
    $proben = 0; $haenger = 0; $fortschritt = ''; $bildGemacht = $false
    $ende = (Get-Date).AddSeconds(90)
    while (-not ((Get-AppProtokoll) -match 'Viel Spass') -and (Get-Date) -lt $ende) {
        if ($script:app.HasExited) { Stop-MitFehler "Das Programm hat sich unerwartet beendet" }
        $proben++
        if (-not (Test-FensterReagiert $hwnd)) { $haenger++ }
        $t = Get-FortschrittText $hwnd
        if ($t) {
            $fortschritt = $t
            if (-not $bildGemacht -and $t -match 'Lade auf den Server hoch') { Save-Bild 'hochladen'; $bildGemacht = $true }
        }
        Start-Sleep -Milliseconds 300
    }
    Wait-Protokoll 'Viel Spass' 5
    Write-Host ("   {0} Proben, davon {1} ohne Antwort; Fortschrittsanzeige: '{2}'" -f $proben, $haenger, $fortschritt)
    if ($proben -lt 10) { Stop-MitFehler "Zu wenige Proben ($proben) - das Hochladen war nicht langsam genug zum Pruefen" }
    if ($haenger -gt 0) { Stop-MitFehler "Das Fenster hat $haenger-mal nicht reagiert, waehrend hochgeladen wurde" }
    if (-not $bildGemacht) { Stop-MitFehler "Die Fortschrittsanzeige 'Lade auf den Server hoch' war nie zu sehen (zuletzt: '$fortschritt')" }
    Write-Host "   Fenster reagiert, Fortschrittsanzeige sichtbar: ok"
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
        $p = $null
        try { $p = $_.Path } catch { Write-Verbose "Pfad nicht lesbar: $($_.Exception.Message)" }
        $p -and $p -like "$fake*"
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

    Schritt "Spielzeit-Dialog mit Wochen und Rekorden"
    Invoke-Knopf 'Spielzeit'
    $dlg = $null
    $ende = (Get-Date).AddSeconds(30)
    while (-not $dlg -and (Get-Date) -lt $ende) {
        $dlg = Get-ProgrammFenster | Where-Object { $_.Current.Name -eq 'Spielzeit' } | Select-Object -First 1
        Start-Sleep -Milliseconds 300
    }
    if (-not $dlg) { Stop-MitFehler "Der Spielzeit-Dialog geht nicht auf" }
    Start-Sleep -Seconds 1
    Save-Bild 'spielzeit-gesamt'
    $reiter = Find-InFenster $dlg -Klasse 'SysTabControl32'
    if (-not $reiter) { Stop-MitFehler "Reiter im Spielzeit-Dialog nicht gefunden" }
    $hReiter = [IntPtr]$reiter.Current.NativeWindowHandle
    foreach ($nr in 1, 2) {
        [void][AcssUi.Win]::PostMessage($hReiter, 0x1330, [IntPtr]$nr, [IntPtr]::Zero)   # TCM_SETCURFOCUS
        Start-Sleep -Seconds 1
        if ($script:app.HasExited) { Stop-MitFehler "Programm beim Wechsel des Reiters beendet" }
        Save-Bild $(if ($nr -eq 1) { 'spielzeit-wochen' } else { 'spielzeit-rekorde' })
    }
    $zu = Find-InFenster $dlg -Name 'Schliessen'
    if (-not $zu) { Stop-MitFehler "Knopf 'Schliessen' im Spielzeit-Dialog nicht gefunden" }
    [void][AcssUi.Win]::PostMessage([IntPtr]$zu.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    $ende = (Get-Date).AddSeconds(10)
    while ((Get-ProgrammFenster | Where-Object { $_.Current.Name -eq 'Spielzeit' }) -and (Get-Date) -lt $ende) { Start-Sleep -Milliseconds 300 }
    if (Get-ProgrammFenster | Where-Object { $_.Current.Name -eq 'Spielzeit' }) { Stop-MitFehler "Spielzeit-Dialog schliesst sich nicht" }
    Write-Host "   Dialog geoeffnet, drei Reiter, geschlossen: ok"

    Schritt "Ruebenkurs: Preise eintragen und speichern"
    $rkName = "R$([char]0xFC)benkurs"
    Invoke-Knopf $rkName
    $dlg = $null
    $ende = (Get-Date).AddSeconds(60)
    while (-not $dlg -and (Get-Date) -lt $ende) {
        $dlg = Get-ProgrammFenster | Where-Object { $_.Current.Name -eq $rkName } | Select-Object -First 1
        Start-Sleep -Milliseconds 300
    }
    if (-not $dlg) { Stop-MitFehler "Der Ruebenkurs geht nicht auf" }
    Start-Sleep -Seconds 1
    # Eintragen per WM_SETTEXT - das Programm bekommt dabei dieselbe
    # Aenderungsmeldung wie beim Tippen. UI Automation meldet die Textfelder
    # ohne Namen; sie kommen aber in der Reihenfolge, in der das Fenster sie
    # anlegt: Sigrids Preis, Deine Rueben, dann Mo vorm., Mo nachm., Di ...
    $felder = @($dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) |
        Where-Object { $_.Current.ClassName -like '*EDIT*' })
    if ($felder.Count -ne 14) { Stop-MitFehler "14 Eingabefelder erwartet, gefunden: $($felder.Count)" }
    $eintraege = @('100', '400', '88', '85', '120', '180')
    for ($i = 0; $i -lt $eintraege.Count; $i++) {
        [void][AcssUi.Win]::SendMessage([IntPtr]$felder[$i].Current.NativeWindowHandle, 0x000C, [IntPtr]::Zero, $eintraege[$i])   # WM_SETTEXT
    }
    Start-Sleep -Seconds 2
    Save-Bild 'ruebenkurs'
    $prozent = @($dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) |
        ForEach-Object { $_.Current.Name } | Where-Object { $_ -match '^\d+\s?%$' })
    Write-Host ("   Muster-Anzeige: {0}" -f ($prozent -join ' / '))
    if ($prozent -notcontains '100 %' -and $prozent -notcontains '100%') { Stop-MitFehler "Die Einschaetzung zeigt nicht 100 % fuer die grosse Spitze" }
    $speichern = Find-InFenster $dlg -Name 'Speichern'
    if (-not $speichern) { Stop-MitFehler "Knopf 'Speichern' nicht gefunden" }
    [void][AcssUi.Win]::PostMessage([IntPtr]$speichern.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    $ende = (Get-Date).AddSeconds(60)
    $json = ''
    while ((Get-Date) -lt $ende) {
        $alt = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $json = (& git --git-dir $server show main:rueben.json 2>$null) -join "`n"
        $ErrorActionPreference = $alt
        if ($json -match '"400"|: 400' -and $json -match '180') { break }
        Start-Sleep -Milliseconds 500
    }
    if ($json -notmatch '180') { Stop-MitFehler "Die Preise sind nicht auf dem Server angekommen: $json" }
    $readme = G --git-dir $server show main:README.md
    if ($readme -notmatch 'Sigrids Preis: 100 Sternis' -or $readme -notmatch '\| vormittags \| 88 \| 120') { Stop-MitFehler "README-Abschnitt fehlt oder ist falsch: $readme" }
    Write-Host "   Preise und README-Abschnitt auf dem Server: ok"
    Start-Sleep -Seconds 1
    Save-Bild 'ruebenkurs-gespeichert'
    $zu = Find-InFenster $dlg -Name 'Schliessen'
    if (-not $zu) { Stop-MitFehler "Knopf 'Schliessen' im Ruebenkurs nicht gefunden" }
    [void][AcssUi.Win]::PostMessage([IntPtr]$zu.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    $ende = (Get-Date).AddSeconds(10)
    while ((Get-ProgrammFenster | Where-Object { $_.Current.Name -eq $rkName }) -and (Get-Date) -lt $ende) { Start-Sleep -Milliseconds 300 }
    if (Get-ProgrammFenster | Where-Object { $_.Current.Name -eq $rkName }) { Stop-MitFehler "Ruebenkurs schliesst sich nicht (Rueckfrage offen?)" }
    Write-Host "   Ruebenkurs geoeffnet, gespeichert, geschlossen: ok"

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
    if ($script:app -and -not $script:app.HasExited) {
        try { $script:app.Kill() } catch { Write-Verbose "Programm schon beendet: $($_.Exception.Message)" }
    }
    Get-Process -Name 'Dolphin' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { Write-Verbose "Pfad nicht lesbar: $($_.Exception.Message)" }
        $p -and $p -like "$fake*"
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
