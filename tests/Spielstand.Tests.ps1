# Spielstand: Einrichtung, Sichern, Zurueckschreiben, halbe Staende.
# Die Tests mit robocopy und gesperrten Dateien laufen nur unter Windows.

function New-SaveOrdner {
    param([string]$Inhalt = 'meine Stadt')
    $s = Join-Path $script:TestWurzel ('save-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path (Join-Path $s 'data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $s 'data/stadt.bin') -Value $Inhalt
    Set-Content -LiteralPath (Join-Path $s 'banner.bin') -Value 'banner'
    return $s
}

# Haelt eine Datei exklusiv offen - robocopy kann sie dann weder lesen noch
# ueberschreiben (wie bei einem Dolphin, das noch im Hintergrund laeuft).
function Lock-Datei {
    param([string]$Pfad)
    return [IO.File]::Open($Pfad, 'Open', 'ReadWrite', 'None')
}

Test "Undo-RepoSaveDir stellt den letzten gespeicherten Stand wieder her" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $save = Join-Path $r.a 'save'
    New-Item -ItemType Directory -Path (Join-Path $save 'data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $save 'data/a.bin') -Value 'gut'
    Set-Content -LiteralPath (Join-Path $save 'b.bin') -Value 'gut2'
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm save | Out-Null
    Set-Content -LiteralPath (Join-Path $save 'data/a.bin') -Value 'halb'
    Remove-Item -LiteralPath (Join-Path $save 'b.bin')
    Set-Content -LiteralPath (Join-Path $save 'c.bin') -Value 'neu'
    Undo-RepoSaveDir
    Soll ((Get-Content -LiteralPath (Join-Path $save 'data/a.bin')) -eq 'gut') "geaenderte Datei zurueck"
    Soll (Test-Path -LiteralPath (Join-Path $save 'b.bin')) "geloeschte Datei zurueck"
    Soll (-not (Test-Path -LiteralPath (Join-Path $save 'c.bin'))) "neue Datei entfernt"
}

Test "Einrichtung durch den Ersten laedt dessen Spielstand hoch" {
    $r = New-TestRepos
    $script:cfg.RepoPath = Join-Path $r.Wurzel 'neu'
    $script:cfg.SaveFolder = New-SaveOrdner 'Annas Stadt'
    function Save-ConfigFromUI { }
    if (-not $script:AufWindows) {
        function Backup-Saves {
            $d = Get-RepoSaveDir
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Copy-Item -Path (Join-Path $script:cfg.SaveFolder '*') -Destination $d -Recurse -Force
            return $true
        }
    }
    Initialize-Repo
    $dateien = Invoke-G $script:cfg.RepoPath ls-files
    Soll ($dateien -match 'save/data/stadt.bin') "Spielstand im ersten Commit (war: $dateien)"
    Soll ((Get-ProtokollText) -match 'gemeinsamer Ausgangsstand') "Meldung im Protokoll"

    # Zweiter Aufruf (z. B. versehentlich im geklonten Ordner): nichts ueberschreiben
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'andere Stadt'
    Initialize-Repo
    Soll ((Get-Content -LiteralPath (Join-Path $script:cfg.RepoPath 'save/data/stadt.bin')) -eq 'Annas Stadt') "vorhandener Stand bleibt"
}

