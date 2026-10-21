#requires -Version 5.1
<#
  probe-type.ps1 - fetch one or more types straight from the assemblies (no corpus needed).
  Exit 0 = every requested type exists; exit 1 = at least one missing.
  dnSpy.Console semantics (verified): exit 0 + source on stdout = found; exit 1 + usage text = not found.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Type,

    [string]$Assembly = 'Assembly-CSharp.dll',
    [string]$GameRoot = (Join-Path $PSScriptRoot '..\RimWorld'),
    [string]$DnSpy    = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [string]$OutFile  = '',
    [string]$Lang     = 'C#'
)

$ErrorActionPreference = 'Stop'
# comma form survives only in-process; -File passes "a,b" as one string
$Type = @($Type | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$asmPath = Join-Path $GameRoot $Assembly
if (-not (Test-Path -LiteralPath $asmPath)) { Write-Error "assembly not found: $asmPath"; exit 2 }

$missing = 0
$buffer = New-Object System.Text.StringBuilder

foreach ($t in $Type) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $out = & $DnSpy -l $Lang -t $t $asmPath 2>&1
    $code = $LASTEXITCODE
    $sw.Stop()
    $state = if ($code -eq 0) { 'FOUND' } else { 'missing'; $missing++ }
    Write-Output ("{0,-6} {1,-52} exit={2} lines={3} ms={4}" -f $state, $t, $code, $out.Count, $sw.ElapsedMilliseconds)
    if ($OutFile -and $code -eq 0) {
        [void]$buffer.AppendLine("===== $t =====")
        [void]$buffer.AppendLine(($out -join "`n"))
        [void]$buffer.AppendLine("")
    }
}

if ($OutFile -and $buffer.Length -gt 0) {
    [System.IO.File]::WriteAllText($OutFile, $buffer.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ("written: {0}" -f $OutFile)
}

if ($missing -gt 0) { Write-Output ("missing={0}" -f $missing); exit 1 }
exit 0
