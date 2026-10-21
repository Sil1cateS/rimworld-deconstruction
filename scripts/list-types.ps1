#requires -Version 5.1
<#
  list-types.ps1 - build the type index from the decompiled corpus (no extra dependencies).
  For every generated .cs file: namespace, full type name (nested as Outer+Inner), kind, Token RID, file, line, approx loc.
  This index is the same surface the mechanism docs cite, so claim verification and index always agree.
  ASCII only (Windows PowerShell 5.1 + UTF-8 without BOM silently corrupts non-ASCII text).
#>
param(
    [string]$Root   = (Join-Path $PSScriptRoot '..\analysis\decompiled'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\analysis\index'),
    [string]$LogDir = (Join-Path $PSScriptRoot '..\logs')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$nsRx   = [regex]'^namespace\s+(?<ns>[A-Za-z0-9_.]+)\s*$'
$nsFile = [regex]'^namespace\s+(?<ns>[A-Za-z0-9_.]+)\s*;'
$tokRx  = [regex]'//\s*Token:\s*(?<token>0x[0-9A-Fa-f]+)\s+RID:\s*(?<rid>\d+)'
$typeRx = [regex]'^\s*(?<mods>(?:(?:public|internal|private|protected|static|sealed|abstract|partial|readonly|ref|unsafe|new|file)\s+)*)(?<kind>class|struct|interface|enum|record|delegate)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)'

$rows = New-Object System.Collections.Generic.List[object]
$assemblies = Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $LogDir ("index-{0}.log" -f $stamp)
function Say([string]$t) { Write-Output $t; Add-Content -LiteralPath $log -Value $t -Encoding UTF8 }

foreach ($asmDir in $assemblies) {
    $asm = $asmDir.Name
    $files = @(Get-ChildItem -LiteralPath $asmDir.FullName -Recurse -File -Include *.cs,*.il)
    Say ("scan {0}: {1} files" -f $asm, $files.Count)
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8
        $total = $lines.Count
        $ns = ''
        $pending = $null
        $stack = @{}
        $decl = New-Object System.Collections.Generic.List[object]

        for ($n = 0; $n -lt $total; $n++) {
            $line = $lines[$n]
            $m = $nsRx.Match($line)
            if ($m.Success) { $ns = $m.Groups['ns'].Value; continue }
            $m = $nsFile.Match($line)
            if ($m.Success) { $ns = $m.Groups['ns'].Value; continue }
            $m = $tokRx.Match($line)
            if ($m.Success) { $pending = $m.Groups['token'].Value; continue }
            $m = $typeRx.Match($line)
            if ($m.Success) {
                $name = $m.Groups['name'].Value
                $depth = $line.Length - $line.TrimStart("`t").Length
                if ($depth -le 1) {
                    $full = if ($ns) { "$ns.$name" } else { $name }
                } else {
                    $parent = $stack[$depth - 1]
                    $full = if ($parent) { "$parent+$name" } else { $name }
                }
                $stack[$depth] = $full
                $decl.Add([pscustomobject]@{ Line = $n + 1; Full = $full; Kind = $m.Groups['kind'].Value; Token = $pending })
                $pending = $null
            }
        }

        for ($k = 0; $k -lt $decl.Count; $k++) {
            $d = $decl[$k]
            $endLine = if ($k + 1 -lt $decl.Count) { $decl[$k + 1].Line } else { $total + 1 }
            $lastDot = $d.Full.LastIndexOf('.')
            $nsOut = ''
            if ($lastDot -gt 0 -and -not $d.Full.Substring(0, $lastDot).Contains('+')) { $nsOut = $d.Full.Substring(0, $lastDot) }
            elseif ($lastDot -gt 0) { $nsOut = $d.Full.Substring(0, $d.Full.IndexOf('.')) }
            $rows.Add([pscustomobject]@{
                Assembly  = $asm
                Namespace = $nsOut
                Type      = $d.Full
                Kind      = $d.Kind
                Token     = if ($d.Token) { $d.Token } else { '' }
                File      = $rel
                Line      = $d.Line
                LocApprox = $endLine - $d.Line
            })
        }
    }
}

$typesPath = Join-Path $OutDir 'types.tsv'
$nsPath    = Join-Path $OutDir 'namespaces.tsv'

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("assembly`tnamespace`ttype`tkind`ttoken`tfile`tline`tloc_approx")
foreach ($r in ($rows | Sort-Object Assembly, Type)) {
    [void]$sb.AppendLine(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}" -f $r.Assembly, $r.Namespace, $r.Type, $r.Kind, $r.Token, $r.File, $r.Line, $r.LocApprox))
}
[System.IO.File]::WriteAllText($typesPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$nsRows = $rows | Group-Object Assembly, Namespace | ForEach-Object {
    [pscustomobject]@{
        Assembly  = $_.Group[0].Assembly
        Namespace = $_.Group[0].Namespace
        Types     = $_.Count
        LocApprox = ($_.Group | Measure-Object LocApprox -Sum).Sum
    }
}
$sb2 = New-Object System.Text.StringBuilder
[void]$sb2.AppendLine("assembly`tnamespace`ttypes`tloc_approx")
foreach ($r in ($nsRows | Sort-Object Assembly, Namespace)) {
    [void]$sb2.AppendLine(("{0}`t{1}`t{2}`t{3}" -f $r.Assembly, $r.Namespace, $r.Types, $r.LocApprox))
}
[System.IO.File]::WriteAllText($nsPath, $sb2.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Say ("TOTAL types={0} namespaces={1}" -f $rows.Count, @($nsRows).Count)
Say ("written: {0}" -f $typesPath)
Say ("written: {0}" -f $nsPath)
$rows | Group-Object Assembly | ForEach-Object { Say ("  {0}: {1} types" -f $_.Name, $_.Count) }
