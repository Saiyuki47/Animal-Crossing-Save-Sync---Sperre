# Sperre: Herzschlag-Grenze, fremde Sperre, verlorene Sperre, Uebernahme, Wettlauf.

# Start-Play braucht ein "Dolphin", das es starten kann. Ohne Spiel-Datei wird
# es ohne Argumente gestartet - unter Windows beendet sich ping dann sofort.
function Get-TestDolphinPfad {
    if ($script:AufWindows) { return (Get-FakeDolphin).Exe }
    return '/bin/true'
}

Test "Herzschlag wird auf ein Drittel der Sperrdauer begrenzt" {
    $faelle = @(
        @{ L = 5; H = 60; Soll = 60 }, @{ L = 5; H = 300; Soll = 100 },
        @{ L = 1; H = 60; Soll = 20 }, @{ L = 1; H = 10; Soll = 10 }
    )
    foreach ($f in $faelle) {
        $script:cfg.LeaseMinutes = $f.L; $script:cfg.HeartbeatSeconds = $f.H
        $ist = Get-HerzschlagSek
        Soll ($ist -eq $f.Soll) ("Sperre {0} Min, Herzschlag {1} s -> {2} s (war {3})" -f $f.L, $f.H, $f.Soll, $ist)
    }
}

Test "Sperrdauer steht in der Sperre: es gilt die des Spielenden" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a
    $script:cfg.LeaseMinutes = 7
    Set-LockFile -Neu
    $eigen = Get-Content -LiteralPath (Get-LockPath) -Raw -Encoding UTF8 | ConvertFrom-Json
    Soll ((Get-JsonWert $eigen 'leaseMinutes') -eq 7) "eigene Sperrdauer steht in der Sperr-Datei"
    Remove-Item -LiteralPath (Get-LockPath) -Force

    # Max: letzter Herzschlag vor 4 Minuten, seine Sperre gilt 15 Minuten
    $t = [datetime]::UtcNow.AddMinutes(-4).ToString('o')
    $mitDauer = { param($m) '{"owner":"Max","machine":"ANDERER-PC","startedUtc":"' + $t + '","updatedUtc":"' + $t + '","leaseMinutes":' + $m + '}' }
    Push-Als $r.b 'PLAYING.lock' (& $mitDauer 15)
    $script:cfg.LeaseMinutes = 3
    Soll (-not (Get-LockStateRemote).Stale) "bei mir 3 Min eingestellt - Max' Sperre (15 Min) ist trotzdem frisch"
    Invoke-G $r.a pull -q origin main | Out-Null
    Soll (-not (Get-LockState).Stale) "auch oertlich gelesen frisch"

    Push-Als $r.b 'PLAYING.lock' (& $mitDauer 3)
    $script:cfg.LeaseMinutes = 15
    Soll ((Get-LockStateRemote).Stale) "Max hat 3 Min: abgelaufen, obwohl bei mir 15 eingestellt sind"

    # Sperr-Datei einer aelteren Fassung ohne Angabe: eigene Einstellung
    Push-Als $r.b 'PLAYING.lock' (New-SperrText -Besitzer 'Max' -VorMinuten 4)
    $script:cfg.LeaseMinutes = 3
    Soll ((Get-LockStateRemote).Stale) "ohne Angabe, eigene 3 Min: abgelaufen"
    $script:cfg.LeaseMinutes = 15
    Soll (-not (Get-LockStateRemote).Stale) "ohne Angabe, eigene 15 Min: frisch"
}

Test "Test-FremdeSperre: blockiert, solange jemand anderes spielt" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a
    Push-Als $r.b 'PLAYING.lock' (New-SperrText -Besitzer 'Max')
    Soll ((Test-FremdeSperre -Titel 'x') -eq $true) "gesperrt"
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 1 -and $t[0] -match '^Max spielt gerade' -and $t[0] -notmatch '\{\d\}') "Meldung mit Namen, fertig formatiert"
    Invoke-G $r.b rm -q PLAYING.lock | Out-Null; Invoke-G $r.b commit -qm frei | Out-Null; Invoke-G $r.b push -q origin main | Out-Null
    Soll ((Test-FremdeSperre -Titel 'x') -eq $false) "frei -> nicht gesperrt"
}

