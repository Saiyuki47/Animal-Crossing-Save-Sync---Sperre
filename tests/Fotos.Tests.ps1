# Fotos: nach dem Spielen aus dem Spielfotos-Ordner in den gemeinsamen Ordner
# kopieren (Originale bleiben), schon Geteiltes erkennen, bei vielen Fotos
# nachfragen, ungeeignete Ordner ablehnen, beim Abgleich nichts verlieren -
# und die Galerie in der README.

# Jedes Bild bekommt einen eigenen Inhalt: gleicher Inhalt gilt als dasselbe Foto.
function New-Bild {
    param([string]$Pfad, [datetime]$Zeit, [string]$Inhalt = ('Bild ' + [guid]::NewGuid()))
    New-Item -ItemType Directory -Path (Split-Path -Parent $Pfad) -Force | Out-Null
    [IO.File]::WriteAllText($Pfad, $Inhalt)
    (Get-Item -LiteralPath $Pfad).LastWriteTime = $Zeit
}

function New-FotoQuelle {
    return (Join-Path $script:TestWurzel ('spielfotos-' + [guid]::NewGuid().ToString('N').Substring(0, 6)))
}

# Namen der Fotos im gemeinsamen Ordner - immer als Liste, auch bei keinem
# oder einem Foto (das Komma verhindert, dass PowerShell sie auspackt).
function Get-PicsNamen {
    param([string]$Repo)
    $ziel = Join-Path $Repo 'pics'
    if (-not (Test-Path -LiteralPath $ziel)) { return , @() }
    return , @(Get-ChildItem -LiteralPath $ziel -File | ForEach-Object { $_.Name } | Sort-Object)
}

Test "Copy-Pics: Fotos in den gemeinsamen Ordner kopiert, Originale bleiben liegen" {
    $r = New-TestRepos
    $quelle = New-FotoQuelle
    $zeit = New-Object DateTime(2026, 9, 20, 18, 30, 15)
    New-Bild (Join-Path $quelle 'a.JPG') $zeit
    New-Bild (Join-Path $quelle 'unter/Mein Foto (1).png') $zeit.AddMinutes(1)
    New-Bild (Join-Path $quelle 'c.jpeg') $zeit.AddMinutes(2)
    Set-Content -LiteralPath (Join-Path $quelle 'notiz.txt') -Value 'bleibt'
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle; $script:cfg.PlayerName = 'Anna Lena!'

    Copy-Pics
    $namen = Get-PicsNamen $r.a
    Soll ($namen.Count -eq 3) "drei Fotos im gemeinsamen Ordner (waren: $($namen -join ', '))"
    Soll ($namen -ccontains 'Anna_Lena__20260920-183015_a.jpg') "Name: Spieler_Zeit_Original, Endung klein"
    Soll ($namen -ccontains 'Anna_Lena__20260920-183115_Mein_Foto__1_.png') "Sonderzeichen im Originalnamen ersetzt"
    Soll (@(Get-ChildItem -LiteralPath $quelle -Recurse -File).Count -eq 4) "Originale und andere Dateien bleiben liegen"
    Soll ((Get-ProtokollText) -match '3 Foto\(s\) in den gemeinsamen Ordner kopiert') "im Protokoll"
}

