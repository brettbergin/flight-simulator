#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExportProofRoot,[Parameter(Mandatory)][string]$ToolchainRoot,[string]$NativeBuildRoot)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Whole-flight portable preview currently targets Windows x64'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
function Assert-PreviewProcessResult($Result,[string]$Label){
 if($Result.exit_code -ne 0 -or $Result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed'){throw "Preview $Label failed; raw evidence retained"}
}
function Save-PreviewFacadeObservation {
 param([string]$TargetPath,[string]$Evidence,[string]$Name)
 $raw=Join-Path $TargetPath 'facade-check-receipt.json'
 if(-not (Test-Path -LiteralPath $raw -PathType Leaf)){return}
 # Preserve failed process output before the unchanged process guard throws.
 Copy-Item -LiteralPath $raw -Destination (Join-Path $Evidence ($Name+'-facade-observed-receipt.json'))
 try{$observed=Get-Content -LiteralPath $raw -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}
 catch{throw 'Exported facade receipt unreadable or malformed; copied raw evidence retained'}
 if($observed.passed -ne $true){
  $names=@()
  foreach($group in @(@{name='host';value=$observed},@{name='facade';value=$observed.facade},@{name='input';value=$observed.input},@{name='instruments';value=$observed.instruments},@{name='cockpit_adapter';value=$observed.cockpit.adapter},@{name='cockpit_scan';value=$observed.cockpit.scan},@{name='cockpit_scene';value=$observed.cockpit.scene})){
   foreach($failure in @($group.value.failures)){
    # Print only bounded fixture identifiers, never copied values or local paths.
    if($failure -is [string] -and $failure -cmatch '^[A-Za-z0-9_-]{1,96}$' -and $names.Count -lt 16){$names+=($group.name+':'+$failure)}
   }
  }
  Write-Output ('Exported facade failure assertions: '+$(if($names.Count){$names -join ', '}else{'no bounded assertion identifiers available; inspect retained receipt'}))
 }
}
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
$simulationRoot=Join-Path $repo 'app/simulation'
$simulationEntries=@('session_facade.gd','render_origin.gd','origin_participant.gd','wire_validation.gd','flight_scene.gd','flight_scene.tscn')
$simulationSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $simulationRoot -RequiredEntries $simulationEntries)
$facadeTestRoot=Join-Path $repo 'tests/integration/sim_loop'
$facadeTestEntries=@('facade_checks.gd','independent-reference.json','scene_checks.gd')
$facadeTestSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -RequiredEntries $facadeTestEntries)
$inputGroups=@(Get-InputSourceGroups -RepoRoot $repo)
$cockpitGroups=@(Get-CockpitSourceGroups -RepoRoot $repo)
$engineTestRoot=Join-Path $repo 'tests/engine'
$engineTestEntries=@('status_checks.gd','facade_checks.gd','input_boundary_checks.gd','presentation_checks.gd','reference/expected-v3.json')
$engineTestSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $engineTestRoot -RequiredEntries $engineTestEntries)
$inputs=@()
foreach($directory in @('app/proof/interactive','app/simulation','app/input','app/ui/controls','tests/input','app/cockpit','tests/instruments','tests/engine','content/aircraft/prototype','tests/integration/sim_loop','tools/interactive-preview','native/godot_bridge','native/fdm_jsbsim/interactive','native/fdm_jsbsim/models/original-interactive','native/fdm_jsbsim/models/original-piston-prop')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File){
  $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/');sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
 }
}
foreach($kind in @('AircraftSnapshot','AtmosphereSample','ControlCommand','OperationalEvent')){
 $file=Get-Item (Join-Path $repo "tests/contracts/fixtures/$kind.json")
 $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace([char]92,[char]47);sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
}
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive') -Destination (Join-Path $project 'interactive') -Recurse
Copy-SimulationSourceSnapshot -SourceRoot $simulationRoot -DestinationRoot (Join-Path $project 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Copy-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -DestinationRoot (Join-Path $project 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Copy-InputSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $inputGroups
Copy-CockpitSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $cockpitGroups
Copy-SimulationSourceSnapshot -SourceRoot $engineTestRoot -DestinationRoot (Join-Path $project 'engine_tests') -Snapshot $engineTestSnapshot -RequiredEntries $engineTestEntries
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive/project-settings.cfg') -Destination (Join-Path $project 'project.godot')
Set-SimulationMainScene -ProjectFile (Join-Path $project 'project.godot')
Write-SimulationCheckHarness -ProjectRoot $project -RepoRoot $repo
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/flight.gdextension'),(Join-Path $repo 'app/proof/export_presets.cfg'),(Join-Path $repo 'LICENSE') -Destination $project
Copy-Item -LiteralPath (Join-Path $proof 'payload/bin') -Destination $project -Recurse
$build=if($NativeBuildRoot){(Resolve-Path -LiteralPath $NativeBuildRoot).Path}else{Join-Path $repo '.local/build/native-release'}
$bridge=Join-Path $build 'bin/flight_godot_bridge.dll'
$initialBridgeHash=(Get-FileHash $bridge).Hash
Copy-Item -LiteralPath $bridge -Destination (Join-Path $project 'bin/flight_godot_bridge.dll') -Force
$model=Join-Path $repo 'native/fdm_jsbsim/models/original-interactive'
& node (Join-Path $PSScriptRoot 'package.mjs') models $model (Join-Path $project 'models')
if($LASTEXITCODE -ne 0){throw 'Combined model pin gate failed'}
& node (Join-Path $PSScriptRoot 'package.mjs') models (Join-Path $repo 'native/fdm_jsbsim/models/original-piston-prop') (Join-Path $project 'piston-models') original-piston-prop-v1
if($LASTEXITCODE -ne 0){throw 'Piston model and metadata pin gate failed'}

$preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
$preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template.Replace('\','/')+'"').Replace('exclude_filter=""','exclude_filter="smoke-receipt.json,loop.records.ndjson,compile-all.gd,facade-check-receipt.json,controls*-receipt.json,controls*-preset.json,controls*.png"')
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
 for path in ["res://simulation/session_facade.gd","res://simulation/render_origin.gd","res://simulation/origin_participant.gd","res://simulation/wire_validation.gd","res://simulation/flight_scene.gd","res://sim_loop_tests/facade_checks.gd","res://sim_loop_checks.gd","res://input/input_mapper.gd","res://input/input_preset.gd","res://ui/controls/controls_panel.gd","res://input_tests/input_checks.gd","res://input_tests/scene_checks.gd","res://cockpit/instruments/native_readings.gd","res://cockpit/instruments/scan_panel.gd","res://instrument_tests/instrument_checks.gd","res://instrument_tests/adapter_checks.gd","res://instrument_tests/scan_checks.gd","res://instrument_tests/scene_checks.gd","res://cockpit/instruments/engine_status.gd","res://engine_tests/status_checks.gd","res://engine_tests/facade_checks.gd","res://engine_tests/input_boundary_checks.gd","res://engine_tests/presentation_checks.gd","res://input_tests/piston_checks.gd","res://input_tests/piston_panel_checks.gd"]:
  var dependency=load(path) as Script
  if dependency==null or not dependency.can_instantiate():
   push_error("Simulation resource compile rejected: "+path)
   quit(1)
   return
 if script==null or not script.can_instantiate() or scene==null or load("res://simulation/flight_scene.tscn")==null:
  push_error("Whole-flight resource compile rejected")
  quit(1)
  return
 print("WHOLE_FLIGHT_RESOURCE_COMPILE_PASSED")
 quit(0)
')
 foreach($operation in @(
  @{name='import';args=@('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100')},
  @{name='compile';args=@('--headless','--path',$project,'--script','res://compile-all.gd')},
  @{name='facade-checks';args=@('--headless','--path',$project,'res://sim_loop_checks.tscn')},
  @{name='editor-smoke';args=@('--headless','--path',$project,'--','--smoke')},
  @{name='export';args=@('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $payload 'WholeFlightPreview.exe'))}
 )){
  $result=Invoke-ProofProcess -Executable $godot -Arguments $operation.args -WorkingDirectory $root -Log (Join-Path $evidence ($operation.name+'.log'))
  Assert-PreviewProcessResult $result $operation.name
  if($operation.name -eq 'facade-checks'){
   $receipt=Get-Content (Join-Path $project 'facade-check-receipt.json') -Raw | ConvertFrom-Json
   if($result.text -notmatch 'SIM_LOOP_CHECKS_PASSED' -or $receipt.passed -ne $true -or $receipt.failures.Count -ne 0){throw 'Actual facade checks failed'}
   Copy-Item -LiteralPath (Join-Path $project 'facade-check-receipt.json') -Destination (Join-Path $evidence 'editor-facade-receipt.json')
  }
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
Copy-Item -LiteralPath (Join-Path $project 'piston-models') -Destination (Join-Path $payload 'piston-models') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launch.ps1'),(Join-Path $PSScriptRoot 'README.md') -Destination $payload
$source=Join-Path $payload 'source/whole-flight-preview'
New-Item -ItemType Directory -Force $source | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive'),$PSScriptRoot,(Join-Path $repo 'native'),(Join-Path $repo 'LICENSE'),(Join-Path $repo 'CMakeLists.txt'),(Join-Path $repo 'CMakePresets.json') -Destination $source -Recurse
# Keep the native CMake source layout rebuildable, including its tests and pins.
Copy-Item -LiteralPath (Join-Path $repo 'tests') -Destination $source -Recurse
New-Item -ItemType Directory -Force (Join-Path $source 'tools'),(Join-Path $source 'third_party')|Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'tools/bootstrap') -Destination (Join-Path $source 'tools') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'third_party/dependencies.lock.json') -Destination (Join-Path $source 'third_party')
Copy-SimulationSourceSnapshot -SourceRoot $simulationRoot -DestinationRoot (Join-Path $source 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Copy-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -DestinationRoot (Join-Path $source 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Copy-InputSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $inputGroups
Copy-CockpitSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $cockpitGroups
Copy-SimulationSourceSnapshot -SourceRoot $engineTestRoot -DestinationRoot (Join-Path $source 'engine_tests') -Snapshot $engineTestSnapshot -RequiredEntries $engineTestEntries
Copy-Item -LiteralPath (Join-Path $project 'wire_fixtures'),(Join-Path $project 'sim_loop_checks.gd'),(Join-Path $project 'sim_loop_checks.tscn') -Destination $source -Recurse
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
foreach($target in @(@{name='portable';path=$payload},@{name='replacement';path=$replacement})){
 $result=Invoke-ProofProcess -Executable (Join-Path $target.path 'WholeFlightPreview.exe') -Arguments @('--headless','--','--facade-checks') -WorkingDirectory $root -Log (Join-Path $evidence ($target.name+'-facade.log')) -CleanEnvironment -ProfileRoot (Join-Path $root ('facade-userdata-'+$target.name))
 Save-PreviewFacadeObservation -TargetPath $target.path -Evidence $evidence -Name $target.name
 Assert-PreviewProcessResult $result ($target.name+'-facade')
 if($result.text -notmatch 'SIM_LOOP_CHECKS_PASSED' -or $result.text -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED'){throw 'Exported actual facade checks failed'}
 $receipt=Get-Content (Join-Path $target.path 'facade-check-receipt.json') -Raw | ConvertFrom-Json
 if($receipt.passed -ne $true -or $receipt.checks -le 0 -or $receipt.failures.Count -ne 0){throw 'Exported actual facade receipt failed'}
 Move-Item -LiteralPath (Join-Path $target.path 'facade-check-receipt.json') -Destination (Join-Path $evidence ($target.name+'-facade-receipt.json'))
}
Write-ProofDependencyReport -Payload $payload -BuildManifest (Join-Path $build 'toolchain-build-manifest.txt') -Output (Join-Path $evidence 'native-dependencies.json')
& node (Join-Path $PSScriptRoot 'package.mjs') audit $root $proof $build
if($LASTEXITCODE -ne 0){throw 'Whole-flight package integrity failed'}
# Detect concurrent source/toolchain drift before publishing a successful receipt.
Assert-SimulationSourceSnapshot -SourceRoot $simulationRoot -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $project 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries -AllowGeneratedUIDs
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $source 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Assert-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $project 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries -AllowGeneratedUIDs
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $source 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Assert-InputSourceGroups -DestinationRoot $repo -Groups $inputGroups -Authoring
Assert-InputSourceGroups -DestinationRoot $project -Groups $inputGroups -AllowGeneratedUIDs
Assert-InputSourceGroups -DestinationRoot $source -Groups $inputGroups
Assert-CockpitSourceGroups -DestinationRoot $repo -Groups $cockpitGroups -Authoring
Assert-CockpitSourceGroups -DestinationRoot $project -Groups $cockpitGroups -AllowGeneratedUIDs
Assert-CockpitSourceGroups -DestinationRoot $source -Groups $cockpitGroups
Assert-SimulationSourceSnapshot -SourceRoot $engineTestRoot -Snapshot $engineTestSnapshot -RequiredEntries $engineTestEntries
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $project 'engine_tests') -Snapshot $engineTestSnapshot -RequiredEntries $engineTestEntries -AllowGeneratedUIDs
Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $source 'engine_tests') -Snapshot $engineTestSnapshot -RequiredEntries $engineTestEntries
if((Get-FileHash $bridge).Hash -ne $initialBridgeHash){throw 'Native bridge changed during proof'}
foreach($input in $inputs){if((Get-FileHash (Join-Path $repo $input.path)).Hash.ToLowerInvariant() -ne $input.sha256){throw 'Authoring source changed during proof'}}
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins-final.json')
if($LASTEXITCODE -ne 0){throw 'Toolchain drift detected'}
if((Get-FileHash (Join-Path $evidence 'tool-pins.json')).Hash -ne (Get-FileHash (Join-Path $evidence 'tool-pins-final.json')).Hash){throw 'Selected tool identities changed during proof'}
$inventory=@(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {@{path=[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}} | Sort-Object {$_.path})
$manifest=@{schema_version=1;kind='original-whole-flight-preview';passed=$true;scope='Windows original model, actual functional headless proof; GPU/human acceptance separate';git_head=(& git -c "safe.directory=$repo" -C $repo rev-parse HEAD);powershell=$PSVersionTable.PSVersion.ToString();authoring_sources=$inputs;staged_compile_sha256=(Get-FileHash (Join-Path $project 'compile-all.gd')).Hash.ToLowerInvariant();staged_generated_uid_metadata=@(Get-ChildItem (Join-Path $project 'simulation'),(Join-Path $project 'sim_loop_tests'),(Join-Path $project 'input'),(Join-Path $project 'ui/controls'),(Join-Path $project 'input_tests'),(Join-Path $project 'cockpit'),(Join-Path $project 'instrument_tests'),(Join-Path $project 'engine_tests') -Recurse -File -Filter '*.gd.uid'|ForEach-Object {@{path=[IO.Path]::GetRelativePath($project,$_.FullName).Replace([char]92,[char]47);sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}});staged_facade_harness_sha256=(Get-FileHash (Join-Path $project 'sim_loop_checks.gd')).Hash.ToLowerInvariant();staged_project_sha256=(Get-FileHash (Join-Path $project 'project.godot')).Hash.ToLowerInvariant();tool_pins=$pins;godot_version=$version.text.Trim();accepted_native_export_root=$proof;accepted_package_inventory_sha256=(Get-FileHash (Join-Path $proof 'evidence/package-inventory.json')).Hash.ToLowerInvariant();files=$inventory}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $evidence 'manifest.json')
@{root=$root;project=$project;payload=$payload;evidence=$evidence;passed=$true} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $repo '.local/interactive-preview/latest-run.json')
Write-Output $root


