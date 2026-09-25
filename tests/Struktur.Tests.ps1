# Aufbau des Skripts: Syntax, Meldungstexte, Version, gebaute .cmd.

Test "Syntax fehlerfrei (mit genau dieser PowerShell-Fassung)" {
    $f = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script:SkriptPfad, [ref]$null, [ref]$f)
    Soll (-not $f -or $f.Count -eq 0) ("keine Syntaxfehler (erster: {0})" -f $(if ($f) { $f[0] } else { '' }))
}

Test "Keine Meldung, in der -f nur das letzte Teilstueck formatiert" {
    # "-f" bindet staerker als "+": ("a {0}" + "b" -f $x) formatiert nur "b".
    $kaputt = $script:Ast.FindAll({
            $a = $args[0]
            $a -is [System.Management.Automation.Language.BinaryExpressionAst] -and $a.Operator -eq 'Plus' -and
            $a.Right -is [System.Management.Automation.Language.BinaryExpressionAst] -and $a.Right.Operator -eq 'Format' -and
            $a.Left.Extent.Text -match '\{\d'
        }, $true)
    $zeilen = @($kaputt | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
    Soll (@($kaputt).Count -eq 0) "keine solchen Stellen (gefunden in Zeile $zeilen)"
}

Test "Versionsnummer vorhanden und gueltig" {
    $t = Select-String -LiteralPath $script:SkriptPfad -Pattern "^\`$script:Version = '([^']+)'"
    Soll ($null -ne $t) "Zeile `$script:Version gefunden"
    $v = $t.Matches[0].Groups[1].Value
    $ok = $true; try { [void][version]$v } catch { $ok = $false }
    Soll $ok "als Versionsnummer lesbar ($v)"
}

Test "Gebaute .cmd enthaelt das Skript unveraendert und ohne BOM" {
    $ziel = Join-Path $script:TestWurzel 'AC-SaveSync.cmd'
    $bauer = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Build-Cmd.ps1'
    & $bauer -Output $ziel | Out-Null
    $b = [IO.File]::ReadAllBytes($ziel)
    Soll ($b[0] -ne 0xEF) "kein BOM (cmd.exe wuerde sonst die erste Zeile zerreissen)"
    $raw = [IO.File]::ReadAllText($ziel, [Text.UTF8Encoding]::new($false))
    $m = [char]10 + '@@AC-SAVESYNC-POWERSHELL-BODY@@'
    $i = $raw.IndexOf($m)
    Soll ($i -ge 0) "Markerzeile vorhanden"
    $rumpf = $raw.Substring($i + $m.Length).TrimStart([char]13, [char]10) -replace "`r`n", "`n"
    $orig = [IO.File]::ReadAllText($script:SkriptPfad, [Text.UTF8Encoding]::new($false)).TrimStart([char]13, [char]10) -replace "`r`n", "`n"
    Soll ($rumpf -ceq $orig) "Rumpf identisch mit AC-SaveSync.ps1"
    $f = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($rumpf, [ref]$null, [ref]$f)
    Soll (-not $f -or $f.Count -eq 0) "Rumpf fehlerfrei"
}