Test "Verlorene Sperre: Uebernahme, Freigabe und fehlender Server" {
    $r = New-TestRepos -Klone a, b
    $script:cfg.RepoPath = $r.a
    Set-LockFile -Neu; $p = Invoke-GitCommitPush 'lock'
    Soll ($p.Code -eq 0) "eigene Sperre hochgeladen"

    Test-SperreNochMeine
    Soll (-not $script:sperreVerloren -and [AcssTest.Dialog]::Texte.Count -eq 0) "eigene Sperre -> kein Alarm"

    # Mitspieler uebernimmt, unser naechster Herzschlag wird abgelehnt
    Push-Als $r.b 'PLAYING.lock' (New-SperrText -Besitzer 'Max')
    Set-LockFile; $p = Invoke-GitCommitPush 'heartbeat'
    Soll ($p.Code -ne 0 -and $p.Stage -eq 'push') "Herzschlag abgelehnt"
    Test-SperreNochMeine
    Soll ($script:sperreVerloren) "Uebernahme erkannt"
    Soll ($script:lblStatus.Text -match 'Max hat uebernommen') "Statusanzeige nennt Max"
    Soll ([AcssTest.Dialog]::Texte.Count -eq 1 -and $script:timer.Stops -eq 1 -and $script:timer.Starts -eq 1) "eine Meldung, Timer waehrenddessen angehalten"

    # Freigabe von Hand
    $script:sperreVerloren = $false
    Invoke-G $r.b rm -q PLAYING.lock | Out-Null; Invoke-G $r.b commit -qm frei | Out-Null; Invoke-G $r.b push -q origin main | Out-Null
    Test-SperreNochMeine
    Soll ($script:sperreVerloren -and $script:lblStatus.Text -match 'freigegeben') "Freigabe erkannt"

    # Server weg -> keine Aussage, kein Fehlalarm
    $script:sperreVerloren = $false
    Invoke-G $r.a remote set-url origin (Join-Path $r.Wurzel 'gibtsnicht.git') | Out-Null
    Test-SperreNochMeine
    Soll (-not $script:sperreVerloren) "kein Fehlalarm ohne Server"
}

Test "Nach verlorener Sperre: nichts hochladen, Sicherheitskopie anlegen" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $save = Join-Path $script:TestWurzel ('save-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path (Join-Path $save 'data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $save 'data/stadt.bin') -Value 'mein Stand'
    $script:cfg.SaveFolder = $save
    $script:gepusht = $false; $script:bilder = $false
    function Invoke-GitCommitPush { $script:gepusht = $true; [pscustomobject]@{ Code = 0; Text = ''; Stage = 'push' } }
    function Copy-Pics { $script:bilder = $true }
    if (-not $script:AufWindows) { function Save-Sicherheitskopie { '/ersatz/gerettet' } }   # ohne robocopy

    $script:sperreVerloren = $true; $script:holdingLock = $true
    Complete-Session
    Soll (-not $script:gepusht) "nichts hochgeladen"
    Soll (-not $script:bilder) "keine Fotos in den gemeinsamen Ordner kopiert"
    Soll (-not $script:holdingLock -and -not $script:btnStop.Enabled) "Sitzung beendet"
    Soll ((Get-ProtokollText) -match 'Kopie deines Spielstands liegt hier') "Pfad der Kopie im Protokoll"
    if ($script:AufWindows) {
        $kopie = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'gerettet') -Directory | Select-Object -First 1
        Soll ($null -ne $kopie) "Ordner gerettet\<Zeit> angelegt"
        Soll ((Get-Content -LiteralPath (Join-Path $kopie.FullName 'data/stadt.bin')) -eq 'mein Stand') "Spielstand darin kopiert"
    }
}

Test "Abgelaufene Sperre: erst fragen, dann (nur bei Ja) uebernehmen" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.DolphinPath = Get-TestDolphinPfad
    Push-Als $r.b 'PLAYING.lock' (New-SperrText -Besitzer 'Max' -VorMinuten 20)
    function Save-ConfigFromUI { }

    [AcssTest.Dialog]::Reset('No')
    Start-Play
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 1 -and $t[0] -match 'Max' -and $t[0] -match '20 Min' -and $t[0] -notmatch '\{\d\}') "Rueckfrage mit Name und Dauer"
    Soll (-not $script:holdingLock) "bei Nein nicht uebernommen"
    Soll ((Invoke-G $r.a show origin/main:PLAYING.lock) -match 'Max') "Sperre auf dem Server unveraendert"

    [AcssTest.Dialog]::Reset('Yes')
    Start-Play
    Soll ($script:holdingLock) "bei Ja uebernommen"
    Soll ((Invoke-G $r.a show origin/main:PLAYING.lock) -match 'Anna') "Server zeigt jetzt Anna"
}

Test "Wettlauf: der andere war schneller -> Abbruch ohne Verwirrfrage" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.DolphinPath = Get-TestDolphinPfad
    function Save-ConfigFromUI { }
    function Sync-Remote { }   # der erste Abgleich "verpasst" den Push des anderen
    Push-Als $r.b 'PLAYING.lock' (New-SperrText -Besitzer 'Max')
    Start-Play
    Soll ((Get-ProtokollText) -match 'Max war schneller') "Abbruch gemeldet"
    Soll (-not $script:holdingLock) "keine Sitzung"
    Soll ([AcssTest.Dialog]::Texte.Count -eq 0) "keine Frage 'Fortschritt verwerfen?'"
    Soll ((Invoke-G $r.a rev-parse HEAD) -eq (Invoke-G $r.a rev-parse origin/main)) "lokal auf Server-Stand"
    Soll (-not (Invoke-G $r.a status --porcelain)) "nichts Liegengebliebenes"
}

