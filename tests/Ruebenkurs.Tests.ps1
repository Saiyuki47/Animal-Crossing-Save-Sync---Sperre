# Ruebenkurs: Einschaetzung der Muster, Empfehlung, Daten im gemeinsamen
# Repo (Zusammenfuehren, Hochladen ohne Sperre, Einmischen beim Push) und
# der Abschnitt in der README.

# Wuerfelt eine Woche nach den Regeln der vier Muster aus. Bewusst unabhaengig
# von der Auswertung geschrieben (direkt nach der Beschreibung der Muster) -
# so faellt auf, wenn die Auswertung einen moeglichen Verlauf nicht kennt.
function New-RkTestWoche {
    param([System.Random]$Zufall, [int]$Muster = -1)
    $u = { param($a, $b) $a + ($b - $a) * $Zufall.NextDouble() }
    $preis = { param($f) [int][math]::Floor($f * $grund + 0.99999) }
    $grund = $Zufall.Next(90, 111)
    if ($Muster -lt 0) { $Muster = $Zufall.Next(0, 4) }
    $p = New-Object System.Collections.ArrayList
    $fallend = {
        param($anzahl, $a, $b, $s1, $s2)
        $f = & $u $a $b
        for ($i = 0; $i -lt $anzahl; $i++) { [void]$p.Add((& $preis $f)); $f -= (& $u $s1 $s2) }
    }
    switch ($Muster) {
        0 {
            $h1 = $Zufall.Next(0, 7); $d1 = if ($Zufall.Next(0, 2)) { 3 } else { 2 }
            $h23 = 7 - $h1; $h3 = $Zufall.Next(0, $h23)
            for ($i = 0; $i -lt $h1; $i++) { [void]$p.Add((& $preis (& $u 0.9 1.4))) }
            & $fallend $d1 0.6 0.8 0.04 0.10
            for ($i = 0; $i -lt ($h23 - $h3); $i++) { [void]$p.Add((& $preis (& $u 0.9 1.4))) }
            & $fallend (5 - $d1) 0.6 0.8 0.04 0.10
            for ($i = 0; $i -lt $h3; $i++) { [void]$p.Add((& $preis (& $u 0.9 1.4))) }
        }
        1 {
            $d = $Zufall.Next(1, 8)
            & $fallend $d 0.85 0.9 0.03 0.05
            foreach ($ab in @(0.9, 1.4), @(1.4, 2.0), @(2.0, 6.0), @(1.4, 2.0), @(0.9, 1.4)) { [void]$p.Add((& $preis (& $u $ab[0] $ab[1]))) }
            while ($p.Count -lt 12) { [void]$p.Add((& $preis (& $u 0.4 0.9))) }
        }
        2 { & $fallend 12 0.85 0.9 0.03 0.05 }
        3 {
            $d = $Zufall.Next(0, 8)
            & $fallend $d 0.4 0.9 0.03 0.05
            [void]$p.Add((& $preis (& $u 0.9 1.4))); [void]$p.Add((& $preis (& $u 0.9 1.4)))
            $r = & $u 1.4 2.0
            [void]$p.Add((& $preis (& $u 1.4 $r)) - 1); [void]$p.Add((& $preis $r)); [void]$p.Add((& $preis (& $u 1.4 $r)) - 1)
            if ($p.Count -lt 12) { & $fallend (12 - $p.Count) 0.4 0.9 0.03 0.05 }
        }
    }
    return [pscustomobject]@{ Muster = $Muster; Grund = $grund; Preise = $p.ToArray() }
}

function Get-RkTestPreise {
    param([object[]]$Alle, [int]$Anzahl)
    $p = @($null) * 12
    for ($i = 0; $i -lt $Anzahl; $i++) { $p[$i] = $Alle[$i] }
    return , $p
}

