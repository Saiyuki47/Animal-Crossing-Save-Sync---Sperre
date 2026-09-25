# Fotos: nach dem Spielen aus dem Bilder-Ordner ins Repo verschieben, Namen,
# Zeiten und die Galerie in der README.

function New-Bild {
    param([string]$Pfad, [datetime]$Zeit)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Pfad) -Force | Out-Null
    [IO.File]::WriteAllBytes($Pfad, [byte[]](1, 2, 3))
    (Get-Item -LiteralPath $Pfad).LastWriteTime = $Zeit
}

Test "Move-Pics: Bilder ins Repo, eindeutige Namen, anderes bleibt liegen" {
    $r = New-TestRepos
    $quelle = Join-Path $script:TestWurzel ('bilder-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $zeit = New-Object DateTime(2026, 9, 20, 18, 30, 15)
    New-Bild (Join-Path $quelle 'a.JPG') $zeit
    New-Bild (Join-Path $quelle 'unter/Mein Foto (1).png') $zeit.AddMinutes(1)
    New-Bild (Join-Path $quelle 'c.jpeg') $zeit.AddMinutes(2)
    Set-Content -LiteralPath (Join-Path $quelle 'notiz.txt') -Value 'bleibt'
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle; $script:cfg.PlayerName = 'Anna Lena!'

    Move-Pics
    $ziel = Join-Path $r.a 'pics'
    $namen = @(Get-ChildItem -LiteralPath $ziel -File | ForEach-Object { $_.Name } | Sort-Object)
    Soll ($namen.Count -eq 3) "drei Bilder im Repo (waren: $($namen -join ', '))"
    Soll ($namen -ccontains 'Anna_Lena__20260920-183015_a.jpg') "Name: Spieler_Zeit_Original, Endung klein"
    Soll ($namen -ccontains 'Anna_Lena__20260920-183115_Mein_Foto__1_.png') "Sonderzeichen im Originalnamen ersetzt"
    Soll (-not (Get-ChildItem -LiteralPath $quelle -Recurse -File | Where-Object { $_.Extension -ne '.txt' })) "Bilder lokal entfernt"
    Soll (Test-Path -LiteralPath (Join-Path $quelle 'notiz.txt')) "andere Dateien bleiben liegen"
    Soll ((Get-ProtokollText) -match '3 Bild\(er\) ins Repo verschoben') "im Protokoll"
}

Test "Move-Pics: gleicher Name wird nicht ueberschrieben" {
    $r = New-TestRepos
    $quelle = Join-Path $script:TestWurzel ('bilder-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $zeit = New-Object DateTime(2026, 9, 20, 18, 30, 15)
    New-Bild (Join-Path $quelle 'a.png') $zeit
    $ziel = Join-Path $r.a 'pics'
    New-Item -ItemType Directory -Path $ziel -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a.png') -Value 'altes Bild'
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    Move-Pics
    Soll ((Get-Content -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a.png')) -eq 'altes Bild') "vorhandenes Bild unveraendert"
    Soll (Test-Path -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a_1.png')) "neues Bild mit _1"
}

Test "Move-Pics: ohne Bilder-Ordner passiert nichts" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $script:cfg.PicsFolder = ''
    Move-Pics
    Soll (-not (Test-Path -LiteralPath (Join-Path $r.a 'pics'))) "leeres Feld: Funktion aus"
    $script:cfg.PicsFolder = Join-Path $script:TestWurzel 'gibt-es-nicht'
    Move-Pics
    Soll ((Get-ProtokollText) -match 'Bilder-Ordner nicht gefunden') "fehlender Ordner: Hinweis"
}

Test "Aufnahmezeit: aus dem Namen, sonst aus der Datei" {
    $ordner = Join-Path $script:TestWurzel ('zeit-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $zeit = New-Object DateTime(2026, 1, 2, 3, 4, 5)
    New-Bild (Join-Path $ordner 'Anna_Lena_20260915-201500_x.png') $zeit
    New-Bild (Join-Path $ordner 'von-hand.png') $zeit
    $mitName = Get-Item -LiteralPath (Join-Path $ordner 'Anna_Lena_20260915-201500_x.png')
    $ohne = Get-Item -LiteralPath (Join-Path $ordner 'von-hand.png')
    Soll ((Get-BildZeit $mitName) -eq (New-Object DateTime(2026, 9, 15, 20, 15, 0))) "Zeit aus dem Namen"
    Soll ((Get-BildZeit $ohne) -eq $zeit) "Zeit aus der Datei"
    $info = Get-FotoInfo $mitName
    Soll ($info.Spieler -eq 'Anna Lena' -and $info.Text -match '^Anna Lena  -  15\.09\.2026, 20:15 Uhr$') "Anzeige: Spieler und Zeit (war '$($info.Text)')"
    Soll ((Get-FotoInfo $ohne).Text -match '^von-hand\.png') "von Hand hineingelegt: Dateiname"
}

Test "Galerie in der README: neueste zuerst, unabhaengig vom Spielernamen" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $pics = Join-Path $r.a 'pics'
    New-Bild (Join-Path $pics 'Zoe_20260901-120000_alt.png') (Get-Date)
    New-Bild (Join-Path $pics 'Anna_20260915-120000_neu.png') (Get-Date)
    Write-Readme @{}
    $readme = Get-Content -LiteralPath (Join-Path $r.a 'README.md') -Raw
    Soll ($readme -match '## Fotos \(2\)') "Abschnitt mit Anzahl"
    Soll ($readme.IndexOf('Anna_20260915') -lt $readme.IndexOf('Zoe_20260901')) "Annas neueres Bild vor Zoes aelterem"
    Soll ($readme -match '!\[Anna_20260915-120000_neu\]\(pics/Anna_20260915-120000_neu\.png\)') "als Bild eingebunden"
}
