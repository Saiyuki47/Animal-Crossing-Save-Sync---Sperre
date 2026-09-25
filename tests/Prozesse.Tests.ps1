# Ende-Erkennung: Starter, die sich sofort beenden, und "Spielen beenden".
# Unter Windows ist das Ersatz-Dolphin eine Kopie von ping.exe namens
# Dolphin.exe, der Starter eine .cmd; sonst "sleep" und ein sh-Skript.

Test "Laufendes Dolphin -> Sitzung nicht beendet" {
    $script:dolphinNamen = @((Get-FakeDolphin).Name)
    $script:proc = Start-FakeDolphin
    Soll (-not (Test-DolphinBeendet)) "nicht beendet"
}

Test "Starter beendet sich, Dolphin laeuft weiter -> wird uebernommen" {
    $script:dolphinNamen = @((Get-FakeDolphin).Name)
    $script:proc = Start-FakeStarter
    $starter = $script:proc.Id
    Soll (Wait-Bis { Test-ProzessWeg $script:proc } 15) "Starter hat sich beendet"
    Soll (Wait-Bis { $null -ne (Find-DolphinProzess $starter) } 10) "Ersatz-Dolphin laeuft"
    Soll (-not (Test-DolphinBeendet)) "Sitzung NICHT beendet"
    Soll ($script:proc.Id -ne $starter -and $script:proc.ProcessName -eq (Get-FakeDolphin).Name) "Dolphin uebernommen"
    Soll ((Get-ProtokollText) -match 'Dolphin laeuft aber weiter') "im Protokoll vermerkt"
}

Test "Dolphin zu -> erst nach kurzer Wartezeit beendet, mit -Sofort gleich" {
    $script:dolphinNamen = @((Get-FakeDolphin).Name)
    $script:proc = Start-FakeDolphin
    $script:proc.Kill(); [void]$script:proc.WaitForExit(5000)
    Soll (-not (Test-DolphinBeendet)) "erster Blick: noch nicht (Wartezeit laeuft)"
    Soll ($null -ne $script:endeSeit) "Wartezeit gestartet"
    $script:endeSeit = (Get-Date).AddSeconds(-7)
    Soll (Test-DolphinBeendet) "nach 6 s beendet"
    $script:endeSeit = $null
    Soll (Test-DolphinBeendet -Sofort) "mit -Sofort ohne Wartezeit"
    $script:proc = $null
    Soll (Test-DolphinBeendet) "ohne Prozess: beendet"
}

Test "Spielen beenden mit wartendem Starter: erst Dolphin selbst, dann Abschluss" {
    $script:dolphinNamen = @((Get-FakeDolphin).Name)
    $script:holdingLock = $true
    $script:abgeschlossen = 0
    function Complete-Session { $script:abgeschlossen++ }
    $script:proc = Start-FakeStarter -Wartet
    $starter = $script:proc.Id
    Soll (Wait-Bis { $null -ne (Find-DolphinProzess $starter) } 10) "Ersatz-Dolphin laeuft"

    [AcssTest.Dialog]::Reset('Yes')      # "beenden?" und "hart abbrechen?" jeweils Ja
    Stop-Play
    Soll ($script:abgeschlossen -eq 0) "noch NICHT abgeschlossen (Dolphin laeuft noch)"
    Soll ($script:proc.Id -ne $starter) "Dolphin uebernommen"
    Soll ($script:btnStop.Enabled -and $script:timer.Enabled) "Sitzung bleibt bedienbar"

    Stop-Play
    Soll ($script:abgeschlossen -eq 1) "zweiter Klick beendet Dolphin und schliesst ab"
}
