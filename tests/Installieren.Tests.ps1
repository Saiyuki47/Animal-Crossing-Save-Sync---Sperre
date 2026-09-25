# Fest installieren: Die .cmd kopiert sich beim ersten Start in den festen
# Ordner, legt Verknuepfungen an, traegt sich unter "Apps" ein und laesst sich
# dort wieder entfernen. Alle Orte zeigen in Test-Ordner und einen
# Test-Schluessel (siehe Reset-Zustand) - der echte Desktop, das Startmenue
# und "Apps" bleiben unberuehrt.

# Baut eine .cmd mit der gewuenschten Versionsnummer - wie ein Download.
function New-TestCmd {
    param(
        [string]$Version = '1.0',
        [string]$Ordner = (Join-Path $script:TestWurzel ('dl-' + [guid]::NewGuid().ToString('N').Substring(0, 6)))
    )
    New-Item -ItemType Directory -Path $Ordner -Force | Out-Null
    $text = [IO.File]::ReadAllText($script:SkriptPfad, [Text.UTF8Encoding]::new($false)) -replace
        "(?m)^\`$script:Version = '[^']+'", "`$script:Version = '$Version'"
    $ps1 = Join-Path $Ordner 'quelle.ps1'
    [IO.File]::WriteAllText($ps1, $text, [Text.UTF8Encoding]::new($false))
    $cmd = Join-Path $Ordner 'AC-SaveSync.cmd'
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Build-Cmd.ps1') -Source $ps1 -Output $cmd | Out-Null
    Remove-Item -LiteralPath $ps1
    return $cmd
}

# Entfernt den Test-Eintrag unter "Apps" - nur unterhalb des Test-Schluessels.
function Remove-TestSchluessel {
    if ($script:UninstallKey -like "$($script:TestSchluessel)\*" -and (Test-Path -LiteralPath $script:UninstallKey)) {
        Remove-Item -LiteralPath $script:UninstallKey -Recurse -Force
    }
}

function Get-DateiBase64 { param([string]$Pfad) [Convert]::ToBase64String([IO.File]::ReadAllBytes($Pfad)) }

Test "Get-InstallSchritt: wann installiert, uebergeben oder gefragt wird" {
    Soll ((Get-InstallSchritt -VorhandeneVersion '' -Erststart $true -Abgelehnt $false) -eq 'installieren') "erster Start: installieren"
    Soll ((Get-InstallSchritt -VorhandeneVersion '' -Erststart $false -Abgelehnt $false) -eq 'fragen') "aeltere Einrichtung: fragen"
    Soll ((Get-InstallSchritt -VorhandeneVersion '' -Erststart $false -Abgelehnt $true) -eq 'normal') "einmal abgelehnt: nicht mehr fragen"
    Soll ((Get-InstallSchritt -VorhandeneVersion $script:Version -Erststart $false -Abgelehnt $false) -eq 'uebergeben') "gleiche Fassung installiert: die starten"
    Soll ((Get-InstallSchritt -VorhandeneVersion '99.0' -Erststart $true -Abgelehnt $false) -eq 'uebergeben') "neuere installiert: nie mit dieser ueberschreiben"
    Soll ((Get-InstallSchritt -VorhandeneVersion '0.1' -Erststart $false -Abgelehnt $true) -eq 'installieren') "aeltere installiert: ersetzen (Update per Download)"

    # Anderer Inhalt: nur bei gleicher Nummer zaehlt das (selbst gebaut)
    Soll ((Get-InstallSchritt -VorhandeneVersion $script:Version -Erststart $false -Abgelehnt $false -Abweichend $true) -eq 'normal') "gleiche Nummer, anderer Inhalt: von hier laufen"
    Soll ((Get-InstallSchritt -VorhandeneVersion '99.0' -Erststart $false -Abgelehnt $false -Abweichend $true) -eq 'uebergeben') "neuere installiert: trotzdem die starten"
    Soll ((Get-InstallSchritt -VorhandeneVersion '0.1' -Erststart $false -Abgelehnt $false -Abweichend $true) -eq 'installieren') "aeltere installiert: trotzdem ersetzen"
}

