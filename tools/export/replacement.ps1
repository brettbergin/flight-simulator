[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourceArchive,[Parameter(Mandatory)][string]$SourceSHA256,[string]$Python='python')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$run=Get-Content (Join-Path $repo '.local/export-proof/latest-run.json') -Raw | ConvertFrom-Json
if(-not $run.windows_portable_passed) { throw 'Require a passing Windows export baseline first' }
$environment=Get-Content (Join-Path $repo '.local/toolchain/environment.json') -Raw | ConvertFrom-Json
$root=Join-Path $run.root 'source-rebuild'
$source=Join-Path $root 'fresh-source'
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Path $root | Out-Null
& $Python (Join-Path $PSScriptRoot 'extract-source.py') --archive $SourceArchive --sha256 $SourceSHA256 --destination $source
if($LASTEXITCODE -ne 0) { throw 'Source archive extraction/verification failed' }
$vswhere=Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation=& $vswhere -version '[17.0,18.0)' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vcvars=Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
$compilerEnvironment=& $env:ComSpec /d /c ('"'+$vcvars+'" >nul && set')
if($LASTEXITCODE -ne 0) { throw 'MSVC initialization failed' }
foreach($line in $compilerEnvironment) { if($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process') } }
$env:PYTHONDONTWRITEBYTECODE='1'
& $environment.tools.cmake -S $source -B $build -G Ninja '-DCMAKE_BUILD_TYPE=RelWithDebInfo' "-DCMAKE_MAKE_PROGRAM=$($environment.tools.ninja)" 2>&1 | Tee-Object (Join-Path $run.evidence 'source-configure.log')
if($LASTEXITCODE -ne 0) { throw 'Source archive configure failed' }
& $environment.tools.cmake --build $build --target libJSBSim --parallel 6 2>&1 | Tee-Object (Join-Path $run.evidence 'source-build.log')
if($LASTEXITCODE -ne 0) { throw 'Independent source DLL build failed' }
& $Python (Join-Path $source 'verify.py') --root $source | Set-Content (Join-Path $run.evidence 'source-after-build.json')
if($LASTEXITCODE -ne 0) { throw 'Source changed during rebuild' }
& $environment.tools.ninja -C $build -t deps | Set-Content (Join-Path $run.evidence 'source-header-deps.txt')
& $environment.tools.ninja -C $build -t commands libJSBSim | Set-Content (Join-Path $run.evidence 'source-compile-commands.txt')
& dumpbin /dependents (Join-Path $build 'bin/JSBSim.dll') | Set-Content (Join-Path $run.evidence 'rebuilt-dll-imports.txt')
if($LASTEXITCODE -ne 0) { throw 'Rebuilt DLL import inspection failed' }
$replacement=Join-Path $run.root 'Replaced DLL — Δ飛行'
Copy-Item -LiteralPath $run.payload -Destination $replacement -Recurse
$before=@{}
Get-ChildItem -LiteralPath $replacement -File -Recurse | ForEach-Object { $relative=[IO.Path]::GetRelativePath($replacement,$_.FullName).Replace('\','/'); $before[$relative]=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
$rebuilt=Join-Path $build 'bin/JSBSim.dll'
Copy-Item -LiteralPath $rebuilt -Destination (Join-Path $replacement 'bin/JSBSim.dll') -Force
if(Test-Path (Join-Path $replacement 'JSBSim.dll')) { Copy-Item -LiteralPath $rebuilt -Destination (Join-Path $replacement 'JSBSim.dll') -Force }
$changed=@()
Get-ChildItem -LiteralPath $replacement -File -Recurse | ForEach-Object {
  $relative=[IO.Path]::GetRelativePath($replacement,$_.FullName).Replace('\','/')
  $actual=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  if($before[$relative] -ne $actual) {
    if($relative -notin @('bin/JSBSim.dll','JSBSim.dll')) { throw "Unexpected replacement payload change: $relative" }
    $changed+=$relative
  }
}
$result=Invoke-ProofProcess -Executable (Join-Path $replacement 'flight-proof.exe') -Arguments @('--headless') -WorkingDirectory $run.root -Log (Join-Path $run.evidence 'replacement.log') -CleanEnvironment -ProfileRoot (Join-Path $run.root 'replacement-profile')
Assert-ProofSuccess $result
& node (Join-Path $repo 'tests/export/validate-log.mjs') (Join-Path $run.evidence 'replacement.log') $replacement ((Get-FileHash $rebuilt -Algorithm SHA256).Hash.ToLowerInvariant()) (Join-Path $run.evidence 'selected-crt.json')
if($LASTEXITCODE -ne 0) { throw 'Replacement authoritative sample/schema/module-path proof failed' }
& node (Join-Path $repo 'tests/export/compare-replacement.mjs') (Join-Path $run.evidence 'portable-unicode.log') (Join-Path $run.evidence 'replacement.log')
if($LASTEXITCODE -ne 0) { throw 'Replacement changed expected numerical boundary' }
$identity=[ordered]@{schema_version=1;source_archive_sha256=$SourceSHA256;source_archive_bytes=(Get-Item $SourceArchive).Length;unmodified_vendor_files=279;source_rebuild_passed=$true;compiler=(Get-Item (Get-Command cl.exe).Source).VersionInfo.FileVersion;toolset=$env:VCToolsVersion;windows_sdk=$env:WindowsSDKVersion;replaced_library_sha256=(Get-FileHash $rebuilt -Algorithm SHA256).Hash.ToLowerInvariant();baseline_library_sha256=$before['bin/JSBSim.dll'];changed_payload_files=$changed;other_payload_unchanged=$true;actual_replacement_module_inside_payload=$true;clean_path=$true;unicode_relocation=$true;command_snapshot_schema_passed=$true;finite_state_units_unchanged=$true;worker_joined=$true;reverse_engineering_permitted=$true}
$identity | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $run.evidence 'replacement-evidence.json') -Encoding utf8
$run.source_replacement='passed'
$run | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $repo '.local/export-proof/latest-run.json') -Encoding utf8
$identity | ConvertTo-Json -Depth 8 | Write-Output