Test "Einrichtung: Sammelordner wird nicht ungefragt hochgeladen" {
    $r = New-TestRepos
    $script:cfg.RepoPath = Join-Path $r.Wurzel 'neu'
    $wii = Join-Path $script:TestWurzel ('sammel-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '/Wii')
    New-Item -ItemType Directory -Path (Join-Path $wii 'title') -Force | Out-Null
    $script:cfg.SaveFolder = $wii
    function Save-ConfigFromUI { }
    $script:backups = 0
    function Backup-Saves { $script:backups++; $true }
    [AcssTest.Dialog]::Reset('No')
    Initialize-Repo
    Soll ([AcssTest.Dialog]::Texte.Count -eq 1) "Warnung gezeigt"
    Soll ($script:backups -eq 0) "bei Nein nichts kopiert"
}

Test "Backup-Saves spiegelt den Save-Ordner exakt ins Repo" -NurWindows {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'v1'
    Soll (Backup-Saves) "erster Durchgang ok"
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'v2'
    Remove-Item -LiteralPath (Join-Path $script:cfg.SaveFolder 'banner.bin')
    Soll (Backup-Saves) "zweiter Durchgang ok"
    Soll ((Get-Content -LiteralPath (Join-Path $r.a 'save/data/stadt.bin')) -eq 'v2') "Aenderung uebernommen"
    Soll (-not (Test-Path -LiteralPath (Join-Path $r.a 'save/banner.bin'))) "Loeschung uebernommen"
}

Test "Backup-Saves: gesperrte Datei -> Fehler, save/ bleibt beim letzten Stand" -NurWindows {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'gut'
    Soll (Backup-Saves) "Ausgangsstand gesichert"
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm gut | Out-Null
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'neu'
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'banner.bin') -Value 'banner neu'
    $sperre = Lock-Datei (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')
    try { $ok = Backup-Saves } finally { $sperre.Close() }
    Soll (-not $ok) "Fehler gemeldet"
    Soll (-not (Invoke-G $r.a status --porcelain -- save)) "save/ exakt wie im letzten Commit (kein Mischmasch)"
}

Test "Restore-Saves: gesperrte Zieldatei -> Fehler statt stillem Weitermachen" -NurWindows {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'alt'
    New-Item -ItemType Directory -Path (Join-Path $r.a 'save/data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $r.a 'save/data/stadt.bin') -Value 'neu vom Server'
    $sperre = Lock-Datei (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')
    try { $ok = Restore-Saves } finally { $sperre.Close() }
    Soll (-not $ok) "Fehler gemeldet"
    Soll (Restore-Saves) "ohne Sperre klappt es"
    Soll ((Get-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')) -eq 'neu vom Server') "Stand geschrieben"
}

Test "Test-SaveGleich: gleiche Inhalte, andere Zeitstempel -> gleich" {
    $a = New-SaveOrdner 'Stand'
    $b = New-SaveOrdner 'Stand'
    (Get-Item -LiteralPath (Join-Path $b 'data/stadt.bin')).LastWriteTime = (Get-Date).AddDays(-3)
    Soll (Test-SaveGleich $a $b) "gleicher Inhalt, andere Zeit: gleich"
    Set-Content -LiteralPath (Join-Path $b 'data/stadt.bin') -Value 'Stanx'      # gleiche Groesse
    Soll (-not (Test-SaveGleich $a $b)) "gleiche Groesse, anderer Inhalt: verschieden"
    Set-Content -LiteralPath (Join-Path $b 'data/stadt.bin') -Value 'Stand'
    Set-Content -LiteralPath (Join-Path $b 'extra.bin') -Value 'x'
    Soll (-not (Test-SaveGleich $a $b)) "zusaetzliche Datei: verschieden"
    Soll ($script:beschaeftigt -eq 0) "danach nicht mehr beschaeftigt"
}

Test "Restore-Saves sichert den bisherigen Stand, bevor er ueberschrieben wird" -NurWindows {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'mein neuerer Stand'
    New-Item -ItemType Directory -Path (Join-Path $r.a 'save/data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $r.a 'save/data/stadt.bin') -Value 'Stand vom Server'
    Set-Content -LiteralPath (Join-Path $r.a 'save/banner.bin') -Value 'banner'
    $ersetzt = Join-Path $script:AppDir 'ersetzt'

    Soll (Restore-Saves) "zurueckgeschrieben"
    Soll ((Get-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')) -eq 'Stand vom Server') "Stand vom Server im Dolphin-Ordner"
    $kopien = @(Get-ChildItem -LiteralPath $ersetzt -Directory)
    Soll ($kopien.Count -eq 1) "eine Sicherheitskopie"
    Soll ((Get-Content -LiteralPath (Join-Path $kopien[0].FullName 'data/stadt.bin')) -eq 'mein neuerer Stand') "darin der bisherige Stand"
    Soll ((Get-ProtokollText) -match 'Bisheriger Spielstand dieses PCs gesichert') "im Protokoll"

    Soll (Restore-Saves) "noch einmal"
    Soll (@(Get-ChildItem -LiteralPath $ersetzt -Directory).Count -eq 1) "gleicher Stand: keine neue Kopie"

    foreach ($i in 1..12) { New-Item -ItemType Directory -Path (Join-Path $ersetzt ('20200101-0000{0:D2}' -f $i)) -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'wieder anders'
    Soll (Restore-Saves) "mit anderem Stand"
    $namen = @(Get-ChildItem -LiteralPath $ersetzt -Directory | ForEach-Object { $_.Name })
    Soll ($namen.Count -eq 10) "nur die zehn juengsten Kopien bleiben (waren $($namen.Count))"
    Soll ($namen -notcontains '20200101-000001' -and $namen -contains '20200101-000012') "die aeltesten sind weg"
}

# Die letzte eigene Sitzung wurde nicht sauber beendet: Auf dem Server liegt
# die eigene (abgelaufene) Sperre mit dem Stand vom letzten Herzschlag, im
# Dolphin-Ordner ein neuerer Stand.
function New-UnbeendeteSitzung {
    $r = New-TestRepos -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'weitergespielt'
    $script:cfg.DolphinPath = (Get-FakeDolphin).Exe
    New-Item -ItemType Directory -Path (Join-Path $r.a 'save/data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $r.a 'save/data/stadt.bin') -Value 'letzter Herzschlag'
    Set-Content -LiteralPath (Join-Path $r.a 'save/banner.bin') -Value 'banner'
    Set-Content -LiteralPath (Join-Path $r.a 'PLAYING.lock') -Value (New-SperrText -Besitzer 'Anna' -Rechner 'TEST-PC' -VorMinuten 20)
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm 'heartbeat: Anna' | Out-Null; Invoke-G $r.a push -q origin main | Out-Null
    return $r
}

Test "Eigene Sitzung nicht beendet, Ja: Stand im Dolphin-Ordner bleibt" -NurWindows {
    [void](New-UnbeendeteSitzung)
    function Save-ConfigFromUI { }
    [AcssTest.Dialog]::Reset('Yes')
    Start-Play
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 1 -and $t[0] -match 'nicht sauber beendet') "genau eine Rueckfrage - kein 'Sperre uebernehmen?' fuer die eigene (war: $($t -join ' | '))"
    Soll ($script:holdingLock) "Sitzung laeuft"
    Soll ((Get-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')) -eq 'weitergespielt') "Stand im Dolphin-Ordner nicht ueberschrieben"
}

Test "Eigene Sitzung nicht beendet, Nein: Stand vom Server, der eigene als Kopie" -NurWindows {
    [void](New-UnbeendeteSitzung)
    function Save-ConfigFromUI { }
    [AcssTest.Dialog]::Reset('No')
    Start-Play
    Soll ($script:holdingLock) "Sitzung laeuft"
    Soll ((Get-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')) -eq 'letzter Herzschlag') "Stand vom Server geschrieben"
    $kopie = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'ersetzt') -Directory | Select-Object -First 1
    Soll ($null -ne $kopie -and (Get-Content -LiteralPath (Join-Path $kopie.FullName 'data/stadt.bin')) -eq 'weitergespielt') "der eigene Stand liegt als Kopie bereit"
}

Test "Herzschlag wartet, solange das Spiel speichert - hoechstens 20 Sekunden" {
    $script:cfg.RepoPath = (New-TestRepos).a
    $script:cfg.SaveFolder = New-SaveOrdner 'wird gerade geschrieben'
    $script:holdingLock = $true
    $script:gesichert = 0; $script:gesendet = 0
    function Set-LockFile { }
    function Backup-Saves { $script:gesichert++; $true }
    function Invoke-GitCommitPush { $script:gesendet++; [pscustomobject]@{ Code = 0; Text = ''; Stage = 'push' } }
    $alt = { Get-ChildItem -LiteralPath $script:cfg.SaveFolder -Recurse -File | ForEach-Object { $_.LastWriteTime = (Get-Date).AddMinutes(-1) } }

    $script:lastHeartbeat = (Get-Date).AddMinutes(-5)
    Soll (Test-SaveWirdGeschrieben) "gerade geschriebene Datei erkannt"
    Invoke-Tick
    Soll ($script:gesendet -eq 0 -and $null -ne $script:hbAufgeschobenSeit) "Herzschlag wartet"

    & $alt
    Soll (-not (Test-SaveWirdGeschrieben)) "fertig gespeichert"
    Invoke-Tick
    Soll ($script:gesichert -eq 1 -and $script:gesendet -eq 1) "gleich danach: mit Spielstand gesendet"
    Soll ($null -eq $script:hbAufgeschobenSeit) "Wartezeit zurueckgesetzt"

    # Das Spiel schreibt dauernd: nach 20 Sekunden nur die Sperre auffrischen
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'schreibt immer noch'
    $script:lastHeartbeat = (Get-Date).AddMinutes(-5)
    $script:hbAufgeschobenSeit = (Get-Date).AddSeconds(-25)
    Invoke-Tick
    Soll ($script:gesendet -eq 2 -and $script:gesichert -eq 1) "Sperre aufgefrischt, halber Spielstand nicht gesichert"
    Soll ((Get-ProtokollText) -match 'nur die Sperre aufgefrischt') "im Protokoll"

    Get-ChildItem -LiteralPath $script:cfg.SaveFolder -Recurse -File | ForEach-Object { $_.LastWriteTime = (Get-Date).AddHours(2) }
    Soll (-not (Test-SaveWirdGeschrieben)) "Zeitstempel in der Zukunft (verstellte Uhr) zaehlen nicht"
}

Test "Spielen starten: Zurueckschreiben scheitert -> kein Dolphin, Sperre wieder frei" -NurWindows {
    $r = New-TestRepos -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'alt'
    $script:cfg.DolphinPath = (Get-FakeDolphin).Exe
    New-Item -ItemType Directory -Path (Join-Path $r.a 'save/data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $r.a 'save/data/stadt.bin') -Value 'Server-Stand'
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm save | Out-Null; Invoke-G $r.a push -q origin main | Out-Null
    function Save-ConfigFromUI { }
    $sperre = Lock-Datei (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')
    try { Start-Play } finally { $sperre.Close() }
    Soll ($null -eq $script:proc) "Dolphin nicht gestartet"
    Soll (-not $script:holdingLock) "keine Sitzung"
    Soll ((Invoke-G $r.a ls-tree --name-only origin/main) -notmatch 'PLAYING.lock') "Sperre auf dem Server wieder frei"
    Soll ((Invoke-G $r.a log -1 --format=%s origin/main) -match 'Start abgebrochen') "Freigabe-Commit hochgeladen"
}

Test "Beenden: Sichern scheitert -> Sitzung bleibt offen, spaeter sauber abschliessen" -NurWindows {
    $r = New-TestRepos -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.SaveFolder = New-SaveOrdner 'vorher'
    Set-LockFile -Neu; [void](Invoke-GitCommitPush 'lock')
    $script:holdingLock = $true
    Set-Content -LiteralPath (Join-Path $script:cfg.SaveFolder 'data/stadt.bin') -Value 'nachher'

    [AcssTest.Dialog]::Reset('Cancel')
    $sperre = Lock-Datei (Join-Path $script:cfg.SaveFolder 'data/stadt.bin')
    try { Complete-Session } finally { $sperre.Close() }
    Soll ([AcssTest.Dialog]::Texte.Count -eq 1 -and [AcssTest.Dialog]::Texte[0] -match 'nicht ins Repo gesichert') "Rueckfrage gezeigt"
    Soll ($script:holdingLock -and $script:btnStop.Enabled -and $script:timer.Enabled) "Sitzung bleibt offen"
    Soll ((Invoke-G $r.a show origin/main:PLAYING.lock) -match 'Anna') "Sperre bleibt bestehen"

    # Datei wieder frei -> "Spielen beenden" schliesst ab
    Stop-Play
    Soll (-not $script:holdingLock) "Sitzung abgeschlossen"
    Soll ((Invoke-G $r.a ls-tree --name-only origin/main) -notmatch 'PLAYING.lock') "Sperre frei"
    Soll ((Invoke-G $r.a show origin/main:save/data/stadt.bin) -match 'nachher') "neuer Stand auf dem Server"
}
