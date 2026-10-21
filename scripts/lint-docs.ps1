#requires -Version 5.1
<#
  lint-docs.ps1 - structural gate for docs/mechanisms.
  Checks per document:
    1. six required English section anchors, in order
    2. every ``` fence is closed; every mermaid block is closed and non-empty
    3. every relative markdown link target exists
    4. every [claim:ID] block has file: and match: fields; ids are unique across the doc set
  ASCII only: section anchors are English so this script stays ASCII while docs stay Chinese-primary.
#>
param(
    [string]$DocsRoot = '',
    [ValidateSet('v1', 'v3')][string]$Profile = 'v1'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($DocsRoot)) {
    $DocsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\mechanisms'
}
if (-not [System.IO.Path]::IsPathRooted($DocsRoot)) {
    $DocsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) $DocsRoot
}
if ($Profile -eq 'v3') {
    $required = @('## Where it sits', '## Evolution', '## Stage detail', '## Branches', '## Contracts', '## Evidence', '## Open questions')
} else {
    $required = @('## Scope', '## Key types', '## Control flow', '## Constants', '## Claims', '## Open questions')
}
$docs = @(Get-ChildItem -LiteralPath $DocsRoot -File -Filter *.md -ErrorAction SilentlyContinue | Sort-Object Name)
if ($docs.Count -eq 0) { Write-Output 'no docs found'; exit 2 }

$errors = New-Object System.Collections.Generic.List[string]
$claimIds = @{}
$claimCount = 0
$mermaidCount = 0

foreach ($doc in $docs) {
    $lines = Get-Content -LiteralPath $doc.FullName -Encoding UTF8
    $rel = $doc.Name
    $headings = @()
    $inFence = $false
    $mermaidStart = 0
    $mermaidLines = 0
    $docMermaid = 0
    $relLinks = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $t = $line.TrimEnd()
        if ($t.StartsWith('```')) {
            if (-not $inFence) {
                $inFence = $true
                if ($t.StartsWith('```mermaid')) { $mermaidStart = $i + 1; $mermaidLines = 0 }
            } else {
                $inFence = $false
                if ($mermaidStart -gt 0) {
                    if ($mermaidLines -eq 0) { $errors.Add("${rel}:$mermaidStart empty mermaid block") }
                    $mermaidCount++
                    $docMermaid++
                    $mermaidStart = 0
                }
            }
            continue
        }
        if ($mermaidStart -gt 0) { if ($t.Trim().Length -gt 0) { $mermaidLines++ }; continue }
        if ($t -match '^##\s') { $headings += $t }
        if ($t -match '^\[claim:(?<id>[^\]]+)\]') {
            $id = $Matches['id']
            $claimCount++
            if ($claimIds.ContainsKey($id)) { $errors.Add("${rel}:$($i+1) duplicate claim id $id") } else { $claimIds[$id] = $rel }
            # look ahead for file:/match: inside the block
            $hasFile = $false; $hasMatch = $false
            for ($k = $i + 1; $k -lt [Math]::Min($i + 8, $lines.Count); $k++) {
                $n = $lines[$k]
                if ($n -match '^\s*file\s*:') { $hasFile = $true }
                if ($n -match '^\s*match\s*:') { $hasMatch = $true }
                if ($n -match '^\s*\[claim:') { break }
            }
            if (-not $hasFile)  { $errors.Add("${rel}:$($i+1) claim $id missing file:") }
            if (-not $hasMatch) { $errors.Add("${rel}:$($i+1) claim $id missing match:") }
        }
        # claim 字段行里是代码字面量（可能含 A[i](x) 这类片段），不当作 markdown 链接
        if ($t -notmatch '^\s*(src|file|match|anchor|note)\s*:') {
            foreach ($m in [regex]::Matches($t, '\]\((?<t>[^)#\s]+)(#[^)]*)?\)')) {
                $target = $m.Groups['t'].Value
                if ($target -match '^(https?:|mailto:)') { continue }
                $relLinks += @{ Target = $target; Line = $i + 1 }
            }
        }
    }
    if ($inFence) { $errors.Add("$rel unclosed code fence") }
    if ($Profile -eq 'v3' -and $docMermaid -eq 0) { $errors.Add("$rel missing mermaid diagram (v3 requires at least one)") }

    foreach ($req in $required) {
        if (-not ($headings -contains $req)) { $errors.Add("$rel missing section: $req") }
    }
    if ($required.Count -ge 2) {
        $idx = @()
        foreach ($req in $required) { $idx += [array]::IndexOf($headings, $req) }
        for ($i = 1; $i -lt $idx.Count; $i++) {
            if ($idx[$i] -ge 0 -and $idx[$i - 1] -ge 0 -and $idx[$i] -lt $idx[$i - 1]) {
                $errors.Add("$rel section order broken at $($required[$i])")
            }
        }
    }
    foreach ($l in $relLinks) {
        $path = Join-Path $DocsRoot $l.Target
        if (-not (Test-Path -LiteralPath $path)) { $errors.Add("$rel`:$($l.Line) broken link -> $($l.Target)") }
    }
}