Test "Wettlauf: fremder Commit ohne Sperre -> zweiter Versuch klappt" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.DolphinPath = Get-TestDolphinPfad
    function Save-ConfigFromUI { }
    function Sync-Remote { }
    Push-Als $r.b 'playtime.json' '{}'
    Start-Play
    Soll ($script:holdingLock) "Sperre gesichert"
    Soll ((Invoke-G $r.a show origin/main:PLAYING.lock) -match 'Anna') "Sperre auf dem Server"
    Soll ([AcssTest.Dialog]::Texte.Count -eq 0) "keine Frage"
    Soll ((Invoke-G $r.a log --format=%s origin/main) -match 'playtime.json') "Commit des anderen erhalten"
}

Test "Wettlauf mit echtem lokalem Fortschritt: der bleibt erhalten" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.DolphinPath = Get-TestDolphinPfad
    function Save-ConfigFromUI { }
    $script:syncAufrufe = 0
    function Sync-Remote { $script:syncAufrufe++ }
    Set-Content -LiteralPath (Join-Path $r.a 'fortschritt.txt') -Value 'x'
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm 'lokaler Fortschritt' | Out-Null
    Push-Als $r.b 'andere.txt' 'y'
    Start-Play
    Soll ($script:syncAufrufe -ge 2) "normaler Abgleich (mit Rueckfrage) wird aufgerufen"
    Soll ((Invoke-G $r.a log --format=%s) -match 'lokaler Fortschritt') "Fortschritt nicht weggeworfen"
}

Test "git add scheitert (index.lock): Fehler statt vorgetaeuschtem Erfolg, keine Sitzung" {
    $r = New-TestRepos -Klone a -MitStart
    $script:cfg.RepoPath = $r.a; $script:cfg.DolphinPath = Get-TestDolphinPfad
    function Save-ConfigFromUI { }
    # So bleibt sie liegen, wenn git mittendrin abstuerzt oder beendet wird.
    $indexSperre = Join-Path $r.a '.git/index.lock'
    New-Item -ItemType File -Path $indexSperre | Out-Null
    try {
        Set-LockFile -Neu
        $p = Invoke-GitCommitPush 'lock: Anna'
        Soll ($p.Code -ne 0 -and $p.Stage -eq 'commit') "Fehler statt Erfolg (Code $($p.Code), Stage $($p.Stage))"
        Soll ((Get-ProtokollText) -match 'blockiert sich selbst') "Klartext zur index.lock im Protokoll"
        Remove-Item -LiteralPath (Get-LockPath) -Force

        Start-Play
        Soll (-not $script:holdingLock -and $null -eq $script:proc) "keine Sitzung, kein Dolphin"
        Soll (-not (Test-Path -LiteralPath (Get-LockPath))) "keine liegengebliebene Sperr-Datei"
    }
    finally { Remove-Item -LiteralPath $indexSperre -Force -ErrorAction SilentlyContinue }
    Soll ((Invoke-G $r.a ls-tree --name-only origin/main) -notmatch 'PLAYING.lock') "keine Sperre auf dem Server"
}

Test "Dolphin startet nicht: keine Sitzung, keine Spielzeit, Sperre wieder frei" -NurWindows {
    $r = New-TestRepos -Klone a -MitStart
    $script:cfg.RepoPath = $r.a
    # Die Datei gibt es, ein Programm ist sie aber nicht - Start-Process scheitert.
    $kaputt = Join-Path $script:TestWurzel ('kaputt-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.exe')
    Set-Content -LiteralPath $kaputt -Value 'kein Programm'
    $script:cfg.DolphinPath = $kaputt
    function Save-ConfigFromUI { }
    $script:lastAccounted = (Get-Date).AddHours(-3)     # das Programm laeuft schon lange
    Start-Play
    Soll ((Get-ProtokollText) -match 'Start fehlgeschlagen') "Fehlstart erkannt"
    Soll (-not $script:holdingLock -and $null -eq $script:proc) "keine Sitzung"
    Soll ((Get-Playtime).Count -eq 0) "keine Sitzung und keine Spielzeit gezaehlt"
    Soll ((Invoke-G $r.a ls-tree --name-only origin/main) -notmatch 'PLAYING.lock') "Sperre auf dem Server wieder frei"
    Soll ((Invoke-G $r.a log -1 --format=%s origin/main) -match 'Start abgebrochen') "im Verlauf als abgebrochener Start"
}
