# Regeln fuer PSScriptAnalyzer (Aufruf: tests\Start-Lint.ps1).
# Geprueft werden Fehler und Warnungen. Ausgeschlossen sind nur Regeln, die
# fuer ein Programm mit Oberflaeche nicht passen - jeweils mit Begruendung.
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Meldungen gehen bewusst auch in die Konsole: vor dem Aufbau des
        # Fensters und in den Test-Skripten gibt es keinen anderen Ausgabeweg.
        'PSAvoidUsingWriteHost',

        # Das ist kein Cmdlet fuer die Pipeline. -WhatIf/-Confirm an jeder
        # Funktion, die etwas veraendert, ergaeben hier keinen Sinn - die
        # Rueckfragen stellt das Programm selbst in eigenen Fenstern.
        'PSUseShouldProcessForStateChangingFunctions',

        # Namen wie Backup-Saves oder Set-AutoPaths stehen bewusst in der
        # Mehrzahl: sie behandeln mehrere Dateien bzw. Pfade auf einmal.
        'PSUseSingularNouns'
    )

    Rules        = @{
        # Das Programm laeuft unter Windows PowerShell 5.1. Ohne diese Angabe
        # vergleicht die Regel mit PowerShell 6.1 und haelt "Write-Log" dort
        # faelschlich fuer ein eingebautes Cmdlet.
        PSAvoidOverwritingBuiltInCmdlets = @{
            PowerShellVersion = @('desktop-5.1.14393.206-windows')
        }
    }
}