Test "Einschaetzung: in 1500 ausgewuerfelten Wochen stimmen Muster und Spannen immer" {
    $z = New-Object System.Random 20260925
    $fehler = @()
    for ($n = 0; $n -lt 1500 -and $fehler.Count -lt 3; $n++) {
        $w = New-RkTestWoche $z
        $k = $z.Next(0, 12)
        $grund = if ($n % 4 -eq 0) { 0 } else { $w.Grund }      # jede vierte Woche ohne Sonntagspreis
        $a = Get-RkAuswertung -Grundpreis $grund -Preise (Get-RkTestPreise $w.Preise $k)
        $was = "Muster {0}, Grund {1}, Preise {2}, bekannt {3}" -f $w.Muster, $w.Grund, ($w.Preise -join ','), $k
        if (-not $a.Passt -or $a.Toleranz -ne 0) { $fehler += "passt nicht: $was"; continue }
        if ($a.Muster[$w.Muster] -le 0) { $fehler += "wahres Muster ausgeschlossen: $was" }
        for ($i = $k; $i -lt 12; $i++) {
            if ($w.Preise[$i] -lt $a.Min[$i] -or $w.Preise[$i] -gt $a.Max[$i]) {
                $fehler += ("Halbtag {0}: {1} nicht in {2}-{3}: {4}" -f $i, $w.Preise[$i], $a.Min[$i], $a.Max[$i], $was); break
            }
        }
    }
    Soll ($fehler.Count -eq 0) ("keine Abweichung (" + ($fehler -join ' | ') + ")")
}

Test "Einschaetzung: Wahrscheinlichkeiten stimmen mit der Haeufigkeit ueberein" {
    # Wochen nach der langfristigen Verteilung auswuerfeln, die ersten Preise
    # zeigen - und pruefen, dass "70 %" auch etwa in 70 % der Faelle stimmt.
    $z = New-Object System.Random 4711
    $vert = Get-RkGrundverteilung
    $summeP = 0.0; $treffer = 0; $anzahl = 0
    for ($n = 0; $n -lt 800; $n++) {
        $r = $z.NextDouble(); $m = 3; $acc = 0.0
        for ($i = 0; $i -lt 4; $i++) { $acc += $vert[$i]; if ($r -lt $acc) { $m = $i; break } }
        $w = New-RkTestWoche $z $m
        $a = Get-RkAuswertung -Grundpreis $w.Grund -Preise (Get-RkTestPreise $w.Preise $z.Next(1, 7))
        for ($j = 0; $j -lt 4; $j++) {
            if ($a.Muster[$j] -ge 0.3 -and $a.Muster[$j] -lt 0.9) {
                $anzahl++; $summeP += $a.Muster[$j]; if ($j -eq $w.Muster) { $treffer++ }
            }
        }
    }
    $erwartet = $summeP / $anzahl; $echt = $treffer / $anzahl
    Soll ($anzahl -gt 200) "genug unsichere Faelle ($anzahl)"
    Soll ([math]::Abs($erwartet - $echt) -lt 0.06) ("vorhergesagt {0:P1}, eingetroffen {1:P1}" -f $erwartet, $echt)
}

Test "Einschaetzung: eindeutige Faelle, Tippfehler, Toleranz" {
    Soll ([ACSS.Ruebenkurs]::AnzahlVerlaeufe() -eq 72) "72 moegliche Verlaeufe"
    $leer = Get-RkAuswertung -Grundpreis 100 -Preise (@($null) * 12)
    $g = Get-RkGrundverteilung
    Soll ($leer.Passt -and [math]::Abs($leer.Muster[1] - $g[1]) -lt 1e-9) "ohne Preise: die Grundverteilung"
    Soll ($leer.Max[5] -eq 600 -and $leer.Min[0] -eq 40) "Spanne ohne Preise: 40 bis 600 bei Grundpreis 100 (war $($leer.Min[0])-$($leer.Max[5]))"

    # Grosse Spitze: fallend, dann 1,4x - das kann nur die grosse Spitze sein
    $a = Get-RkAuswertung -Grundpreis 100 -Preise (@(88, 85, 120, 180) + @($null) * 8)
    Soll ($a.Passt -and $a.Muster[1] -gt 0.999) ("eindeutig grosse Spitze (war {0:P1})" -f $a.Muster[1])
    Soll ($a.Min[4] -eq 200 -and $a.Max[4] -eq 600) "Spitze am Mi vormittags: 200 bis 600 (war $($a.Min[4])-$($a.Max[4]))"

    # Fallend: zwoelf fallende Preise passen nur zum fallenden Muster
    $f = Get-RkAuswertung -Grundpreis 100 -Preise @(90, 86, 82, 78, 74, 70, 66, 62, 58, 54, 50, 46)
    Soll ($f.Passt -and $f.Muster[2] -gt 0.999) ("eindeutig fallend (war {0:P1})" -f $f.Muster[2])

    # Tippfehler: 900 Sternis gibt es nicht
    $t = Get-RkAuswertung -Grundpreis 100 -Preise (@(900) + @($null) * 11)
    Soll (-not $t.Passt -and $t.Min[3] -eq -1) "900 am Montag passt zu nichts"
    # Knapp daneben: mit einem Stern Toleranz passt es noch
    # (moeglich sind am Montag 40 bis 140 Sternis)
    $k = Get-RkAuswertung -Grundpreis 100 -Preise (@(141) + @($null) * 11)
    Soll ($k.Passt -and $k.Toleranz -eq 1) "141 bei Grundpreis 100 am Montag: nur mit Toleranz 1 (war Passt=$($k.Passt), Toleranz $($k.Toleranz))"
}

