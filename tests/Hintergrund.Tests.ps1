# Arbeit im Hintergrund: git, robocopy und Downloads frieren das Fenster
# nicht mehr ein. Geprueft wird, dass Argumente unveraendert ankommen, die
# Ausgabe richtig zurueckkommt, beim Warten Nachrichten abgearbeitet werden
# und nichts haengen bleibt (Zeitueberschreitung, Fehler, Zaehler).

# Liest die Ausgabe von "git rev-parse --sq-quote" zurueck in einzelne
# Argumente. Git setzt jedes Argument in '...'; wir verwenden keine ' darin.
function ConvertFrom-SqQuote {
    param([string]$Text)
    return @([regex]::Matches($Text, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
}

# Ein Programm, das etwa eine Sekunde laeuft.
function Get-KurzesProgramm {
    $d = Get-FakeDolphin
    if ($script:AufWindows) { return @{ Exe = $d.Exe; Args = @('-n', '2', '127.0.0.1') } }
    return @{ Exe = $d.Exe; Args = @('1') }
}

Test "Befehlszeile: schwierige Argumente kommen bei git unveraendert an" {
    $bs = [char]92   # Backslash
    $argumente = @(
        'einfach', 'mit Leerzeichen', 'Session beendet + Spielstand (Anna)',
        'an"fuehrung', ('C:' + $bs + 'Pfad mit Leerzeichen' + $bs), ('ende' + $bs + $bs),
        ('a' + $bs + '"b'), '', "J$([char]0xF6)rg", "tab`there", '100%', '-C'
    )
    $r = Invoke-GitRaw (@('rev-parse', '--sq-quote') + $argumente)
    Soll ($r.Code -eq 0) "git laeuft (Code $($r.Code): $($r.Text))"
    $zurueck = ConvertFrom-SqQuote $r.Out
    Soll ($zurueck.Count -eq $argumente.Count) ("{0} Argumente zurueck (erwartet {1}): {2}" -f $zurueck.Count, $argumente.Count, $r.Out)
    for ($i = 0; $i -lt $argumente.Count; $i++) {
        Soll ($zurueck[$i] -ceq $argumente[$i]) ("Argument {0}: '{1}' kam als '{2}' an" -f $i, $argumente[$i], $zurueck[$i])
    }
}

Test "stdout und stderr getrennt, Exitcode stimmt" {
    $gut = Invoke-GitRaw @('--version')
    Soll ($gut.Code -eq 0 -and $gut.Out -match '^git version' -and -not $gut.Err) "Erfolg: Ausgabe nur in Out ($($gut.Text))"
    $r = New-TestRepos -MitStart
    $schlecht = Invoke-GitRaw @('rev-parse', '--verify', 'gibt-es-nicht') $r.a
    Soll ($schlecht.Code -ne 0) "Fehler erkannt"
    Soll (-not $schlecht.Out -and $schlecht.Err) "Meldung in Err, Out leer (Out='$($schlecht.Out)')"
    Soll ($schlecht.Text -eq $schlecht.Err) "Text enthaelt die Meldung"
}

Test "Fehlendes Programm meldet 9009 statt abzustuerzen" {
    $r = Invoke-Extern -Datei 'gibt-es-nicht-acss-xyz' -Argumente @('a')
    Soll ($r.Code -eq 9009 -and $r.Text) "Code 9009 mit Meldung"
    Soll ($script:beschaeftigt -eq 0) "nichts bleibt als 'beschaeftigt' haengen"
}

Test "Beim Warten werden Nachrichten abgearbeitet (Fenster bleibt bedienbar)" {
    $k = Get-KurzesProgramm
    $vorher = [AcssTest.Dialog]::DoEventsAnzahl
    $r = Invoke-Extern -Datei $k.Exe -Argumente $k.Args -Text 'Test'
    $anzahl = [AcssTest.Dialog]::DoEventsAnzahl - $vorher
    Soll ($r.Code -eq 0) "Programm lief durch (Code $($r.Code))"
    Soll ($anzahl -ge 10) "DoEvents waehrend des Wartens aufgerufen ($anzahl mal)"
    Soll ($script:beschaeftigt -eq 0) "danach nicht mehr beschaeftigt"
}

Test "Zeitueberschreitung: Prozess wird beendet, Code 124" {
    $d = Get-FakeDolphin
    $start = Get-Date
    $r = Invoke-Extern -Datei $d.Exe -Argumente $d.Args -TimeoutSek 1
    $dauer = ((Get-Date) - $start).TotalSeconds
    Soll ($r.Code -eq 124) "Code 124 (war $($r.Code))"
    Soll ($r.Err -match 'Zeitueberschreitung') "Meldung nennt die Zeitueberschreitung"
    Soll ($dauer -lt 15) "bricht zuegig ab ($([math]::Round($dauer, 1)) s)"
    Soll (Wait-Bis { -not (Get-Process -Name $d.Name -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited }) } 5) "Prozess laeuft nicht mehr"
    Soll ($script:beschaeftigt -eq 0) "danach nicht mehr beschaeftigt"
    $klar = $script:GitKlartext | Where-Object { $r.Text -match $_.Muster } | Select-Object -First 1
    Soll ($null -ne $klar) "es gibt eine Klartext-Erklaerung dafuer"
}

Test "Invoke-ImHintergrund: Ergebnis, Fehler, Zeitueberschreitung" {
    $summe = Invoke-ImHintergrund -Skript { param($a, $b) $a + $b } -Argumente @(2, 3)
    Soll ($summe -eq 5) "Ergebnis kommt zurueck (war $summe)"

    $meldung = ''
    try { Invoke-ImHintergrund -Skript { throw 'kaputt im Runspace' } | Out-Null }
    catch { $meldung = $_.Exception.Message }
    Soll ($meldung -eq 'kaputt im Runspace') "Fehler kommt mit seiner Meldung an (war '$meldung')"

    $vorher = [AcssTest.Dialog]::DoEventsAnzahl
    $meldung = ''
    try { Invoke-ImHintergrund -Skript { Start-Sleep -Seconds 20 } -TimeoutSek 1 | Out-Null }
    catch { $meldung = $_.Exception.Message }
    Soll ($meldung -match 'Zeitueberschreitung') "Zeitueberschreitung gemeldet (war '$meldung')"
    Soll (([AcssTest.Dialog]::DoEventsAnzahl - $vorher) -ge 10) "beim Warten Nachrichten abgearbeitet"
    Soll ($script:beschaeftigt -eq 0) "danach nicht mehr beschaeftigt"
}

Test "Fortschrittstext passt zum git-Befehl" {
    $faelle = @(
        @{ A = @('push', 'origin', 'main'); T = 'Lade auf den Server hoch' },
        @{ A = @('fetch', 'origin'); T = 'Hole den Stand vom Server' },
        @{ A = @('clone', '--', 'x', 'y'); T = 'Hole das gemeinsame Repo' },
        @{ A = @('ls-remote', '--heads', 'origin'); T = 'Pruefe die Verbindung zum Server' },
        @{ A = @('status', '--porcelain'); T = 'Git arbeitet' }
    )
    foreach ($f in $faelle) {
        $t = Get-GitSchrittText $f.A
        Soll ($t -eq $f.T) ("{0} -> '{1}' (war '{2}')" -f ($f.A -join ' '), $f.T, $t)
    }
}

Test "Fortschrittsanzeige: erscheint verzoegert, zeigt Sekunden, verschwindet wieder" {
    $script:fortschrittPanel = New-Object AcssTest.Feld
    $script:fortschrittText = New-Object AcssTest.Feld
    [AcssTest.Dialog]::UseWaitCursor = $false

    Start-Beschaeftigt 'Lade auf den Server hoch'
    Update-Fortschritt
    Soll (-not $script:fortschrittPanel.Visible) "kurze Vorgaenge bleiben unsichtbar (kein Flackern)"
    $script:beschaeftigtSeit = (Get-Date).AddSeconds(-1)
    Update-Fortschritt
    Soll ($script:fortschrittPanel.Visible -and [AcssTest.Dialog]::UseWaitCursor) "nach einer Drittelsekunde sichtbar, Warte-Mauszeiger an"
    Soll ($script:fortschrittText.Text -eq 'Lade auf den Server hoch ...') "Text ohne Sekunden (war '$($script:fortschrittText.Text)')"
    $script:beschaeftigtSeit = (Get-Date).AddSeconds(-7)
    Update-Fortschritt
    Soll ($script:fortschrittText.Text -eq 'Lade auf den Server hoch ... (7 s)') "nach 3 s mit Sekunden (war '$($script:fortschrittText.Text)')"
    Stop-Beschaeftigt

    Invoke-FortschrittTick
    Soll ($script:fortschrittPanel.Visible) "direkt danach noch sichtbar (kein Flackern zwischen zwei git-Aufrufen)"
    $script:letzteArbeit = (Get-Date).AddSeconds(-1)
    Invoke-FortschrittTick
    Soll (-not $script:fortschrittPanel.Visible -and -not [AcssTest.Dialog]::UseWaitCursor) "danach ausgeblendet, Mauszeiger normal"
}

Test "Schliessen waehrend eines Vorgangs wird nachgeholt, sobald er fertig ist" {
    $script:mainForm = New-Object AcssTest.Fenster
    $script:schliessenWennFrei = $true
    Start-Beschaeftigt 'Test'
    Invoke-FortschrittTick
    Soll ($script:mainForm.Geschlossen -eq 0) "waehrend des Vorgangs nicht geschlossen"
    Stop-Beschaeftigt
    Invoke-FortschrittTick
    Soll ($script:mainForm.Geschlossen -eq 1 -and -not $script:schliessenWennFrei) "danach geschlossen"
}

Test "Timer setzen aus, solange ein Vorgang laeuft" {
    $script:abgeschlossen = 0; $script:abfragen = 0
    function Complete-Session { $script:abgeschlossen++ }
    function Get-LockStateRemote { $script:abfragen++; $null }
    $r = New-TestRepos
    $script:cfg.RepoPath = $r.a
    $script:proc = Start-FakeDolphin
    $script:proc.Kill(); [void]$script:proc.WaitForExit(5000)
    $script:dolphinNamen = @((Get-FakeDolphin).Name)
    $script:endeSeit = (Get-Date).AddSeconds(-10)

    $script:beschaeftigt = 1
    Invoke-Tick
    Invoke-AutoAuffrischen
    Soll ($script:abgeschlossen -eq 0 -and $script:abfragen -eq 0) "waehrend des Vorgangs: nichts"
    $script:beschaeftigt = 0
    Invoke-Tick
    Invoke-AutoAuffrischen
    Soll ($script:abgeschlossen -eq 1) "danach: Ende erkannt"
    Soll ($script:abfragen -eq 1) "danach: Anzeige aufgefrischt"
}
