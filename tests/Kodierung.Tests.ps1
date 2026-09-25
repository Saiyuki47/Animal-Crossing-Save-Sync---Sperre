# Dateien im gemeinsamen Repo: ohne BOM schreiben, als UTF-8 lesen, Umlaute heil.
# Umlaute werden per Zeichencode gebaut - Windows PowerShell 5.1 liest diese
# Datei (ohne BOM) sonst als ANSI und der Test wuerde sich selbst verfaelschen.
$script:Joerg = "J$([char]0xF6)rg"

Test "Write-TextDatei schreibt ohne BOM, auch mit relativem Pfad" {
    $ordner = Join-Path $script:TestWurzel 'rel'
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    Push-Location $ordner
    try { Write-TextDatei 'datei.txt' "hallo $script:Joerg" } finally { Pop-Location }
    $b = [IO.File]::ReadAllBytes((Join-Path $ordner 'datei.txt'))
    Soll ($b[0] -ne 0xEF) "kein BOM am Anfang"
    Soll ([Text.Encoding]::UTF8.GetString($b) -eq "hallo $script:Joerg") "Inhalt als UTF-8"
}

Test "Sperre mit Umlaut-Namen: schreiben und selbst wieder erkennen" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.PlayerName = $script:Joerg
    Set-LockFile -Neu
    $b = [IO.File]::ReadAllBytes((Get-LockPath))
    Soll ($b[0] -ne 0xEF) "Sperr-Datei ohne BOM"
    $l = Get-LockState
    Soll ($l.State -eq 'locked' -and $l.Mine) "eigene Sperre erkannt"
    Soll ($l.Owner -eq $script:Joerg) "Name mit Umlaut unveraendert (war: $($l.Owner))"
}

Test "Sperre vom Server lesen (git show) - mit Umlaut-Namen" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.PlayerName = $script:Joerg
    Set-LockFile -Neu
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm lock | Out-Null; Invoke-G $r.a push -q origin main | Out-Null
    $s = Get-LockStateRemote
    Soll ($null -ne $s) "Sperre lesbar (vorher scheiterte das an Kodierung/BOM)"
    Soll ($s.State -eq 'locked' -and $s.Mine) "als eigene erkannt"
    Soll ($s.Owner -eq $script:Joerg) "Umlaut kommt heil an (war: $($s.Owner))"
}

Test "Alte Sperr-Datei MIT BOM (fruehere Fassung) wird trotzdem gelesen" {
    $r = New-TestRepos -Klone a, b
    $script:cfg.RepoPath = $r.a
    # So schrieb Set-Content -Encoding UTF8 unter Windows PowerShell 5.1:
    [IO.File]::WriteAllText((Join-Path $r.b 'PLAYING.lock'), (New-SperrText -Besitzer $script:Joerg), [Text.UTF8Encoding]::new($true))
    Invoke-G $r.b add -A | Out-Null; Invoke-G $r.b commit -qm alt | Out-Null; Invoke-G $r.b push -q origin main | Out-Null
    $s = Get-LockStateRemote
    Soll ($null -ne $s -and $s.State -eq 'locked') "vom Server lesbar"
    Soll ($s.Owner -eq $script:Joerg -and -not $s.Mine) "fremde Sperre mit richtigem Namen (war: $($s.Owner))"
    Invoke-G $r.a pull -q origin main | Out-Null
    $l = Get-LockState
    Soll ($l.State -eq 'locked' -and $l.Owner -eq $script:Joerg) "auch oertlich lesbar"
}

Test "Spielzeit und README ohne BOM, Umlaut-Name bleibt erhalten" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a; $script:cfg.PlayerName = $script:Joerg
    $script:lastAccounted = (Get-Date).AddMinutes(-5)
    Add-Playtime -EndSession
    foreach ($f in 'playtime.json', 'README.md') {
        $b = [IO.File]::ReadAllBytes((Join-Path $r.a $f))
        Soll ($b[0] -ne 0xEF) "$f ohne BOM"
    }
    $h = Get-Playtime
    Soll ($h.ContainsKey($script:Joerg)) "Eintrag unter dem richtigen Namen"
    Soll ($h[$script:Joerg].Sessions -eq 1 -and $h[$script:Joerg].TotalSeconds -ge 290) "Zeit und Sitzung gezaehlt"
}
