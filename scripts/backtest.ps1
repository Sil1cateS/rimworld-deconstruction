#requires -Version 5.1
<#
  backtest.ps1 - independent regression of every documented rule against the binaries.
  Three independent checks, none of which trusts the decompiled corpus:
    1. GOLDEN: a table of key constants/idioms is re-decompiled straight from the DLL via
       dnSpy.Console -t and the literal must appear in the fresh output.
    2. SAMPLE: claims from the docs are sampled; their owning type is re-decompiled from the
       DLL and the claim's literal must appear in that fresh output (catches corpus drift).
    3. INTEGRITY: corpus file counts, Waylith type coverage, doc/claim census.
  ASCII only (Windows PowerShell 5.1 reads BOM-less non-ASCII scripts as GBK and breaks).
#>
param(
    [string]$GameRoot    = (Join-Path $PSScriptRoot '..\RimWorld'),
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..'),
    [string]$DnSpy       = $(if ($env:DNSPY_CONSOLE) { $env:DNSPY_CONSOLE } else { 'dnSpy.Console.exe' }),
    [int]$SampleTypes    = 30,
    [int]$TimeoutSec     = 25,
    [switch]$Gate
)

$ErrorActionPreference = 'Continue'
$docsRoot = Join-Path $ProjectRoot 'docs\mechanisms'
$indexTsv = Join-Path $ProjectRoot 'analysis\index\types.tsv'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $ProjectRoot ("logs\backtest-{0}.log" -f $stamp)
function Say([string]$t) { Write-Output $t; Add-Content -LiteralPath $report -Value $t -Encoding UTF8 }

