#requires -Version 5.1
<#
  dump-types.ps1 - per-type decompilation with a hard timeout per type.
  Use when dnSpy.Console project-wide output stalls on a pathological type:
  it isolates and skips only the offending type instead of losing the whole assembly.
  Type list comes from analysis/index/types.tsv (produced by list-types.ps1 under PowerShell 7).
#>
param(
    [Parameter(Mandatory = $true)][string]$Assembly,
    [string]$GameRoot = (Join-Path $PSScriptRoot '..\RimWorld'),
    [string]$OutRoot  = (Join-Path $PSScriptRoot '..\analysis\decompiled'),
    [string]$IndexTsv = (Join-Path $PSScriptRoot '..\analysis\index\types.tsv'),
    [string]$LogDir   = (Join-Path $PSScriptRoot '..\logs'),
    [string]$DnSpy    = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [int]$TimeoutSec  = 25,
    [string]$Lang     = 'C#',
    [switch]$Clean,
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Continue'
$asmPath = Join-Path $GameRoot $Assembly
if (-not (Test-Path -LiteralPath $asmPath)) { Write-Output "missing assembly: $asmPath"; exit 2 }
if (-not (Test-Path -LiteralPath $IndexTsv)) { Write-Output "missing index: $IndexTsv"; exit 2 }

$asmBase = [System.IO.Path]::GetFileNameWithoutExtension($Assembly)
$outDir  = Join-Path $OutRoot $asmBase
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
if ($Clean -and (Test-Path -LiteralPath $outDir)) { Get-ChildItem -LiteralPath $outDir -Recurse -File | Remove-Item -Force }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $LogDir ("dump-types-{0}-{1}.log" -f $asmBase, $stamp)
$failLog = Join-Path $LogDir ("dump-types-{0}-{1}.failed.txt" -f $asmBase, $stamp)
function Say([string]$t) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t; Write-Output $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$types = @(Get-Content -LiteralPath $IndexTsv -Encoding UTF8 | Select-Object -Skip 1 | ForEach-Object {
    $c = $_ -split "`t"
    if ($c[0] -eq $Assembly) { [pscustomobject]@{ Ns = $c[1]; Type = $c[2] } }
})

Say ("assembly={0} types={1} timeout={2}s lang={3}" -f $Assembly, $types.Count, $TimeoutSec, $Lang)
$tmpOut = Join-Path $env:TEMP ("dumptypes_{0}.out" -f $PID)
$tmpErr = Join-Path $env:TEMP ("dumptypes_{0}.err" -f $PID)
$ok = 0; $timeout = 0; $fail = 0
$failed = New-Object System.Collections.Generic.List[string]
$i = 0

foreach ($t in $types) {
    $i++
    $safe = ($t.Type -replace '[+]', '_') -replace '[<>]', '_'
    $nsDir = if ($t.Ns) { Join-Path $outDir ($t.Ns -replace '\.', '\') } else { $outDir }
    $target = Join-Path $nsDir ($safe + '.cs')
    if ($SkipExisting -and (Test-Path -LiteralPath $target)) { $ok++; continue }
    New-Item -ItemType Directory -Force -Path $nsDir | Out-Null

    $args = @('-l', $Lang, '-t', $t.Type, $asmPath)
    $p = Start-Process -FilePath $DnSpy -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $done = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $done) {
        try { $p.Kill() } catch { }
        $timeout++
        $failed.Add("TIMEOUT`t$($t.Type)")
        Say ("TIMEOUT {0}" -f $t.Type)
        continue
    }
    $text = if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 } else { '' }
    if ($p.ExitCode -eq 0 -and $text -and $text.Length -gt 20) {
        [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($false)))
        $ok++
    } else {
        $fail++
        $failed.Add("FAIL`t$($t.Type)`texit=$($p.ExitCode)")
        Say ("FAIL {0} exit={1}" -f $t.Type, $p.ExitCode)
    }
    if ($i % 100 -eq 0) { Say ("progress {0}/{1} ok={2} timeout={3} fail={4}" -f $i, $types.Count, $ok, $timeout, $fail) }
}

Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue
if ($failed.Count -gt 0) { $failed | Set-Content -LiteralPath $failLog -Encoding UTF8 }
Say ("done {0}: ok={1} timeout={2} fail={3}" -f $Assembly, $ok, $timeout, $fail)
if ($failed.Count -gt 0) { Say ("failed list: {0}" -f $failLog); exit 1 }
exit 0
