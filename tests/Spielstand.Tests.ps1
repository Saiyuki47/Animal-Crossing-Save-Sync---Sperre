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
