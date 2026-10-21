#requires -Version 5.1
<#
  decompile.ps1 - full headless decompilation of the RimWorld 1.7 assemblies.
  Action: dnSpy.Console (dnSpyEx 6.6) -> C# corpus, one project folder per assembly.
  ASCII only on purpose: Windows PowerShell 5.1 mis-decodes UTF-8 .ps1 without BOM.
#>
param(
    [string]$GameRoot = (Join-Path $PSScriptRoot '..\RimWorld'),
    [string]$OutRoot  = (Join-Path $PSScriptRoot '..\analysis\decompiled'),
    [string]$DnSpy    = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [string]$LogDir   = (Join-Path $PSScriptRoot '..\logs'),
    [string]$Lang     = '',
    [string[]]$Assemblies = @(
        'Assembly-CSharp.dll',
        'RimWorld.dll',
        'Waylith.dll',
        'Waylith.UnityCompat.dll',
        'UnityStubs.dll'
    )
)

$ErrorActionPreference = 'Continue'
# comma form survives only in-process; -File passes "a,b" as one string
$Assemblies = @($Assemblies | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $LogDir ("decompile-{0}-{1}.log" -f $stamp, $PID)
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir  | Out-Null

function Say([string]$text) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $text
    Write-Output $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

Say "decompile start  game=$GameRoot  out=$OutRoot"
$results = @()

foreach ($asm in $Assemblies) {
    $path = Join-Path $GameRoot $asm
    if (-not (Test-Path -LiteralPath $path)) {
        Say "SKIP missing assembly: $asm"
        $results += [pscustomobject]@{ Assembly = $asm; Exit = -99; Ms = 0; CsFiles = 0; Bytes = 0 }
        continue
    }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($asm)
    $target = Join-Path $OutRoot $base
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Say "BEGIN $asm -> $target"
    # --no-resources / --no-baml: keep only text (images and XAML are not evidence for this project)
    $dnArgs = @('-o', $target, '--no-resources', '--no-baml', '--no-sln')
    if ($Lang) { $dnArgs += @('-l', $Lang) }
    $dnArgs += $path
    $out = & $DnSpy @dnArgs 2>&1
    $code = $LASTEXITCODE
    $sw.Stop()
    # dnSpy nests a project folder named after the assembly inside -o; flatten it so paths stay
    # analysis/decompiled/<Asm>/<Namespace>/<Type>.cs and can be cited directly by the docs.
    $inner = Join-Path $target $base
    if (Test-Path -LiteralPath $inner) {
        Get-ChildItem -LiteralPath $inner -Force | Move-Item -Destination $target -Force
        Remove-Item -LiteralPath $inner -Recurse -Force
    }
    $cs  = @(Get-ChildItem -LiteralPath $target -Recurse -File -Include *.cs,*.il -ErrorAction SilentlyContinue)
    $bytes = 0
    if ($cs.Count -gt 0) { $bytes = ($cs | Measure-Object Length -Sum).Sum }
    Say ("END   {0} exit={1} ms={2} cs={3} bytes={4}" -f $asm, $code, $sw.ElapsedMilliseconds, $cs.Count, $bytes)
    if ($out) { $out | Select-Object -Last 5 | ForEach-Object { Say ("  out: " + $_) } }
    $results += [pscustomobject]@{ Assembly = $asm; Exit = $code; Ms = $sw.ElapsedMilliseconds; CsFiles = $cs.Count; Bytes = $bytes }
}

$results | Format-Table -AutoSize | Out-String -Width 160 | ForEach-Object { Say $_ }
$bad = @($results | Where-Object { $_.Exit -ne 0 })
Say ("decompile done  assemblies={0}  failed={1}" -f $results.Count, $bad.Count)
if ($bad.Count -gt 0) { exit 1 } else { exit 0 }