Test "Vorwoche: erkannt aus ihren Preisen oder von Hand gewaehlt" {
    $d = New-RkDaten
    $f = @(90, 86, 82, 78, 74, 70, 66, 62, 58, 54, 50, 46)
    Set-RkWert $d '2026-09-13' 'sonntag' '' 100
    for ($i = 0; $i -lt 12; $i++) { Set-RkWert $d '2026-09-13' 'preise' "$i" $f[$i] }
    $v = Get-RkVorwissen $d '2026-09-20'
    $soll = (Get-RkUebergang)[2]
    Soll ([math]::Abs($v.Werte[1] - $soll[1]) -lt 0.001) ("nach fallender Vorwoche: grosse Spitze {0:P1} (soll 45 %)" -f $v.Werte[1])
    Soll ($v.Text -match 'wahrscheinlich Fallend') "Anzeige nennt die Vorwoche (war '$($v.Text)')"

    Set-RkWert $d '2026-09-20' 'vorwoche' '' '1'
    $h = Get-RkVorwissen $d '2026-09-20'
    Soll ([math]::Abs($h.Werte[1] - 0.05) -lt 1e-9 -and $h.Text -match 'von Hand') "von Hand: nach grosser Spitze nur 5 % grosse Spitze"
    Set-RkWert $d '2026-09-20' 'vorwoche' '' 'unbekannt'
    Soll ([math]::Abs((Get-RkVorwissen $d '2026-09-20').Werte[0] - (Get-RkGrundverteilung)[0]) -lt 1e-9) "unbekannt: Grundverteilung"
    Soll ((Get-RkVorwissen $d '2026-10-04').Text -match 'keine Preise') "Vorwoche ohne Preise: Grundverteilung"
}

Test "Wochen und Halbtage: Sonntag, 12 Uhr, Samstagabend" {
    Soll ((Get-RkWochenKey (Get-Date '2026-09-20 09:00')) -eq '2026-09-20') "Sonntag gehoert zu seiner Woche"
    Soll ((Get-RkWochenKey (Get-Date '2026-09-26 23:00')) -eq '2026-09-20') "Samstag gehoert zur Woche davor"
    $w = '2026-09-20'
    Soll ((Get-RkHalbtag (Get-Date '2026-09-20 11:00') $w) -eq -1) "Sonntag: noch kein Preis"
    Soll ((Get-RkHalbtag (Get-Date '2026-09-21 11:59') $w) -eq 0) "Mo 11:59: vormittags"
    Soll ((Get-RkHalbtag (Get-Date '2026-09-21 12:00') $w) -eq 1) "Mo 12:00: nachmittags"
    Soll ((Get-RkHalbtag (Get-Date '2026-09-26 23:30') $w) -eq 11) "Sa abends: letzter Halbtag"
    Soll ((Get-RkHalbtag (Get-Date '2026-09-27 08:00') $w) -eq 12) "naechster Sonntag: Woche vorbei"
    Soll ((Get-RkHalbtagName 5) -eq 'Mi nachmittags') "Name des Halbtags"
}

