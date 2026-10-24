#requires -Version 7.0
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dnlib='E:/dnSpy/bin/dnlib.dll'
[void][Reflection.Assembly]::LoadFrom($dnlib)
$references=@($dnlib)+@(Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
Add-Type -Path (Join-Path $PSScriptRoot 'AssemblySnapshot.cs') -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701'
foreach($version in @('1.6','1.7')) {
    $game = if($version -eq '1.6') { Join-Path $workspace 'RimWorld1.6/RimWorldWin64_Data/Managed/Assembly-CSharp.dll' } else { Join-Path $workspace 'RimWorld/Assembly-CSharp.dll' }
    [AssemblySnapshot]::AuditReferences($game,(Join-Path $workspace 'RimWorld/UnityStubs.dll'),(Join-Path $workspace "docs/readable/chapters/diff/evidence/$version-unity-reference-signatures.tsv"))
}
