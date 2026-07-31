<#
================================================================================
  Animal Crossing Save-Sync + Sperre (Git) - mit grafischer Oberflaeche
================================================================================

  Was macht das Skript?
  ---------------------
  Es startet Dolphin NICHT direkt, sondern kuemmert sich drumherum:
    1. Vor dem Spielen:  holt den neuesten Spielstand aus dem Git-Repo
    2. Setzt eine "Sperre" (PLAYING.lock) mit deinem Namen + Zeitstempel
    3. Waehrend des Spielens: sendet regelmaessig einen "Herzschlag"
       (aktualisiert den Zeitstempel + sichert den Spielstand)
    4. Nach dem Beenden: laedt den Spielstand hoch und gibt die Sperre frei

  Warum kann die Sperre NICHT dauerhaft haengen bleiben?
  ------------------------------------------------------
    - Lease/Ablauf:  Ist der Zeitstempel aelter als "LeaseMinutes" (Standard 5),
      gilt die Sperre als tot und wird automatisch uebernommen. Ein Absturz
      stoppt den Herzschlag -> Sperre laeuft von allein ab.
    - Aufraeumen:  Beendet sich Dolphin normal, wird die Sperre sofort freigegeben.
    - Notausgang:  Der Knopf "Sperre erzwingen freigeben" loescht sie sofort.
    - Beim Schliessen des Fensters wirst du gewarnt; selbst dann laeuft die
      Sperre spaetestens nach LeaseMinutes ab.

  Voraussetzungen (einmalig):
  ---------------------------
    - Git muss installiert und im PATH sein  (git --version testen)
    - Ihr habt EIN gemeinsames privates Git-Repo (z. B. GitHub) und BEIDE
      habt es lokal geklont. RepoPath zeigt auf diesen Ordner.
    - Der Dolphin-Spielstand liegt in diesem Repo-Ordner (oder ihr verlinkt
      den Dolphin-Save-Ordner per Symlink dort hinein).
    - Eure Git-Zugangsdaten sind gespeichert (Git Credential Manager bei HTTPS
      oder ein SSH-Key), sonst kann das Skript nicht ohne Nachfrage pushen.
    - Beide benutzen dieses Skript, ABER mit UNTERSCHIEDLICHEM Spielernamen.

  Starten:
  --------
    Rechtsklick auf die Datei -> "Mit PowerShell ausfuehren"
    Oder in PowerShell:   powershell -ExecutionPolicy Bypass -File .\AC-SaveSync.ps1
================================================================================
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --------------------------------------------------------------------------
# Kurzhilfen (Tooltips), die beim Ueberfahren mit der Maus erscheinen
# --------------------------------------------------------------------------
# EIN ToolTip-Bauteil reicht fuer alle Fenster; es merkt sich pro Control
# einen Text. Wird weiter unten mit Set-Tip befuellt.
$script:tips = New-Object Windows.Forms.ToolTip
$script:tips.InitialDelay = 350       # ms, bis der Hinweis aufgeht
$script:tips.ReshowDelay = 120        # ms beim Wechsel zum naechsten Feld
$script:tips.AutoPopDelay = 30000     # ms, so lange bleibt er stehen
$script:tips.ShowAlways = $true       # auch wenn das Fenster nicht aktiv ist

# Haengt denselben Hinweis an mehrere Controls (Beschriftung + Feld + Knopf),
# damit es egal ist, worueber die Maus steht.
function Set-Tip {
    param(
        [string]$Text,
        [Parameter(ValueFromRemainingArguments = $true)]$Controls
    )
    foreach ($c in $Controls) {
        if ($c) { $script:tips.SetToolTip($c, $Text) }
    }
}

# Eingebettetes Deko-Banner (Base64-PNG, 192x64)
$script:BannerBase64 = "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"

# Git soll nie interaktiv nach Passwoertern fragen (sonst haengt das Skript):
$env:GIT_TERMINAL_PROMPT = "0"

# --------------------------------------------------------------------------
# Konfiguration
# --------------------------------------------------------------------------
# Die Konfig liegt im Windows-Benutzerprofil unter %APPDATA%\AC-SaveSync\.
# Dieser Ordner ist im Explorer standardmaessig ausgeblendet und liegt voellig
# getrennt vom Skript - es landet also nichts Sichtbares neben der .ps1.
$script:AppDir = if ($env:APPDATA) { Join-Path $env:APPDATA "AC-SaveSync" }
elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "AC-SaveSync" }
else { Join-Path (Get-Location).Path "AC-SaveSync" }
if (-not (Test-Path $script:AppDir)) {
    New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null
}
$script:ConfigPath = Join-Path $script:AppDir "acsync-config.json"

$script:defaults = @{
    DolphinPath      = "C:\Program Files\Dolphin-x64\Dolphin.exe"
    RepoPath         = "$env:USERPROFILE\Documents\ACSave"
    GamePath         = ""
    SaveFolder       = ""
    PicsFolder       = ""
    PlayerName       = $env:USERNAME
    Branch           = "main"
    LeaseMinutes     = 5
    HeartbeatSeconds = 60
}
$script:cfg = $script:defaults.Clone()

# Laufzeit-Zustand
$script:proc = $null
$script:holdingLock = $false
$script:lastHeartbeat = Get-Date
$script:lastAccounted = Get-Date
# Meldungen, die anfallen, bevor das Protokollfeld existiert (z. B. beim Laden
# der Konfig). Sie werden nachgetragen, sobald die Oberflaeche steht.
$script:pendingLog = @()
# Ergebnis des letzten Speicherversuchs der Einstellungen (siehe Save-ConfigFromUI)
$script:configSaved = $false

function Import-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            $j = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            foreach ($k in @($script:cfg.Keys)) {
                if ($null -ne $j.$k -and "$($j.$k)" -ne "") { $script:cfg[$k] = $j.$k }
            }
        }
        catch {
            Write-Log "WARNUNG: Einstellungsdatei unlesbar - es gelten die Standardwerte."
            Write-Log ("  Datei: {0}" -f $script:ConfigPath)
            Write-Log ("  Grund: {0}" -f $_.Exception.Message)
        }
    }
}

function Save-ConfigFromUI {
    $script:cfg.DolphinPath = $script:txtDolphin.Text
    $script:cfg.RepoPath = $script:txtRepo.Text
    $script:cfg.GamePath = $script:txtGame.Text
    $script:cfg.SaveFolder = $script:txtSave.Text
    $script:cfg.PicsFolder = $script:txtPics.Text
    $script:cfg.PlayerName = $script:txtName.Text
    $script:cfg.Branch = $script:txtBranch.Text

    $lm = 5; [void][int]::TryParse($script:txtLease.Text, [ref]$lm)
    $hb = 60; [void][int]::TryParse($script:txtHeart.Text, [ref]$hb)
    if ($lm -lt 1) { $lm = 1 }
    if ($hb -lt 10) { $hb = 10 }
    $script:cfg.LeaseMinutes = $lm
    $script:cfg.HeartbeatSeconds = $hb

    # Ob das Schreiben geklappt hat, merken - sonst wuerde der Speichern-Knopf
    # "gespeichert" melden, obwohl die Datei nicht geschrieben werden konnte.
    $script:configSaved = $false
    try {
        ($script:cfg | ConvertTo-Json) | Set-Content -Path $script:ConfigPath -Encoding UTF8
        $script:configSaved = $true
    }
    catch {
        Write-Log "FEHLER: Einstellungen konnten nicht gespeichert werden."
        Write-Log ("  Datei: {0}" -f $script:ConfigPath)
        Write-Log ("  Grund: {0}" -f $_.Exception.Message)
    }
}

# --------------------------------------------------------------------------
# Kleine Helfer
# --------------------------------------------------------------------------
function Write-Log {
    param([string]$msg)
    $line = "[{0}] {1}`r`n" -f (Get-Date).ToString("HH:mm:ss"), $msg
    if ($script:txtLog) {
        # Zuerst nachtragen, was vor dem Fensteraufbau gemeldet wurde
        if ($script:pendingLog.Count -gt 0) {
            foreach ($p in $script:pendingLog) { $script:txtLog.AppendText($p) }
            $script:pendingLog = @()
        }
        $script:txtLog.AppendText($line)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    }
    else {
        # Noch kein Protokollfeld -> merken und zusaetzlich in die Konsole
        $script:pendingLog += $line
        Write-Host $line
    }
}