Test "Get-DateiVersion liest die Versionsnummer, ohne die Datei auszufuehren" {
    Soll ((Get-DateiVersion (New-TestCmd -Version '1.5')) -eq '1.5') ".cmd: Version gelesen"
    Soll ((Get-DateiVersion $script:SkriptPfad) -eq $script:Version) ".ps1: Version gelesen"
    $leer = Join-Path $script:TestWurzel ('ohne-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.cmd')
    Set-Content -LiteralPath $leer -Value '@echo off'
    Soll ($null -eq (Get-DateiVersion $leer)) "ohne Versionszeile: nichts"
    Soll ($null -eq (Get-DateiVersion (Join-Path $script:TestWurzel 'gibt-es-nicht.cmd'))) "fehlende Datei: nichts"
}

Test "Test-LaeuftInstalliert: gleicher Pfad auch in anderer Schreibweise" {
    $script:SelfPath = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
    Soll (Test-LaeuftInstalliert) "aus dem festen Ordner"
    $script:SelfPath = $script:SelfPath.ToUpperInvariant()
    Soll (Test-LaeuftInstalliert) "Gross-/Kleinschreibung zaehlt nicht"
    $script:SelfPath = Join-Path $script:TestWurzel 'Downloads/AC-SaveSync.cmd'
    Soll (-not (Test-LaeuftInstalliert)) "aus dem Downloads-Ordner: nicht installiert"
    $script:SelfPath = ''
    Soll (-not (Test-LaeuftInstalliert)) "ohne eigenen Pfad: nicht installiert"
    $script:SelfPath = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
    $script:InstallDir = $null
    Soll (-not (Test-LaeuftInstalliert)) "ohne festen Ordner: nicht installiert"
}

Test "Install-Programm: kopiert sich in den festen Ordner und ersetzt eine aeltere Fassung" {
    try {
        $script:SelfPath = New-TestCmd -Version '1.5'
        $ziel = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
        Soll (Install-Programm) "installiert"
        Soll ((Get-DateiVersion $ziel) -eq '1.5') "Kopie im festen Ordner"
        Soll ((Get-DateiBase64 $ziel) -eq (Get-DateiBase64 $script:SelfPath)) "Byte fuer Byte gleich"
        Soll ((Get-ProtokollText) -match 'Installiert: ') "im Protokoll"

        $script:SelfPath = New-TestCmd -Version '1.6'
        Soll (Install-Programm) "neuere Fassung installiert"
        Soll ((Get-DateiVersion $ziel) -eq '1.6') "aeltere ersetzt"
        Soll (-not (Test-Path -LiteralPath ($ziel + '.neu'))) "keine Zwischendatei uebrig"
    }
    finally { Remove-TestSchluessel }
}

Test "Install-Programm: eine kaputte Datei ersetzt nie eine vorhandene Fassung" {
    try {
        $script:SelfPath = New-TestCmd -Version '1.5'
        Soll (Install-Programm) "erst eine gute Fassung installiert"
        $ziel = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
        $vorher = Get-DateiBase64 $ziel

        $kaputt = Join-Path $script:TestWurzel ('kaputt-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.cmd')
        Set-Content -LiteralPath $kaputt -Value '@echo off'
        $script:SelfPath = $kaputt
        Soll (-not (Install-Programm)) "kaputte Datei: nicht installiert"
        Soll ((Get-ProtokollText) -match 'Installieren fehlgeschlagen') "Grund im Protokoll"
        Soll ((Get-DateiBase64 $ziel) -eq $vorher) "vorhandene Fassung unveraendert"
        Soll (-not (Test-Path -LiteralPath ($ziel + '.neu'))) "keine Zwischendatei uebrig"

        $script:SelfPath = ''
        Soll (-not (Install-Programm)) "ohne eigenen Pfad: nicht installiert"
    }
    finally { Remove-TestSchluessel }
}

Test "Install-Programm: die Kopie traegt keine Marke 'aus dem Internet'" -NurWindows {
    try {
        $script:SelfPath = New-TestCmd
        Set-Content -LiteralPath $script:SelfPath -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3"
        Soll ($null -ne (Get-Item -LiteralPath $script:SelfPath -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)) "Download traegt die Marke (Voraussetzung)"
        Soll (Install-Programm) "installiert"
        $ziel = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
        Soll ($null -eq (Get-Item -LiteralPath $ziel -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)) "installierte Kopie ohne Marke - sonst fragte Windows bei jedem Start"
    }
    finally { Remove-TestSchluessel }
}

