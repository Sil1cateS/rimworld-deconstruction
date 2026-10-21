#requires -Version 5.1
<#
  decompile-diagnose.ps1 - single-assembly decompile with per-5s progress sampling.
  Purpose: when dnSpy.Console stalls, capture (a) how far it got, (b) whether it is CPU-busy or blocked,
  (c) which files were written last, so the offending type can be localized.
  ASCII only.
#>
param(
    [Parameter(Mandatory = $true)][string]$Assembly,
    [string]$GameRoot = (Join-Path $PSScriptRoot '..\RimWorld'),
    [string]$OutDir   = (Join-Path $PSScriptRoot '..\analysis\diag'),
    [string]$LogDir   = (Join-Path $PSScriptRoot '..\logs'),
    [string]$DnSpy    = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [int]$TimeoutSec  = 150,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Continue'
$asmPath = Join-Path $GameRoot $Assembly
if (-not (Test-Path -LiteralPath $asmPath)) { Write-Output "missing: $asmPath"; exit 2 }

$tag = [System.IO.Path]::GetFileNameWithoutExtension($Assembly)
$target = Join-Path $OutDir ("diag_{0}_{1}" -f $tag, (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Force -Path $target | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $LogDir ("diag-{0}-{1}.log" -f $tag, $stamp)
$outFile = Join-Path $LogDir ("diag-{0}-{1}.stdout.txt" -f $tag, $stamp)
$errFile = Join-Path $LogDir ("diag-{0}-{1}.stderr.txt" -f $tag, $stamp)

function Say([string]$t) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t
    Write-Output $line
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

$args = @('-o', $target, '--no-resources', '--no-baml', '--no-sln') + $ExtraArgs + @($asmPath)
Say ("start: {0} extra={1} timeout={2}s out={3}" -f $Assembly, ($ExtraArgs -join ' '), $TimeoutSec, $target)
$p = Start-Process -FilePath $DnSpy -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastCount = -1
$stallSamples = 0
$lastCpu = 0.0

while (-not $p.HasExited) {
    Start-Sleep -Seconds 5
    $p.Refresh()
    if ($p.HasExited) { break }
    $files = @(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue)
    $count = $files.Count
    $cpu = $p.CPU
    $dCpu = [math]::Round($cpu - $lastCpu, 1)
    $lastCpu = $cpu
    $ws = [int]($p.WorkingSet64 / 1MB)
    if ($count -eq $lastCount) { $stallSamples++ } else { $stallSamples = 0 }
    Say ("t={0,3}s files={1,4} cpu={2,6:N1}s (+{3,4:N1}) ws={4,4}MB stalled_samples={5}" -f $sw.Elapsed.TotalSeconds, $count, $cpu, $dCpu, $ws, $stallSamples)
    $lastCount = $count
    if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
        Say "TIMEOUT -> killing process"
        try { $p.Kill() } catch { }
        Start-Sleep -Milliseconds 800
        break
    }
}
$sw.Stop()
$code = if ($p.HasExited) { $p.ExitCode } else { -1 }
Say ("end: exit={0} elapsed={1:N1}s files={2}" -f $code, $sw.Elapsed.TotalSeconds, @(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue).Count)

Say "last 12 files by write time:"
Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 12 |
    ForEach-Object { Say ("  {0}  {1} bytes" -f $_.Name, $_.Length) }

if (Test-Path -LiteralPath $errFile) {
    $err = Get-Content -LiteralPath $errFile -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 5
    if ($err) { Say "stderr tail:"; $err | ForEach-Object { Say ("  " + $_) } }
}
if (Test-Path -LiteralPath $outFile) {
    $out = Get-Content -LiteralPath $outFile -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 5
    if ($out) { Say "stdout tail:"; $out | ForEach-Object { Say ("  " + $_) } }
}
exit 0
