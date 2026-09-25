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
    function Move-Pics { $script:bilder = $true }
    if (-not $script:AufWindows) { function Save-Sicherheitskopie { '/ersatz/gerettet' } }   # ohne robocopy

    $script:sperreVerloren = $true; $script:holdingLock = $true
    Complete-Session
    Soll (-not $script:gepusht) "nichts hochgeladen"
    Soll (-not $script:bilder) "Bilder nicht ins Repo verschoben"
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
