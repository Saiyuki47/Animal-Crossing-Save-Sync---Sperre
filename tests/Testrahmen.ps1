<#
================================================================================
  Testrahmen.ps1 - gemeinsame Grundlage aller Tests
================================================================================

  Wird von Start-Tests.ps1 per Punkt eingebunden. Stellt bereit:

    Test "Name" { ... }            ein Testfall; -NurWindows ueberspringt ihn
                                   auf anderen Systemen (robocopy, Prozesse)
    Soll <Bedingung> "Erwartung"   bricht den Testfall ab, wenn falsch
    Reset-Zustand                  Laufzeit-Zustand wie beim Programmstart
    New-TestRepos                  lokaler "Server" (bare) + Klone
    [AcssTest.Dialog]              Ersatz fuer Meldungsfenster: merkt sich die
                                   Texte und antwortet, wie der Test es vorgibt

  Die Funktionen des Programms werden direkt aus AC-SaveSync.ps1 geladen -
  getestet wird also genau der Code, der ausgeliefert wird. Umgelenkt werden
  nur Meldungsfenster (wuerden auf eine Antwort warten), DoEvents und der
  Warte-Mauszeiger (gibt es ohne Oberflaeche nicht). DoEvents zaehlt dabei
  mit - so laesst sich pruefen, dass das Fenster beim Warten bedienbar bleibt.

  Bewusst ohne Pester: so laeuft alles ohne Nachinstallieren identisch unter
  Windows PowerShell 5.1 und PowerShell 7 (auch unter Linux).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:AufWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
$script:SkriptPfad = Join-Path (Split-Path -Parent $PSScriptRoot) 'AC-SaveSync.ps1'
# Unter diesem Schluessel legen die Tests ihre Eintraege fuer "Apps" an -
# Start-Tests.ps1 raeumt ihn am Ende komplett weg.
$script:TestSchluessel = 'HKCU:\Software\AC-SaveSync-Tests'
$script:Ergebnisse = New-Object System.Collections.ArrayList
$script:TestWurzel = Join-Path ([IO.Path]::GetTempPath()) ("acss-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $script:TestWurzel -Force | Out-Null

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# --- Ersatz fuer Meldungsfenster und Oberflaechen-Bauteile -------------------
Add-Type -TypeDefinition @'
using System.Collections.Generic;
namespace AcssTest {
    public static class Dialog {
        public static List<string> Texte = new List<string>();
        public static Queue<string> Antworten = new Queue<string>();
        public static string Standard = "No";
        static string Antwort(object text) {
            Texte.Add(text == null ? "" : text.ToString());
            return Antworten.Count > 0 ? Antworten.Dequeue() : Standard;
        }
        public static string Show(object a) { return Antwort(a); }
        public static string Show(object a, object b) { return Antwort(a); }
        public static string Show(object a, object b, object c) { return Antwort(a); }
        public static string Show(object a, object b, object c, object d) { return Antwort(a); }
        public static string Show(object a, object b, object c, object d, object e) { return Antwort(a); }
        public static int DoEventsAnzahl;
        public static bool UseWaitCursor;
        public static void DoEvents() { DoEventsAnzahl++; }
        public static void Reset(string standard) { Texte.Clear(); Antworten.Clear(); Standard = standard; DoEventsAnzahl = 0; }
    }
    public class Uhr {   // Ersatz fuer Windows.Forms.Timer
        public bool Enabled; public int Starts; public int Stops; public int Interval;
        public void Start() { Enabled = true; Starts++; }
        public void Stop() { Enabled = false; Stops++; }
    }
    public class Feld {  // Ersatz fuer Label, Button, TextBox, Panel
        public string Text = ""; public object BackColor; public object ForeColor; public bool Enabled; public bool Visible;
    }
    public class Fenster {  // Ersatz fuer das Hauptfenster
        public int Geschlossen; public void Close() { Geschlossen++; }
    }
    public class Tipps { // Ersatz fuer Windows.Forms.ToolTip
        public int Anzahl; public void SetToolTip(object c, string t) { Anzahl++; }
    }
}
'@

# --- Programmfunktionen laden ------------------------------------------------
function Import-AcssFunktionen {
    $text = [IO.File]::ReadAllText($script:SkriptPfad, [Text.UTF8Encoding]::new($false))
    $fehler = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$fehler)
    if ($fehler -and $fehler.Count) { throw "AC-SaveSync.ps1 hat Syntaxfehler: $($fehler[0])" }

    # Nur Funktionen auf oberster Ebene (keine Hilfsfunktionen in Funktionen).
    $funktionen = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $null -eq $args[0].Parent.Parent.Parent
        }, $false)
    foreach ($f in $funktionen) {
        $code = $f.Extent.Text.Replace('[Windows.Forms.MessageBox]::Show(', '[AcssTest.Dialog]::Show(').
        Replace('[Windows.Forms.Application]::DoEvents()', '[AcssTest.Dialog]::DoEvents()').
        Replace('[Windows.Forms.Application]::UseWaitCursor', '[AcssTest.Dialog]::UseWaitCursor')
        . ([scriptblock]::Create($code))
        # Die Funktion lebt sonst nur im Bereich dieses Aufrufs.
        Set-Item -Path "function:script:$($f.Name)" -Value (Get-Item "function:$($f.Name)").ScriptBlock
    }

    # Einige Werte stehen nicht in Funktionen, sondern ganz oben im Skript:
    # die Klartext-Tabelle fuer Git-Meldungen und die Versionsangaben.
    $werte = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $args[0].Left.Extent.Text -match '^\$script:(GitKlartext|Version|ReleaseApi|ReleaseSeite)$' -and
            $null -eq $args[0].Parent.Parent.Parent
        }, $false)
    foreach ($w in $werte) { . ([scriptblock]::Create($w.Extent.Text)) }

    # Genau die Zeile ausfuehren, mit der das Programm die Konsole auf UTF-8
    # stellt - so wird auch geprueft, dass es sie noch gibt.
    $kodierung = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.TryStatementAst] -and
            $args[0].Extent.Text -match 'OutputEncoding' -and
            $null -eq $args[0].Parent.Parent.Parent
        }, $false) | Select-Object -First 1
    if (-not $kodierung) { throw 'Die Umstellung der Konsole auf UTF-8 fehlt in AC-SaveSync.ps1' }
    . ([scriptblock]::Create($kodierung.Extent.Text))
    return $ast
}

