#requires -Version 7.0
param(
    [string]$GameRoot = (Join-Path $PSScriptRoot '../RimWorld1.6'),
    [string]$DnSpy = 'E:/dnSpy/dnSpy.Console.exe',
    [string[]]$Assemblies = @('Assembly-CSharp.dll','UnityEngine.CoreModule.dll','UnityEngine.IMGUIModule.dll','UnityEngine.AudioModule.dll','UnityEngine.AssetBundleModule.dll','UnityEngine.InputLegacyModule.dll','UnityEngine.TextRenderingModule.dll','UnityEngine.PhysicsModule.dll')
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out = Join-Path $workspace 'analysis/decompiled1.6'
$evidence = Join-Path $workspace 'docs/readable/chapters/diff/evidence'
[IO.Directory]::CreateDirectory($out) | Out-Null
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$managed = Join-Path $GameRoot 'RimWorldWin64_Data/Managed'
$results = foreach ($assembly in $Assemblies) {
    $source = Join-Path $managed $assembly
    $name = [IO.Path]::GetFileNameWithoutExtension($assembly)
    if (Test-Path -LiteralPath (Join-Path $out $name)) { throw "Output already exists: $name (refusing to overwrite)" }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "BEGIN $assembly"
    & $DnSpy -o $out --no-resources --no-baml --no-sln --threads 8 --asm-path $managed $source *> (Join-Path $evidence "decompile-$name.log")
    $code = $LASTEXITCODE
    $watch.Stop()
    if ($code -ne 0) { throw "dnSpy failed: $assembly exit=$code" }
    $count = @(Get-ChildItem -LiteralPath (Join-Path $out $name) -Recurse -File -Filter '*.cs').Count
    Write-Host "END $assembly cs=$count elapsed=$($watch.Elapsed)"
    [pscustomobject]@{Assembly=$assembly;Exit=$code;CsFiles=$count;Seconds=$watch.Elapsed.TotalSeconds;SHA256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'decompilation.json') -Encoding utf8