Test "Empfehlung: verkaufen, warten, letzte Gelegenheit, passt nicht" {
    # Grosse Spitze erreicht (Mi vormittags 480 bei 100): verkaufen
    $p = @(88, 85, 120, 180, 480) + @($null) * 7
    $a = Get-RkAuswertung -Grundpreis 100 -Preise $p
    $e = Get-RkEmpfehlung $a $p 4 100
    Soll ($e.Titel -eq 'Jetzt verkaufen') "Spitze erreicht: verkaufen (war '$($e.Titel)': $($e.Text))"

    # Anstieg hat begonnen (Di vormittags 120 nach Fallen): die Spitze kommt noch
    $p = @(88, 85, 120) + @($null) * 9
    $a = Get-RkAuswertung -Grundpreis 100 -Preise $p
    $e = Get-RkEmpfehlung $a $p 2 100
    Soll ($e.Titel -eq 'Warten' -and $e.Chance -gt 0.9) ("vor der Spitze: warten (war '{0}', {1:P0})" -f $e.Titel, $e.Chance)
    Soll ($e.Text -match 'Grosse Spitze noch moeglich') "nennt die kommende Spitze ($($e.Text))"

    $f = @(90, 86, 82, 78, 74, 70, 66, 62, 58, 54, 50, 46)
    $a = Get-RkAuswertung -Grundpreis 100 -Preise $f
    Soll ((Get-RkEmpfehlung $a $f 11 100).Titel -eq 'Heute verkaufen') "Sa nachmittags: letzte Gelegenheit"
    $e = Get-RkEmpfehlung $a $f 5 100
    Soll ($e.Titel -eq 'Jetzt verkaufen' -and $e.Text -match 'Gewinn wird es') "fallender Kurs: verkaufen, kein Gewinn mehr ($($e.Text))"

    $leer = @($null) * 12
    $a = Get-RkAuswertung -Grundpreis 100 -Preise $leer
    Soll ((Get-RkEmpfehlung $a $leer 3 100).Titel -eq 'Preis von jetzt eintragen') "ohne Preis von jetzt: bitte eintragen"
    Soll ((Get-RkEmpfehlung $a $leer -1 100).Titel -eq 'Heute ist Sonntag') "Sonntag"
    $x = @(900) + @($null) * 11
    Soll ((Get-RkEmpfehlung (Get-RkAuswertung -Grundpreis 100 -Preise $x) $x 0 100).Titel -match 'keinem bekannten Muster') "passt nicht"
}

Test "Zusammenfuehren: neuerer Eintrag gewinnt, geloeschte Werte bleiben geloescht" {
    $a = New-RkDaten; $b = New-RkDaten
    $script:cfg.PlayerName = 'Anna'
    Set-RkWert $a '2026-09-20' 'preise' '0' 95
    Set-RkWert $a '2026-09-20' 'kauf' 'Anna' 400
    Start-Sleep -Milliseconds 20
    $script:cfg.PlayerName = 'Max'
    Set-RkWert $b '2026-09-20' 'preise' '0' 96          # spaeter korrigiert
    Set-RkWert $b '2026-09-20' 'preise' '1' 110
    Set-RkWert $b '2026-09-20' 'kauf' 'Max' 300
    Set-RkWert $b '2026-09-13' 'sonntag' '' 99
    $m = Merge-RkDaten $a $b
    $w = Get-RkWoche $m '2026-09-20'
    Soll ((Get-RkWert $w.preise['0']) -eq 96 -and $w.preise['0'].von -eq 'Max') "neuerer Wert gewinnt, mit Namen"
    Soll ((Get-RkWert $w.preise['1']) -eq 110 -and (Get-RkWert $w.kauf['Anna']) -eq 400 -and (Get-RkWert $w.kauf['Max']) -eq 300) "Eintraege beider bleiben"
    Soll ((Get-RkWert (Get-RkWoche $m '2026-09-13').sonntag) -eq 99) "andere Woche kommt dazu"
    Soll ((ConvertTo-RkText (Merge-RkDaten $a $b)) -eq (ConvertTo-RkText (Merge-RkDaten $b $a))) "Reihenfolge egal"

    Start-Sleep -Milliseconds 20
    Set-RkWert $a '2026-09-20' 'preise' '1' $null          # Anna loescht den Wert
    $m2 = Merge-RkDaten $m $a
    Soll ($null -eq (Get-RkWert (Get-RkWoche $m2 '2026-09-20').preise['1'])) "geloescht bleibt geloescht"

    # Hin und zurueck als Text
    $zurueck = ConvertFrom-RkText (ConvertTo-RkText $m2)
    Soll ((ConvertTo-RkText $zurueck) -eq (ConvertTo-RkText $m2)) "Text hin und zurueck unveraendert"
    Soll ((ConvertFrom-RkText '{kaputt').wochen.Count -eq 0 -and (Get-ProtokollText) -match 'nicht lesbar') "kaputte Datei: leer, mit Hinweis"
}