Test "Installieren und Deinstallieren: Verknuepfungen und Eintrag unter 'Apps'" -NurWindows {
    try {
        New-Item -ItemType Directory -Path $script:DesktopDir, $script:StartmenueDir -Force | Out-Null
        $script:IconBase64 = [Convert]::ToBase64String([byte[]](0, 0, 1, 0, 0, 0))
        $script:SelfPath = New-TestCmd
        $ziel = Join-Path $script:InstallDir 'AC-SaveSync.cmd'
        Soll (Install-Programm) "installiert"
        foreach ($ordner in $script:DesktopDir, $script:StartmenueDir) {
            $lnk = Join-Path $ordner $script:VerknuepfungsName
            Soll (Test-Path -LiteralPath $lnk) "Verknuepfung in $ordner"
            Soll ((Get-VerknuepfungsZiel $lnk) -eq $ziel) "zeigt auf die installierte Fassung (war: $(Get-VerknuepfungsZiel $lnk))"
        }
        $e = Get-ItemProperty -LiteralPath $script:UninstallKey
        Soll ($e.DisplayName -match 'Animal Crossing') "Name eingetragen"
        Soll ($e.DisplayVersion -eq $script:Version) "Version eingetragen"
        Soll ($e.InstallLocation -eq $script:InstallDir) "Ort eingetragen"
        Soll ($e.UninstallString -eq (Get-DeinstallBefehl) -and $e.UninstallString -match '/deinstallieren"$') "Befehl zum Deinstallieren"
        Soll ($e.UninstallString.StartsWith('"' + (Join-Path $env:SystemRoot 'System32\cmd.exe') + '" /c ')) "ueber das cmd.exe von Windows, nicht %ComSpec%"
        Soll ((Test-Path -LiteralPath $e.DisplayIcon) -and $e.DisplayIcon -like "$($script:InstallDir)*") "Symbol liegt neben dem Programm"
        Soll ($e.NoModify -eq 1 -and $e.NoRepair -eq 1 -and $e.EstimatedSize -gt 100) "ohne Aendern/Reparieren, mit Groesse"

        # "Verknuepfungen neu anlegen" meldet nur Erfolg, wenn beide stehen.
        Remove-Item -LiteralPath (Join-Path $script:DesktopDir $script:VerknuepfungsName)
        Soll (Install-Verknuepfungen) "neu angelegt"
        Soll (Test-Path -LiteralPath (Join-Path $script:DesktopDir $script:VerknuepfungsName)) "geloeschte Verknuepfung wieder da"
        $startmenue = $script:StartmenueDir
        $script:StartmenueDir = Join-Path $script:TestWurzel 'gibt-es-nicht'
        Soll (-not (Install-Verknuepfungen)) "eine scheitert: kein Erfolg gemeldet"
        Soll ((Get-ProtokollText) -match 'konnte nicht angelegt werden') "Grund im Protokoll"
        $script:StartmenueDir = $startmenue

        # Eine selbst angelegte Verknuepfung auf eine andere Datei bleibt stehen.
        [void](New-Verknuepfung -Ordner $script:DesktopDir -Ziel $script:SelfPath -Symbol '')
        $rest = @(Uninstall-Programm)
        Soll ($rest.Count -eq 0) "alles entfernt (Rest: $($rest -join ', '))"
        Soll (-not (Test-Path -LiteralPath $script:InstallDir)) "Programmordner weg"
        Soll (-not (Test-Path -LiteralPath (Join-Path $script:StartmenueDir $script:VerknuepfungsName))) "Verknuepfung im Startmenue weg"
        Soll (Test-Path -LiteralPath (Join-Path $script:DesktopDir $script:VerknuepfungsName)) "fremde Verknuepfung bleibt"
        Soll (-not (Test-Path -LiteralPath $script:UninstallKey)) "Eintrag unter 'Apps' weg"
        Soll (Test-Path -LiteralPath $script:AppDir) "Einstellungen bleiben"
    }
    finally { Remove-TestSchluessel }
}

