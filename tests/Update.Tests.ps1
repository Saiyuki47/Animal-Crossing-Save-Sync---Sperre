# Selbst aktualisieren: Datei pruefen, ersetzen, Sicherheitskopie, Rueckfragen.
# Das Herunterladen (Save-Download) und die Anfrage an GitHub (Get-ReleaseDaten)
# werden ersetzt - getestet wird alles drumherum, ohne Netz.

function New-UpdateDateien {
    # Legt "installierte" und "neue" Fassung als .ps1 und .cmd an.
    $ordner = Join-Path $script:TestWurzel ('upd-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    $original = [IO.File]::ReadAllText($script:SkriptPfad, [Text.UTF8Encoding]::new($false))
    $alt = $original -replace "(?m)^\`$script:Version = '[^']+'", "`$script:Version = '1.0'"
    $neu = $original -replace "(?m)^\`$script:Version = '[^']+'", "`$script:Version = '9.9'"
    $d = @{ Ordner = $ordner }
    foreach ($paar in @(@('Alt', $alt), @('Neu', $neu))) {
        $ps1 = Join-Path $ordner ("{0}.ps1" -f $paar[0])
        [IO.File]::WriteAllText($ps1, $paar[1], [Text.UTF8Encoding]::new($false))
        $cmd = Join-Path $ordner ("{0}.cmd" -f $paar[0])
        & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Build-Cmd.ps1') -Source $ps1 -Output $cmd | Out-Null
        $d["$($paar[0])Ps1"] = $ps1
        $d["$($paar[0])Cmd"] = $cmd
    }
    return $d
}

function New-ReleaseInfo {
    param([string[]]$Dateien = @('AC-SaveSync.cmd', 'AC-SaveSync.ps1'))
    return [pscustomobject]@{
        Version = '9.9'; Tag = 'v9.9'; Text = ''
        Dateien = @($Dateien | ForEach-Object { [pscustomobject]@{ name = $_; browser_download_url = "https://example.invalid/$_" } })
    }
}

Test "Test-UpdateDatei: gute Dateien werden angenommen, kaputte abgelehnt" {
    $d = New-UpdateDateien
    Soll ((Test-UpdateDatei $d.NeuPs1 '.ps1') -eq '') "gute .ps1 angenommen"
    Soll ((Test-UpdateDatei $d.NeuCmd '.cmd') -eq '') "gute .cmd angenommen"

    $klein = Join-Path $d.Ordner 'klein.ps1'; Set-Content -LiteralPath $klein -Value 'Write-Host 1'
    Soll ((Test-UpdateDatei $klein '.ps1') -match 'verdaechtig klein') "zu kleine Datei abgelehnt"

    $bom = Join-Path $d.Ordner 'bom.ps1'
    [IO.File]::WriteAllText($bom, [IO.File]::ReadAllText($d.NeuPs1), [Text.UTF8Encoding]::new($true))
    Soll ((Test-UpdateDatei $bom '.ps1') -match 'BOM') "Datei mit BOM abgelehnt"

    $ohneMarke = Join-Path $d.Ordner 'ohne.cmd'; Copy-Item -LiteralPath $d.NeuPs1 -Destination $ohneMarke
    Soll ((Test-UpdateDatei $ohneMarke '.cmd') -match 'Markerzeile') ".cmd ohne Markerzeile abgelehnt"

    $kaputt = Join-Path $d.Ordner 'kaputt.ps1'
    [IO.File]::WriteAllText($kaputt, [IO.File]::ReadAllText($d.NeuPs1) + "`nfunction Kaputt { if ( }`n", [Text.UTF8Encoding]::new($false))
    Soll ((Test-UpdateDatei $kaputt '.ps1') -match 'Syntaxfehler') "Datei mit Syntaxfehler abgelehnt"
    Soll ((Test-UpdateDatei (Join-Path $d.Ordner 'gibtsnicht.ps1') '.ps1') -match 'fehlt') "fehlende Datei abgelehnt"
}

Test "Install-Update ersetzt die eigene .ps1 und legt eine Sicherheitskopie an" {
    $d = New-UpdateDateien
    $script:SelfPath = Join-Path $d.Ordner 'AC-SaveSync.ps1'
    Copy-Item -LiteralPath $d.AltPs1 -Destination $script:SelfPath
    $script:quelle = $d.NeuPs1
    function Save-Download { param($Uri, $Ziel) $script:geladen = $Uri; Copy-Item -LiteralPath $script:quelle -Destination $Ziel -Force }
    $ok = Install-Update (New-ReleaseInfo)
    Soll ($ok -eq $true) "Update gemeldet"
    Soll ($script:geladen -like '*AC-SaveSync.ps1') "die .ps1 wurde geladen (nicht die .cmd)"
    Soll ((Get-Content -LiteralPath $script:SelfPath -Raw) -match "Version = '9.9'") "eigene Datei ersetzt"
    $kopie = Join-Path $script:AppDir 'update/vorher.ps1'
    Soll ((Get-Content -LiteralPath $kopie -Raw) -match "Version = '1.0'") "alte Fassung als Sicherheitskopie"
    Soll ((Get-ProtokollText) -match 'Aktualisiert auf Version 9.9') "im Protokoll"
}

Test "Install-Update ersetzt die eigene .cmd" {
    $d = New-UpdateDateien
    $script:SelfPath = Join-Path $d.Ordner 'AC-SaveSync.cmd'
    Copy-Item -LiteralPath $d.AltCmd -Destination $script:SelfPath
    $script:quelle = $d.NeuCmd
    function Save-Download { param($Uri, $Ziel) $script:geladen = $Uri; Copy-Item -LiteralPath $script:quelle -Destination $Ziel -Force }
    Soll ((Install-Update (New-ReleaseInfo)) -eq $true) "Update gemeldet"
    Soll ($script:geladen -like '*AC-SaveSync.cmd') "die .cmd wurde geladen"
    Soll ((Get-Content -LiteralPath $script:SelfPath -Raw) -match "Version = '9.9'") "eigene Datei ersetzt"
}

Test "Install-Update laesst die eigene Datei bei jedem Problem unangetastet" {
    $d = New-UpdateDateien
    $script:SelfPath = Join-Path $d.Ordner 'AC-SaveSync.ps1'
    Copy-Item -LiteralPath $d.AltPs1 -Destination $script:SelfPath
    $vorher = Get-Content -LiteralPath $script:SelfPath -Raw

    # 1) Download liefert Unsinn
    function Save-Download { param($Uri, $Ziel) $script:geladen = $Uri; Set-Content -LiteralPath $Ziel -Value '<html>Fehler</html>' }
    Soll ((Install-Update (New-ReleaseInfo)) -eq $false) "kaputter Download: kein Update"
    Soll ((Get-ProtokollText) -match 'NICHT uebernommen') "Grund im Protokoll"
    # 2) Download scheitert
    function Save-Download { throw 'keine Verbindung' }
    Soll ((Install-Update (New-ReleaseInfo)) -eq $false) "gescheiterter Download: kein Update"
    Soll ((Get-ProtokollText) -match 'Herunterladen fehlgeschlagen: keine Verbindung') "Grund im Protokoll"
    # 3) Release ohne passende Datei
    Soll ((Install-Update (New-ReleaseInfo -Dateien @('etwas-anderes.zip'))) -eq $false) "keine passende Datei: kein Update"
    Soll ((Get-ProtokollText) -match "keine Datei 'AC-SaveSync.ps1'") "Grund im Protokoll"

    Soll ((Get-Content -LiteralPath $script:SelfPath -Raw) -eq $vorher) "eigene Datei unveraendert"

    # 4) eigener Pfad unbekannt
    $script:SelfPath = ''
    Soll ((Install-Update (New-ReleaseInfo)) -eq $false) "ohne eigenen Pfad: kein Update"
}

Test "Neueste Version: Antwort von GitHub auswerten, Versionen vergleichen" {
    function Get-ReleaseDaten {
        [pscustomobject]@{ tag_name = 'v1.18'; body = "## Was ist neu`n`nSchneller"; assets = @([pscustomobject]@{ name = 'AC-SaveSync.cmd' }) }
    }
    $i = Get-NeuesteVersion
    Soll ($i.Version -eq '1.18' -and $i.Tag -eq 'v1.18' -and $i.Text -match 'Schneller' -and @($i.Dateien).Count -eq 1) "Felder uebernommen"

    function Get-ReleaseDaten { [pscustomobject]@{ message = 'API rate limit exceeded' } }
    Soll ($null -eq (Get-NeuesteVersion)) "Fehlerantwort von GitHub: keine Auskunft"
    function Get-ReleaseDaten { throw 'kein Netz' }
    Soll ($null -eq (Get-NeuesteVersion)) "kein Netz: keine Auskunft"
    Soll ((Get-ProtokollText) -match 'Update-Pruefung nicht moeglich: kein Netz') "Grund im Protokoll"

    Soll (Test-VersionNeuer '1.11' '1.9') "1.11 ist neuer als 1.9 (nicht als Text verglichen)"
    Soll (Test-VersionNeuer 'v1.18' '1.17') "fuehrendes v wird ignoriert"
    Soll (-not (Test-VersionNeuer '1.17' '1.17')) "gleiche Version ist nicht neuer"
    Soll (-not (Test-VersionNeuer 'Quatsch' '1.17')) "Unsinn ist nicht neuer"
}

Test "Neuigkeiten: nur der Abschnitt 'Was ist neu', hoechstens fuenf Zeilen" {
    $text = "## Was ist neu`r`n`r`nErstens`r`n`r`n- Zweitens`r`n* Drittens`r`n## Installation`r`n1. Herunterladen"
    $n = @(Get-UpdateNeuigkeiten $text)
    Soll (($n -join '|') -eq 'Erstens|Zweitens|Drittens') "drei Zeilen, ohne Spiegelstriche und ohne Installation (war: $($n -join '|'))"
    $viele = "## Was ist neu`n" + ((1..9 | ForEach-Object { "Punkt $_" }) -join "`n")
    Soll (@(Get-UpdateNeuigkeiten $viele).Count -eq 5) "hoechstens fuenf"
    Soll (@(Get-UpdateNeuigkeiten "## Installation`nnur das").Count -eq 0) "ohne den Abschnitt: nichts"
    Soll (@(Get-UpdateNeuigkeiten '').Count -eq 0) "leerer Text: nichts"
}

Test "Update-Pruefung: waehrend einer Sitzung wird nicht aktualisiert" {
    function Get-NeuesteVersion { [pscustomobject]@{ Version = '9.9'; Text = "## Was ist neu`nToll"; Dateien = @() } }
    $script:installiert = 0
    function Install-Update { $script:installiert++; $true }
    $script:holdingLock = $true
    [AcssTest.Dialog]::Reset('Yes')
    Invoke-UpdatePruefung
    $t = [AcssTest.Dialog]::Texte
    Soll ($t.Count -eq 2 -and $t[0] -match 'Version 9.9 ist verfuegbar' -and $t[0] -match '- Toll') "Angebot mit Neuigkeit"
    Soll ($t[1] -match 'laeuft gerade eine Sitzung') "Hinweis: erst Spielen beenden"
    Soll ($script:installiert -eq 0) "nicht installiert"
}

Test "Update-Pruefung: Nein heisst nein, aktuell heisst still" {
    $script:installiert = 0
    function Install-Update { $script:installiert++; $true }
    function Get-NeuesteVersion { [pscustomobject]@{ Version = '9.9'; Text = ''; Dateien = @() } }
    [AcssTest.Dialog]::Reset('No')
    Invoke-UpdatePruefung
    Soll ($script:installiert -eq 0 -and [AcssTest.Dialog]::Texte.Count -eq 1) "abgelehnt: nichts installiert"

    function Get-NeuesteVersion { [pscustomobject]@{ Version = $script:Version; Text = ''; Dateien = @() } }
    [AcssTest.Dialog]::Reset('Yes')
    Invoke-UpdatePruefung -Still
    Soll ([AcssTest.Dialog]::Texte.Count -eq 0 -and (Get-ProtokollText) -match 'ist aktuell') "aktuell und -Still: keine Meldung, nur Protokoll"
}

Test "Update-Pruefung: nach erfolgreichem Update Neustart und Fenster zu" {
    function Get-NeuesteVersion { [pscustomobject]@{ Version = '9.9'; Text = ''; Dateien = @() } }
    function Install-Update { $true }
    $script:neustarts = 0
    function Restart-Programm { $script:neustarts++ }
    $script:mainForm = New-Object AcssTest.Fenster
    [AcssTest.Dialog]::Reset('Yes')
    Invoke-UpdatePruefung
    Soll ($script:neustarts -eq 1) "neu gestartet"
    Soll ($script:updateLaeuft -and $script:mainForm.Geschlossen -eq 1) "Fenster geschlossen, ohne Rueckfrage beim Schliessen"
}