Say ("backtest start " + (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'))
$fail = 0
$pass = 0

function Invoke-Dump([string]$type, [string]$asm) {
    $asmPath = Join-Path $GameRoot $asm
    $job = Start-Job -ScriptBlock { param($exe, $t, $a) & $exe -t $t $a 2>&1 } -ArgumentList $DnSpy, $type, $asmPath
    $done = Wait-Job $job -Timeout $TimeoutSec
    if (-not $done) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Get-Process -Name dnSpy.Console -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $null
    }
    $lines = @(Receive-Job $job)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($lines.Count -lt 3) { return $null }
    return ($lines -join "`n")
}

# ---------- 1. GOLDEN constants ----------
Say "--- GOLDEN (re-decompile from DLL, 13 key rules) ---"
$golden = @(
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.TickManager';                     Lit='ticksThisFrame < tickRateMultiplier * 2f'; What='per-frame tick cap = multiplier x2' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.TickManager';                     Lit='45.454544f';                              What='single-frame budget 45.45ms' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.TickList';                        Lit='return 250;';                             What='Rare bucket interval 250' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.TickList';                        Lit='return 2000;';                            What='Long bucket interval 2000' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.GenTicks';                        Lit='public const int TicksPerRealSecond = 60;'; What='60 ticks per second' },
    @{ Asm='Assembly-CSharp.dll'; Type='RimWorld.GenDate';                      Lit='public const int TicksPerYear = 3600000;'; What='one year = 3600000 ticks' },
    @{ Asm='Assembly-CSharp.dll'; Type='RimWorld.Need_Food';                    Lit='* 150f';                                  What='need quantum 150 ticks' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.ArmorUtility';                    Lit='float num = damAmount * 0.25f;';          What='apparel takes 25% damage' },
    @{ Asm='Assembly-CSharp.dll'; Type='RimWorld.Storyteller';                  Lit='% 1000 == 0';                             What='incident cadence 1000 ticks' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.HediffComp_SeverityModifierBase'; Lit='0.0033333334f';                           What='severity scale 200/60000' },
    @{ Asm='Assembly-CSharp.dll'; Type='Verse.Room';                            Lit='this.RegionCount > 60';                   What='IsHuge threshold 60 regions' },
    @{ Asm='Waylith.dll';         Type='Waylith.Jobs.WaylithJobRuntime';        Lit='Environment.ProcessorCount - 1';          What='job workers = cores - 1' },
    @{ Asm='Waylith.dll';         Type='Waylith.EngineApplication';             Lit='this._stopwatch.Elapsed.TotalSeconds';    What='frame source is Stopwatch' }
)
foreach ($g in $golden) {
    $text = Invoke-Dump $g.Type $g.Asm
    if ($null -eq $text) { Say ("FAIL  GOLDEN {0,-40} dump failed/timeout ({1})" -f $g.What, $g.Type); $fail++; continue }
    if ($text.Contains($g.Lit)) { Say ("PASS  GOLDEN {0,-40} {1}" -f $g.What, $g.Type); $pass++ }
    else { Say ("FAIL  GOLDEN {0,-40} literal missing: {1}" -f $g.What, $g.Lit); $fail++ }
}

# ---------- 2. SAMPLE claims ----------
Say "--- SAMPLE (claims re-checked against fresh DLL output) ---"
$claimRx = [regex]'^\s*\[claim:(?<id>[^\]]+)\]'
$fileRx  = [regex]'^\s*file\s*:\s*(?<v>.+)$'
$matchRx = [regex]'^\s*match\s*:\s*(?<v>.+)$'
$claims = New-Object System.Collections.Generic.List[object]
foreach ($doc in (Get-ChildItem -LiteralPath $docsRoot -File -Filter *.md | Sort-Object Name)) {
    $cur = $null
    foreach ($line in (Get-Content -LiteralPath $doc.FullName -Encoding UTF8)) {
        $m = $claimRx.Match($line)
        if ($m.Success) { if ($cur) { $claims.Add($cur) }; $cur = [pscustomobject]@{ Id = $m.Groups['id'].Value; File = ''; Match = '' }; continue }
        if ($cur) {
            $f = $fileRx.Match($line); if ($f.Success) { $cur.File = $f.Groups['v'].Value.Trim(); continue }
            $mm = $matchRx.Match($line); if ($mm.Success) { $cur.Match = $mm.Groups['v'].Value.Trim() }
        }
    }
    if ($cur) { $claims.Add($cur) }
}
Say ("claims parsed: {0}" -f $claims.Count)

$map = @{}
foreach ($line in (Get-Content -LiteralPath $indexTsv -Encoding UTF8 | Select-Object -Skip 1)) {
    $c = $line -split "`t"
    $key = ($c[5] -replace '/', '\')
    if (-not $map.ContainsKey($key)) { $map[$key] = @{ Asm = ($c[0] + '.dll'); Type = $c[2] } }
}
Say ("index entries: {0}" -f $map.Count)

$byType = @{}
foreach ($c in $claims) {
    if (-not $c.File -or -not $c.Match) { continue }
    $rel = ($c.File -replace '#L\d+.*$', '').Trim() -replace '/', '\'
    $rel = $rel -replace '^analysis\\decompiled\\', ''
    if (-not $map.ContainsKey($rel)) { continue }
    $t = $map[$rel].Type
    if (-not $byType.ContainsKey($t)) { $byType[$t] = @{ Asm = $map[$rel].Asm; Claims = New-Object System.Collections.Generic.List[object] } }
    $byType[$t].Claims.Add($c)
}
Say ("mapped types: {0}" -f $byType.Count)
$typeKeys = @($byType.Keys | Sort-Object)
$step = [Math]::Max(1, [Math]::Floor($typeKeys.Count / $SampleTypes))
$picked = @()
for ($i = 0; $i -lt $typeKeys.Count -and $picked.Count -lt $SampleTypes; $i += $step) { $picked += $typeKeys[$i] }
Say ("sampled types: {0} (step={1})" -f $picked.Count, $step)

foreach ($t in $picked) {
    $info = $byType[$t]
    $text = Invoke-Dump $t $info.Asm
    if ($null -eq $text) { Say ("FAIL  SAMPLE {0} dump failed/timeout" -f $t); $fail++; continue }
    $bad = 0
    foreach ($c in $info.Claims) { if (-not $text.Contains($c.Match)) { Say ("FAIL  SAMPLE {0} claim {1} literal missing in fresh dump" -f $t, $c.Id); $bad++ } }
    if ($bad -eq 0) { Say ("PASS  SAMPLE {0,-46} {1} claim(s)" -f $t, $info.Claims.Count); $pass++ } else { $fail++ }
}

# ---------- 3. INTEGRITY ----------
Say "--- INTEGRITY ---"
$corpusRoot = Join-Path $ProjectRoot 'analysis\decompiled'
$corpus = Get-ChildItem $corpusRoot -Recurse -File -Include *.cs,*.il
Say ("corpus files={0} MB={1:N1}" -f $corpus.Count, (($corpus | Measure-Object Length -Sum).Sum / 1MB))
foreach ($a in ($corpus | Group-Object { $_.FullName.Substring($corpusRoot.Length + 1).Split('\')[0] } | Sort-Object Name)) {
    Say ("  {0,-20} {1,5} files" -f $a.Name, $a.Count)
}

$wlTypes = Join-Path $ProjectRoot 'analysis\index\waylith-types.tsv'
if (Test-Path $wlTypes) {
    $wlRows = @(Get-Content -LiteralPath $wlTypes -Encoding UTF8 | Select-Object -Skip 1)
    $names = New-Object 'System.Collections.Generic.HashSet[string]'
    Get-ChildItem (Join-Path $corpusRoot 'Waylith') -Recurse -File -Include *.cs,*.il | ForEach-Object { [void]$names.Add($_.BaseName.ToLower()) }
    $miss = 0
    foreach ($line in $wlRows) {
        $c = $line -split "`t"; $short = (($c[3] -split '\.')[-1]) -replace '[<>]', '-' -replace '`\d+$', '' -replace '[+]', '.'
        if (-not $names.Contains($short.ToLower())) { $miss++ }
    }
    Say ("waylith coverage: {0} types, missing_files={1}" -f $wlRows.Count, $miss)
    if ($miss -eq 0) { $pass++ } else { $fail++ }
} else { Say "FAIL waylith-types.tsv missing"; $fail++ }

$docCount = (Get-ChildItem -LiteralPath $docsRoot -File -Filter 'V*.md').Count
Say ("docs={0} claims={1}" -f $docCount, $claims.Count)
if ($docCount -eq 24 -and $claims.Count -eq 621) { $pass++ } else { Say "FAIL census mismatch"; $fail++ }

Say ("backtest done: pass={0} fail={1}" -f $pass, $fail)
if ($Gate) {
    $gateLog = Join-Path $ProjectRoot 'logs\GATE.log'
    $line = "{0}`tbacktest`tgolden=13`tsample_types={1}`tclaims={2}`tdocs={3}`tpass={4}`tfail={5}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'), $picked.Count, $claims.Count, $docCount, $pass, $fail
    Add-Content -LiteralPath $gateLog -Value $line -Encoding UTF8
}
if ($fail -gt 0) { exit 1 } else { exit 0 }
