#requires -Version 5.1
<#
  dump-waylith.ps1 - per-type extraction with timeout and IL fallback.
  Motivation (R19): dnSpy's project-wide C# decompilation of Waylith.dll hangs on
  Waylith.Rendering.Bc7BlockEncoder (RID 56, 190 methods). The same type decompiles
  fine to IL, so the workaround is: dump type by type, time out on the offender and
  fall back to IL for it.
  Type list comes from analysis/index/waylith-types.tsv (rid, token, depth, type, kind, methods).
  ASCII only.
#>
param(
    [string]$TypeList  = (Join-Path $PSScriptRoot '..\analysis\index\waylith-types.tsv'),
    [string]$Assembly  = (Join-Path $PSScriptRoot '..\RimWorld\Waylith.dll'),
    [string]$OutRoot   = (Join-Path $PSScriptRoot '..\analysis\decompiled\Waylith'),
    [string]$LogDir    = (Join-Path $PSScriptRoot '..\logs'),
    [string]$DnSpy     = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [int]$TimeoutCs    = 20,
    [int]$TimeoutIl    = 60
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir  | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $LogDir ("dump-waylith-{0}.log" -f $stamp)
$failLog = Join-Path $LogDir ("dump-waylith-{0}.failed.txt" -f $stamp)
function Say([string]$t) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t; Write-Output $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

function Invoke-DnSpy([string[]]$dnArgs, [int]$timeoutSec, [string]$outFile) {
    $job = Start-Job -ScriptBlock {
        param($exe, $a)
        & $exe @a 2>&1
    } -ArgumentList $DnSpy, $dnArgs
    $done = Wait-Job $job -Timeout $timeoutSec
    if (-not $done) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Get-Process -Name dnSpy.Console -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }
    $lines = @(Receive-Job $job)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($lines.Count -lt 5) { return $false }
    $text = ($lines -join "`r`n")
    [System.IO.File]::WriteAllText($outFile, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

$types = Get-Content -LiteralPath $TypeList -Encoding UTF8 | Select-Object -Skip 1 | ForEach-Object {
    $c = $_ -split "`t"
    [pscustomobject]@{ Rid = [int]$c[0]; Type = $c[3] }
}
Say ("start: types={0} timeoutCs={1}s timeoutIl={2}s" -f $types.Count, $TimeoutCs, $TimeoutIl)

$okCs = 0; $okIl = 0; $failed = New-Object System.Collections.Generic.List[string]
$skipped = 0
$i = 0
foreach ($t in $types) {
    $i++
    $nsIdx = $t.Type.LastIndexOf('.')
    $nsDir = if ($nsIdx -gt 0) { $t.Type.Substring(0, $nsIdx) -replace '\.', '\' } else { '' }
    $short = ($t.Type.Substring($nsIdx + 1)) -replace '[<>]', '-' -replace '`\d+$', '' -replace '[+]', '.'
    $dir = if ($nsDir) { Join-Path $OutRoot $nsDir } else { $OutRoot }
    $csPath = Join-Path $dir ($short + '.cs')
    $ilPath = Join-Path $dir ($short + '.il')

    if ((Test-Path -LiteralPath $csPath) -or (Test-Path -LiteralPath $ilPath)) { $skipped++; continue }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    if (Invoke-DnSpy @('-t', $t.Type, $Assembly) $TimeoutCs $csPath) { $okCs++; continue }
    Say ("CS timeout/fail RID {0} {1} -> try IL" -f $t.Rid, $t.Type)
    if (Invoke-DnSpy @('-l', 'IL', '-t', $t.Type, $Assembly) $TimeoutIl $ilPath) { $okIl++; continue }
    $failed.Add(("RID {0}`t{1}" -f $t.Rid, $t.Type))
    Say ("FAILED both modes: RID {0} {1}" -f $t.Rid, $t.Type)
    if ($i % 25 -eq 0) { Say ("progress {0}/{1} cs={2} il={3} skip={4} fail={5}" -f $i, $types.Count, $okCs, $okIl, $skipped, $failed.Count) }
}
if ($failed.Count -gt 0) { $failed | Set-Content -LiteralPath $failLog -Encoding UTF8 }
Say ("done: cs={0} il={1} skipped={2} failed={3}" -f $okCs, $okIl, $skipped, $failed.Count)
if ($failed.Count -gt 0) { Say ("failed list: " + $failLog) }
exit 0