Test "Copy-Pics: gleicher Name wird nicht ueberschrieben" {
    $r = New-TestRepos
    $quelle = New-FotoQuelle
    $zeit = New-Object DateTime(2026, 9, 20, 18, 30, 15)
    New-Bild (Join-Path $quelle 'a.png') $zeit
    $ziel = Join-Path $r.a 'pics'
    New-Item -ItemType Directory -Path $ziel -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a.png') -Value 'altes Bild'
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    Copy-Pics
    Soll ((Get-Content -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a.png')) -eq 'altes Bild') "vorhandenes Bild unveraendert"
    Soll (Test-Path -LiteralPath (Join-Path $ziel 'Anna_20260920-183015_a_1.png')) "neues Bild mit _1"
}

Test "Copy-Pics: ohne Spielfotos-Ordner passiert nichts" {
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $script:cfg.PicsFolder = ''
    Copy-Pics
    Soll (-not (Test-Path -LiteralPath (Join-Path $r.a 'pics'))) "leeres Feld: Funktion aus"
    $script:cfg.PicsFolder = Join-Path $script:TestWurzel 'gibt-es-nicht'
    Copy-Pics
    Soll ((Get-ProtokollText) -match 'Spielfotos-Ordner nicht gefunden') "fehlender Ordner: Hinweis"
}

Test "Copy-Pics: schon Geteiltes kommt nicht doppelt - auch nicht nach dem Loeschen im Album" {
    $r = New-TestRepos -MitStart
    $quelle = New-FotoQuelle
    New-Bild (Join-Path $quelle 'a.png') (Get-Date).AddDays(-1)
    New-Bild (Join-Path $quelle 'b.png') (Get-Date).AddDays(-1)
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    Copy-Pics
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm 'Session beendet + Spielstand (Anna)' | Out-Null
    Soll ((Get-PicsNamen $r.a).Count -eq 2) "zwei Fotos geteilt"

    Copy-Pics
    Soll ((Get-PicsNamen $r.a).Count -eq 2) "naechste Sitzung: nichts doppelt"
    # Dolphin schreibt seinen SD-Ordner neu: andere Zeit, gleicher Inhalt
    (Get-Item -LiteralPath (Join-Path $quelle 'a.png')).LastWriteTime = Get-Date
    Copy-Pics
    Soll ((Get-PicsNamen $r.a).Count -eq 2) "neuer Zeitstempel, gleicher Inhalt: nichts doppelt"

    # Im Album geloescht (wie "Fotos ansehen" -> "Loeschen")
    $a = @((Get-PicsNamen $r.a) | Where-Object { $_ -like '*_a.png' })[0]
    Invoke-G $r.a rm -q -- "pics/$a" | Out-Null; Invoke-G $r.a commit -qm "Foto geloescht: $a" | Out-Null
    Copy-Pics
    Soll ((Get-PicsNamen $r.a) -notcontains $a) "geloeschtes Foto kommt nicht zurueck"

    New-Bild (Join-Path $quelle 'neu/c.png') (Get-Date)
    Copy-Pics
    $namen = Get-PicsNamen $r.a
    Soll ($namen.Count -eq 2 -and @($namen | Where-Object { $_ -like '*_c.png' }).Count -eq 1) "ein wirklich neues Foto kommt dazu (waren: $($namen -join ', '))"
    Soll (@(Get-ChildItem -LiteralPath $quelle -Recurse -File).Count -eq 3) "alle Originale noch da"
}

Test "Copy-Pics: nie hochgeladene, verworfene Kopie wird wieder mitgenommen" {
    $r = New-TestRepos -MitStart
    $quelle = New-FotoQuelle
    New-Bild (Join-Path $quelle 'a.png') (Get-Date).AddHours(-1)
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    Copy-Pics
    Invoke-G $r.a add -A | Out-Null; Invoke-G $r.a commit -qm 'Session beendet + Spielstand (Anna)' | Out-Null
    Invoke-G $r.a reset -q --hard origin/main | Out-Null      # Stand vom Server geholt, Kopie verworfen
    Soll ((Get-PicsNamen $r.a).Count -eq 0) "Kopie weg"
    Copy-Pics
    Soll ((Get-PicsNamen $r.a).Count -eq 1) "beim naechsten Mal wieder kopiert - das Original lag ja noch da"
}

Test "Copy-Pics: sehr viele neue Fotos auf einmal - erst fragen" {
    $r = New-TestRepos
    $quelle = New-FotoQuelle
    foreach ($i in 1..31) { New-Bild (Join-Path $quelle ("foto{0:D2}.jpg" -f $i)) (Get-Date).AddMinutes(-$i) }
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle

    [AcssTest.Dialog]::Reset('No')
    Copy-Pics
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 1 -and $t[0] -match '31 neue Fotos' -and $t[0] -match [regex]::Escape($quelle)) "Rueckfrage mit Anzahl und Ordner"
    Soll ((Get-PicsNamen $r.a).Count -eq 0) "Nein: nichts kopiert"

    [AcssTest.Dialog]::Reset('Yes')
    Copy-Pics
    Soll ((Get-PicsNamen $r.a).Count -eq 31) "Ja: alle kopiert"

    New-Bild (Join-Path $quelle 'noch-eins.jpg') (Get-Date)
    [AcssTest.Dialog]::Reset('No')
    Copy-Pics
    Soll ([AcssTest.Dialog]::Texte.Count -eq 0 -and (Get-PicsNamen $r.a).Count -eq 32) "einzelnes neues Foto: ohne Rueckfrage"
}

Test "Copy-Pics: ungeeigneter Ordner - nichts wird kopiert" {
    $r = New-TestRepos
    $quelle = New-FotoQuelle
    New-Bild (Join-Path $quelle 'urlaub.jpg') (Get-Date)
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    function Test-SpielfotoOrdner { 'Das ist dein Windows-Ordner "Bilder".' }
    Copy-Pics
    Soll (-not (Test-Path -LiteralPath (Join-Path $r.a 'pics'))) "nichts kopiert"
    Soll ((Get-ProtokollText) -match 'ungeeignet: Das ist dein Windows-Ordner') "Grund im Protokoll"
}

Test "Spielfotos-Ordner: die eigenen Windows-Ordner werden abgelehnt" -NurWindows {
    $bilder = [Environment]::GetFolderPath('MyPictures')
    Soll ((Test-SpielfotoOrdner $bilder) -match '^Das ist dein Windows-Ordner "Bilder"') "Windows-Ordner Bilder"
    Soll ((Test-SpielfotoOrdner ($bilder + '\')) -match 'Bilder') "auch mit Schraegstrich am Ende"
    Soll ((Test-SpielfotoOrdner $env:USERPROFILE) -eq 'Das ist dein Benutzerordner.') "Benutzerordner"
    Soll ((Test-SpielfotoOrdner (Split-Path -Parent $env:USERPROFILE)) -match '^Darin liegt') "Ordner, der sie enthaelt"
    Soll ((Test-SpielfotoOrdner ([Environment]::GetFolderPath('Desktop'))) -match 'Desktop') "Desktop"
    Soll ((Test-SpielfotoOrdner ([IO.Path]::GetPathRoot($env:SystemRoot))) -match 'Laufwerk') "ganzes Laufwerk"
    Soll ((Test-SpielfotoOrdner (Join-Path $bilder 'Dolphin')) -eq '') "Unterordner bleibt erlaubt"
    Soll ((Test-SpielfotoOrdner (Join-Path $script:TestWurzel 'Dolphin\User\Load\WiiSDSync')) -eq '') "Ordner von Dolphin passt"
    Soll ((Test-SpielfotoOrdner '') -eq '') "leer: kein Einwand"
}

Test "Abgleich nach gescheitertem Hochladen: die Fotos gehen nicht verloren" {
    $r = New-TestRepos -MitStart
    $quelle = New-FotoQuelle
    New-Bild (Join-Path $quelle 'a.png') (Get-Date).AddHours(-1)
    New-Bild (Join-Path $quelle 'b.png') (Get-Date).AddHours(-1)
    $script:cfg.RepoPath = $r.a; $script:cfg.PicsFolder = $quelle
    Copy-Pics
    # Der Server nimmt nichts an - wie bei einem zu grossen Push oder einer Zeitueberschreitung
    $haken = Join-Path $r.Server 'hooks/pre-receive'
    [IO.File]::WriteAllText($haken, "#!/bin/sh`nexit 1`n")
    Soll ((Invoke-GitCommitPush 'Session beendet + Spielstand (Anna)').Code -ne 0) "Hochladen gescheitert"

    [AcssTest.Dialog]::Reset('Yes')
    Sync-Remote
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 1 -and $t[0] -match 'darunter 2 Foto' -and $t[0] -match 'die Fotos nicht') "Rueckfrage nennt die Fotos (war: $($t -join ' | '))"
    Soll ((Get-PicsNamen $r.a).Count -eq 2) "Fotos liegen weiter im gemeinsamen Ordner"
    Soll ((Invoke-G $r.a rev-parse HEAD) -eq (Invoke-G $r.a rev-parse origin/main)) "sonst Stand vom Server"

    [AcssTest.Dialog]::Reset('Yes')
    Sync-Remote
    Soll ([AcssTest.Dialog]::Texte.Count -eq 0) "beim naechsten Abgleich keine Frage mehr"
    Soll ((Get-PicsNamen $r.a).Count -eq 2) "Fotos immer noch da"

    Remove-Item -LiteralPath $haken -Force
    Soll ((Invoke-GitCommitPush 'heartbeat: Anna').Code -eq 0) "Server nimmt wieder an"
    $oben = @((& git --git-dir $r.Server ls-tree -r --name-only main -- pics 2>$null) | Where-Object { $_ })
    Soll ($oben.Count -eq 2) "das naechste Hochladen bringt die Fotos mit (auf dem Server: $($oben.Count))"
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