Test "Installierte Fassung haelt den Eintrag unter 'Apps' aktuell" -NurWindows {
    try {
        $script:IconBase64 = [Convert]::ToBase64String([byte[]](0, 0, 1, 0, 0, 0))
        $script:SelfPath = New-TestCmd -Version $script:Version -Ordner $script:InstallDir
        Soll (Test-LaeuftInstalliert) "laeuft aus dem festen Ordner (Voraussetzung)"
        Soll (-not (Invoke-InstallBeimStart)) "startet ganz normal"
        Soll ((Get-ItemProperty -LiteralPath $script:UninstallKey).DisplayVersion -eq $script:Version) "fehlender Eintrag angelegt"
        Soll (Test-Path -LiteralPath (Join-Path $script:InstallDir 'ac-savesync.ico')) "fehlendes Symbol ersetzt"
        Set-ItemProperty -LiteralPath $script:UninstallKey -Name 'DisplayVersion' -Value '0.1'
        Update-InstallEintrag
        Soll ((Get-ItemProperty -LiteralPath $script:UninstallKey).DisplayVersion -eq $script:Version) "nach einem Update: neue Versionsnummer"
    }
    finally { Remove-TestSchluessel }
}

Test "Beim Start: frisch heruntergeladen - installieren und die Kopie starten" {
    $script:SelfPath = New-TestCmd -Version $script:Version
    $script:istErststart = $true
    $script:aufrufe = @()
    function Install-Programm { $script:aufrufe += 'installieren'; $true }
    function Start-Installiertes { $script:aufrufe += 'starten'; $true }
    Soll (Invoke-InstallBeimStart) "dieses Programm beendet sich"
    Soll (($script:aufrufe -join ',') -eq 'installieren,starten') "erst installiert, dann die Kopie gestartet (war: $($script:aufrufe -join ','))"

    # Scheitert das Installieren, laeuft es einfach von hier weiter.
    $script:aufrufe = @()
    function Install-Programm { $script:aufrufe += 'installieren'; $false }
    Soll (-not (Invoke-InstallBeimStart)) "laeuft weiter"
    Soll (($script:aufrufe -join ',') -eq 'installieren') "nichts gestartet"
    Soll ((Get-ProtokollText) -match 'von hier aus weiter') "im Protokoll"
}

Test "Beim Start: installierte Fassung vorhanden - starten, eine aeltere vorher ersetzen" {
    $script:aufrufe = @()
    function Install-Programm { $script:aufrufe += 'installieren'; $true }
    function Start-Installiertes { $script:aufrufe += 'starten'; $true }
    $script:SelfPath = New-TestCmd -Version $script:Version

    [void](New-TestCmd -Version $script:Version -Ordner $script:InstallDir)
    Soll (Invoke-InstallBeimStart) "gleiche Fassung: beenden"
    Soll (($script:aufrufe -join ',') -eq 'starten') "nur die installierte gestartet"

    $script:aufrufe = @()
    [void](New-TestCmd -Version '99.0' -Ordner $script:InstallDir)
    Soll (Invoke-InstallBeimStart) "neuere installiert: beenden"
    Soll (($script:aufrufe -join ',') -eq 'starten') "neuere nicht ueberschrieben"

    $script:aufrufe = @()
    [void](New-TestCmd -Version '0.1' -Ordner $script:InstallDir)
    Soll (Invoke-InstallBeimStart) "aeltere installiert: beenden"
    Soll (($script:aufrufe -join ',') -eq 'installieren,starten') "aeltere erst ersetzt"

    # Eine beschaedigte Fassung dort zaehlt nicht - bei einer aelteren
    # Einrichtung wird dann gefragt, statt an sie weiterzureichen.
    $script:aufrufe = @()
    Set-Content -LiteralPath (Join-Path $script:InstallDir 'AC-SaveSync.cmd') -Value '@echo off'
    Soll (-not (Invoke-InstallBeimStart) -and $script:installFrage) "beschaedigt: fragen"
    Soll ($script:aufrufe.Count -eq 0) "nichts gestartet"
}

