#requires -Version 5.1
<#
  verify-claims.ps1 - machine-check every [claim:*] block in docs/mechanisms against the corpus.
  Claim block (see 00_PROJECT_RULES.md 3):
    [claim:ID] statement
      src: Namespace.Type.Member  Token: 0x...
      file: analysis/decompiled/<Asm>/<Path>.cs#Lnn
      match: literal that must appear in that file
  Optional extra line:
      anchor: literal; match is then searched within +/- 40 lines of the first anchor hit
  Exit 0 = all claims hit, exit 1 = at least one miss, exit 2 = no claim found.
#>
param(
    [string]$DocsRoot = '',
    [string]$ProjectRoot = '',
    [int]$Window = 40,
    [switch]$Gate
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($ProjectRoot)) {
    $ProjectRoot = $repoRoot
} elseif (-not [System.IO.Path]::IsPathRooted($ProjectRoot)) {
    $ProjectRoot = Join-Path $repoRoot $ProjectRoot
}
if ([string]::IsNullOrEmpty($DocsRoot)) {
    $DocsRoot = Join-Path $ProjectRoot 'docs\mechanisms'
} elseif (-not [System.IO.Path]::IsPathRooted($DocsRoot)) {
    $DocsRoot = Join-Path $repoRoot $DocsRoot
}
if (-not (Test-Path -LiteralPath $DocsRoot)) { Write-Output "no docs dir: $DocsRoot"; exit 2 }

$claimRx  = [regex]'^\s*\[claim:(?<id>[^\]]+)\]\s*(?<text>.*)$'
$fieldRx  = [regex]'^\s*(?<k>src|file|match|anchor|note)\s*:\s*(?<v>.*)$'
$fileCache = @{}

function Get-Lines([string]$path) {
    if ($fileCache.ContainsKey($path)) { return $fileCache[$path] }
    $lines = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Encoding UTF8 } else { $null }
    $fileCache[$path] = $lines
    return $lines
}

$claims = New-Object System.Collections.Generic.List[object]
foreach ($doc in (Get-ChildItem -LiteralPath $DocsRoot -File -Filter *.md | Sort-Object Name)) {
    $lines = Get-Content -LiteralPath $doc.FullName -Encoding UTF8
    $cur = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $m = $claimRx.Match($line)
        if ($m.Success) {
            if ($cur) { $claims.Add($cur) }
            $cur = [pscustomobject]@{
                Id = $m.Groups['id'].Value; Doc = $doc.Name; Line = $i + 1
                Text = $m.Groups['text'].Value.Trim()
                Src = ''; File = ''; Match = ''; Anchor = ''
            }
            continue
        }
        if ($cur) {
            $f = $fieldRx.Match($line)
            if ($f.Success) {
                switch ($f.Groups['k'].Value) {
                    'src'    { $cur.Src = $f.Groups['v'].Value.Trim() }
                    'file'   { $cur.File = $f.Groups['v'].Value.Trim() }
                    'match'  { $cur.Match = $f.Groups['v'].Value.Trim() }
                    'anchor' { $cur.Anchor = $f.Groups['v'].Value.Trim() }
                }
            } elseif ($line.Trim().Length -gt 0 -and -not $line.StartsWith(' ')) {
                $claims.Add($cur); $cur = $null
            }
        }
    }
    if ($cur) { $claims.Add($cur) }
}

if ($claims.Count -eq 0) { Write-Output 'no claims found'; exit 2 }

$fail = 0
$pass = 0
foreach ($c in $claims) {
    $problems = New-Object System.Collections.Generic.List[string]
    if (-not $c.File) { $problems.Add('missing file: field') }
    if (-not $c.Match) { $problems.Add('missing match: field') }
    $hitLine = 0
    $rel = $c.File
    if ($rel) {
        $rel = ($rel -replace '#L\d+.*$', '').Trim()
        $abs = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $ProjectRoot $rel }
        $abs = $abs -replace '/', '\'
        $lines = Get-Lines $abs
        if ($null -eq $lines) {
            $problems.Add("file not found: $rel")
        } elseif ($c.Match) {
            $from = 0; $to = $lines.Count - 1
            if ($c.Anchor) {
                $a = 0
                for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($c.Anchor)) { $a = $i; break } }
                if ($a -eq 0 -and -not $lines[0].Contains($c.Anchor)) { $problems.Add("anchor not found: $($c.Anchor)") }
                $from = [Math]::Max(0, $a - $Window); $to = [Math]::Min($lines.Count - 1, $a + $Window)
            }
            for ($i = $from; $i -le $to; $i++) {
                if ($lines[$i].Contains($c.Match)) { $hitLine = $i + 1; break }
            }
            if ($hitLine -eq 0) { $problems.Add("match not found: $($c.Match)") }
        }
    }
    if ($problems.Count -eq 0) {
        $pass++
        Write-Output ("PASS {0,-18} {1}:{2} ({3})" -f $c.Id, $c.Doc, $c.Line, $hitLine)
    } else {
        $fail++
        Write-Output ("FAIL {0,-18} {1}:{2}  {3}" -f $c.Id, $c.Doc, $c.Line, ($problems -join '; '))
    }
}

Write-Output ("claims={0} pass={1} fail={2}" -f $claims.Count, $pass, $fail)
$code = if ($fail -gt 0) { 1 } else { 0 }
if ($Gate) {
    $gateLog = Join-Path $ProjectRoot 'logs\GATE.log'
    $stamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $line = "{0}`tverify-claims`tclaims={1} pass={2} fail={3} exit={4}" -f $stamp, $claims.Count, $pass, $fail, $code
    Add-Content -LiteralPath $gateLog -Value $line -Encoding UTF8
}
exit $code