Test "README: Abschnitt wird eingesetzt, ersetzt und laesst den Rest in Ruhe" {
    $d = New-RkDaten
    $jetzt = Get-Date '2026-09-23 10:00'
    Set-RkWert $d '2026-09-20' 'sonntag' '' 100
    Set-RkWert $d '2026-09-20' 'preise' '0' 88
    Set-RkWert $d '2026-09-20' 'kauf' 'Anna' 400
    $alt = "# Titel`r`n`r`n## Spielzeiten`r`nTabelle`r`n`r`n## Fotos (1)`r`n![a](pics/a.png)`r`n`r`n_Zuletzt aktualisiert: x_`r`n"
    $neu = Update-RkReadmeText $alt $d $jetzt
    Soll ($neu.IndexOf('benkurs') -gt $neu.IndexOf('Spielzeiten') -and $neu.IndexOf('benkurs') -lt $neu.IndexOf('## Fotos')) "zwischen Spielzeit und Fotos"
    Soll ($neu -match '\| vormittags \| 88 \| - \|' -and $neu -match 'Sigrids Preis: 100 Sternis' -and $neu -match 'Gekaufte Rueben: Anna: 400') "Tabelle, Preis, Kaeufe"
    Soll ($neu -match 'Einschaetzung: ') "mit Einschaetzung"
    Set-RkWert $d '2026-09-20' 'preise' '1' 84
    $nochmal = Update-RkReadmeText $neu $d $jetzt
    Soll (([regex]::Matches($nochmal, '<!-- ruebenkurs -->')).Count -eq 1 -and $nochmal -match '\| nachmittags \| 84 \|') "ersetzt statt verdoppelt"
    Soll ($nochmal.EndsWith("_Zuletzt aktualisiert: x_`r`n") -and $nochmal -match '!\[a\]\(pics/a\.png\)') "Rest unveraendert"
    Soll ((Update-RkReadmeText '' $d $jetzt) -match '^# Gemeinsamer') "ohne README: neue mit Titel"
}

# --- Hochladen und Einmischen mit echten Repos -------------------------------
function Get-RkServerDaten {
    param($Repos)
    return (ConvertFrom-RkText (& git --git-dir $Repos.Server show main:rueben.json 2>$null | Out-String))
}

Test "Hochladen ohne Sperre: nur rueben.json und README, eigener Ordner bleibt heil" {
    $r = New-TestRepos -Klone a, b -MitStart
    $script:cfg.RepoPath = $r.a
    $neu = New-RkDaten
    Set-RkWert $neu (Get-RkWochenKey (Get-Date)) 'sonntag' '' 97
    $e = Save-RkDaten $neu
    Soll ($e.Ok) "hochgeladen ($($e.Text))"
    Soll ((Get-RkWert (Get-RkWoche (Get-RkServerDaten $r) (Get-RkWochenKey (Get-Date))).sonntag) -eq 97) "Wert auf dem Server"
    $geaendert = (& git --git-dir $r.Server show --name-only --format= main 2>$null) -join ','
    Soll ($geaendert -eq 'README.md,rueben.json') "Commit enthaelt nur README.md und rueben.json (war $geaendert)"
    Soll ((& git --git-dir $r.Server show main:README.md 2>$null | Out-String) -match 'Sigrids Preis: 97') "README auf dem Server hat den Abschnitt"
    Soll ((& git --git-dir $r.Server log -1 --format=%s main) -eq 'Ruebenkurs: Anna') "Commit-Betreff"
    Soll (-not (Test-Path -LiteralPath (Get-RkOffenPfad))) "nichts mehr offen"
    Soll ((Invoke-G $r.a rev-parse HEAD) -eq (Invoke-G $r.a rev-parse origin/main)) "eigener Ordner vorgespult"
    Soll (Test-Path -LiteralPath (Join-Path $r.a 'rueben.json')) "rueben.json im eigenen Ordner"

    # Der Mitspieler traegt parallel etwas ein - beides bleibt erhalten
    $script:cfg.RepoPath = $r.b; $script:cfg.PlayerName = 'Max'
    $n2 = New-RkDaten; Set-RkWert $n2 (Get-RkWochenKey (Get-Date)) 'kauf' 'Max' 300
    Soll ((Save-RkDaten $n2).Ok) "Max laedt hoch, obwohl sein Ordner veraltet ist"
    $w = Get-RkWoche (Get-RkServerDaten $r) (Get-RkWochenKey (Get-Date))
    Soll ((Get-RkWert $w.sonntag) -eq 97 -and (Get-RkWert $w.kauf['Max']) -eq 300) "beide Eintraege auf dem Server"
}

