[CmdletBinding()]
param([switch]$EditorOnly,[string]$Python='python',[string]$NativeBuildRoot='', [string]$ToolchainRoot='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if([string]::IsNullOrWhiteSpace($ToolchainRoot)){$ToolchainRoot=Join-Path $repo '.local/toolchain'}
$environment=Get-Content (Join-Path $ToolchainRoot 'environment.json') -Raw | ConvertFrom-Json
$godot=$environment.tools.godot
if([string]::IsNullOrWhiteSpace($NativeBuildRoot)){$NativeBuildRoot=Join-Path $repo '.local/build/native-release'}
. (Join-Path $repo 'tools/interactive-preview/simulation-staging.ps1')
$nativeIdentity=Get-PreviewNativeBuildIdentity -RepoRoot $repo -NativeBuildRoot $NativeBuildRoot -Python $Python
$build=$nativeIdentity.root
$windowsHost=$env:OS -eq 'Windows_NT'
if(-not $windowsHost -and -not $EditorOnly) { throw 'Release export proof currently targets Windows only' }
$root=Join-Path $repo ('.local/export-proof/run-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Force -Path $project,$evidence,(Join-Path $project 'bin') | Out-Null
$nativeIdentity | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'native-build-identity.json') -Encoding utf8
$rawSelection=& node (Join-Path $PSScriptRoot 'selected-source.mjs') build (Join-Path $evidence 'native-build-identity.json')
if($LASTEXITCODE -ne 0){throw 'Selected source has no matching reviewed release policy'}
$selection=$rawSelection|ConvertFrom-Json -ErrorAction Stop
$selection|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $evidence 'selected-library-release.json') -Encoding utf8
Get-ChildItem -LiteralPath (Join-Path $repo 'app/proof') -File | Copy-Item -Destination $project
Copy-Item -LiteralPath (Join-Path $repo 'tests/export/initializer.bin') -Destination (Join-Path $project 'initializer.bin')
Copy-Item -LiteralPath (Join-Path $repo 'native/fdm_jsbsim/models/original-synthetic') -Destination (Join-Path $project 'models') -Recurse
$bridge=if($windowsHost) {'flight_godot_bridge.dll'} else {'libflight_godot_bridge.so'}
$jsbsim=if($windowsHost) {'JSBSim.dll'} else {'libJSBSim.so'}
Copy-Item -LiteralPath (Join-Path $build "bin/$bridge") -Destination (Join-Path $project "bin/$bridge")
Copy-Item -LiteralPath (Join-Path $build "bin/$jsbsim") -Destination (Join-Path $project "bin/$jsbsim")
if(-not $windowsHost) {
  # The pinned upstream library's DT_SONAME is libJSBSim.so.1. Copy the
  # dereferenced bytes under that runtime name as well as the link name.
  Copy-Item -LiteralPath (Join-Path $build 'bin/libJSBSim.so.1') -Destination (Join-Path $project 'bin/libJSBSim.so.1')
}
$crtFiles=@()
if($windowsHost) {
  $vswhere=Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio/Installer/vswhere.exe'
  $installation=& $vswhere -version '[17.0,18.0)' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if(-not $installation) { throw 'Selected MSVC release redistributables not found' }
  $redistRoot=Join-Path $installation 'VC/Redist/MSVC'
  $redist=Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object {$_.Name -match '^14\.\d+\.\d+$'} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
  if(-not $redist) { throw 'Release CRT version directory missing' }
  foreach($name in @('msvcp140.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    $source=Join-Path $redist.FullName "x64/Microsoft.VC143.CRT/$name"
    if(-not (Test-Path -LiteralPath $source) -or $source -match 'debug_nonredist') { throw 'Required release CRT unavailable' }
    $signature=Get-AuthenticodeSignature -LiteralPath $source
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') { throw 'CRT Microsoft signature invalid' }
    $identity=[ordered]@{name=$name;source=$source;version=(Get-Item $source).VersionInfo.FileVersion;bytes=(Get-Item $source).Length;sha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();signature='Valid';signer=$signature.SignerCertificate.Subject}
    $crtFiles+=$identity
    Copy-Item -LiteralPath $source -Destination (Join-Path $project "bin/$name")
  }
  $crtFiles | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'selected-crt.json') -Encoding utf8
}
$import=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100') -WorkingDirectory $root -Log (Join-Path $evidence 'editor-import.log')
if($import.exit_code -ne 0 -or $import.text -match 'ERROR:|SCRIPT ERROR:|FATAL:') { throw "Godot project import failed exit=$($import.exit_code); log=$evidence/editor-import.log" }
$editor=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project) -WorkingDirectory $root -Log (Join-Path $evidence 'editor-scene.log')
Assert-ProofSuccess $editor
& node (Join-Path $repo 'tests/export/validate-log.mjs') (Join-Path $evidence 'editor-scene.log')
if($LASTEXITCODE -ne 0) { throw 'Editor snapshot/command schemas rejected' }
if(-not $EditorOnly) {
  $templates=Join-Path $ToolchainRoot 'godot-templates'
  if(-not (Test-Path (Join-Path $templates 'windows_release_x86_64.exe'))) { throw 'Fetch matching export templates with bootstrap.py --with-godot --with-export-templates' }
  $preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
  $template=(Join-Path $templates 'windows_release_x86_64.exe').Replace('\','/')
  $preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template+'"')
  Set-Content -LiteralPath (Join-Path $project 'export_presets.cfg') -Value $preset -Encoding utf8
  $package=Join-Path $root 'payload'
  New-Item -ItemType Directory -Path $package | Out-Null
  $export=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $package 'flight-proof.exe')) -WorkingDirectory $root -Log (Join-Path $evidence 'windows-export.log')
  if($export.exit_code -ne 0 -or $export.text -match 'ERROR:|SCRIPT ERROR:|FATAL:') { throw 'Godot release export failed' }
  New-Item -ItemType Directory -Force -Path (Join-Path $package 'bin') | Out-Null
  Copy-Item -LiteralPath (Join-Path $project "bin/$bridge") -Destination (Join-Path $package "bin/$bridge") -Force
  Copy-Item -LiteralPath (Join-Path $project "bin/$jsbsim") -Destination (Join-Path $package "bin/$jsbsim") -Force
  foreach($crt in $crtFiles) {
    Copy-Item -LiteralPath $crt.source -Destination (Join-Path $package $crt.name)
    Copy-Item -LiteralPath $crt.source -Destination (Join-Path $package "bin/$($crt.name)")
  }
  Copy-Item -LiteralPath (Join-Path $project 'models') -Destination (Join-Path $package 'models') -Recurse
  Write-ProofDependencyReport -Payload $package -BuildManifest (Join-Path $build 'toolchain-build-manifest.txt') -Output (Join-Path $evidence 'native-dependencies.json')
  $relocated=Join-Path $root 'Relocated space — Δ飛行'
  Copy-Item -LiteralPath $package -Destination $relocated -Recurse
  $profile=Join-Path $root 'isolated-profile'
  $portable=Invoke-ProofProcess -Executable (Join-Path $relocated 'flight-proof.exe') -Arguments @('--headless') -WorkingDirectory $root -Log (Join-Path $evidence 'portable-unicode.log') -CleanEnvironment -ProfileRoot $profile
  Assert-ProofSuccess $portable
  & node (Join-Path $repo 'tests/export/validate-log.mjs') (Join-Path $evidence 'portable-unicode.log') $relocated ((Get-FileHash (Join-Path $package 'bin/JSBSim.dll') -Algorithm SHA256).Hash.ToLowerInvariant()) (Join-Path $evidence 'selected-crt.json')
  if($LASTEXITCODE -ne 0) { throw 'Portable relocation/module/schema witness failed' }
  foreach($mode in @('destructor','bad-initializer')) {
    $result=Invoke-ProofProcess -Executable (Join-Path $relocated 'flight-proof.exe') -Arguments @('--headless','--',"--proof-mode=$mode") -WorkingDirectory $root -Log (Join-Path $evidence "$mode.log") -CleanEnvironment -ProfileRoot $profile
    if($mode -eq 'bad-initializer') { Assert-ProofSuccess $result -ExpectedRejection } else { Assert-ProofSuccess $result }
  }
  $missing=Join-Path $root 'missing-dll-negative'
  Copy-Item -LiteralPath $relocated -Destination $missing -Recurse
  foreach($candidate in @((Join-Path $missing 'bin/JSBSim.dll'),(Join-Path $missing 'JSBSim.dll'))) {
    if(Test-Path -LiteralPath $candidate) { Move-Item -LiteralPath $candidate -Destination ($candidate+'.quarantined') }
  }
  $negative=Invoke-ProofProcess -Executable (Join-Path $missing 'flight-proof.exe') -Arguments @('--headless') -WorkingDirectory $root -Log (Join-Path $evidence 'missing-dll.log') -CleanEnvironment -ProfileRoot $profile
  if($negative.exit_code -eq 0 -or $negative.text -match 'FLIGHT_PROOF_OK' -or $negative.text -notmatch 'ERROR:|FLIGHT_PROOF_FAILED') { throw 'Missing DLL negative control did not fail visibly' }
  foreach($crt in $crtFiles) {
    $missingRuntime=Join-Path $root ('missing-runtime-'+$crt.name)
    Copy-Item -LiteralPath $relocated -Destination $missingRuntime -Recurse
    foreach($relative in @($crt.name,"bin/$($crt.name)")) {
      $candidate=Join-Path $missingRuntime $relative
      if(Test-Path -LiteralPath $candidate) { Move-Item -LiteralPath $candidate -Destination ($candidate+'.quarantined') }
    }
    $control=Invoke-ProofProcess -Executable (Join-Path $missingRuntime 'flight-proof.exe') -Arguments @('--headless') -WorkingDirectory $root -Log (Join-Path $evidence ('missing-runtime-'+$crt.name+'.log')) -CleanEnvironment -ProfileRoot $profile
    if($control.exit_code -eq 0 -or $control.text -match 'FLIGHT_PROOF_OK') { throw 'Missing CRT control used an unapproved fallback' }
    # Startup may fail before engine logging on Windows without a global CRT;
    # with an installed global CRT, the bridge must reject its escaped module path.
  }
}
$manifest=[ordered]@{schema_version=1;root=$root;project=$project;evidence=$evidence;payload=$(if($EditorOnly){$null}else{$package});relocated=$(if($EditorOnly){$null}else{$relocated});editor_passed=$true;windows_portable_passed=(-not $EditorOnly);clean_path=(-not $EditorOnly);unicode_path=(-not $EditorOnly);source_replacement='pending independent source rebuild/replacement stage';selected_crt=$crtFiles;native_build_identity=$nativeIdentity;selected_library=$selection;python_executable=$Python;toolchain_root=$ToolchainRoot}
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $repo '.local/export-proof/latest-run.json') -Encoding utf8
$manifest | ConvertTo-Json -Depth 8 | Write-Output
