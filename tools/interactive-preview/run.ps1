#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExportProofRoot,[Parameter(Mandatory)][string]$ToolchainRoot)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Whole-flight portable preview currently targets Windows x64'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
& (Join-Path $PSScriptRoot 'check-guards.ps1')
$proof=(Resolve-Path -LiteralPath $ExportProofRoot).Path
$toolchain=(Resolve-Path -LiteralPath $ToolchainRoot).Path
$root=Join-Path $repo ('.local/interactive-preview/run-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
$payload=Join-Path $root 'payload'
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Force $project,$payload,$evidence | Out-Null
$environment=Get-Content (Join-Path $toolchain 'environment.json') -Raw | ConvertFrom-Json
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins.json')
if($LASTEXITCODE -ne 0){throw 'Actual editor/template pins rejected'}
$pins=Get-Content (Join-Path $evidence 'tool-pins.json') -Raw | ConvertFrom-Json
$godot=$pins.tools.godot.executable
$template=$pins.tools.'godot-templates'.executable
$version=Invoke-ProofProcess -Executable $godot -Arguments @('--version') -WorkingDirectory $root -Log (Join-Path $evidence 'godot-version.log')
if($version.exit_code -ne 0 -or $version.text.Trim() -ne '4.7.2.stable.official.ed1daf0bf'){throw 'Actual engine version differs from pin'}
# Verify every accepted package component before reusing any payload bytes.
$audit=Get-Content (Join-Path $proof 'evidence/package-audit.json') -Raw | ConvertFrom-Json
$accepted=Get-Content (Join-Path $proof 'evidence/package-inventory.json') -Raw | ConvertFrom-Json
if($audit.rights_integrity_passed -ne $true -or $audit.actual_replacement_passed -ne $true){throw 'Accepted native export audit/replacement evidence required'}
foreach($component in $accepted.components){foreach($file in $component.files){
 $candidate=Join-Path $proof ('payload/'+$file.path)
 if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw "Accepted package changed: $($file.path)"}
}}
$inputs=@()
foreach($directory in @('app/proof/interactive','tools/interactive-preview','native/godot_bridge','native/fdm_jsbsim/interactive','native/fdm_jsbsim/models/original-interactive')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File){
  $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/');sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
 }
}
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive') -Destination (Join-Path $project 'interactive') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive/project-settings.cfg') -Destination (Join-Path $project 'project.godot')
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/flight.gdextension'),(Join-Path $repo 'app/proof/export_presets.cfg'),(Join-Path $repo 'LICENSE') -Destination $project
Copy-Item -LiteralPath (Join-Path $proof 'payload/bin') -Destination $project -Recurse
$build=Join-Path $repo '.local/build/native-release'
$bridge=Join-Path $build 'bin/flight_godot_bridge.dll'
$initialBridgeHash=(Get-FileHash $bridge).Hash
Copy-Item -LiteralPath $bridge -Destination (Join-Path $project 'bin/flight_godot_bridge.dll') -Force
$model=Join-Path $repo 'native/fdm_jsbsim/models/original-interactive'
& node (Join-Path $PSScriptRoot 'package.mjs') models $model (Join-Path $project 'models')
if($LASTEXITCODE -ne 0){throw 'Combined model pin gate failed'}

$preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
$preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template.Replace('\','/')+'"').Replace('exclude_filter=""','exclude_filter="smoke-receipt.json,loop.records.ndjson,compile-all.gd"')
$preset | Set-Content -Encoding utf8 (Join-Path $project 'export_presets.cfg')
# Keep engine/profile/cache writes within this fresh run even during authoring.
$prior=@{}
foreach($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP','FLIGHT_PREVIEW_PROFILE_ROOT')){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
 $profile=Join-Path $root 'userdata'
 $env:FLIGHT_PREVIEW_PROFILE_ROOT=$profile.Replace('\','/')
 foreach($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')){
  $directory=Join-Path $profile $name
  New-Item -ItemType Directory -Force $directory | Out-Null
  [Environment]::SetEnvironmentVariable($name,$directory,'Process')
 }
 [IO.File]::WriteAllText((Join-Path $project 'compile-all.gd'),'extends SceneTree
func _initialize() -> void:
 var script=load("res://interactive/preview.gd") as Script
 var scene=load("res://interactive/preview.tscn") as PackedScene
 if script==null or not script.can_instantiate() or scene==null:
  push_error("Whole-flight resource compile rejected")
  quit(1)
  return
 print("WHOLE_FLIGHT_RESOURCE_COMPILE_PASSED")
 quit(0)
')
 foreach($operation in @(
  @{name='import';args=@('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100')},
  @{name='compile';args=@('--headless','--path',$project,'--script','res://compile-all.gd')},
  @{name='editor-smoke';args=@('--headless','--path',$project,'--','--smoke')},
  @{name='export';args=@('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $payload 'WholeFlightPreview.exe'))}
 )){
  $result=Invoke-ProofProcess -Executable $godot -Arguments $operation.args -WorkingDirectory $root -Log (Join-Path $evidence ($operation.name+'.log'))
  if($result.exit_code -ne 0 -or $result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed'){throw "Preview $($operation.name) failed; raw evidence retained"}
  if($operation.name -eq 'editor-smoke'){
   $receipt=Get-Content (Join-Path $project 'smoke-receipt.json') -Raw | ConvertFrom-Json
   if($result.text -notmatch 'WHOLE_FLIGHT_PREVIEW_SMOKE' -or $receipt.passed -ne $true -or $receipt.failures.Count -ne 0){throw 'Actual editor smoke assertions failed'}
   Copy-Item -LiteralPath (Join-Path $project 'smoke-receipt.json') -Destination (Join-Path $evidence 'editor-smoke-receipt.json')
   Copy-Item -LiteralPath (Join-Path $project 'loop.records.ndjson') -Destination (Join-Path $evidence 'editor.records.ndjson')
  }
 }
} finally {foreach($name in $prior.Keys){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}}
foreach($name in @('bin','notices','source')){Copy-Item -LiteralPath (Join-Path $proof "payload/$name") -Destination (Join-Path $payload $name) -Recurse}
foreach($name in @('flight_godot_bridge.dll','JSBSim.dll','msvcp140.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','vcruntime140.dll','vcruntime140_1.dll')){
 $original=if($name -eq 'flight_godot_bridge.dll'){$bridge}else{Join-Path $proof "payload/$name"}
 Copy-Item -LiteralPath $original -Destination (Join-Path $payload $name) -Force
 Copy-Item -LiteralPath $original -Destination (Join-Path $payload ("bin/"+$name)) -Force
 foreach($copy in @($name,"bin/$name")){if((Get-FileHash (Join-Path $payload $copy)).Hash -ne (Get-FileHash $original).Hash){throw "Dependency copy changed: $copy"}}
}
Copy-Item -LiteralPath (Join-Path $project 'models') -Destination (Join-Path $payload 'models') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launch.ps1'),(Join-Path $PSScriptRoot 'README.md') -Destination $payload
$source=Join-Path $payload 'source/whole-flight-preview'
New-Item -ItemType Directory -Force $source | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive'),$PSScriptRoot,(Join-Path $repo 'native'),(Join-Path $repo 'LICENSE'),(Join-Path $repo 'CMakeLists.txt'),(Join-Path $repo 'CMakePresets.json') -Destination $source -Recurse
& (Join-Path $payload 'launch.ps1') -HeadlessSmoke
Copy-Item -LiteralPath (Join-Path $payload 'smoke-receipt.json'),(Join-Path $payload 'portable-smoke.log'),(Join-Path $payload 'loop.records.ndjson') -Destination $evidence
$replacement=Join-Path $root 'Replacement space — Δ飛行'
Copy-Item -LiteralPath $payload -Destination $replacement -Recurse
$oldReplacement=Get-Content (Join-Path $proof 'evidence/replacement-evidence.json') -Raw | ConvertFrom-Json
$rebuilt=Join-Path $proof 'Replaced DLL — Δ飛行/bin/JSBSim.dll'
if((Get-FileHash $rebuilt).Hash.ToLowerInvariant() -ne $oldReplacement.replaced_library_sha256){throw 'Source rebuilt JSBSim identity changed'}
foreach($relative in @('JSBSim.dll','bin/JSBSim.dll')){Copy-Item -LiteralPath $rebuilt -Destination (Join-Path $replacement $relative) -Force}
& (Join-Path $replacement 'launch.ps1') -HeadlessSmoke
Copy-Item -LiteralPath (Join-Path $replacement 'smoke-receipt.json') -Destination (Join-Path $evidence 'replacement-smoke-receipt.json')
Copy-Item -LiteralPath (Join-Path $replacement 'loop.records.ndjson') -Destination (Join-Path $evidence 'replacement.records.ndjson')
Copy-Item -LiteralPath (Join-Path $replacement 'portable-smoke.log') -Destination (Join-Path $evidence 'replacement.log')
Write-ProofDependencyReport -Payload $payload -BuildManifest (Join-Path $build 'toolchain-build-manifest.txt') -Output (Join-Path $evidence 'native-dependencies.json')
& node (Join-Path $PSScriptRoot 'package.mjs') audit $root $proof $build
if($LASTEXITCODE -ne 0){throw 'Whole-flight package integrity failed'}
# Detect concurrent source/toolchain drift before publishing a successful receipt.
if((Get-FileHash $bridge).Hash -ne $initialBridgeHash){throw 'Native bridge changed during proof'}
foreach($input in $inputs){if((Get-FileHash (Join-Path $repo $input.path)).Hash.ToLowerInvariant() -ne $input.sha256){throw 'Authoring source changed during proof'}}
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins-final.json')
if($LASTEXITCODE -ne 0){throw 'Toolchain drift detected'}
if((Get-FileHash (Join-Path $evidence 'tool-pins.json')).Hash -ne (Get-FileHash (Join-Path $evidence 'tool-pins-final.json')).Hash){throw 'Selected tool identities changed during proof'}
$inventory=@(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {@{path=[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}} | Sort-Object {$_.path})
$manifest=@{schema_version=1;kind='original-whole-flight-preview';passed=$true;scope='Windows original model, actual functional headless proof; GPU/human acceptance separate';git_head=(& git -c "safe.directory=$repo" -C $repo rev-parse HEAD);powershell=$PSVersionTable.PSVersion.ToString();authoring_sources=$inputs;staged_compile_sha256=(Get-FileHash (Join-Path $project 'compile-all.gd')).Hash.ToLowerInvariant();staged_project_sha256=(Get-FileHash (Join-Path $project 'project.godot')).Hash.ToLowerInvariant();tool_pins=$pins;godot_version=$version.text.Trim();accepted_native_export_root=$proof;accepted_package_inventory_sha256=(Get-FileHash (Join-Path $proof 'evidence/package-inventory.json')).Hash.ToLowerInvariant();files=$inventory}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $evidence 'manifest.json')
@{root=$root;project=$project;payload=$payload;evidence=$evidence;passed=$true} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $repo '.local/interactive-preview/latest-run.json')
Write-Output $root