Test "Beim Start: selbst gebaute .cmd mit gleicher Nummer laeuft von dort, wo sie liegt" {
    $script:aufrufe = @()
    function Install-Programm { $script:aufrufe += 'installieren'; $true }
    function Start-Installiertes { $script:aufrufe += 'starten'; $true }
    [void](New-TestCmd -Version $script:Version -Ordner $script:InstallDir)
    $script:SelfPath = New-TestCmd -Version $script:Version
    Add-Content -LiteralPath $script:SelfPath -Value '# selbst geaendert'
    Soll (-not (Invoke-InstallBeimStart)) "laeuft von hier"
    Soll ($script:aufrufe.Count -eq 0 -and -not $script:installFrage) "weder installiert, gestartet noch gefragt"
    Soll ((Get-ProtokollText) -match 'anderer Inhalt') "Grund im Protokoll"

    # Test-GleicherInhalt: im Zweifel "gleich" - dann bleibt es beim Uebergeben
    Soll (-not (Test-GleicherInhalt $script:SelfPath (Join-Path $script:InstallDir 'AC-SaveSync.cmd'))) "anderer Inhalt erkannt"
    Soll (Test-GleicherInhalt $script:SelfPath (Join-Path $script:TestWurzel 'gibt-es-nicht.cmd')) "nicht lesbar: gilt als gleich"
}

Test "Beim Start: aeltere Einrichtung wird gefragt, .ps1 und Weitergereichtes nie" {
    $script:aufrufe = @()
    function Install-Programm { $script:aufrufe += 'installieren'; $true }
    function Start-Installiertes { $script:aufrufe += 'starten'; $true }

    $script:SelfPath = New-TestCmd
    Soll (-not (Invoke-InstallBeimStart)) "laeuft weiter"
    Soll ($script:installFrage) "nach dem Start wird gefragt"

    $script:installFrage = $false
    $script:cfg.InstallDeclined = $true
    Soll (-not (Invoke-InstallBeimStart) -and -not $script:installFrage) "einmal abgelehnt: keine Frage mehr"

    $script:cfg.InstallDeclined = $false
    $script:istErststart = $true
    $script:SelfPath = Join-Path $script:TestWurzel 'repo/AC-SaveSync.ps1'
    Soll (-not (Invoke-InstallBeimStart) -and -not $script:installFrage) ".ps1 aus dem Repo: nichts"

    # Gerade weitergereicht, aber nicht im festen Ordner: nie noch einmal
    # weiterreichen - sonst startete es sich endlos neu.
    $script:SelfPath = New-TestCmd
    $script:UebergabeVon = Join-Path $script:TestWurzel 'Downloads/AC-SaveSync.cmd'
    Soll (-not (Invoke-InstallBeimStart)) "laeuft von hier"
    Soll ((Get-ProtokollText) -match 'WARNUNG: Laeuft nicht aus dem festen Ordner') "Warnung im Protokoll"
    Soll ($script:aufrufe.Count -eq 0) "weder installiert noch gestartet"
}

