#requires -Version 7.0
param([string]$Dnlib = 'E:/dnSpy/bin/dnlib.dll', [switch]$GameOnly)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out = Join-Path $workspace 'docs/readable/chapters/diff/evidence/metadata'
[IO.Directory]::CreateDirectory($out) | Out-Null
[void][Reflection.Assembly]::LoadFrom($Dnlib)
$references = @($Dnlib) + @(Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $PSScriptRoot 'AssemblySnapshot.cs') -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'
$old = Join-Path $workspace 'RimWorld1.6/RimWorldWin64_Data/Managed'
$new = Join-Path $workspace 'RimWorld'
$targets = @(
    @('1.6', (Join-Path $old 'Assembly-CSharp.dll')),
    @('1.7', (Join-Path $new 'Assembly-CSharp.dll')),
    @('1.7', (Join-Path $new 'RimWorld.dll')),
    @('1.7', (Join-Path $new 'UnityStubs.dll')),
    @('1.7', (Join-Path $new 'Waylith.dll')),
    @('1.7', (Join-Path $new 'Waylith.UnityCompat.dll'))
)
$targets += @(Get-ChildItem -LiteralPath $old -File -Filter 'Unity*.dll' | ForEach-Object { ,@('1.6', $_.FullName) })
if ($GameOnly) { $targets = @($targets | Where-Object { [IO.Path]::GetFileName($_[1]) -eq 'Assembly-CSharp.dll' }) }
$manifest = foreach($target in $targets) {
    $path = [IO.Path]::GetFullPath($target[1])
    $prefix = Join-Path $out ($target[0] + '-' + [IO.Path]::GetFileNameWithoutExtension($path))
    $summary = [AssemblySnapshot]::Export($path, $prefix)
    Write-Host $summary
    [pscustomobject]@{Version=$target[0];File=$path.Substring($workspace.Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;Summary=$summary}
}
$manifestName = if ($GameOnly) { 'game-assembly-manifest.json' } else { 'assembly-manifest.json' }
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out "../$manifestName") -Encoding utf8
