# Selbsttest (Test-Setup): jeder Punkt erkennt sein Problem und sagt, was zu
# tun ist. Name und E-Mail von Git werden ueber GIT_CONFIG_GLOBAL gesteuert -
# so haengt der Test nicht von der Git-Einrichtung des Rechners ab.

# Richtet eine Umgebung ein, in der alles passt. Einzelne Tests verderben
# dann gezielt einen Punkt.
function Set-GuteUmgebung {
    $r = New-TestRepos -MitStart
    $spiel = Join-Path $script:TestWurzel ('spiel-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '/52555550')
    New-Item -ItemType Directory -Path (Join-Path $spiel 'data') -Force | Out-Null
    $script:cfg.RepoPath = $r.a
    $script:cfg.SaveFolder = $spiel
    $script:cfg.DolphinPath = (Get-FakeDolphin).Exe
    $script:cfg.PlayerName = 'Anna'
    Set-GitIdentitaet -Mit
    return $r
}

function Set-GitIdentitaet {
    param([switch]$Mit)
    $datei = Join-Path $script:TestWurzel ('gitconfig-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $inhalt = if ($Mit) { "[user]`n`tname = Anna Test`n`temail = anna@example.com`n" } else { "" }
    [IO.File]::WriteAllText($datei, $inhalt)
    $env:GIT_CONFIG_GLOBAL = $datei
}

function Get-Punkt {
    param($Ergebnis, [string]$Name)
    return ($Ergebnis | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

# Jeder Test raeumt GIT_CONFIG_GLOBAL wieder weg.
$script:altGitConfig = $env:GIT_CONFIG_GLOBAL

Test "Selbsttest: alles in Ordnung" {
    try {
        [void](Set-GuteUmgebung)
        function Get-UhrAbweichung { 2.0 }
        $e = @(Test-Setup)
        $namen = @($e | ForEach-Object { $_.Name })
        $erwartet = @('Git installiert', 'Git kennt dich', 'Dein Name', 'Dolphin gefunden', 'Save-Ordner', 'Uhrzeit',
            'Gemeinsamer Ordner', 'Adresse des Repos', 'Verbindung zum Server', 'Branch vorhanden')
        Soll (($namen -join '|') -eq ($erwartet -join '|')) "alle Punkte in dieser Reihenfolge (waren: $($namen -join ', '))"
        $schlecht = @($e | Where-Object { -not $_.Ok })
        Soll ($schlecht.Count -eq 0) ("alles OK (offen: {0})" -f (($schlecht | ForEach-Object { "$($_.Name): $($_.Hinweis)" }) -join '; '))
        Soll ((Get-Punkt $e 'Git kennt dich').Hinweis -eq 'Anna Test <anna@example.com>') "Name und E-Mail angezeigt"
    }
    finally { $env:GIT_CONFIG_GLOBAL = $script:altGitConfig }
}

Test "Selbsttest: Git fehlt - alles Weitere wird uebersprungen" {
    function Get-GitPfad { $null }
    $e = @(Test-Setup)
    Soll ($e.Count -eq 2 -and -not $e[0].Ok -and $e[0].Name -eq 'Git installiert') "Git fehlt"
    Soll ($e[0].Hinweis -match 'git-scm.com') "Hinweis mit Download-Adresse"
    Soll ($e[1].Name -eq 'Weitere Pruefungen' -and -not $e[1].Ok) "Rest uebersprungen"
}

Test "Selbsttest: fehlende Angaben werden einzeln erkannt" {
    try {
        [void](Set-GuteUmgebung)
        function Get-UhrAbweichung { $null }
        Set-GitIdentitaet
        $script:cfg.PlayerName = ''
        $script:cfg.DolphinPath = Join-Path $script:TestWurzel 'gibt-es-nicht/Dolphin.exe'
        $script:cfg.SaveFolder = ''
        $e = @(Test-Setup)
        Soll (-not (Get-Punkt $e 'Git kennt dich').Ok) "Name/E-Mail fehlen"
        Soll ((Get-Punkt $e 'Git kennt dich').Hinweis -match 'git config --global user.name') "mit Anleitung"
        Soll (-not (Get-Punkt $e 'Dein Name').Ok) "Spielername fehlt"
        Soll (-not (Get-Punkt $e 'Dolphin gefunden').Ok) "Dolphin fehlt"
        Soll (-not (Get-Punkt $e 'Save-Ordner').Ok -and (Get-Punkt $e 'Save-Ordner').Hinweis -match 'NICHT synchronisiert') "Save-Ordner leer"
        Soll ((Get-Punkt $e 'Uhrzeit').Ok -and (Get-Punkt $e 'Uhrzeit').Hinweis -match 'uebersprungen') "Uhrzeit ohne Netz: uebersprungen, kein Fehler"

        $script:cfg.SaveFolder = Join-Path $script:TestWurzel 'gibt-es-nicht'
        Soll ((Get-Punkt @(Test-Setup) 'Save-Ordner').Hinweis -match 'gibt es nicht') "Save-Ordner fehlt"
        $wii = Join-Path $script:TestWurzel ('nand-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '/Wii')
        New-Item -ItemType Directory -Path (Join-Path $wii 'title') -Force | Out-Null
        $script:cfg.SaveFolder = $wii
        $p = Get-Punkt @(Test-Setup) 'Save-Ordner'
        Soll (-not $p.Ok -and $p.Hinweis -match 'ALLER Spiele') "Sammelordner erkannt"
    }
    finally { $env:GIT_CONFIG_GLOBAL = $script:altGitConfig }
}

Test "Selbsttest: Uhr geht falsch - auch wenn das Repo noch fehlt" {
    try {
        [void](Set-GuteUmgebung)
        function Get-UhrAbweichung { 300.0 }
        $script:cfg.RepoPath = Join-Path $script:TestWurzel 'noch-kein-repo'
        $e = @(Test-Setup)
        $u = Get-Punkt $e 'Uhrzeit'
        Soll ($null -ne $u -and -not $u.Ok -and $u.Hinweis -match '5 Min vor') "Uhr 5 Minuten vor erkannt (war: $($u.Hinweis))"
        Soll (-not (Get-Punkt $e 'Gemeinsamer Ordner').Ok) "kein Repo erkannt"
        Soll ((Get-Punkt $e 'Verbindung zum Server').Hinweis -match 'Uebersprungen') "Verbindung uebersprungen"
    }
    finally { $env:GIT_CONFIG_GLOBAL = $script:altGitConfig }
}

Test "Selbsttest: Adresse fehlt, Server weg, Branch fehlt" {
    try {
        $r = Set-GuteUmgebung
        function Get-UhrAbweichung { 0.0 }

        Invoke-G $r.a remote remove origin | Out-Null
        $e = @(Test-Setup)
        Soll (-not (Get-Punkt $e 'Adresse des Repos').Ok) "keine Adresse"
        Soll ($null -eq (Get-Punkt $e 'Verbindung zum Server')) "danach Schluss"

        Invoke-G $r.a remote add origin (Join-Path $r.Wurzel 'gibt-es-nicht.git') | Out-Null
        $v = Get-Punkt @(Test-Setup) 'Verbindung zum Server'
        Soll (-not $v.Ok -and $v.Roh) "Server nicht erreichbar, mit Originalmeldung"

        Invoke-G $r.a remote set-url origin $r.Server | Out-Null
        $script:cfg.Branch = 'gibt-es-nicht'
        $b = Get-Punkt @(Test-Setup) 'Branch vorhanden'
        Soll (-not $b.Ok -and $b.Hinweis -match "keinen Branch 'gibt-es-nicht'") "Branch fehlt"
    }
    finally { $env:GIT_CONFIG_GLOBAL = $script:altGitConfig }
}

Test "Selbsttest: Spielfotos-Ordner nur geprueft, wenn einer eingetragen ist" {
    try {
        [void](Set-GuteUmgebung)
        function Get-UhrAbweichung { 0.0 }
        Soll ($null -eq (Get-Punkt @(Test-Setup) 'Spielfotos-Ordner')) "leer: kein Punkt (Fotos teilen ist aus)"

        $script:cfg.PicsFolder = Join-Path $script:TestWurzel ('wiisdsync-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $p = Get-Punkt @(Test-Setup) 'Spielfotos-Ordner'
        Soll ($null -ne $p -and -not $p.Ok -and $p.Hinweis -match 'gibt es nicht') "fehlender Ordner gemeldet"

        New-Item -ItemType Directory -Path $script:cfg.PicsFolder -Force | Out-Null
        Soll ((Get-Punkt @(Test-Setup) 'Spielfotos-Ordner').Ok) "passender Ordner: OK"

        function Test-SpielfotoOrdner { 'Das ist dein Windows-Ordner "Bilder".' }
        $p = Get-Punkt @(Test-Setup) 'Spielfotos-Ordner'
        Soll (-not $p.Ok -and $p.Hinweis -match 'Windows-Ordner "Bilder"' -and $p.Hinweis -match 'keine Fotos geteilt') "ungeeigneter Ordner: mit Grund und Folge"
    }
    finally { $env:GIT_CONFIG_GLOBAL = $script:altGitConfig }
}

Test "Selbsttest-Bericht zum Kopieren" {
    $erg = @(
        [pscustomobject]@{ Name = 'Git installiert'; Ok = $true; Hinweis = 'git version 2'; Roh = '' },
        [pscustomobject]@{ Name = 'Verbindung zum Server'; Ok = $false; Hinweis = 'Server weg'; Roh = "fatal: eins`nzwei" }
    )
    $t = Format-SelbsttestBericht $erg
    Soll ($t -match '^\[OK   \] Git installiert') "OK-Zeile"
    Soll ($t -match '\[FEHLT\] Verbindung zum Server') "FEHLT-Zeile"
    Soll ($t -match 'git: fatal: eins\r\n\s+zwei') "Originalmeldung mehrzeilig eingerueckt"
}