# Protokoll des Programms mitschreiben statt ins (nicht vorhandene) Fenster.
$script:Protokoll = New-Object System.Collections.ArrayList
function Write-Log { param([string]$msg) [void]$script:Protokoll.Add($msg) }
function Get-ProtokollText { return ($script:Protokoll -join "`n") }

# Laufzeit-Zustand so, wie ihn das Programm beim Start anlegt.
function Reset-Zustand {
    $script:Protokoll.Clear()
    [AcssTest.Dialog]::Reset('No')
    $script:AppDir = Join-Path $script:TestWurzel ('appdir-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null
    $script:cfg = @{
        DolphinPath = ''; RepoPath = ''; GamePath = ''; SaveFolder = ''; PicsFolder = ''
        PlayerName = 'Anna'; Branch = 'main'; LeaseMinutes = 5; HeartbeatSeconds = 60
        InstallDeclined = $false
    }
    # Fest installieren: alles in eigene Test-Ordner und einen eigenen
    # Test-Schluessel - nie auf den echten Desktop, ins Startmenue oder unter
    # "Apps" (siehe Remove-TestSchluessel).
    $orte = Join-Path $script:TestWurzel ('inst-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $script:InstallDir = Join-Path $orte 'Programs/AC-SaveSync'
    $script:DesktopDir = Join-Path $orte 'Desktop'
    $script:StartmenueDir = Join-Path $orte 'Startmenue'
    $script:VerknuepfungsName = 'Animal Crossing Save-Sync.lnk'
    $script:UninstallKey = $script:TestSchluessel + '\' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $script:SelfPath = ''
    $script:Auftrag = ''
    $script:UebergabeVon = ''
    $script:installFrage = $false
    $script:istErststart = $false
    $script:UebergabeWarteSek = 30
    $script:uebergeben = $false
    $script:instanzName = $null
    $script:proc = $null
    $script:holdingLock = $false
    $script:lastHeartbeat = Get-Date
    $script:lastAccounted = Get-Date
    $script:gitDa = $true
    $script:hbFehler = 0
    $script:hbLetzterErfolg = Get-Date
    $script:sperreVerloren = $false
    $script:dolphinNamen = @()
    $script:endeSeit = $null
    $script:letzterFremdstand = $null
    $script:updateLaeuft = $false
    $script:timer = New-Object AcssTest.Uhr
    $script:autoTimer = New-Object AcssTest.Uhr
    $script:saveTimer = New-Object AcssTest.Uhr
    $script:lblStatus = New-Object AcssTest.Feld
    $script:btnPlay = New-Object AcssTest.Feld
    $script:btnStop = New-Object AcssTest.Feld
    $script:tips = New-Object AcssTest.Tipps
    $script:mainForm = $null
    $script:fortschrittPanel = $null
    $script:fortschrittText = $null
    $script:eingabeSperreDa = $false
    $script:beschaeftigt = 0
    $script:beschaeftigtText = ''
    $script:beschaeftigtSeit = Get-Date
    $script:letzteArbeit = [datetime]::MinValue
    $script:schliessenWennFrei = $false
    $script:gitPfad = $null
    $script:schliesseAb = $false
    $script:hbAufgeschobenSeit = $null
    $script:instanzSperre = $null
    $script:FakeName = 'fd' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $env:COMPUTERNAME = 'TEST-PC'
}

# --- Testfaelle --------------------------------------------------------------
function Soll {
    param([bool]$Bedingung, [string]$Erwartung)
    if (-not $Bedingung) { throw "Erwartet: $Erwartung" }
}

function Test {
    param([string]$Name, [scriptblock]$Block, [switch]$NurWindows)
    if ($NurWindows -and -not $script:AufWindows) {
        [void]$script:Ergebnisse.Add([pscustomobject]@{ Name = $Name; Status = 'uebersprungen'; Grund = 'nur unter Windows' })
        Write-Host ("  --   {0}  (nur unter Windows)" -f $Name) -ForegroundColor DarkGray
        return
    }
    Reset-Zustand
    # Der Testblock laeuft in diesem Bereich - eigene Variablen deshalb mit
    # Namen, die ein Test nicht versehentlich ueberschreibt.
    $__testName = $Name
    $__testOrt = Get-Location
    try {
        . $Block
        [void]$script:Ergebnisse.Add([pscustomobject]@{ Name = $__testName; Status = 'ok'; Grund = '' })
        Write-Host ("  OK   {0}" -f $__testName) -ForegroundColor Green
    }
    catch {
        $__wo = $_.InvocationInfo
        $__grund = "{0}  (Zeile {1}: {2})" -f $_.Exception.Message, $__wo.ScriptLineNumber, $__wo.Line.Trim()
        [void]$script:Ergebnisse.Add([pscustomobject]@{ Name = $__testName; Status = 'FEHLER'; Grund = $__grund })
        Write-Host ("  FEHL {0}" -f $__testName) -ForegroundColor Red
        Write-Host ("       {0}" -f $__grund) -ForegroundColor Red
        $__letzte = @($script:Protokoll | Select-Object -Last 8)
        if ($__letzte.Count) { Write-Host ("       Protokoll: " + ($__letzte -join ' | ')) -ForegroundColor DarkYellow }
    }
    finally {
        Set-Location $__testOrt
        Stop-TestProzesse
    }
}

# --- Git-Hilfen ----------------------------------------------------------------
function Invoke-G {
    # git im Ordner (erstes Argument) ohne PowerShell-Fehlerdatensaetze.
    # Bewusst ohne param-Block: sonst deutet PowerShell Git-Schalter wie "-A"
    # als eigene Parameter dieser Funktion.
    $Ordner = $args[0]
    $GitArgs = @($args | Select-Object -Skip 1)
    $out = & git -C $Ordner @GitArgs 2>&1
    return (@($out | ForEach-Object { "$_" }) -join "`n")
}

# Legt einen "Server" (bare) und Klone an. Rueckgabe: Hashtable mit Pfaden.
function New-TestRepos {
    param([string[]]$Klone = @('a'), [switch]$MitStart)
    $wurzel = Join-Path $script:TestWurzel ('repos-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $wurzel -Force | Out-Null
    $server = Join-Path $wurzel 'server.git'
    & git init -q --bare -b main $server 2>&1 | Out-Null
    $r = @{ Wurzel = $wurzel; Server = $server }
    foreach ($k in $Klone) {
        $pfad = Join-Path $wurzel $k
        & git clone -q $server $pfad 2>&1 | Out-Null
        Invoke-G $pfad config user.name $k | Out-Null
        Invoke-G $pfad config user.email "$k@test" | Out-Null
        $r[$k] = $pfad
    }
    if ($MitStart) {
        $erster = $r[$Klone[0]]
        Set-Content -LiteralPath (Join-Path $erster 'start.txt') -Value 'start'
        Invoke-G $erster add -A | Out-Null
        Invoke-G $erster commit -qm start | Out-Null
        Invoke-G $erster push -q origin main | Out-Null
        foreach ($k in $Klone | Select-Object -Skip 1) { Invoke-G $r[$k] pull -q origin main | Out-Null }
    }
    return $r
}

# Commit + Push im Namen eines Mitspielers (anderer Klon).
function Push-Als {
    param([string]$Klon, [string]$Datei, [string]$Inhalt)
    Invoke-G $Klon pull -q origin main | Out-Null
    Set-Content -LiteralPath (Join-Path $Klon $Datei) -Value $Inhalt -Encoding UTF8
    Invoke-G $Klon add -A | Out-Null
    Invoke-G $Klon commit -qm $Datei | Out-Null
    Invoke-G $Klon push -q origin main | Out-Null
}

function New-SperrText {
    param([string]$Besitzer, [string]$Rechner = 'ANDERER-PC', [int]$VorMinuten = 0)
    $t = [datetime]::UtcNow.AddMinutes(-$VorMinuten).ToString('o')
    return ('{"owner":"' + $Besitzer + '","machine":"' + $Rechner + '","startedUtc":"' + $t + '","updatedUtc":"' + $t + '"}')
}

# --- Ersatz-Dolphin und Starter -----------------------------------------------
# Windows: eine Kopie von ping.exe, die eine Weile laeuft, ohne etwas zu tun.
# Sonst: eine Kopie von sleep.
# Jeder Test bekommt einen EIGENEN Prozessnamen (siehe Reset-Zustand): So kann
# ein Ueberbleibsel aus einem frueheren Test nie mit dem Dolphin des aktuellen
# verwechselt werden. (Unter Linux in Containern bleiben beendete Prozesse
# ohne Elternprozess zudem als "Zombie" in der Prozessliste stehen.)
$script:TestProzesse = New-Object System.Collections.ArrayList
$script:FakeName = 'fd000000'

function Get-FakeDolphin {
    $ordner = Join-Path $script:TestWurzel 'FakeDolphin'
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    if ($script:AufWindows) {
        $exe = Join-Path $ordner ($script:FakeName + '.exe')
        if (-not (Test-Path -LiteralPath $exe)) {
            Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\PING.EXE') -Destination $exe
        }
        return @{ Exe = $exe; Name = $script:FakeName; Args = @('-n', '120', '127.0.0.1') }
    }
    $exe = Join-Path $ordner $script:FakeName
    if (-not (Test-Path -LiteralPath $exe)) {
        Copy-Item -LiteralPath (Get-Command sleep).Source -Destination $exe
        & chmod +x $exe
    }
    return @{ Exe = $exe; Name = $script:FakeName; Args = @('120') }
}

function Start-FakeDolphin {
    $d = Get-FakeDolphin
    $p = if ($script:AufWindows) {
        Start-Process -FilePath $d.Exe -ArgumentList $d.Args -WindowStyle Hidden -PassThru
    }
    else { Start-Process -FilePath $d.Exe -ArgumentList $d.Args -PassThru }
    [void]$script:TestProzesse.Add($p)
    return $p
}

# Starter, der Dolphin startet. -Wartet: bleibt offen, bis Dolphin endet
# (wie eine .bat ohne "start"); sonst beendet er sich sofort.
function Start-FakeStarter {
    param([switch]$Wartet)
    $d = Get-FakeDolphin
    if ($script:AufWindows) {
        $datei = Join-Path $script:TestWurzel ('starter-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.cmd')
        $aufruf = '"{0}" {1}' -f $d.Exe, ($d.Args -join ' ')
        $zeile = if ($Wartet) { $aufruf } else { 'start "" /b ' + $aufruf }
        Set-Content -LiteralPath $datei -Value "@echo off`r`n$zeile`r`n" -Encoding ASCII
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList '/c', "`"$datei`"" -WindowStyle Hidden -PassThru
    }
    else {
        $datei = Join-Path $script:TestWurzel ('starter-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.sh')
        $aufruf = "'{0}' 120 &" -f $d.Exe
        $zeilen = if ($Wartet) { "#!/bin/sh`n$aufruf`nwait`n" } else { "#!/bin/sh`n$aufruf`nexit 0`n" }
        [IO.File]::WriteAllText($datei, $zeilen)
        & chmod +x $datei
        $p = Start-Process -FilePath $datei -PassThru
    }
    [void]$script:TestProzesse.Add($p)
    return $p
}

# Raeumt alle Ersatz-Dolphins und Starter nach jedem Test weg. Der Name ist
# pro Test eindeutig - ein echtes Dolphin wird so nie angefasst.
function Stop-TestProzesse {
    foreach ($p in @($script:TestProzesse)) {
        try { if (-not $p.HasExited) { $p.Kill() } }
        catch { Write-Verbose "Prozess schon weg: $($_.Exception.Message)" }
    }
    $script:TestProzesse.Clear()
    Get-Process -Name $script:FakeName -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch { Write-Verbose "Prozess schon weg: $($_.Exception.Message)" }
    }
}

# Wartet, bis eine Bedingung eintritt (Prozesse brauchen einen Moment).
function Wait-Bis {
    param([scriptblock]$Bedingung, [int]$Sekunden = 10)
    $ende = (Get-Date).AddSeconds($Sekunden)
    while ((Get-Date) -lt $ende) {
        if (& $Bedingung) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return [bool](& $Bedingung)
}