Test "Ohne Verbindung: Eintraege bleiben auf dem PC und kommen spaeter nach" {
    $r = New-TestRepos -Klone a -MitStart
    $script:cfg.RepoPath = $r.a
    Invoke-G $r.a remote set-url origin (Join-Path $r.Wurzel 'weg.git') | Out-Null
    $neu = New-RkDaten; Set-RkWert $neu '2026-09-20' 'preise' '3' 123
    $e = Save-RkDaten $neu
    Soll (-not $e.Ok -and $e.Offen -and $e.Text -match 'naechsten Mal') "nicht hochgeladen, mit Hinweis ($($e.Text))"
    Soll (Test-Path -LiteralPath (Get-RkOffenPfad)) "in rueben-offen.json gemerkt"
    Soll ((Get-RkWert (Get-RkWoche (Get-RkDaten) '2026-09-20').preise['3']) -eq 123) "wird trotzdem angezeigt"
    Invoke-G $r.a remote set-url origin $r.Server | Out-Null
    Send-RkOffen
    Soll (-not (Test-Path -LiteralPath (Get-RkOffenPfad))) "beim naechsten Mal nachgeschickt"
    Soll ((Get-RkWert (Get-RkWoche (Get-RkServerDaten $r) '2026-09-20').preise['3']) -eq 123) "jetzt auf dem Server"
}

Test "Waehrend einer Sitzung: Eintraege des Mitspielers werden beim Herzschlag eingemischt" {
    $r = New-TestRepos -Klone a, b -MitStart
    # Anna spielt (haelt die Sperre) und hat selbst etwas eingetragen
    $script:cfg.RepoPath = $r.a
    $script:holdingLock = $true
    $key = Get-RkWochenKey (Get-Date)
    $eigen = New-RkDaten; Set-RkWert $eigen $key 'preise' '0' 91
    Write-TextDatei (Get-RkPfad) (ConvertTo-RkText $eigen)
    Set-Content -LiteralPath (Join-Path $r.a 'spielstand.txt') -Value 'Stand 1'

    # Max traegt waehrenddessen etwas ein (von seinem PC, ohne Sperre)
    $script:cfg.RepoPath = $r.b; $script:cfg.PlayerName = 'Max'; $script:holdingLock = $false
    $n = New-RkDaten; Set-RkWert $n $key 'preise' '1' 87
    Soll ((Save-RkDaten $n).Ok) "Max hat hochgeladen"

    # Annas Herzschlag: abgelehnt, eingemischt, dann angenommen
    $script:cfg.RepoPath = $r.a; $script:cfg.PlayerName = 'Anna'; $script:holdingLock = $true
    $p = Invoke-GitCommitPush 'heartbeat: Anna'
    Soll ($p.Code -eq 0) "Herzschlag angekommen ($($p.Text))"
    $w = Get-RkWoche (Get-RkServerDaten $r) $key
    Soll ((Get-RkWert $w.preise['0']) -eq 91 -and (Get-RkWert $w.preise['1']) -eq 87) "beide Preise auf dem Server"
    Soll ((& git --git-dir $r.Server show main:spielstand.txt 2>$null) -eq 'Stand 1') "Annas Spielstand auf dem Server"
    $betreffe = (& git --git-dir $r.Server log --format=%s main) -join '|'
    Soll ($betreffe -match 'heartbeat: Anna' -and $betreffe -match 'Ruebenkurs: Max') "Verlauf erhalten ($betreffe)"
    Soll ((& git --git-dir $r.Server show main:README.md 2>$null | Out-String) -match '\| vormittags \| 91') "README mit beiden Staenden"
}

Test "Echter Konflikt bleibt ein Konflikt (fremde Sperre wird nicht eingemischt)" {
    $r = New-TestRepos -Klone a, b -MitStart
    Push-Als $r.b 'PLAYING.lock' (New-SperrText 'Max')
    $script:cfg.RepoPath = $r.a
    Set-Content -LiteralPath (Join-Path $r.a 'PLAYING.lock') -Value (New-SperrText 'Anna')
    $p = Invoke-GitCommitPush 'lock: Anna'
    Soll ($p.Code -ne 0) "Push abgelehnt wie bisher"
    Soll ((& git --git-dir $r.Server show main:PLAYING.lock 2>$null | Out-String) -match 'Max') "Max' Sperre bleibt"
    Soll (-not (Test-Path -LiteralPath (Join-Path $r.a '.git/MERGE_HEAD'))) "kein halber Merge zurueckgelassen"
}