function Invoke-Git {
    param([string[]]$GitArgs)
    $out = & git -C $script:cfg.RepoPath @GitArgs 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out | Out-String).Trim() }
}

function Test-Repo {
    if (-not (Test-Path (Join-Path $script:cfg.RepoPath ".git"))) {
        Write-Log "FEHLER: Unter RepoPath liegt kein Git-Repo. Bitte erst das gemeinsame Repo dorthin klonen."
        return $false
    }
    return $true
}

# Auf den Remote-Stand zwingen (kein Merge -> keine Konflikte).
# Nur aufrufen, wenn wir die Sperre NICHT halten (sonst wuerden wir eigenen
# Fortschritt verwerfen).
function Sync-Remote {
    $f = Invoke-Git @('fetch', 'origin')
    if ($f.Code -ne 0) { Write-Log "fetch-Warnung: $($f.Text)" }
    $r = Invoke-Git @('reset', '--hard', "origin/$($script:cfg.Branch)")
    if ($r.Code -ne 0) { Write-Log "reset-Warnung: $($r.Text)" }
}

function Get-LockPath { Join-Path $script:cfg.RepoPath "PLAYING.lock" }

function Set-LockFile {
    $obj = [ordered]@{
        owner      = $script:cfg.PlayerName
        machine    = $env:COMPUTERNAME
        updatedUtc = [datetime]::UtcNow.ToString("o")
    }
    ($obj | ConvertTo-Json) | Set-Content -Path (Get-LockPath) -Encoding UTF8
}

function Get-LockState {
    $lf = Get-LockPath
    if (-not (Test-Path $lf)) { return [pscustomobject]@{ State = 'free' } }
    try {
        $j = Get-Content $lf -Raw -ErrorAction Stop | ConvertFrom-Json
        $upd = [datetimeoffset]::Parse($j.updatedUtc).UtcDateTime
        $age = ([datetime]::UtcNow - $upd).TotalMinutes
        $mine = ($j.owner -eq $script:cfg.PlayerName) -and ($j.machine -eq $env:COMPUTERNAME)
        return [pscustomobject]@{
            State      = 'locked'
            Owner      = $j.owner
            Machine    = $j.machine
            AgeMinutes = $age
            Stale      = ($age -gt $script:cfg.LeaseMinutes)
            Mine       = $mine
        }
    }
    catch {
        return [pscustomobject]@{ State = 'unknown' }
    }
}

# Liegt etwas zum Committen bereit? Ueber den Exitcode statt ueber den
# Ausgabetext ("nothing to commit"), damit es auch mit anderssprachigem Git
# funktioniert:  0 = Index deckt sich mit HEAD,  1 = es gibt Vorgemerktes.
function Test-Staged {
    return ((Invoke-Git @('diff', '--cached', '--quiet')).Code -ne 0)
}

# Committet die aktuellen Aenderungen und pusht sie. Rueckgabe wie Invoke-Git,
# damit der Aufrufer an .Code erkennt, ob wirklich alles beim Remote angekommen
# ist. WICHTIG: Scheitert schon der Commit, wird NICHT gepusht und der Fehler
# durchgereicht - sonst wuerde ein "Everything up-to-date" des Push einen
# Erfolg vortaeuschen und z. B. eine Sperre als gesichert gelten, die nie
# beim anderen Spieler ankommt.
function Invoke-GitCommitPush {
    param([string]$msg)
    Invoke-Git @('add', '-A') | Out-Null
    if (Test-Staged) {
        $c = Invoke-Git @('commit', '-m', $msg)
        if ($c.Code -ne 0) {
            Write-Log "FEHLER: Commit fehlgeschlagen - es wird nichts hochgeladen."
            Write-Log ("  git commit: {0}" -f $c.Text)
            if ($c.Text -match 'user\.email|user\.name|identity') {
                Write-Log "  Tipp: Git kennt dich noch nicht. Einmalig ausfuehren:"
                Write-Log '        git config --global user.name "Dein Name"'
                Write-Log '        git config --global user.email "du@example.com"'
            }
            return [pscustomobject]@{ Code = $c.Code; Text = $c.Text; Stage = 'commit' }
        }
    }
    # Auch ohne neuen Commit pushen: es koennen aeltere Commits liegen
    # geblieben sein, deren Push beim letzten Mal fehlgeschlagen ist.
    $p = Invoke-Git @('push', 'origin', $script:cfg.Branch)
    return [pscustomobject]@{ Code = $p.Code; Text = $p.Text; Stage = 'push' }
}

function Update-StatusUI {
    param($lock)
    switch ($lock.State) {
        'free' {
            $script:lblStatus.Text = "FREI  -  niemand spielt gerade"
            $script:lblStatus.BackColor = [Drawing.Color]::FromArgb(200, 240, 200)
        }
        'locked' {
            if ($lock.Mine) {
                $script:lblStatus.Text = "DU spielst gerade  (Sperre liegt bei dir)"
                $script:lblStatus.BackColor = [Drawing.Color]::FromArgb(200, 220, 255)
            }
            elseif ($lock.Stale) {
                $script:lblStatus.Text = ("ABGELAUFENE Sperre von {0}  (seit {1} Min)  -  kann uebernommen werden" -f $lock.Owner, [math]::Round($lock.AgeMinutes, 1))
                $script:lblStatus.BackColor = [Drawing.Color]::FromArgb(255, 235, 180)
            }
            else {
                $script:lblStatus.Text = ("GESPERRT  -  {0} spielt  (seit {1} Min)" -f $lock.Owner, [math]::Round($lock.AgeMinutes, 1))
                $script:lblStatus.BackColor = [Drawing.Color]::FromArgb(255, 200, 200)
            }
        }
        default {
            $script:lblStatus.Text = "Status unbekannt (Sperr-Datei unlesbar)"
            $script:lblStatus.BackColor = [Drawing.Color]::FromArgb(230, 230, 230)
        }
    }
}

