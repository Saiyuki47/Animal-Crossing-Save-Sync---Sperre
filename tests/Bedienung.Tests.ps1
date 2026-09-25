# Bedienung: Meldungen, Schliessen waehrend eines Vorgangs, doppelte Klicks
# und doppelt gestartete Programme.

Test "Meldungen gehoeren zu einem Fenster des Programms" -NurWindows {
    Add-Type -AssemblyName System.Windows.Forms
    Soll ($null -eq (Get-MeldungsBesitzer)) "ohne Fenster: keins (dann entscheidet Windows)"
    $haupt = New-Object Windows.Forms.Form
    try {
        $script:mainForm = $haupt
        Soll ([object]::ReferenceEquals((Get-MeldungsBesitzer), $haupt)) "sonst das Hauptfenster"
    }
    finally { $haupt.Dispose() }
}

Test "Dialoge lassen sich nicht schliessen, solange etwas laeuft" {
    # Ersatz fuer ein Fenster: merkt sich, was bei FormClosing aufgerufen wird.
    $fenster = [pscustomobject]@{ Handler = $null }
    $fenster | Add-Member -MemberType ScriptMethod -Name Add_FormClosing -Value { param($h) $this.Handler = $h }
    Add-SchliessSperre $fenster
    Soll ($null -ne $fenster.Handler) "Handler angemeldet"

    $e = [pscustomobject]@{ Cancel = $false }
    $script:beschaeftigt = 1
    & $fenster.Handler $fenster $e
    Soll ($e.Cancel) "waehrend eines Vorgangs: Schliessen abgelehnt (X, Alt+F4)"
    $script:beschaeftigt = 0
    $e.Cancel = $false
    & $fenster.Handler $fenster $e
    Soll (-not $e.Cancel) "danach: schliesst wie gewohnt"
}

Test "Sitzungsende laeuft nicht zweimal gleichzeitig" {
    $script:cfg.RepoPath = (New-TestRepos).a
    $script:holdingLock = $true
    $script:btnStop.Enabled = $true
    $script:gesichert = 0

    # Ein Abschluss laeuft schon (z. B. wartet er gerade auf Dolphin) - ein
    # zweiter Aufruf, etwa per Klick auf "Spielen beenden", tut nichts.
    $script:schliesseAb = $true
    function Backup-SavesMitWiederholung { $script:gesichert++; $true }
    Complete-Session
    Soll ($script:gesichert -eq 0 -and $script:holdingLock) "zweiter Aufruf tut nichts"
    Soll ($script:schliesseAb) "der erste Abschluss bleibt vermerkt"

    # Normaler Abschluss: Knopf gleich gesperrt, danach alles wieder frei
    $script:schliesseAb = $false
    $script:knopfBeimSichern = $null
    function Backup-SavesMitWiederholung { $script:knopfBeimSichern = $script:btnStop.Enabled; $script:gesichert++; $true }
    function Copy-Pics { }
    function Add-Playtime { }   # Ersatz; -EndSession landet in $args
    function Invoke-GitCommitPush { [pscustomobject]@{ Code = 0; Text = ''; Stage = 'push' } }
    Complete-Session
    Soll ($script:gesichert -eq 1 -and -not $script:holdingLock) "abgeschlossen"
    Soll ($script:knopfBeimSichern -eq $false) "'Spielen beenden' schon beim Sichern gesperrt"
    Soll (-not $script:schliesseAb) "danach wieder frei fuer die naechste Sitzung"
}

Test "Kein Herzschlag kommt an: einmal Ton und Blinken, nicht jede Minute" {
    $script:cfg.RepoPath = (New-TestRepos).a
    $script:holdingLock = $true
    $script:hinweise = 0
    function Invoke-Aufmerksamkeit { $script:hinweise++ }
    function Set-LockFile { }
    function Backup-Saves { $true }
    function Invoke-GitCommitPush { [pscustomobject]@{ Code = 1; Text = 'fatal: unable to access: Could not resolve host: github.com'; Stage = 'push' } }
    function Test-SperreNochMeine { }
    foreach ($i in 1..4) {
        $script:lastHeartbeat = (Get-Date).AddMinutes(-5)
        Invoke-Tick
    }
    Soll ($script:hbFehler -eq 4) "vier Fehlschlaege gezaehlt (waren $($script:hbFehler))"
    Soll ($script:hinweise -eq 1) "genau einmal aufmerksam gemacht (waren $($script:hinweise))"
    Soll ($script:lblStatus.Text -match '^ACHTUNG') "Warnung im Statusfeld"
}

Test "Nur einmal starten: ein zweites Programm bekommt die Sperre nicht" -NurWindows {
    Soll ((Get-InstanzName 'C:\Spiel\AC') -like 'Local\AC-SaveSync-*') "Name mit festem Anfang"
    Soll ((Get-InstanzName 'C:\Spiel\AC') -eq (Get-InstanzName 'c:\spiel\ac\')) "Gross/klein und Schraegstrich am Ende egal"
    Soll ((Get-InstanzName 'C:\Spiel\AC') -ne (Get-InstanzName 'C:\Spiel\Test')) "anderer Einstellungsordner, andere Sperre"

    # Ein anderes Programm haelt die Sperre ...
    $name = Get-InstanzName (Join-Path $script:TestWurzel ('einzel-' + [guid]::NewGuid().ToString('N')))
    $marke = Join-Path $script:TestWurzel ('haelt-' + [guid]::NewGuid().ToString('N'))
    $befehl = "`$m = New-Object Threading.Mutex(`$false, '$name'); [void]`$m.WaitOne(); " +
    "Set-Content -LiteralPath '$marke' -Value ok; Start-Sleep -Seconds 60"
    $kodiert = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
    $p = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-EncodedCommand', $kodiert `
        -WindowStyle Hidden -PassThru
    [void]$script:TestProzesse.Add($p)
    Soll (Wait-Bis { Test-Path -LiteralPath $marke } 30) "das andere Programm haelt die Sperre"
    Soll (-not (Enter-EinzelInstanz -Name $name -WarteSek 1)) "dieses bekommt sie nicht"
    Soll ($null -eq $script:instanzSperre) "und merkt sich auch nichts"

    # ... und stuerzt ab, ohne sie freizugeben: dann gehoert sie diesem
    $p.Kill(); [void]$p.WaitForExit(5000)
    Soll (Enter-EinzelInstanz -Name $name -WarteSek 2) "nach dem Absturz des anderen: frei"
    Soll ($null -ne $script:instanzSperre) "Sperre gehalten"
    Exit-EinzelInstanz
    Soll ($null -eq $script:instanzSperre) "beim Beenden wieder freigegeben"
}