Test "Start-Installiertes: startet die Kopie mit Merker und gibt die Einzelstart-Sperre frei" -NurWindows {
    # Als "installierte Fassung" ein winziges Programm, das nur aufschreibt,
    # welchen Merker es mitbekommt.
    $ausgabe = Join-Path $script:TestWurzel ('merker-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
    New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
    $mini = Join-Path $script:InstallDir 'mini.ps1'
    [IO.File]::WriteAllText($mini, ('[IO.File]::WriteAllText(''{0}'', "[$env:ACSS_UEBERGABE]")' -f $ausgabe), [Text.UTF8Encoding]::new($false))
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Build-Cmd.ps1') -Source $mini -Output (Get-InstallPfad) | Out-Null

    $script:SelfPath = Join-Path $script:TestWurzel 'Downloads/AC-SaveSync.cmd'
    $name = Get-InstanzName (Join-Path $script:TestWurzel ('einzel-' + [guid]::NewGuid().ToString('N')))
    Soll (Enter-EinzelInstanz -Name $name -WarteSek 0) "Sperre gehalten (Voraussetzung)"
    Soll (Start-Installiertes) "gestartet"
    Soll ($null -eq $env:ACSS_UEBERGABE) "Merker hier gleich wieder weg"
    Soll ($null -eq $script:instanzSperre) "Einzelstart-Sperre freigegeben"
    Soll (Wait-Bis { Test-Path -LiteralPath $ausgabe } 60) "installierte Fassung gestartet"
    Soll ((Wait-Bis { (Get-Content -LiteralPath $ausgabe -Raw) -eq "[$($script:SelfPath)]" } 5)) "Merker kommt an (war: $(Get-Content -LiteralPath $ausgabe -Raw))"

    # Laesst sie sich nicht starten, laeuft dieses Programm weiter - mit Sperre.
    $script:InstallDir = Join-Path $script:TestWurzel ('fehlt-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    Soll (Enter-EinzelInstanz -Name $name -WarteSek 0) "Sperre wieder gehalten"
    Soll (-not (Start-Installiertes)) "Start gescheitert"
    Soll ((Get-ProtokollText) -match 'liess sich nicht starten') "Grund im Protokoll"
    Soll ($null -ne $script:instanzSperre) "Sperre bleibt"
    Exit-EinzelInstanz
}

Test "Frage bei aelterer Einrichtung: Nein wird gemerkt, Ja installiert und startet neu" {
    $script:SelfPath = Join-Path $script:TestWurzel 'Downloads/AC-SaveSync.cmd'
    $script:gespeichert = 0
    function Save-ConfigFromUI { $script:gespeichert++ }
    $script:installiert = 0
    function Install-Programm { $script:installiert++; $true }
    function Start-Installiertes { $true }

    $script:installFrage = $true
    [AcssTest.Dialog]::Reset('No')
    Soll (-not (Invoke-InstallFrage)) "Nein: laeuft weiter"
    Soll ($script:cfg.InstallDeclined -and $script:gespeichert -eq 1) "Nein gemerkt und gespeichert"
    Soll ($script:installiert -eq 0 -and -not $script:installFrage) "nichts installiert, keine zweite Frage"
    $t = [AcssTest.Dialog]::Texte[0]
    Soll ($t -match '^Neu: ' -and $t.Contains($script:SelfPath)) "nennt die Datei, die danach uebrig ist"

    # Ueber "Erweitert..." nachgeholt
    $script:mainForm = New-Object AcssTest.Fenster
    [AcssTest.Dialog]::Reset('Yes')
    Soll (Invoke-InstallFrage -Nachholen) "Ja: installiert und neu gestartet"
    Soll ($script:installiert -eq 1) "installiert"
    Soll ($script:updateLaeuft -and $script:mainForm.Geschlossen -eq 1) "Fenster zu, ohne Rueckfrage beim Schliessen"
    Soll (-not $script:cfg.InstallDeclined) "das fruehere Nein ist vergessen"
    Soll ([AcssTest.Dialog]::Texte[0] -notmatch '^Neu: ') "nachgeholt: ohne 'Neu:'"
}

Test "Fest installieren: waehrend einer Sitzung erst Spielen beenden, Fehler melden" {
    $script:installiert = 0
    function Install-Programm { $script:installiert++; $false }
    $script:holdingLock = $true
    [AcssTest.Dialog]::Reset('Yes')
    Soll (-not (Install-UndNeustart)) "waehrend einer Sitzung: nicht installiert"
    Soll ($script:installiert -eq 0 -and [AcssTest.Dialog]::Texte[0] -match 'Sitzung') "Hinweis: erst Spielen beenden"

    $script:holdingLock = $false
    $script:mainForm = New-Object AcssTest.Fenster
    [AcssTest.Dialog]::Reset('Yes')
    Soll (-not (Install-UndNeustart)) "gescheitert: laeuft weiter"
    Soll ($script:mainForm.Geschlossen -eq 0 -and [AcssTest.Dialog]::Texte[0] -match 'nicht geklappt') "Fenster bleibt offen, Meldung"
}

Test "Deinstallieren: erst fragen, Einstellungen und gemeinsamer Ordner bleiben" {
    $script:entfernt = 0
    function Uninstall-Programm { $script:entfernt++ }
    [AcssTest.Dialog]::Reset('No')
    Invoke-Deinstallation
    Soll ($script:entfernt -eq 0) "Nein: nichts entfernt"
    Soll ([AcssTest.Dialog]::Texte[0] -match 'Einstellungen') "Rueckfrage sagt, was bleibt"

    $script:cfg.RepoPath = $script:TestWurzel
    [AcssTest.Dialog]::Reset('Yes')
    Invoke-Deinstallation
    $t = [AcssTest.Dialog]::Texte
    Soll ($script:entfernt -eq 1) "Ja: entfernt"
    Soll ($t.Count -eq 2 -and $t[1].Contains($script:AppDir) -and $t[1].Contains($script:TestWurzel)) "sagt, wo Einstellungen und Spielstand noch liegen"

    function Uninstall-Programm { 'C:\irgendwo\gesperrt.lnk' }
    [AcssTest.Dialog]::Reset('Yes')
    Invoke-Deinstallation
    Soll ([AcssTest.Dialog]::Texte[1] -match 'Nicht alles' -and [AcssTest.Dialog]::Texte[1].Contains('gesperrt.lnk')) "Reste werden genannt"
}

Test "Starter: erstes Argument wird als Auftrag weitergereicht" {
    $text = [IO.File]::ReadAllText((New-TestCmd), [Text.UTF8Encoding]::new($false))
    $kopf = $text.Substring(0, $text.IndexOf([char]10 + '@@AC-SAVESYNC-POWERSHELL-BODY@@'))
    Soll ($kopf.Contains('set "ACSS_AUFTRAG=%~1"')) "Kopf setzt ACSS_AUFTRAG aus dem ersten Argument"
    Soll ($kopf.IndexOf('ACSS_AUFTRAG') -lt $kopf.IndexOf('powershell')) "bevor PowerShell startet"
}

Test "Starter: 'Deinstallieren' unter 'Apps' kommt als Auftrag an, auch bei Sonderzeichen im Pfad" -NurWindows {
    $ordner = Join-Path $script:TestWurzel ('Mit Leer & Klammer (' + [guid]::NewGuid().ToString('N').Substring(0, 6) + ')')
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    $ausgabe = Join-Path $ordner 'auftrag.txt'
    # Winziges Programm statt des echten: schreibt nur auf, welchen Auftrag es bekommt.
    $mini = Join-Path $ordner 'mini.ps1'
    [IO.File]::WriteAllText($mini, ('[IO.File]::WriteAllText(''{0}'', "[$env:ACSS_AUFTRAG]")' -f $ausgabe), [Text.UTF8Encoding]::new($false))
    $cmd = Join-Path $ordner 'AC-SaveSync.cmd'
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Build-Cmd.ps1') -Source $mini -Output $cmd | Out-Null

    # Genau der Befehl, der unter "Apps" eingetragen wird: "cmd.exe" /c ""...cmd" /deinstallieren"
    $m = [regex]::Match((Get-DeinstallBefehl -Pfad $cmd), '^"([^"]+)" (.+)$')
    Soll $m.Success "Programm in Anfuehrungszeichen, dann die Argumente"
    $p = Start-Process -FilePath $m.Groups[1].Value -ArgumentList $m.Groups[2].Value -WindowStyle Hidden -PassThru
    [void]$script:TestProzesse.Add($p)
    Soll (Wait-Bis { Test-Path -LiteralPath $ausgabe } 60) "Programm gestartet"
    Soll ((Wait-Bis { (Get-Content -LiteralPath $ausgabe -Raw) -eq '[/deinstallieren]' } 5)) "Auftrag angekommen (war: $(Get-Content -LiteralPath $ausgabe -Raw))"

    # Doppelklick: ohne Argument, also ohne Auftrag. Der Explorer ruft so auf -
    # das aeussere Paar Anfuehrungszeichen nimmt cmd /c wieder weg.
    Remove-Item -LiteralPath $ausgabe
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ""{0}""' -f $cmd) -WindowStyle Hidden -PassThru
    [void]$script:TestProzesse.Add($p)
    Soll (Wait-Bis { Test-Path -LiteralPath $ausgabe } 60) "Programm gestartet"
    Soll ((Wait-Bis { (Get-Content -LiteralPath $ausgabe -Raw) -eq '[]' } 5)) "kein Auftrag (war: $(Get-Content -LiteralPath $ausgabe -Raw))"
}