# --------------------------------------------------------------------------
# Ablauf: Spielen starten
# --------------------------------------------------------------------------
function Start-Play {
    Save-ConfigFromUI

    if (-not (Test-Path $script:cfg.DolphinPath)) {
        Write-Log "FEHLER: Dolphin nicht gefunden unter: $($script:cfg.DolphinPath)"
        return
    }
    if (-not (Test-Repo)) { return }

    Write-Log "Synchronisiere mit dem Remote-Repo..."
    Sync-Remote
    $lock = Get-LockState
    Update-StatusUI $lock

    if ($lock.State -eq 'locked' -and -not $lock.Mine -and -not $lock.Stale) {
        Write-Log ("GESPERRT: {0} spielt gerade (seit {1} Min). Bitte warten." -f $lock.Owner, [math]::Round($lock.AgeMinutes, 1))
        return
    }
    if ($lock.State -eq 'locked' -and $lock.Stale) {
        Write-Log ("Alte Sperre von {0} ist abgelaufen -> ich uebernehme." -f $lock.Owner)
    }

    # Sperre sichern (mit Wettlauf-Schutz: wer zuerst pusht, gewinnt)
    $acquired = $false
    for ($i = 1; $i -le 3 -and -not $acquired; $i++) {
        Set-LockFile
        $p = Invoke-GitCommitPush ("lock: {0}" -f $script:cfg.PlayerName)
        if ($p.Code -eq 0) { $acquired = $true; break }

        # Scheitert schon der Commit, hilft kein zweiter Versuch - das ist kein
        # Wettlauf, sondern ein Problem am lokalen Git (siehe Meldung oben).
        if ($p.Stage -eq 'commit') {
            Write-Log "Abbruch: die Sperre konnte lokal nicht committet werden."
            return
        }

        Write-Log "Push abgelehnt (Versuch $i) - jemand war evtl. schneller. Pruefe erneut..."
        Sync-Remote
        $lock = Get-LockState
        if ($lock.State -eq 'locked' -and -not $lock.Mine -and -not $lock.Stale) {
            Update-StatusUI $lock
            Write-Log ("GESPERRT: {0} war schneller. Abbruch." -f $lock.Owner)
            return
        }
    }
    if (-not $acquired) {
        Write-Log "Konnte die Sperre nicht sichern (Push-Problem?). Abbruch. Siehe Log."
        return
    }

    Write-Log "Sperre gesichert. Starte Dolphin..."
    $script:holdingLock = $true

    Restore-Saves | Out-Null

    try {
        $gp = $script:cfg.GamePath
        if ($gp -and (Test-Path $gp)) {
            $ext = [IO.Path]::GetExtension($gp).ToLowerInvariant()

            if ($ext -eq '.lnk') {
                # Verknuepfung aufloesen und Dolphin direkt mit denselben Argumenten
                # starten (-> zuverlaessiger Prozess-Handle fuers Sitzungsende,
                # und dein Mod-Preset laeuft genau wie beim Doppelklick auf die .lnk).
                $tgt = $null; $ar = ""
                try {
                    $wsh = New-Object -ComObject WScript.Shell
                    $sc = $wsh.CreateShortcut($gp)
                    $tgt = $sc.TargetPath
                    $ar = $sc.Arguments
                }
                catch { $tgt = $null }

                if ([string]::IsNullOrWhiteSpace($tgt) -or -not (Test-Path $tgt)) {
                    Write-Log "Verknuepfung nicht aufloesbar - starte sie direkt."
                    $script:proc = Start-Process -FilePath $gp -PassThru
                }
                else {
                    Write-Log ("Starte via Verknuepfung: `"{0}`" {1}" -f $tgt, $ar)
                    if ([string]::IsNullOrWhiteSpace($ar)) {
                        $script:proc = Start-Process -FilePath $tgt -PassThru
                    }
                    else {
                        $script:proc = Start-Process -FilePath $tgt -ArgumentList $ar -PassThru
                    }
                }
            }
            elseif ($ext -eq '.exe' -or $ext -eq '.bat' -or $ext -eq '.cmd') {
                # Ein Programm/Skript, das sich selbst um Dolphin + Mods kuemmert.
                $script:proc = Start-Process -FilePath $gp -PassThru
            }
            else {
                # Normale Spiel-/Preset-Datei an Dolphin uebergeben.
                # Pfad in Anfuehrungszeichen -> Leerzeichen im Pfad sind kein Problem.
                $argStr = '-b -e "{0}"' -f $gp
                Write-Log ("Starte Dolphin mit: {0}" -f $argStr)
                $script:proc = Start-Process -FilePath $script:cfg.DolphinPath -ArgumentList $argStr -PassThru
            }
        }
        else {
            $script:proc = Start-Process -FilePath $script:cfg.DolphinPath -PassThru
        }
    }
    catch {
        Write-Log "Start fehlgeschlagen: $_"
        Complete-Session
        return
    }

    $script:lastHeartbeat = Get-Date
    $script:lastAccounted = Get-Date
    $script:btnPlay.Enabled = $false
    $script:btnStop.Enabled = $true
    Update-StatusUI (Get-LockState)
    $script:timer.Start()
    Write-Log "Viel Spass. Beim Schliessen von Dolphin - oder mit 'Spielen beenden' - wird automatisch gespeichert & freigegeben."
}

# --------------------------------------------------------------------------
# Herzschlag + Ende-Erkennung (laeuft im Timer-Tick)
# --------------------------------------------------------------------------
function Invoke-Tick {
    if ($null -ne $script:proc -and $script:proc.HasExited) {
        Complete-Session
        return
    }
    if (((Get-Date) - $script:lastHeartbeat).TotalSeconds -ge $script:cfg.HeartbeatSeconds) {
        Set-LockFile
        Backup-Saves | Out-Null
        Add-Playtime
        $p = Invoke-GitCommitPush ("heartbeat: {0}" -f $script:cfg.PlayerName)
        if ($p.Code -ne 0) {
            Write-Log ("Heartbeat-Warnung ({0}): {1}" -f $p.Stage, $p.Text)
        }
        else {
            Write-Log "Herzschlag gesendet (Spielstand + Sperre aktualisiert)."
        }
        $script:lastHeartbeat = Get-Date
    }
}

function Complete-Session {
    if ($script:timer) { $script:timer.Stop() }
    if (-not $script:holdingLock) {
        $script:btnPlay.Enabled = $true
        $script:btnStop.Enabled = $false
        return
    }

    Write-Log "Dolphin beendet. Speichere Fortschritt und gebe Sperre frei..."
    Backup-Saves | Out-Null
    Move-Pics
    Add-Playtime -EndSession
    $lf = Get-LockPath
    Remove-Item $lf -Force -ErrorAction SilentlyContinue
    $p = Invoke-GitCommitPush ("Session beendet + Spielstand ({0})" -f $script:cfg.PlayerName)

    if ($p.Code -ne 0) {
        Write-Log "WARNUNG: Hochladen beim Beenden fehlgeschlagen."
        Write-Log "Deine Aenderungen sind LOKAL committet (nicht verloren), aber noch nicht gepusht."
        Write-Log "Moegliche Ursache: jemand hat per 'Sperre erzwingen' uebernommen. Details:"
        Write-Log $p.Text
    }
    else {
        Write-Log "Fertig. Spielstand hochgeladen, Sperre freigegeben."
    }

    $script:holdingLock = $false
    $script:proc = $null
    $script:btnPlay.Enabled = $true
    $script:btnStop.Enabled = $false
    Update-StatusUI (Get-LockState)
}

# Dolphin aus dem Programm heraus beenden (Knopf "Spielen beenden").
# Erst hoeflich bitten (CloseMainWindow = wie auf das X klicken), damit Dolphin
# sauber herunterfaehrt. Nur wenn das nichts bringt, auf Nachfrage hart abbrechen.
# Danach laeuft alles Weitere ueber Complete-Session - also genau derselbe Weg
# wie beim Schliessen von Hand: sichern, hochladen, Sperre freigeben.
function Stop-Play {
    if (-not $script:holdingLock -or $null -eq $script:proc) {
        Write-Log "Es laeuft gerade keine Sitzung."
        return
    }
    if ($script:proc.HasExited) { Complete-Session; return }

    $r = [Windows.Forms.MessageBox]::Show(
        ("Dolphin jetzt beenden?`n`n" +
        "WICHTIG: Speichere vorher IM SPIEL. Alles seit dem letzten Speichern " +
        "im Spiel ist sonst weg - das Skript kann nur sichern, was Dolphin " +
        "bereits auf die Festplatte geschrieben hat.`n`n" +
        "Danach wird der Spielstand hochgeladen und die Sperre freigegeben."),
        "Spielen beenden", 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }

    # Timer anhalten, damit die Ende-Erkennung nicht parallel Complete-Session
    # aufruft, waehrend wir hier noch warten.
    $script:timer.Stop()
    $script:btnStop.Enabled = $false
    Write-Log "Beende Dolphin..."

    $asked = $false
    try {
        $script:proc.Refresh()
        if ($script:proc.MainWindowHandle -ne [IntPtr]::Zero) {
            $asked = $script:proc.CloseMainWindow()
        }
    }
    catch { $asked = $false }

    if (-not $asked) {
        Write-Log "Dolphin hat kein normales Fenster zum Schliessen (z. B. bei einem Starter-Skript)."
    }
    else {
        # Bis zu 20 s Zeit lassen. DoEvents haelt unser Fenster bedienbar und
        # laesst Dolphin seine eigene Rueckfrage anzeigen.
        $ende = (Get-Date).AddSeconds(20)
        while (-not $script:proc.HasExited -and (Get-Date) -lt $ende) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
        }
    }

    if (-not $script:proc.HasExited) {
        $f = [Windows.Forms.MessageBox]::Show(
            ("Dolphin laesst sich nicht normal beenden.`n`n" +
            "Hart abbrechen? Was Dolphin noch nicht auf die Festplatte " +
            "geschrieben hat, geht dabei verloren."),
            "Beenden erzwingen", 'YesNo', 'Warning')
        if ($f -eq 'Yes') {
            try {
                $script:proc.Kill()
                [void]$script:proc.WaitForExit(5000)
            }
            catch { Write-Log "Konnte Dolphin nicht beenden: $($_.Exception.Message)" }
        }
    }

    if (-not $script:proc.HasExited) {
        # Nichts kaputtgemacht: Sitzung laeuft weiter wie vorher.
        Write-Log "Dolphin laeuft weiter - Sitzung bleibt offen."
        $script:btnStop.Enabled = $true
        $script:timer.Start()
        return
    }

    Complete-Session
}

# --------------------------------------------------------------------------
# Notausgang + Statusknopf
# --------------------------------------------------------------------------
function Unlock-Session {
    Save-ConfigFromUI
    if ($script:holdingLock) {
        Write-Log "Du haeltst die Sperre selbst - nimm 'Spielen beenden' (oder schliesse Dolphin), dann wird sie normal freigegeben."
        return
    }
    if (-not (Test-Repo)) { return }
    $r = [Windows.Forms.MessageBox]::Show(
        "Sperre wirklich zwangsweise freigeben?`n`nNur benutzen, wenn sicher ist, dass niemand spielt (z. B. nach einem Absturz).",
        "Sperre erzwingen", 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }

    Sync-Remote
    $lf = Get-LockPath
    if (Test-Path $lf) { Remove-Item $lf -Force }
    $p = Invoke-GitCommitPush ("force-unlock durch {0}" -f $script:cfg.PlayerName)
    if ($p.Code -eq 0) { Write-Log "Sperre wurde zwangsweise freigegeben." }
    else { Write-Log "Fehler beim Freigeben: $($p.Text)" }
    Update-StatusUI (Get-LockState)
}

function Update-Status {
    # Beim Klick auf "Status pruefen" werden die Felder mitgespeichert.
    # Beim automatischen Start-Check nicht: sonst wuerde das blosse Oeffnen
    # des Fensters die Einstellungen ueberschreiben.
    param([switch]$SkipSave)
    if (-not $SkipSave) { Save-ConfigFromUI }
    if (-not (Test-Repo)) { return }
    Write-Log "Pruefe aktuellen Status..."
    Sync-Remote
    $lock = Get-LockState
    Update-StatusUI $lock
    if ($lock.State -eq 'free') { Write-Log "Frei - du kannst spielen." }
    elseif ($lock.Mine) { Write-Log "Die Sperre liegt bei dir." }
    elseif ($lock.Stale) { Write-Log ("Abgelaufene Sperre von {0} - kann uebernommen werden." -f $lock.Owner) }
    else { Write-Log ("{0} spielt gerade." -f $lock.Owner) }
}

# --------------------------------------------------------------------------
# Screenshots/Fotos ins Repo verschieben (mit kollisionssicheren Namen)
# --------------------------------------------------------------------------
function Move-Pics {
    $src = $script:cfg.PicsFolder
    if ([string]::IsNullOrWhiteSpace($src)) { return }   # Feld leer -> Funktion aus
    if (-not (Test-Path $src)) { Write-Log "Bilder-Ordner nicht gefunden - uebersprungen."; return }
    $dst = Join-Path $script:cfg.RepoPath 'pics'
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

    $exts = @('.jpg', '.jpeg', '.png')
    $files = Get-ChildItem -Path $src -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $exts -contains $_.Extension.ToLowerInvariant() }
    if (-not $files) { Write-Log "Keine neuen Bilder gefunden."; return }

    $safe = ($script:cfg.PlayerName -replace '[^\w\-]', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Unbekannt" }

    $moved = 0
    foreach ($f in $files) {
        # Eindeutiger Name: Spieler + Aufnahme-Zeit + Originalname (alles bereinigt)
        $stamp = $f.LastWriteTime.ToString("yyyyMMdd-HHmmss")
        $stem = ("{0}_{1}_{2}" -f $safe, $stamp, $f.BaseName) -replace '[^\w\-]', '_'
        $ext = $f.Extension.ToLowerInvariant()
        $target = Join-Path $dst ($stem + $ext)
        $i = 1
        while (Test-Path $target) {
            $target = Join-Path $dst ("{0}_{1}{2}" -f $stem, $i, $ext)
            $i++
        }
        try { Move-Item -LiteralPath $f.FullName -Destination $target -Force; $moved++ }
        catch { Write-Log "Bild konnte nicht verschoben werden: $($f.Name)" }
    }
    Write-Log ("{0} Bild(er) ins Repo verschoben und lokal entfernt." -f $moved)
}

# --------------------------------------------------------------------------
# Spielstaende zwischen Dolphin-Ordner und Repo kopieren
# --------------------------------------------------------------------------
function Get-RepoSaveDir { Join-Path $script:cfg.RepoPath 'save' }

# true = ok/uebersprungen, false = echter Fehler
function Restore-Saves {
    $src = Get-RepoSaveDir
    $dst = $script:cfg.SaveFolder
    if ([string]::IsNullOrWhiteSpace($dst)) { return $true }   # Feld leer -> Funktion aus
    if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Write-Log "Noch kein Spielstand im Repo - vorhandener Dolphin-Save bleibt unangetastet."
        return $true
    }
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    Write-Log "Schreibe Spielstand aus dem Repo in den Dolphin-Ordner..."
    # /E = inkl. Unterordner, ueberschreibt; bewusst OHNE Loeschen, damit im
    # Dolphin-Ordner nichts Fremdes geloescht wird.
    $null = robocopy $src $dst /E /NJH /NJS /NDL /NC /NS /NP /R:1 /W:1 2>&1
    if ($LASTEXITCODE -ge 8) { Write-Log "FEHLER beim Zurueckschreiben (robocopy-Code $LASTEXITCODE)."; return $false }
    return $true
}

function Backup-Saves {
    $src = $script:cfg.SaveFolder
    $dst = Get-RepoSaveDir
    if ([string]::IsNullOrWhiteSpace($src)) { return $true }   # Feld leer -> Funktion aus
    if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Write-Log "Dolphin-Save-Ordner ist leer/fehlt - nichts zu sichern."
        return $true
    }
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    # /MIR = spiegelt exakt ins repo-eigene 'save/' (dort ist Spiegeln sicher).
    $null = robocopy $src $dst /MIR /NJH /NJS /NDL /NC /NS /NP /R:1 /W:1 2>&1
    if ($LASTEXITCODE -ge 8) { Write-Log "FEHLER beim Sichern (robocopy-Code $LASTEXITCODE)."; return $false }
    return $true
}

# --------------------------------------------------------------------------
# Spielzeit-Erfassung + README-Statistik
# --------------------------------------------------------------------------
function Get-PlaytimePath { Join-Path $script:cfg.RepoPath 'playtime.json' }

function Get-Playtime {
    $p = Get-PlaytimePath
    $h = @{}
    if (Test-Path $p) {
        try {
            $j = Get-Content $p -Raw | ConvertFrom-Json
            foreach ($prop in $j.PSObject.Properties) {
                $v = $prop.Value
                $h[$prop.Name] = @{
                    TotalSeconds  = [double]$v.TotalSeconds
                    Sessions      = [int]$v.Sessions
                    LastPlayedUtc = [string]$v.LastPlayedUtc
                }
            }
        }
        catch {
            Write-Log "WARNUNG: playtime.json ist beschaedigt - die Spielzeit-Statistik kann unvollstaendig sein."
            Write-Log ("  Grund: {0}" -f $_.Exception.Message)
        }
    }
    return $h
}

function Save-Playtime {
    param($h)
    ($h | ConvertTo-Json -Depth 5) | Set-Content -Path (Get-PlaytimePath) -Encoding UTF8
}

function Format-Duration {
    param([double]$sec)
    if ($sec -lt 0) { $sec = 0 }
    $ts = [TimeSpan]::FromSeconds([math]::Round($sec))
    if ($ts.TotalHours -ge 1) { return ("{0}h {1}m" -f [int][math]::Floor($ts.TotalHours), $ts.Minutes) }
    elseif ($ts.TotalMinutes -ge 1) { return ("{0}m {1}s" -f $ts.Minutes, $ts.Seconds) }
    else { return ("{0}s" -f $ts.Seconds) }
}

function Write-Readme {
    param($h)
    if ($null -eq $h) { $h = @{} }
    $lines = @()
    $lines += "# Gemeinsamer Animal-Crossing-Spielstand"
    $lines += ""
    $lines += "Verwaltet mit ``AC-SaveSync.ps1``."
    $lines += ""
    $lines += "## Spielzeiten"
    $lines += ""
    $lines += "| Spieler | Gesamt | Sitzungen | Zuletzt gespielt |"
    $lines += "|---|---|---|---|"
    $total = 0.0
    if ($h.Keys.Count -eq 0) {
        $lines += "| _noch keine Daten_ | - | - | - |"
    }
    else {
        foreach ($name in ($h.Keys | Sort-Object)) {
            $e = $h[$name]
            $total += [double]$e.TotalSeconds
            $last = "-"
            if ($e.LastPlayedUtc) {
                try { $last = [datetimeoffset]::Parse($e.LastPlayedUtc).LocalDateTime.ToString("yyyy-MM-dd HH:mm") }
                catch { $last = "-" }   # unlesbarer Zeitstempel -> Strich in der Tabelle
            }
            $lines += ("| {0} | {1} | {2} | {3} |" -f $name, (Format-Duration $e.TotalSeconds), $e.Sessions, $last)
        }
    }
    $lines += ""
    $lines += ("**Gesamt zusammen:** {0}" -f (Format-Duration $total))

    # Fotos-Galerie (falls Bilder im Repo liegen), neueste zuerst
    $picsDir = Join-Path $script:cfg.RepoPath 'pics'
    if (Test-Path $picsDir) {
        $imgExts = @('.jpg', '.jpeg', '.png')
        $imgs = Get-ChildItem -Path $picsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $imgExts -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name -Descending
        if ($imgs -and $imgs.Count -gt 0) {
            $lines += ""
            $lines += ("## Fotos ({0})" -f $imgs.Count)
            $lines += ""
            foreach ($img in $imgs) {
                $lines += ("![{0}](pics/{1})" -f $img.BaseName, $img.Name)
            }
        }
    }

    $lines += ""
    $lines += ("_Zuletzt aktualisiert: {0}_" -f (Get-Date).ToString("yyyy-MM-dd HH:mm"))
    ($lines -join "`r`n") | Set-Content -Path (Join-Path $script:cfg.RepoPath 'README.md') -Encoding UTF8
}

# Rechnet die seit dem letzten Zeitpunkt vergangenen Sekunden dem aktuellen
# Spieler an und aktualisiert playtime.json + README. Mit -EndSession wird
# zusaetzlich der Sitzungszaehler erhoeht.
function Add-Playtime {
    param([switch]$EndSession)
    $now = Get-Date
    $deltaSec = ($now - $script:lastAccounted).TotalSeconds
    if ($deltaSec -lt 0) { $deltaSec = 0 }
    $script:lastAccounted = $now

    $name = $script:cfg.PlayerName
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unbekannt" }
    $h = Get-Playtime
    if (-not $h.ContainsKey($name)) {
        $h[$name] = @{ TotalSeconds = 0.0; Sessions = 0; LastPlayedUtc = "" }
    }
    $h[$name].TotalSeconds = [double]$h[$name].TotalSeconds + $deltaSec
    $h[$name].LastPlayedUtc = [datetime]::UtcNow.ToString("o")
    if ($EndSession) { $h[$name].Sessions = [int]$h[$name].Sessions + 1 }
    Save-Playtime $h
    Write-Readme $h
}

# --------------------------------------------------------------------------
# Repo-Einrichtung (gemeinsames Git-Repo erstellen / verbinden / klonen)
# --------------------------------------------------------------------------
function Initialize-Repo {
    Save-ConfigFromUI
    if (-not (Test-Path $script:cfg.RepoPath)) {
        New-Item -ItemType Directory -Path $script:cfg.RepoPath -Force | Out-Null
        Write-Log "Ordner erstellt: $($script:cfg.RepoPath)"
    }
    if (Test-Path (Join-Path $script:cfg.RepoPath '.git')) {
        Write-Log "Ordner ist bereits ein Git-Repo."
    }
    else {
        $r = Invoke-Git @('init')
        Write-Log "git init: $($r.Text)"
    }
    $ga = Join-Path $script:cfg.RepoPath '.gitattributes'
    if (-not (Test-Path $ga)) {
        @"
# Spielstaende sind Binaerdateien: keine Zeilenende-Umwandlung, kein Merge
save/** -text -diff
pics/** -text -diff
*.bin -text -diff
*.raw -text -diff
*.dat -text -diff
*.sav -text -diff
"@ | Set-Content -Path $ga -Encoding UTF8
    }
    Write-Readme (Get-Playtime)
    Invoke-Git @('add', '-A') | Out-Null
    if (-not (Test-Staged)) {
        Write-Log "Nichts Neues zu committen (schon eingerichtet)."
    }
    else {
        $c = Invoke-Git @('commit', '-m', 'Repo-Setup durch AC-SaveSync')
        if ($c.Code -eq 0) {
            Write-Log "Erster Commit erstellt."
        }
        else {
            Write-Log "FEHLER: Commit fehlgeschlagen - das Repo ist noch nicht startklar."
            Write-Log ("  git commit: {0}" -f $c.Text)
            if ($c.Text -match 'user\.email|user\.name|identity') {
                Write-Log "  Tipp: Git kennt dich noch nicht. Einmalig ausfuehren:"
                Write-Log '        git config --global user.name "Dein Name"'
                Write-Log '        git config --global user.email "du@example.com"'
            }
        }
    }
    Invoke-Git @('branch', '-M', $script:cfg.Branch) | Out-Null
    Write-Log "Lokales Repo bereit (Branch: $($script:cfg.Branch))."
}

function Connect-Remote {
    param([string]$url)
    Save-ConfigFromUI
    if ([string]::IsNullOrWhiteSpace($url)) { Write-Log "Bitte im Fenster oben die Remote-URL eintragen."; return }
    if (-not (Test-Path (Join-Path $script:cfg.RepoPath '.git'))) {
        Write-Log "Erst Schritt 1 (Lokales Repo anlegen) ausfuehren."; return
    }
    $r = Invoke-Git @('remote')
    if ($r.Text -match '(^|\r?\n)origin(\r?\n|$)') {
        Invoke-Git @('remote', 'set-url', 'origin', $url) | Out-Null
        Write-Log "origin aktualisiert."
    }
    else {
        Invoke-Git @('remote', 'add', 'origin', $url) | Out-Null
        Write-Log "origin hinzugefuegt."
    }
    $p = Invoke-Git @('push', '-u', 'origin', $script:cfg.Branch)
    if ($p.Code -eq 0) { Write-Log "Hochgeladen. Das Repo ist jetzt startklar - der andere kann es nun klonen." }
    else { Write-Log "Push fehlgeschlagen: $($p.Text)" }
}

function Copy-Repo {
    param([string]$url)
    Save-ConfigFromUI
    if ([string]::IsNullOrWhiteSpace($url)) { Write-Log "Bitte im Fenster oben die Remote-URL eintragen."; return }
    $target = $script:cfg.RepoPath
    if (Test-Path (Join-Path $target '.git')) { Write-Log "Zielordner ist bereits ein Repo - Klonen nicht noetig."; return }
    if ((Test-Path $target) -and (Get-ChildItem -Force $target | Select-Object -First 1)) {
        Write-Log "Zielordner ist nicht leer. Bitte einen leeren/neuen Ordner als RepoPath waehlen."; return
    }
    Write-Log "Klone Repo..."
    $out = & git clone $url $target 2>&1
    Write-Log ("git clone: " + (($out | Out-String).Trim()))
    if (Test-Path (Join-Path $target '.git')) { Write-Log "Klonen erfolgreich. Du kannst jetzt spielen." }
    else { Write-Log "Klonen hat nicht geklappt - URL und Zugangsdaten pruefen." }
}

function New-RemoteWithGh {
    param([string]$name)
    Save-ConfigFromUI
    if ([string]::IsNullOrWhiteSpace($name)) { Write-Log "Bitte einen Repo-Namen eingeben."; return }
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Log "GitHub CLI (gh) nicht gefunden. Erstelle das leere Repo auf github.com und nutze dann 'Verbinden & hochladen'."
        return
    }
    Initialize-Repo
    Write-Log "Erstelle privates GitHub-Repo '$name' und lade hoch..."
    $out = & gh repo create $name --private --source $script:cfg.RepoPath --remote origin --push 2>&1
    Write-Log ("gh: " + (($out | Out-String).Trim()))
}

function Show-SetupDialog {
    Save-ConfigFromUI
    # Wichtig: Die Knopf-Handler unten benutzen bewusst KEIN .GetNewClosure().
    # Ein solcher "Closure" haengt den Klick-Code in ein eigenes kleines Modul,
    # das je nach PowerShell-Version die Funktionen aus diesem Skript nicht mehr
    # findet ("Copy-Repo wurde nicht als Name eines Cmdlets ... erkannt").
    # Stattdessen merken wir uns die Eingabefelder in $script:-Variablen -
    # genau so, wie es das Hauptfenster auch macht.
    $dlg = New-Object Windows.Forms.Form
    $script:setupDlg = $dlg
    $dlg.Text = "Gemeinsames Repo einrichten"
    $dlg.Size = New-Object Drawing.Size(560, 430)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false

    $info = New-Object Windows.Forms.Label
    $info.Text = "Einer legt das Repo an (Schritte 1 + 2), der andere klont es nur (Schritt 3)." + [Environment]::NewLine + [Environment]::NewLine + "Das LEERE Remote-Repo erstellst du vorher einmalig auf github.com (o. ae.) - oder unten per GitHub CLI. Trage oben im Hauptfenster Repo-Ordner, Name und Branch ein."
    $info.Location = New-Object Drawing.Point(15, 10)
    $info.Size = New-Object Drawing.Size(525, 70)
    $dlg.Controls.Add($info)

    $lu = New-Object Windows.Forms.Label
    $lu.Text = "Remote-URL:"; $lu.Location = New-Object Drawing.Point(15, 92); $lu.Size = New-Object Drawing.Size(90, 22)
    $lu.TextAlign = 'MiddleLeft'; $dlg.Controls.Add($lu)
    $tu = New-Object Windows.Forms.TextBox
    $tu.Location = New-Object Drawing.Point(110, 92); $tu.Size = New-Object Drawing.Size(430, 22)
    $dlg.Controls.Add($tu)
    $script:setupUrlBox = $tu
    Set-Tip ("Adresse des gemeinsamen Repos, z. B.`n" +
        "https://github.com/DEINNAME/ac-save.git`n" +
        "Wird fuer Schritt 2 und Schritt 3 gebraucht.") $lu $tu

    $b1 = New-Object Windows.Forms.Button
    $b1.Text = "1) Lokales Repo in diesem Ordner anlegen"
    $b1.Location = New-Object Drawing.Point(15, 128); $b1.Size = New-Object Drawing.Size(525, 32)
    $b1.Add_Click({ Initialize-Repo })
    $dlg.Controls.Add($b1)
    Set-Tip ("Fuer den ERSTEN Spieler: macht aus dem oben eingetragenen`n" +
        "Repo-Ordner ein Git-Repo (legt .gitattributes, die README und`n" +
        "den ersten Commit an). Aendert nichts, wenn es schon eins ist.") $b1

    $b2 = New-Object Windows.Forms.Button
    $b2.Text = "2) Mit Remote-URL verbinden und hochladen"
    $b2.Location = New-Object Drawing.Point(15, 166); $b2.Size = New-Object Drawing.Size(525, 32)
    $b2.Add_Click({ Connect-Remote $script:setupUrlBox.Text })
    $dlg.Controls.Add($b2)
    Set-Tip ("Verbindet das lokale Repo mit der Remote-URL oben ('origin')`n" +
        "und laedt alles hoch. Das Repo im Internet muss dafuer schon`n" +
        "existieren - am besten leer angelegt.") $b2

    $b3 = New-Object Windows.Forms.Button
    $b3.Text = "3) Vorhandenes Repo von URL klonen (fuer den 2. Spieler)"
    $b3.Location = New-Object Drawing.Point(15, 204); $b3.Size = New-Object Drawing.Size(525, 32)
    $b3.Add_Click({ Copy-Repo $script:setupUrlBox.Text })
    $dlg.Controls.Add($b3)
    Set-Tip ("Fuer den ZWEITEN Spieler: laedt das fertige Repo von der URL oben`n" +
        "in den Repo-Ordner herunter. Der Zielordner muss leer sein`n" +
        "(oder darf noch nicht existieren).") $b3

    $sep = New-Object Windows.Forms.Label
    $sep.Text = "Optional (falls GitHub CLI 'gh' installiert ist) - erstellt das Remote automatisch:"
    $sep.Location = New-Object Drawing.Point(15, 248); $sep.Size = New-Object Drawing.Size(525, 20)
    $dlg.Controls.Add($sep)

    $ln = New-Object Windows.Forms.Label
    $ln.Text = "Repo-Name:"; $ln.Location = New-Object Drawing.Point(15, 274); $ln.Size = New-Object Drawing.Size(90, 22)
    $ln.TextAlign = 'MiddleLeft'; $dlg.Controls.Add($ln)
    $tn = New-Object Windows.Forms.TextBox
    $tn.Text = "ac-save"; $tn.Location = New-Object Drawing.Point(110, 274); $tn.Size = New-Object Drawing.Size(190, 22)
    $dlg.Controls.Add($tn)
    $script:setupNameBox = $tn
    Set-Tip ("Name des neuen GitHub-Repos, das per GitHub CLI angelegt wird,`n" +
        "z. B. ac-save. Nur der Name, nicht die ganze Adresse.") $ln $tn

    $b4 = New-Object Windows.Forms.Button
    $b4.Text = "GitHub-Repo per gh erstellen und pushen"
    $b4.Location = New-Object Drawing.Point(310, 272); $b4.Size = New-Object Drawing.Size(230, 26)
    $b4.Add_Click({ New-RemoteWithGh $script:setupNameBox.Text })
    $dlg.Controls.Add($b4)
    Set-Tip ("Erledigt Schritt 1 und 2 auf einen Schlag: legt mit der GitHub CLI`n" +
        "('gh') ein PRIVATES Repo an und laedt den Repo-Ordner hoch.`n" +
        "Klappt nur, wenn 'gh' installiert und angemeldet ist.") $b4

    $bc = New-Object Windows.Forms.Button
    $bc.Text = "Schliessen"; $bc.Location = New-Object Drawing.Point(435, 330); $bc.Size = New-Object Drawing.Size(105, 30)
    $bc.Add_Click({ $script:setupDlg.Close() })
    $dlg.Controls.Add($bc)
    Set-Tip "Schliesst dieses Fenster. Die Einstellungen bleiben erhalten." $bc

    [void]$dlg.ShowDialog()
}

# ==========================================================================
# Grafische Oberflaeche
# ==========================================================================
Import-Config

$form = New-Object Windows.Forms.Form
$form.Text = "Animal Crossing - Save-Sync & Sperre"
# 42 px hoeher als frueher: die Knoepfe stehen jetzt in zwei Reihen,
# das Protokollfeld darunter soll dadurch nicht kleiner werden.
$form.Size = New-Object Drawing.Size(660, 822)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object Drawing.Size(660, 822)

function New-Label {
    param($text, $x, $y, $w = 120)
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y)
    $l.Size = New-Object Drawing.Size($w, 22); $l.TextAlign = 'MiddleLeft'
    $form.Controls.Add($l); return $l
}
function New-Text {
    param($val, $x, $y, $w)
    $t = New-Object Windows.Forms.TextBox
    $t.Text = "$val"; $t.Location = New-Object Drawing.Point($x, $y)
    $t.Size = New-Object Drawing.Size($w, 22)
    $form.Controls.Add($t); return $t
}
function New-Button {
    param($text, $x, $y, $w, $h = 28)
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object Drawing.Point($x, $y)
    $b.Size = New-Object Drawing.Size($w, $h)
    $form.Controls.Add($b); return $b
}

# --- Deko-Banner oben ---
$banner = New-Object Windows.Forms.PictureBox
$banner.Location = New-Object Drawing.Point(15, 8)
$banner.Size = New-Object Drawing.Size(593, 64)
$banner.SizeMode = 'Zoom'
$banner.Anchor = 'Top,Left,Right'
try {
    $bannerBytes = [Convert]::FromBase64String($script:BannerBase64)
    $bannerMs = New-Object IO.MemoryStream(, $bannerBytes)
    $banner.Image = [Drawing.Image]::FromStream($bannerMs)
}
catch {
    # Rein dekorativ - ohne Banner laeuft alles normal weiter.
    Write-Log ("Hinweis: Banner konnte nicht geladen werden ({0})." -f $_.Exception.Message)
}
$form.Controls.Add($banner)

$y = 80
$lblDolphin = New-Label "Dolphin.exe:" 15 $y
$script:txtDolphin = New-Text $script:cfg.DolphinPath 140 $y 400
$btnBrowseDolphin = New-Button "..." 548 $y 60 24
Set-Tip ("Der Emulator, mit dem gespielt wird - die Datei Dolphin.exe.`n" +
    "Beispiel: C:\Program Files\Dolphin-x64\Dolphin.exe") $lblDolphin $script:txtDolphin
Set-Tip "Dolphin.exe per Dateidialog auswaehlen." $btnBrowseDolphin

$y += 32
$lblRepo = New-Label "Repo-Ordner:" 15 $y
$script:txtRepo = New-Text $script:cfg.RepoPath 140 $y 400
$btnBrowseRepo = New-Button "..." 548 $y 60 24
Set-Tip ("Dein oertlicher Ordner des gemeinsamen Git-Repos (enthaelt einen Unterordner .git).`n" +
    "Darueber tauscht ihr Spielstand, Sperre und Bilder aus.`n" +
    "Beide Spieler brauchen dasselbe Repo - jeder in seinem eigenen Ordner.`n" +
    "Noch keins da? Unten auf 'Repo einrichten...' klicken.") $lblRepo $script:txtRepo
Set-Tip "Repo-Ordner auswaehlen: in den Ordner wechseln, dann unten auf 'Oeffnen'." $btnBrowseRepo

$y += 32
$lblGame = New-Label "Spiel (optional):" 15 $y
$script:txtGame = New-Text $script:cfg.GamePath 140 $y 400
$btnBrowseGame = New-Button "..." 548 $y 60 24
Set-Tip ("Was beim Klick auf 'Spielen starten' geoeffnet werden soll:`n" +
    "eine Spieldatei (.iso/.rvz/.wbfs/.gcm), eine Verknuepfung (.lnk)`n" +
    "oder ein eigenes Startprogramm (.exe/.bat) fuer Dolphin mit Mods.`n" +
    "Leer lassen = Dolphin startet einfach ohne Spiel.") $lblGame $script:txtGame
Set-Tip "Spieldatei, Verknuepfung oder Startprogramm auswaehlen." $btnBrowseGame

$y += 32
$lblSave = New-Label "Save-Ordner:" 15 $y
$script:txtSave = New-Text $script:cfg.SaveFolder 140 $y 400
$btnBrowseSave = New-Button "..." 548 $y 60 24
Set-Tip ("Der Ordner, in dem Dolphin den Spielstand dieses Spiels ablegt.`n" +
    "Vor dem Spielen wird er aus dem Repo befuellt, waehrend und nach dem`n" +
    "Spielen wieder ins Repo gesichert.`n" +
    "Leer lassen = Spielstaende werden NICHT synchronisiert.") $lblSave $script:txtSave
Set-Tip "Save-Ordner auswaehlen: in den Ordner wechseln, dann unten auf 'Oeffnen'." $btnBrowseSave

$y += 32
$lblPics = New-Label "Bilder-Ordner:" 15 $y
$script:txtPics = New-Text $script:cfg.PicsFolder 140 $y 400
$btnBrowsePics = New-Button "..." 548 $y 60 24
Set-Tip ("Ordner mit deinen Screenshots/Fotos, z. B. ...\Load\WiiSDSync.`n" +
    "Nach dem Spielen werden die Bilder ins Repo VERSCHOBEN (Unterordner 'pics')`n" +
    "und sind danach hier lokal nicht mehr vorhanden.`n" +
    "Leer lassen = Bilder bleiben unangetastet.") $lblPics $script:txtPics
Set-Tip "Bilder-Ordner auswaehlen: in den Ordner wechseln, dann unten auf 'Oeffnen'." $btnBrowsePics

$y += 32
$lblName = New-Label "Dein Name:" 15 $y
$script:txtName = New-Text $script:cfg.PlayerName 140 $y 180
$lblBranch = New-Label "Branch:" 340 $y 60
$script:txtBranch = New-Text $script:cfg.Branch 400 $y 100
Set-Tip ("Dein Spielername. Er steht in der Sperre und in der Spielzeit-Statistik.`n" +
    "WICHTIG: Beide Spieler muessen UNTERSCHIEDLICHE Namen benutzen,`n" +
    "sonst haelt jeder die Sperre des anderen fuer die eigene.") $lblName $script:txtName
Set-Tip ("Der Git-Zweig, auf dem synchronisiert wird - normalerweise 'main'.`n" +
    "Beide Spieler muessen denselben Branch eingetragen haben.") $lblBranch $script:txtBranch

$y += 32
$lblLease = New-Label "Sperre gilt (Min):" 15 $y
$script:txtLease = New-Text $script:cfg.LeaseMinutes 140 $y 60
$lblHeart = New-Label "Herzschlag (Sek):" 220 $y 120
$script:txtHeart = New-Text $script:cfg.HeartbeatSeconds 340 $y 60
$btnSetup = New-Button "Repo einrichten..." 410 ($y - 2) 198 26
Set-Tip ("Wie lange eine Sperre ohne Herzschlag gueltig bleibt (in Minuten).`n" +
    "Danach gilt sie als abgelaufen und darf uebernommen werden - so bleibt`n" +
    "sie nach einem Absturz nicht ewig haengen.`n" +
    "Standard: 5, Minimum 1.") $lblLease $script:txtLease
Set-Tip ("Wie oft waehrend des Spielens gespeichert und hochgeladen wird (in Sekunden).`n" +
    "Kleiner = bei einem Absturz geht weniger verloren, aber mehr Git-Verkehr.`n" +
    "Sollte deutlich kleiner sein als 'Sperre gilt', sonst laeuft die Sperre`n" +
    "zwischendurch ab.`n" +
    "Standard: 60, Minimum 10.") $lblHeart $script:txtHeart
Set-Tip ("Hilfe fuer die einmalige Einrichtung:`n" +
    "lokales Repo anlegen, mit GitHub verbinden und hochladen,`n" +
    "oder ein vorhandenes Repo klonen (fuer den zweiten Spieler).") $btnSetup

# Statusanzeige
$y += 40
$script:lblStatus = New-Object Windows.Forms.Label
$script:lblStatus.Text = "Noch nicht geprueft"
$script:lblStatus.Location = New-Object Drawing.Point(15, $y)
$script:lblStatus.Size = New-Object Drawing.Size(593, 40)
$script:lblStatus.TextAlign = 'MiddleCenter'
$script:lblStatus.BorderStyle = 'FixedSingle'
$script:lblStatus.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$script:lblStatus.BackColor = [Drawing.Color]::FromArgb(230, 230, 230)
$form.Controls.Add($script:lblStatus)
Set-Tip ("Zeigt an, ob gerade jemand spielt (Stand der letzten Pruefung).`n" +
    "Gruen = frei, Blau = die Sperre liegt bei dir,`n" +
    "Gelb = abgelaufene Sperre (darf uebernommen werden),`n" +
    "Rot = jemand anderes spielt gerade.`n" +
    "Mit 'Status pruefen' aktualisieren.") $script:lblStatus

# Knoepfe - erste Reihe: die beiden Sitzungs-Knoepfe, gross und nebeneinander
$y += 52
$script:btnPlay = New-Button "Spielen starten" 15 $y 289 34
$script:btnPlay.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$script:btnStop = New-Button "Spielen beenden" 319 $y 289 34
$script:btnStop.Font = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$script:btnStop.Enabled = $false          # erst waehrend einer Sitzung nutzbar

# zweite Reihe: alles, was man seltener braucht
$y += 42
$btnRefresh = New-Button "Status pruefen" 15 $y 180 34
$btnUnlock = New-Button "Sperre erzwingen freigeben" 205 $y 220 34
$btnSave = New-Button "Speichern" 435 $y 173 34
Set-Tip ("Der normale Weg zum Spielen:`n" +
    "holt den neuesten Spielstand, setzt die Sperre auf deinen Namen`n" +
    "und startet Dolphin. Bricht ab, wenn jemand anderes gerade spielt.`n" +
    "Beim Beenden von Dolphin wird automatisch gesichert, hochgeladen`n" +
    "und die Sperre wieder freigegeben.") $script:btnPlay
Set-Tip ("Beendet Dolphin aus dem Programm heraus und schliesst die Sitzung`n" +
    "genauso ab wie das Schliessen von Hand: sichern, hochladen, Sperre frei.`n" +
    "Vorher unbedingt IM SPIEL speichern!`n" +
    "Nur waehrend einer laufenden Sitzung anklickbar.") $script:btnStop
Set-Tip ("Holt den aktuellen Stand vom Server und zeigt oben an,`n" +
    "ob gerade jemand spielt. Aendert sonst nichts.") $btnRefresh
Set-Tip ("Notausgang: loescht die Sperre, obwohl niemand Dolphin`n" +
    "sauber beendet hat.`n" +
    "Nur benutzen, wenn sicher ist, dass niemand spielt (z. B. nach`n" +
    "einem Absturz) - sonst kann Fortschritt des anderen verloren gehen.`n" +
    "Normalerweise unnoetig: die Sperre laeuft von allein ab.") $btnUnlock
Set-Tip ("Speichert die Einstellungen dauerhaft, damit sie beim naechsten`n" +
    "Start wieder da sind (in %APPDATA%\AC-SaveSync\acsync-config.json).") $btnSave

# Log
$y += 46
$lblLog = New-Label "Protokoll:" 15 $y 100
$y += 24
$script:txtLog = New-Object Windows.Forms.TextBox
$script:txtLog.Location = New-Object Drawing.Point(15, $y)
$script:txtLog.Size = New-Object Drawing.Size(593, 220)
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.Anchor = 'Top,Bottom,Left,Right'
$script:txtLog.Font = New-Object Drawing.Font("Consolas", 9)
$form.Controls.Add($script:txtLog)
Set-Tip ("Protokoll dieser Sitzung: was das Skript gerade tut.`n" +
    "Wenn etwas nicht klappt, steht hier die Meldung von Git im Klartext -`n" +
    "diesen Text am besten mitkopieren, wenn du nachfragst.") $lblLog $script:txtLog

# Beim Breiterziehen des Fensters mitwachsen lassen:
# - die Pfad-Textfelder dehnen sich nach rechts (lange Pfade werden sichtbar),
# - die "..."-Knoepfe bleiben rechts kleben.
foreach ($tb in @($script:txtDolphin, $script:txtRepo, $script:txtGame, $script:txtSave, $script:txtPics)) {
    $tb.Anchor = 'Top,Left,Right'
}
foreach ($bb in @($btnBrowseDolphin, $btnBrowseRepo, $btnBrowseGame, $btnBrowseSave, $btnBrowsePics)) {
    $bb.Anchor = 'Top,Right'
}
$script:lblStatus.Anchor = 'Top,Left,Right'

# Timer fuer Herzschlag / Ende-Erkennung
$script:timer = New-Object Windows.Forms.Timer
$script:timer.Interval = 3000
$script:timer.Add_Tick({ Invoke-Tick })

# Einmaliger Timer fuer die automatische Pruefung beim Start.
# Warum ein Timer und nicht direkt im "Shown"-Ereignis? Git braucht ein paar
# Sekunden, und in dieser Zeit waere das Fenster noch nicht gezeichnet. So
# erscheint erst die fertige Oberflaeche, dann laeuft die Pruefung.
$script:startTimer = New-Object Windows.Forms.Timer
$script:startTimer.Interval = 200
$script:startTimer.Add_Tick({
        $script:startTimer.Stop()

        if ([string]::IsNullOrWhiteSpace($script:cfg.RepoPath) -or
            -not (Test-Path (Join-Path $script:cfg.RepoPath ".git"))) {
            # Erster Start: noch kein Repo. Hier bewusst keine Fehlermeldung,
            # sondern ein Hinweis - der Nutzer hat ja noch nichts falsch gemacht.
            $script:lblStatus.Text = "Noch kein Repo eingerichtet"
            Write-Log "Noch kein Repo eingerichtet - Status wurde nicht geprueft."
            Write-Log "Pfade oben ausfuellen (oder 'Repo einrichten...'), dann 'Speichern'."
            return
        }

        $script:lblStatus.Text = "Wird geprueft..."
        Update-Status -SkipSave
    })

# Ereignisse verdrahten
# Moderner, Explorer-artiger Ordner-Dialog (statt der alten Baum-Ansicht).
# Trick: OpenFileDialog als Ordnerauswahl nutzen -> in den gewuenschten Ordner
# wechseln und unten auf "Oeffnen" klicken; wir nehmen dann dessen Verzeichnis.
function Select-FolderModern {
    param([string]$InitialPath = "", [string]$Title = "Ordner auswaehlen")
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Title = $Title
    $d.ValidateNames = $false
    $d.CheckFileExists = $false
    $d.CheckPathExists = $true
    $d.Multiselect = $false
    $d.FileName = "Diesen Ordner waehlen"
    if ($InitialPath -and (Test-Path $InitialPath)) { $d.InitialDirectory = $InitialPath }
    if ($d.ShowDialog() -eq 'OK') { return [IO.Path]::GetDirectoryName($d.FileName) }
    return $null
}

$btnBrowseDolphin.Add_Click({
        $d = New-Object Windows.Forms.OpenFileDialog
        $d.Filter = "Dolphin (Dolphin.exe)|Dolphin.exe|Alle Dateien|*.*"
        if ($d.ShowDialog() -eq 'OK') { $script:txtDolphin.Text = $d.FileName }
    })
$btnBrowseRepo.Add_Click({
        $p = Select-FolderModern $script:txtRepo.Text "Repo-Ordner waehlen (in den Ordner wechseln, dann 'Oeffnen')"
        if ($p) { $script:txtRepo.Text = $p }
    })
$btnBrowseGame.Add_Click({
        $d = New-Object Windows.Forms.OpenFileDialog
        $d.Filter = "Spiel/Preset/Verknuepfung|*.iso;*.wbfs;*.rvz;*.gcm;*.ciso;*.json;*.lnk;*.exe|Alle Dateien|*.*"
        if ($d.ShowDialog() -eq 'OK') { $script:txtGame.Text = $d.FileName }
    })
$btnBrowseSave.Add_Click({
        $p = Select-FolderModern $script:txtSave.Text "Save-Ordner dieses Spiels waehlen (in den Ordner wechseln, dann 'Oeffnen')"
        if ($p) { $script:txtSave.Text = $p }
    })
$btnBrowsePics.Add_Click({
        $p = Select-FolderModern $script:txtPics.Text "Bilder-Ordner waehlen, z. B. ...\Load\WiiSDSync (in den Ordner wechseln, dann 'Oeffnen')"
        if ($p) { $script:txtPics.Text = $p }
    })
$script:btnPlay.Add_Click({ Start-Play })
$script:btnStop.Add_Click({ Stop-Play })
$btnRefresh.Add_Click({ Update-Status })
$btnUnlock.Add_Click({ Unlock-Session })
$btnSave.Add_Click({
        Save-ConfigFromUI
        if ($script:configSaved) { Write-Log "Einstellungen gespeichert." }
    })
$btnSetup.Add_Click({ Show-SetupDialog })

$form.Add_FormClosing({
        param($s, $e)
        if ($script:holdingLock) {
            $r = [Windows.Forms.MessageBox]::Show(
                ("Es laeuft noch eine Sitzung und du haeltst die Sperre.`n`n" +
                "Sauberer waere 'Spielen beenden' - dann wird hochgeladen und die Sperre freigegeben.`n`n" +
                "Beim Schliessen wird der Spielstand NICHT automatisch hochgeladen. " +
                "Die Sperre laeuft aber spaetestens nach {0} Min automatisch ab.`n`nTrotzdem schliessen?" -f $script:cfg.LeaseMinutes),
                "Achtung", 'YesNo', 'Warning')
            if ($r -ne 'Yes') { $e.Cancel = $true }
        }
    })

$form.Add_Shown({ $script:startTimer.Start() })

Write-Log "Bereit."
[void]$form.ShowDialog()