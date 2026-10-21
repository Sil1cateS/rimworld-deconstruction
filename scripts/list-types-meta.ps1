#requires -Version 7.0
<#
  list-types-meta.ps1 - authoritative TypeDef enumeration straight from ECMA-335 metadata.
  Why: dnSpy.Console cannot list types, and PowerShell 7 ships a type-less facade of
  System.Reflection.Metadata. We therefore load the real implementation from the installed
  .NET shared framework inside a private AssemblyLoadContext, bypassing the facade binding.
  ASCII only.
#>
param(
    [Parameter(Mandatory = $true)][string]$Assembly,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Assembly)) { Write-Output "missing: $Assembly"; exit 2 }

$fwRoot = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App'
$fw = Get-ChildItem -LiteralPath $fwRoot -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$srmPath = Join-Path $fw.FullName 'System.Reflection.Metadata.dll'
Write-Output ("framework={0}" -f $fw.Name)
Write-Output ("srm={0} exists={1}" -f $srmPath, (Test-Path -LiteralPath $srmPath))
if (-not (Test-Path -LiteralPath $srmPath)) { exit 2 }

$alc = [System.Runtime.Loader.AssemblyLoadContext]::new('srm-isolated', $false)
$srm = $alc.LoadFromAssemblyPath($srmPath)
$peType = $srm.GetType('System.Reflection.PortableExecutable.PEReader')
Write-Output ("PEReader type = " + $(if ($peType) { $peType.FullName } else { 'NULL' }))
if (-not $peType) { exit 3 }

$fs = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Assembly).Path)
try {
    $pe = [System.Activator]::CreateInstance($peType, @($fs))
    $ext = $srm.GetType('System.Reflection.Metadata.PEReaderExtensions')
    $md = $ext::GetMetadataReader($pe)
    $count = $md.TypeDefinitions.Count
    Write-Output ("TypeDefinitions={0}" -f $count)

    $rows = New-Object System.Collections.Generic.List[object]
    $ridCounter = 0
    foreach ($h in $md.TypeDefinitions) {
        $ridCounter++
        $td = $md.GetTypeDefinition($h)
        $name = $md.GetString($td.Name)
        if ($name -eq '<Module>') { continue }
        $ns = $md.GetString($td.Namespace)

        $chain = New-Object System.Collections.Generic.List[string]
        $chain.Add($name)
        $decl = $td.GetDeclaringType()
        $depth = 0
        while (-not $decl.IsNil) {
            $dt = $md.GetTypeDefinition($decl)
            $chain.Insert(0, $md.GetString($dt.Name))
            $ns2 = $md.GetString($dt.Namespace)
            if ($ns2) { $ns = $ns2 }
            $decl = $dt.GetDeclaringType()
            $depth++
        }
        $simple = ($chain -join '+')
        $full = if ($ns) { "$ns.$simple" } else { $simple }
        $token = 0x02000000 -bor $ridCounter
        $rows.Add([pscustomobject]@{
            Rid     = $token -band 0xFFFFFF
            Token   = ('0x{0:X8}' -f $token)
            Depth   = $depth
            Type    = $full
            Kind    = if (($td.Attributes -band [System.Reflection.TypeAttributes]::Interface) -ne 0) { 'interface' } else { 'type' }
            Methods = $td.GetMethods().Count
        })
    }
    Write-Output ("types(excluding <Module>)={0}" -f $rows.Count)
    $sorted = $rows | Sort-Object Rid
    if ($OutFile) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("rid`ttoken`tdepth`ttype`tkind`tmethods")
        foreach ($r in $sorted) { [void]$sb.AppendLine(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $r.Rid, $r.Token, $r.Depth, $r.Type, $r.Kind, $r.Methods)) }
        [System.IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
        Write-Output ("written: {0}" -f $OutFile)
    } else {
        $sorted | Select-Object -First 20 | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Token, $_.Depth, $_.Type }
    }
} finally {
    $fs.Dispose()
}