if ($Profile -eq 'v3') {
    foreach ($doc in $docs) {
        $lines = Get-Content -LiteralPath $doc.FullName -Encoding UTF8
        $blocks = @()
        $i = 0
        while ($i -lt $lines.Count) {
            if ($lines[$i].Trim().StartsWith('```')) {
                $lang = $lines[$i].Trim().Substring(3).Trim()
                $start = $i
                $i++
                $body = @()
                while ($i -lt $lines.Count -and -not $lines[$i].Trim().StartsWith('```')) { $body += $lines[$i]; $i++ }
                $blocks += [pscustomobject]@{ Lang = $lang; Body = ($body -join "`n"); Line = $start + 1; IsClass = (($body -join "`n") -match '(?m)^\s*(?:[a-z]+ )*(?:class|struct|enum)\s') }
            }
            $i++
        }
        for ($k = 0; $k -lt $blocks.Count - 1; $k++) {
            if ($blocks[$k].Lang -eq 'csharp' -and -not $blocks[$k].IsClass -and $blocks[$k + 1].Lang -eq 'text') {
                $sa = 0
                foreach ($l in ($blocks[$k].Body -split "`n")) {
                    $code = $l
                    $ci = $code.IndexOf('//')
                    if ($ci -ge 0) { $code = $code.Substring(0, $ci) }
                    $t = $code.Trim()
                    if ($t -eq '' -or $t -eq '{' -or $t -eq '}') { continue }
                    $sa++
                }
                $sb = 0
                foreach ($l in ($blocks[$k + 1].Body -split "`n")) {
                    $t = $l.Trim()
                    if ($t -eq '' -or $t.StartsWith('#')) { continue }
                    $sb++
                }
                if ($sa -ne $sb) { $errors.Add("$($doc.Name):$($blocks[$k].Line) source/pseudo statement count differs src=$sa pseudo=$sb") }
            }
        }
        $srcRx = [regex]'^\*\*\u6E90\u7801\*\*\uFF08'
        $introRx = [regex]'^\*\*\u8FD9\u4E00\u6BB5\u505A\u4EC0\u4E48\*\*\uFF1A'
        for ($m = 0; $m -lt $lines.Count; $m++) {
            if (-not $srcRx.IsMatch($lines[$m])) { continue }
            $found = $false
            for ($p = $m - 1; $p -ge [Math]::Max(0, $m - 2); $p--) { if ($introRx.IsMatch($lines[$p])) { $found = $true; break } }
            if (-not $found) { $errors.Add("$($doc.Name):$($m + 1) source block has no function intro line") }
        }
    }
}

Write-Output ("docs={0} claims={1} mermaid={2} errors={3}" -f $docs.Count, $claimCount, $mermaidCount, $errors.Count)
foreach ($e in $errors) { Write-Output ("ERROR " + $e) }
if ($errors.Count -gt 0) { exit 1 }
exit 0
