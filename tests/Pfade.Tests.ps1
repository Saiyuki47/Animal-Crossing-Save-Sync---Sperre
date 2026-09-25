# Pfade: leerer Repo-Ordner, eckige Klammern, Sammelordner, automatische Anzeige.

Test "Ohne Repo-Ordner laeuft git NICHT im aktuellen Ordner" {
    $fremd = Join-Path $script:TestWurzel ('fremd-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    & git init -q $fremd 2>&1 | Out-Null
    $script:cfg.RepoPath = ''
    Push-Location $fremd
    try {
        $r = Invoke-Git @('status')
        $t = Test-Repo
    }
    finally { Pop-Location }
    Soll ($r.Code -eq 128 -and $r.Text -match 'Kein Repo-Ordner') "Invoke-Git verweigert"
    Soll ($t -eq $false) "Test-Repo meldet false statt eines Fehlers"
}

Test "Eckige Klammern im Repo-Pfad" {
    $repo = Join-Path $script:TestWurzel ('Spiel [AC] ' + [guid]::NewGuid().ToString('N').Substring(0, 4))
    & git init -q -b main $repo 2>&1 | Out-Null
    $script:cfg.RepoPath = $repo
    Soll (Test-Repo) "als Repo erkannt"
    Set-LockFile -Neu
    $l = Get-LockState
    Soll ($l.State -eq 'locked' -and $l.Mine) "Sperre schreiben und lesen"
    Add-Playtime
    Soll ((Get-Playtime).ContainsKey('Anna')) "Spielzeit schreiben und lesen"
}

Test "Sammelordner werden erkannt, der Ordner eines Spiels nicht" {
    $w = Join-Path $script:TestWurzel ('nand-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $titel = Join-Path $w 'User/Wii/title/00010000'
    foreach ($d in "$titel/52555550/data", "$titel/52555550/content", "$titel/53424545/data",
        "$w/User/Wii/shared2", "$w/User/GC/EUR", "$w/User/GC/USA", "$w/Einzeln/52555550/data",
        "$w/Umbenannt/52555550", "$w/Umbenannt/53424545") {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    Soll (-not (Test-Sammelordner "$titel/52555550")) "Animal-Crossing-Ordner passt"
    Soll (-not (Test-Sammelordner "$w/Einzeln")) "ein einzelnes Spiel darunter passt"
    Soll (-not (Test-Sammelordner "$w/User/GC")) "GC wird bewusst nicht gemeldet"
    Soll ([bool](Test-Sammelordner $titel)) "00010000 gemeldet"
    Soll ([bool](Test-Sammelordner "$w/User/Wii")) "Wii gemeldet"
    Soll ([bool](Test-Sammelordner "$w/User/Wii/")) "Wii mit Schraegstrich am Ende gemeldet"
    Soll ([bool](Test-Sammelordner "$w/User")) "Dolphin-User-Ordner gemeldet"
    Soll ((Test-Sammelordner "$w/Umbenannt") -match '2 Spielen') "beliebiger Name mit zwei Spiel-IDs gemeldet"

    $script:cfg.SaveFolder = "$w/User/Wii"
    [AcssTest.Dialog]::Reset('No')
    Soll (-not (Confirm-SaveOrdner 'Spielen')) "bei Nein abbrechen"
    $t = [AcssTest.Dialog]::Texte[0]
    Soll ($t -notmatch '\{\d\}' -and $t -match 'Spielen trotzdem') "Meldung fertig formatiert"
}

Test "Automatische Anzeige startet, sobald es ein Repo gibt" {
    $r = New-TestRepos
    $script:statusAufrufe = 0
    function Update-Status { param([switch]$SkipSave) $script:statusAufrufe++ }
    $script:cfg.RepoPath = Join-Path $r.Wurzel 'gibtsnicht'
    Start-AutoAuffrischen -MitStatus
    Soll (-not $script:autoTimer.Enabled -and $script:statusAufrufe -eq 0) "ohne Repo: nichts"
    $script:cfg.RepoPath = $r.a
    Start-AutoAuffrischen -MitStatus
    Soll ($script:autoTimer.Enabled -and $script:statusAufrufe -eq 1) "mit Repo: Timer an und Status geprueft"
    Start-AutoAuffrischen -MitStatus
    Soll ($script:statusAufrufe -eq 1) "laeuft schon: nicht noch einmal"
}
