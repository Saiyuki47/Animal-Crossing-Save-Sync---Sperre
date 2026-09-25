# Spielzeit-Statistik: Sitzungen aus dem Git-Verlauf, Wochen, Rekorde, Serien.
# Zeiten liegen bewusst mittags (UTC), damit das Datum in jeder Zeitzone
# zwischen -11 und +11 Stunden dasselbe bleibt.

# Zeile "Zeitstempel<TAB>Betreff" wie aus "git log --format=%ct%x09%s".
function Z {
    param([string]$Zeit, [string]$Betreff)
    $t = [datetime]::SpecifyKind([datetime]::Parse($Zeit, [Globalization.CultureInfo]::InvariantCulture), 'Utc')
    $epoche = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    return ("{0}`t{1}" -f [long]($t - $epoche).TotalSeconds, $Betreff)
}
function Sitzung {
    param([string]$Spieler, [string]$Start, [int]$Minuten)
    $s = [datetime]::SpecifyKind([datetime]::Parse($Start, [Globalization.CultureInfo]::InvariantCulture), 'Utc')
    return [pscustomobject]@{ Spieler = $Spieler; Start = $s; Ende = $s.AddMinutes($Minuten); Sekunden = $Minuten * 60.0; Laeuft = $false }
}
function Tag { param([string]$T) return [datetime]::ParseExact($T, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }

Test "Verlauf: saubere Sitzung, Absturz, Uebernahme, Abbruch, Freigabe" {
    $zeilen = @(
        (Z '2026-09-01 12:00:00' 'Repo-Setup durch AC-SaveSync'),
        # 1) sauber: 12:00 - 13:30
        (Z '2026-09-01 12:00:00' 'lock: Anna'),
        (Z '2026-09-01 12:01:00' 'heartbeat: Anna'),
        (Z '2026-09-01 13:29:00' 'heartbeat: Anna'),
        (Z '2026-09-01 13:30:00' 'Session beendet + Spielstand (Anna)'),
        # 2) Absturz: letztes Lebenszeichen 12:40, danach uebernimmt Max
        (Z '2026-09-02 12:00:00' 'lock: Anna'),
        (Z '2026-09-02 12:40:00' 'heartbeat: Anna'),
        (Z '2026-09-02 13:00:00' 'lock: Max'),
        (Z '2026-09-02 13:45:00' 'Session beendet + Spielstand (Max)'),
        # 3) abgebrochener Start - keine Sitzung
        (Z '2026-09-03 12:00:00' 'lock: Max'),
        (Z '2026-09-03 12:00:05' 'unlock (Start abgebrochen): Max'),
        # 4) zu kurz (unter einer Minute) - keine Sitzung
        (Z '2026-09-04 12:00:00' 'lock: Anna'),
        (Z '2026-09-04 12:00:30' 'Session beendet + Spielstand (Anna)'),
        # 5) von Hand freigegeben: zaehlt bis zum letzten Lebenszeichen
        (Z '2026-09-05 12:00:00' 'lock: Max'),
        (Z '2026-09-05 12:20:00' 'heartbeat: Max'),
        (Z '2026-09-05 15:00:00' 'force-unlock durch Anna'),
        (Z '2026-09-05 15:05:00' 'Foto geloescht: x.png (Anna)')
    )
    $s = @(ConvertFrom-GitVerlauf -Zeilen $zeilen)
    Soll ($s.Count -eq 4) "vier Sitzungen (waren $($s.Count))"
    Soll ($s[0].Spieler -eq 'Anna' -and $s[0].Sekunden -eq 5400) "sauber: 90 Minuten"
    Soll ($s[1].Spieler -eq 'Anna' -and $s[1].Sekunden -eq 2400) "Absturz: bis zum letzten Lebenszeichen (40 Minuten)"
    Soll ($s[2].Spieler -eq 'Max' -and $s[2].Sekunden -eq 2700) "Uebernahme: Max 45 Minuten"
    Soll ($s[3].Spieler -eq 'Max' -and $s[3].Sekunden -eq 1200) "Freigabe von Hand: bis zum letzten Lebenszeichen (20 Minuten)"
    Soll (-not ($s | Where-Object Laeuft)) "keine laeuft mehr"
}

Test "Verlauf: offene Sitzung am Schluss laeuft noch (oder eben nicht)" {
    $zeilen = @((Z '2026-09-10 12:00:00' 'lock: Anna'), (Z '2026-09-10 12:30:00' 'heartbeat: Anna'))
    $jetzt = [datetime]::SpecifyKind([datetime]'2026-09-10 12:35:00', 'Utc')
    $s = @(ConvertFrom-GitVerlauf -Zeilen $zeilen -Jetzt $jetzt)
    Soll ($s.Count -eq 1 -and $s[0].Laeuft -and $s[0].Sekunden -eq 1800) "laeuft (letztes Lebenszeichen vor 5 Minuten)"
    $spaeter = $jetzt.AddHours(3)
    $s = @(ConvertFrom-GitVerlauf -Zeilen $zeilen -Jetzt $spaeter)
    Soll (-not $s[0].Laeuft) "nach drei Stunden ohne Lebenszeichen nicht mehr"
    Soll (@(ConvertFrom-GitVerlauf -Zeilen @('', 'kaputt', "x`ty")).Count -eq 0) "unbrauchbare Zeilen werden uebersprungen"
}

Test "Kalenderwoche nach ISO 8601 (auch um den Jahreswechsel)" {
    $faelle = @(
        @{ T = '2026-09-25'; W = 39 }, @{ T = '2026-09-21'; W = 39 }, @{ T = '2026-09-27'; W = 39 },
        @{ T = '2024-12-30'; W = 1 }, @{ T = '2021-01-03'; W = 53 }, @{ T = '2026-01-01'; W = 1 },
        @{ T = '2027-01-01'; W = 53 }
    )
    foreach ($f in $faelle) {
        $w = Get-IsoWoche (Tag $f.T)
        Soll ($w -eq $f.W) ("{0}: KW {1} (war {2})" -f $f.T, $f.W, $w)
    }
    Soll ((Get-Wochenbeginn (Tag '2026-09-25')) -eq (Tag '2026-09-21')) "Woche beginnt am Montag"
    Soll ((Get-Wochenbeginn (Tag '2026-09-21')) -eq (Tag '2026-09-21')) "Montag bleibt Montag"
    Soll ((Get-Wochenbeginn (Tag '2026-09-27')) -eq (Tag '2026-09-21')) "Sonntag gehoert zur Woche davor"
}

Test "Spieltage am Stueck: Rekord und aktuelle Reihe" {
    $tage = @('2026-09-01', '2026-09-02', '2026-09-03', '2026-09-05', '2026-09-06', '2026-09-07', '2026-09-08', '2026-09-10') | ForEach-Object { Tag $_ }
    $s = Get-Serie -Tage $tage -Heute (Tag '2026-09-11')
    Soll ($s.Laengste -eq 4 -and $s.Von -eq (Tag '2026-09-05') -and $s.Bis -eq (Tag '2026-09-08')) "Rekord 4 Tage (05.-08.)"
    Soll ($s.Aktuell -eq 1) "heute noch nicht gespielt, gestern schon: Reihe von 1 laeuft weiter"
    $s = Get-Serie -Tage $tage -Heute (Tag '2026-09-10')
    Soll ($s.Aktuell -eq 1) "heute gespielt: 1"
    $s = Get-Serie -Tage $tage -Heute (Tag '2026-09-12')
    Soll ($s.Aktuell -eq 0) "vorgestern zuletzt: Reihe gerissen"
    $s = Get-Serie -Tage @() -Heute (Tag '2026-09-12')
    Soll ($s.Laengste -eq 0 -and $s.Aktuell -eq 0) "ohne Spieltage: nichts"
    Soll ((Format-Serie $s) -eq '-') "ohne Spieltage: Strich"
}

Test "Auswertung: Wochen, laengste Sitzung, bester Tag, je Spieler" {
    $sitzungen = @(
        (Sitzung 'Anna' '2026-09-21 12:00:00' 90),   # KW 39
        (Sitzung 'Max' '2026-09-22 12:00:00' 30),    # KW 39
        (Sitzung 'Anna' '2026-09-22 14:00:00' 60),   # KW 39
        (Sitzung 'Max' '2026-09-15 12:00:00' 200),   # KW 38 - laengste
        (Sitzung 'Anna' '2026-07-28 12:00:00' 45)    # KW 31 - ausserhalb der 8 Wochen (39 bis 32)
    )
    $a = Get-SpielzeitAuswertung -Sitzungen $sitzungen -Heute (Tag '2026-09-25') -Wochen 8
    Soll ($a.Anzahl -eq 5 -and ($a.Spieler -join ',') -eq 'Anna,Max') "5 Sitzungen, Spieler Anna und Max"
    Soll ($a.Wochen.Count -eq 8 -and $a.Wochen[0].Woche -eq 39 -and $a.Wochen[1].Woche -eq 38) "8 Wochen, neueste zuerst (KW 39, 38, ...)"
    Soll ($a.Wochen[0].Von -eq (Tag '2026-09-21') -and $a.Wochen[0].Bis -eq (Tag '2026-09-27')) "KW 39 = 21.09. bis 27.09."
    Soll ($a.Wochen[0].JeSpieler['Anna'] -eq 150 * 60 -and $a.Wochen[0].JeSpieler['Max'] -eq 30 * 60) "KW 39: Anna 150 min, Max 30 min"
    Soll ($a.Wochen[0].Sekunden -eq 180 * 60) "KW 39 zusammen 180 min"
    Soll ($a.Wochen[1].Sekunden -eq 200 * 60) "KW 38: 200 min"
    Soll ($a.Wochen[7].Woche -eq 32 -and $a.Wochen[7].Sekunden -eq 0) "aelteste der 8 Wochen ist KW 32, KW 31 liegt ausserhalb"
    Soll ($a.Laengste.Spieler -eq 'Max' -and $a.Laengste.Sekunden -eq 200 * 60) "laengste Sitzung: Max, 200 min"
    Soll ($a.BesterTag.Tag -eq (Tag '2026-09-15') -and $a.BesterTag.Sekunden -eq 200 * 60) "bester Tag: 15.09. mit 200 min"
    $anna = $a.JeSpieler | Where-Object Spieler -eq 'Anna'
    Soll ($anna.Sitzungen -eq 3 -and $anna.Sekunden -eq 195 * 60 -and $anna.Schnitt -eq 65 * 60) "Anna: 3 Sitzungen, 195 min, Schnitt 65 min"
    Soll ($anna.Serie.Laengste -eq 2 -and $anna.Serie.Aktuell -eq 0) "Anna: Rekord 2 Tage am Stueck, aktuell gerissen"
    Soll ($anna.Letzte.Start.Day -eq 22) "Anna: letzte Sitzung am 22."
    Soll ($a.Serie.Laengste -eq 2) "zusammen: 2 Tage am Stueck (21./22.)"
    Soll ($a.Erste.Spieler -eq 'Anna' -and $a.Erste.Start.Month -eq 7) "erste Sitzung im Juli (zaehlt, auch ausserhalb der 8 Wochen)"
    $sw = @($a.SchnittWochen)
    Soll ($sw.Count -eq 7 -and $sw[0].Woche -eq 38 -and $sw[-1].Woche -eq 32) "Schnitt ueber KW 32 bis 38: ohne die laufende KW 39 (waren $($sw.Count))"
    Soll ([math]::Abs($a.SchnittWoche - 200 * 60 / 7) -lt 0.01) "Schnitt: 200 min auf 7 Wochen verteilt"
}

Test "Schnitt pro Woche: erst ab der Woche der ersten Sitzung, ohne die laufende" {
    $heute = Tag '2026-09-25'   # Freitag in KW 39
    $a = Get-SpielzeitAuswertung -Heute $heute -Sitzungen @(
        (Sitzung 'Anna' '2026-09-11 12:00:00' 60),    # KW 37 (Freitag) - erste Sitzung
        (Sitzung 'Max' '2026-09-16 12:00:00' 120),    # KW 38
        (Sitzung 'Anna' '2026-09-24 12:00:00' 600)    # KW 39 - laeuft noch, zaehlt nicht
    )
    $sw = @($a.SchnittWochen)
    Soll ($sw.Count -eq 2 -and $sw[0].Woche -eq 38 -and $sw[1].Woche -eq 37) "KW 37 und 38 (nicht die leeren Wochen davor)"
    Soll ($a.SchnittWoche -eq 90 * 60) "Schnitt 90 min (war $($a.SchnittWoche / 60) min)"

    $nurDieseWoche = Get-SpielzeitAuswertung -Heute $heute -Sitzungen @((Sitzung 'Anna' '2026-09-22 12:00:00' 60))
    Soll (@($nurDieseWoche.SchnittWochen).Count -eq 0 -and $null -eq $nurDieseWoche.SchnittWoche) "erst in dieser Woche angefangen: noch kein Schnitt"
    $leer = Get-SpielzeitAuswertung -Heute $heute -Sitzungen @()
    Soll ($null -eq $leer.SchnittWoche) "ohne Sitzungen: kein Schnitt"
}

Test "Auswertung ohne Sitzungen bricht nicht ab" {
    $a = Get-SpielzeitAuswertung -Sitzungen @() -Heute (Tag '2026-09-25')
    Soll ($a.Anzahl -eq 0 -and $a.Wochen.Count -eq 8 -and $null -eq $a.Laengste -and $null -eq $a.BesterTag) "leere Auswertung"
}

Test "Sitzung ueber Mitternacht zaehlt fuer beide Tage" {
    # 23:30 bis 00:30 Ortszeit - unabhaengig von der Zeitzone des Testrechners
    $start = (Get-Date).Date.AddDays(-3).AddHours(23).AddMinutes(30).ToUniversalTime()
    $s = [pscustomobject]@{ Spieler = 'Anna'; Start = $start; Ende = $start.AddHours(1); Sekunden = 3600.0; Laeuft = $false }
    $tage = @(Get-Spieltage @($s))
    Soll ($tage.Count -eq 2) "zwei Spieltage (waren $($tage.Count))"
}

Test "Balken: eine Skala, beginnt bei null, kurze Wochen bleiben sichtbar" {
    $voll = [string][char]0x2588
    Soll ((Format-Balken 100 100) -eq ($voll * 16)) "Hoechstwert = volle Breite"
    Soll ((Format-Balken 50 100) -eq ($voll * 8)) "halber Wert = halbe Breite"
    Soll ((Format-Balken 1 1000) -eq $voll) "winziger Wert: mindestens ein Block"
    Soll ((Format-Balken 0 100) -eq '') "nichts gespielt: kein Balken"
    Soll ((Format-Balken 5 0) -eq '') "ohne Hoechstwert: kein Balken"
    Soll ((Format-Balken 100 100 12) -eq ($voll * 12) -and (Format-Balken 50 100 12) -eq ($voll * 6)) "Breite waehlbar (passend zur Spalte)"
}

Test "Sitzungen aus einem echten Git-Verlauf (eigener und Server-Stand)" {
    $r = New-TestRepos -Klone a, b
    $script:cfg.RepoPath = $r.a
    function Add-CommitAm {
        param([string]$Klon, [string]$Zeit, [string]$Betreff)
        $env:GIT_COMMITTER_DATE = $Zeit; $env:GIT_AUTHOR_DATE = $Zeit
        try { Invoke-G $Klon commit -q --allow-empty -m $Betreff | Out-Null }
        finally { Remove-Item Env:GIT_COMMITTER_DATE, Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue }
    }
    Add-CommitAm $r.a '2026-09-01T12:00:00Z' 'lock: Anna'
    Add-CommitAm $r.a '2026-09-01T12:30:00Z' 'heartbeat: Anna'
    Add-CommitAm $r.a '2026-09-01T13:00:00Z' 'Session beendet + Spielstand (Anna)'
    Invoke-G $r.a push -q origin main | Out-Null
    # Max spielt danach - sein Stand liegt nur auf dem Server (bei a nur geholt)
    Invoke-G $r.b pull -q origin main | Out-Null
    Add-CommitAm $r.b '2026-09-02T12:00:00Z' "lock: J$([char]0xF6)rg"
    Add-CommitAm $r.b '2026-09-02T12:45:00Z' "Session beendet + Spielstand (J$([char]0xF6)rg)"
    Invoke-G $r.b push -q origin main | Out-Null
    Invoke-G $r.a fetch -q origin | Out-Null

    $s = @(Get-Sitzungen)
    Soll ($s.Count -eq 2) "zwei Sitzungen - auch die nur geholte (waren $($s.Count))"
    Soll ($s[0].Spieler -eq 'Anna' -and $s[0].Sekunden -eq 3600) "Anna 60 Minuten"
    Soll ($s[1].Spieler -eq "J$([char]0xF6)rg" -and $s[1].Sekunden -eq 2700) "Name mit Umlaut, 45 Minuten (war '$($s[1].Spieler)')"
}
