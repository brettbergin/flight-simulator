#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExportProofRoot,[Parameter(Mandatory)][string]$ToolchainRoot,[string]$NativeBuildRoot="",[ValidateRange(120,600)][int]$FacadeCheckTimeoutSeconds=120)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Whole-flight portable preview currently targets Windows x64'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
function Assert-PreviewProcessResult($Result,[string]$Label){
 if($Result.exit_code -ne 0 -or $Result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed'){throw "Preview $Label failed; raw evidence retained"}
}
function Save-PreviewGroundObservation {
 param([string]$TargetPath,[string]$Evidence,[string]$Name)
 $raw=Join-Path $TargetPath 'ground-material-receipt.json'
 if(Test-Path -LiteralPath $raw -PathType Leaf){Copy-Item -LiteralPath $raw -Destination (Join-Path $Evidence ($Name+'-ground-observed-receipt.json'))}
}
function Assert-PreviewGroundResult {
 param($Result,[string]$TargetPath,[string]$Evidence,[string]$Name)
 Save-PreviewGroundObservation -TargetPath $TargetPath -Evidence $Evidence -Name $Name
 Assert-PreviewProcessResult $Result ($Name+'-ground')
 if($Result.text -notmatch 'GROUND_MATERIALS_CHECKS'){throw 'Ground-material checks completion marker missing'}
 $raw=Join-Path $TargetPath 'ground-material-receipt.json'
 & node (Join-Path $PSScriptRoot 'package.mjs') ground-receipt $raw $repo
 if($LASTEXITCODE -ne 0){throw 'Actual ground-material receipt/source identity rejected'}
 Move-Item -LiteralPath $raw -Destination (Join-Path $Evidence ($Name+'-ground-receipt.json'))
}
function Save-PreviewPointerObservation {
 param([string]$TargetPath,[string]$Evidence,[string]$Name)
 foreach($file in @('pointer-check-receipt.json','pointer-flight-trace.json')){
  $raw=Join-Path $TargetPath $file
  if(Test-Path -LiteralPath $raw -PathType Leaf){Copy-Item -LiteralPath $raw -Destination (Join-Path $Evidence ($Name+'-observed-'+$file))}
 }
}
function Assert-PreviewPointerResult {
 param($Result,[string]$TargetPath,[string]$Evidence,[string]$Name)
 Save-PreviewPointerObservation -TargetPath $TargetPath -Evidence $Evidence -Name $Name
 Assert-PreviewProcessResult $Result ($Name+'-pointer')
 if($Result.text -notmatch 'POINTER_ENGINE_CHECKS' -or $Result.text -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED'){throw 'Actual pointer checks completion/join marker missing'}
 & node (Join-Path $PSScriptRoot 'package.mjs') pointer-receipt (Join-Path $TargetPath 'pointer-check-receipt.json') (Join-Path $TargetPath 'pointer-flight-trace.json') $repo $project (Join-Path $evidence 'native-build-identity.json')
 if($LASTEXITCODE -ne 0){throw 'Actual pointer checks/trace/source identity rejected'}
 foreach($file in @('pointer-check-receipt.json','pointer-flight-trace.json')){Move-Item -LiteralPath (Join-Path $TargetPath $file) -Destination (Join-Path $Evidence ($Name+'-'+$file))}
}
function Save-PreviewFacadeObservation {
 param([string]$TargetPath,[string]$Evidence,[string]$Name)
 $coldRaw=Join-Path $TargetPath 'piston-check-receipt.json'
 if(Test-Path -LiteralPath $coldRaw -PathType Leaf){Copy-Item -LiteralPath $coldRaw -Destination (Join-Path $Evidence ($Name+'-piston-observed-receipt.json'))}
 $raw=Join-Path $TargetPath 'facade-check-receipt.json'
 if(-not (Test-Path -LiteralPath $raw -PathType Leaf)){return}
 # Preserve failed process output before the unchanged process guard throws.
 Copy-Item -LiteralPath $raw -Destination (Join-Path $Evidence ($Name+'-facade-observed-receipt.json'))
 try{$observed=Get-Content -LiteralPath $raw -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop}
 catch{throw 'Exported facade receipt unreadable or malformed; copied raw evidence retained'}
 if($observed.passed -ne $true){
  $names=@()
  foreach($group in @(@{name='host';value=$observed},@{name='facade';value=$observed.facade},@{name='input';value=$observed.input},@{name='instruments';value=$observed.instruments},@{name='cockpit_adapter';value=$observed.cockpit.adapter},@{name='cockpit_scan';value=$observed.cockpit.scan},@{name='cockpit_scene';value=$observed.cockpit.scene},@{name='freeflight_geometry';value=$observed.freeflight.geometry},@{name='freeflight_scene';value=$observed.freeflight.scene},@{name='observed_recorder';value=$observed.observed.recorder},@{name='observed_scene';value=$observed.observed.scene},@{name='archive_codec';value=$observed.observed_archive.codec},@{name='archive_files';value=$observed.observed_archive.files},@{name='archive_scene';value=$observed.observed_archive.scene},@{name='wind_bridge';value=$observed.wind.bridge},@{name='wind_cue';value=$observed.wind.cue},@{name='wind_scene';value=$observed.wind.scene})){
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
if([string]::IsNullOrWhiteSpace($NativeBuildRoot)){$NativeBuildRoot=Join-Path $repo '.local/build/native-release'}
$nativeIdentity=Get-PreviewNativeBuildIdentity -RepoRoot $repo -NativeBuildRoot $NativeBuildRoot -Python $environment.python_executable
$nativeIdentity | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $evidence 'native-build-identity.json')
$selectedRaw=& node (Join-Path $repo 'tools/export/selected-source.mjs') match-export (Join-Path $evidence 'native-build-identity.json') $proof
if($LASTEXITCODE -ne 0){throw 'Selected native build requires matching reviewed export/source/replacement provenance'}
$selectedLibrary=$selectedRaw|ConvertFrom-Json -ErrorAction Stop
$selectedLibrary|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $evidence 'selected-library-release.json') -Encoding utf8
$build=$nativeIdentity.root
# Cold groups run only after matching selected-source export qualification above.
$includePiston=$nativeIdentity.source_variant -ceq 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
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
# Both source and consumer ABI must match the independently qualified export.
foreach($module in @('JSBSim.dll','flight_godot_bridge.dll')){
 if((Get-FileHash -LiteralPath (Join-Path $build ('bin/'+$module))).Hash -cne (Get-FileHash -LiteralPath (Join-Path $proof ('payload/bin/'+$module))).Hash){throw 'Selected native source/consumer and accepted export bytes differ'}
}
$simulationRoot=Join-Path $repo 'app/simulation'
$simulationEntries=@('session_facade.gd','render_origin.gd','origin_participant.gd','wire_validation.gd','flight_scene.gd','flight_scene.tscn')
$simulationSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $simulationRoot -RequiredEntries $simulationEntries)
$facadeTestRoot=Join-Path $repo 'tests/integration/sim_loop'
$facadeTestEntries=@('facade_checks.gd','independent-reference.json','scene_checks.gd')
$facadeTestSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -RequiredEntries $facadeTestEntries)
$inputGroups=@(Get-InputSourceGroups -RepoRoot $repo)
$cockpitGroups=@(Get-CockpitSourceGroups -RepoRoot $repo)
$freeflightGroups=@(Get-FreeflightSourceGroups -RepoRoot $repo)
$observedGroups=@(Get-ObservedReviewSourceGroups -RepoRoot $repo)
$windGroups=@(Get-WindSourceGroups -RepoRoot $repo)
$groundGroups=@(Get-GroundMaterialSourceGroups -RepoRoot $repo)
$pointerGroups=@(Get-PointerSourceGroups -RepoRoot $repo)
$pistonSnapshot=@()
if($includePiston){$pistonSnapshot=@(Get-PistonSourceSnapshot -RepoRoot $repo)}
Assert-WindReferences -RepoRoot $repo -Python $environment.python_executable
Assert-ObservedReviewReferences -RepoRoot $repo -Python $environment.python_executable
& $environment.python_executable (Join-Path $repo 'tests/ui/freeflight/reference-generator.py') --check
if($LASTEXITCODE -ne 0){throw 'Frozen landmark reference reproduction rejected'}
$inputs=@()
foreach($directory in @('app/proof/interactive','app/simulation','app/input','app/ui/controls','app/ui/freeflight','tests/ui/freeflight','app/replay/observed','app/ui/debrief/observed','tests/debrief/observed','app/replay/observed_archive','tests/debrief/observed_archive','tests/input','tests/cockpit','tests/integration/input','app/cockpit','tests/instruments','content/aircraft/prototype','tests/integration/sim_loop','app/world/wind','app/ui/wind','tests/world/wind','tests/integration/wind','tests/world/ground-materials','tools/interactive-preview','native/godot_bridge','native/fdm_jsbsim/interactive','native/fdm_jsbsim/models/original-interactive')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File){
  $relative=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace([char]92,[char]47)
  # Cache hygiene applies only to repository reconstruction input collection.
  # Exact runtime/staged source snapshots retain their separate closed policies.
  if($relative.Split('/') -ccontains '__pycache__' -or $relative.EndsWith('.pyc',[StringComparison]::Ordinal)){continue}
  $inputs+=@{path=$relative;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
 }
}
foreach($pointerFile in $pointerGroups){if(@($inputs.path) -cnotcontains $pointerFile.source){$inputs+=@{path=$pointerFile.source;bytes=$pointerFile.bytes;sha256=$pointerFile.sha256}}}
foreach($kind in @('AircraftSnapshot','AtmosphereSample','ControlCommand','OperationalEvent')){
 $file=Get-Item (Join-Path $repo "tests/contracts/fixtures/$kind.json")
 $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace([char]92,[char]47);sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
}
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive') -Destination (Join-Path $project 'interactive') -Recurse
Copy-SimulationSourceSnapshot -SourceRoot $simulationRoot -DestinationRoot (Join-Path $project 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Copy-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -DestinationRoot (Join-Path $project 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Copy-InputSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $inputGroups
Copy-CockpitSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $cockpitGroups
Copy-FreeflightSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $freeflightGroups
Copy-ObservedReviewSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $observedGroups
Copy-WindSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $windGroups
Copy-GroundMaterialSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $groundGroups
Copy-PointerSourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $pointerGroups
if($includePiston){Copy-PistonSourceSnapshot -RepoRoot $repo -DestinationRoot $project -Snapshot $pistonSnapshot}
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive/project-settings.cfg') -Destination (Join-Path $project 'project.godot')
Set-SimulationMainScene -ProjectFile (Join-Path $project 'project.godot')
Copy-PreviewNativeIdentityResource -Identity $nativeIdentity -DestinationRoot $project
Write-SimulationCheckHarness -ProjectRoot $project -RepoRoot $repo -IncludePiston:$includePiston
Write-PointerCheckHarness -ProjectRoot $project
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/flight.gdextension'),(Join-Path $repo 'app/proof/export_presets.cfg'),(Join-Path $repo 'LICENSE') -Destination $project
Copy-Item -LiteralPath (Join-Path $proof 'payload/bin') -Destination $project -Recurse
$bridge=Join-Path $build 'bin/flight_godot_bridge.dll'
$initialBridgeHash=(Get-FileHash $bridge).Hash
Copy-Item -LiteralPath $bridge -Destination (Join-Path $project 'bin/flight_godot_bridge.dll') -Force
$model=Join-Path $repo 'native/fdm_jsbsim/models/original-interactive'
& node (Join-Path $PSScriptRoot 'package.mjs') models $model (Join-Path $project 'models')
if($LASTEXITCODE -ne 0){throw 'Combined model pin gate failed'}

$preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
if($preset -notmatch 'include_filter="\*\.bin"'){throw 'Unexpected raw resource inclusion before archive staging'}
if(([regex]::Matches($preset,'(?m)^script_export_mode=2\r?$')).Count -ne 1){throw 'Unexpected staged script export mode'}
# Raw generated GDScript bytes must survive the PCK; authored preset stays exact.
$preset=$preset.Replace('script_export_mode=2','script_export_mode=0')
$preset=$preset.Replace('include_filter="*.bin"','include_filter="*.bin,*.ps1"')
$preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template.Replace('\','/')+'"').Replace('exclude_filter=""','exclude_filter="pointer-check-receipt.json,pointer-flight-trace.json,pointer-visual-captures/*,ground-material-receipt.json,native-identity-receipt.json,piston-check-receipt.json,smoke-receipt.json,loop.records.ndjson,compile-all.gd,facade-check-receipt.json,controls*-receipt.json,controls*-preset.json,controls*.png,landmark*.png,landmark*-receipt.json,observed*.png,observed*-receipt.json,wind*.png,wind*-receipt.json"')
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
 $pistonCompileResources=if($includePiston){',"res://engine_tests/bridge_profile_checks.gd","res://engine_tests/facade_checks.gd","res://engine_tests/pacing_checks.gd","res://engine_tests/wind_profile_checks.gd","res://engine_tests/scene_checks.gd"'}else{''}
 [IO.File]::WriteAllText((Join-Path $project 'compile-all.gd'),@"
extends SceneTree
func _initialize() -> void:
 var script=load("res://interactive/preview.gd") as Script
 var scene=load("res://interactive/preview.tscn") as PackedScene
 for path in ["res://simulation/session_facade.gd","res://simulation/render_origin.gd","res://simulation/origin_participant.gd","res://simulation/wire_validation.gd","res://simulation/flight_scene.gd","res://sim_loop_tests/facade_checks.gd","res://sim_loop_checks.gd","res://input/input_mapper.gd","res://input/input_preset.gd","res://ui/controls/controls_panel.gd","res://input_tests/input_checks.gd","res://input_tests/scene_checks.gd","res://cockpit/instruments/native_readings.gd","res://cockpit/instruments/scan_panel.gd","res://instrument_tests/instrument_checks.gd","res://instrument_tests/adapter_checks.gd","res://instrument_tests/cockpit_geometry_checks.gd","res://instrument_tests/cockpit_visual.gd","res://instrument_tests/scan_checks.gd","res://instrument_tests/scene_checks.gd","res://ui/freeflight/landmark_board.gd","res://freeflight_tests/landmark_checks.gd","res://freeflight_tests/scene_checks.gd","res://replay/observed/recorder.gd","res://replay/observed/review.gd","res://replay/observed/tick_math.gd","res://replay/observed/values.gd","res://ui/debrief/observed/panel.gd","res://observed_tests/recorder_checks.gd","res://observed_tests/scene_checks.gd","res://replay/observed_archive/strict_json.gd","res://replay/observed_archive/codec.gd","res://replay/observed_archive/files.gd","res://observed_archive_tests/archive_checks.gd","res://observed_archive_tests/file_checks.gd","res://observed_archive_tests/scene_checks.gd","res://world/wind/wind_cue.gd","res://ui/wind/panel.gd","res://wind_tests/wind_checks.gd","res://wind_scene_tests/scene_checks.gd","res://wind_scene_tests/visual_checks.gd","res://cockpit/instruments/engine_status.gd","res://input_tests/piston_checks.gd","res://input_tests/piston_panel_checks.gd","res://instrument_tests/engine_status_checks.gd","res://ground_material_tests/checks.gd","res://pointer_checks.gd","res://cockpit/engine_controls.gd","res://input_tests/pointer_engine_checks.gd","res://cockpit_tests/engine_controls_checks.gd","res://pointer_scene_tests/pointer_engine_scene_checks.gd","res://pointer_scene_tests/pointer_flight_checks.gd","res://pointer_scene_tests/pointer_visual.gd"$pistonCompileResources]:
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
"@)
 foreach($operation in @(
  @{name='import';args=@('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100')},
  @{name='compile';args=@('--headless','--path',$project,'--script','res://compile-all.gd')},
  @{name='pointer-checks';args=@('--headless','--path',$project,'res://simulation/flight_scene.tscn','--','--pointer-checks')},
  @{name='ground-checks';args=@('--headless','--path',$project,'res://sim_loop_checks.tscn','--','--ground-material-checks')},
  @{name='facade-checks';args=@('--headless','--path',$project,'res://sim_loop_checks.tscn')},
  @{name='editor-smoke';args=@('--headless','--path',$project,'--','--smoke')},
  @{name='export';args=@('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $payload 'WholeFlightPreview.exe'))}
 )){
  if($operation.name -eq 'pointer-checks' -and -not $includePiston){continue}
  $deadline=if($operation.name -in @('facade-checks','pointer-checks')){$FacadeCheckTimeoutSeconds}else{120}
  if($operation.name -eq 'pointer-checks'){$result=Invoke-ProofProcess -Executable $godot -Arguments $operation.args -WorkingDirectory $root -Log (Join-Path $evidence ($operation.name+'.log')) -CleanEnvironment -ProfileRoot (Join-Path $root 'pointer-userdata-editor') -TimeoutSeconds $deadline}
  else{$result=Invoke-ProofProcess -Executable $godot -Arguments $operation.args -WorkingDirectory $root -Log (Join-Path $evidence ($operation.name+'.log')) -TimeoutSeconds $deadline}
  if($operation.name -eq 'pointer-checks'){Save-PreviewPointerObservation -TargetPath $project -Evidence $evidence -Name 'editor'}
  if($operation.name -eq 'ground-checks'){Save-PreviewGroundObservation -TargetPath $project -Evidence $evidence -Name 'editor'}
  if($operation.name -eq 'facade-checks'){Save-PreviewFacadeObservation -TargetPath $project -Evidence $evidence -Name 'editor'}
  Assert-PreviewProcessResult $result $operation.name
  if($operation.name -eq 'pointer-checks'){Assert-PreviewPointerResult -Result $result -TargetPath $project -Evidence $evidence -Name 'editor'}
  if($operation.name -eq 'ground-checks'){Assert-PreviewGroundResult -Result $result -TargetPath $project -Evidence $evidence -Name 'editor'}
  if($operation.name -eq 'facade-checks'){
   $receipt=Get-Content (Join-Path $project 'facade-check-receipt.json') -Raw | ConvertFrom-Json
   if($result.text -notmatch 'SIM_LOOP_CHECKS_PASSED'){throw 'Actual facade checks failed'}
   Assert-PreviewFacadeReceipt -Receipt $receipt
   $identityReceipt=Get-Content -LiteralPath (Join-Path $project 'native-identity-receipt.json') -Raw | ConvertFrom-Json
   Assert-PreviewNativeResourceReceipt -Receipt $identityReceipt -Identity $nativeIdentity
   Copy-Item -LiteralPath (Join-Path $project 'native-identity-receipt.json') -Destination (Join-Path $evidence 'editor-native-identity-receipt.json')
   Copy-Item -LiteralPath (Join-Path $project 'facade-check-receipt.json') -Destination (Join-Path $evidence 'editor-facade-receipt.json')
   if($includePiston){
    $coldReceipt=Get-Content -LiteralPath (Join-Path $project 'piston-check-receipt.json') -Raw|ConvertFrom-Json
    Assert-PreviewPistonReceipt -Receipt $coldReceipt
    Copy-Item -LiteralPath (Join-Path $project 'piston-check-receipt.json') -Destination (Join-Path $evidence 'editor-piston-receipt.json')
   }
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
if($includePiston){Copy-Item -LiteralPath (Join-Path $project 'piston-models') -Destination (Join-Path $payload 'piston-models') -Recurse}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launch.ps1'),(Join-Path $PSScriptRoot 'README.md') -Destination $payload
$source=Join-Path $payload 'source/whole-flight-preview'
New-Item -ItemType Directory -Force $source | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/interactive'),$PSScriptRoot,(Join-Path $repo 'native'),(Join-Path $repo 'LICENSE'),(Join-Path $repo 'CMakeLists.txt'),(Join-Path $repo 'CMakePresets.json') -Destination $source -Recurse
Copy-SimulationSourceSnapshot -SourceRoot $simulationRoot -DestinationRoot (Join-Path $source 'simulation') -Snapshot $simulationSnapshot -RequiredEntries $simulationEntries
Copy-SimulationSourceSnapshot -SourceRoot $facadeTestRoot -DestinationRoot (Join-Path $source 'sim_loop_tests') -Snapshot $facadeTestSnapshot -RequiredEntries $facadeTestEntries
Copy-InputSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $inputGroups
Copy-CockpitSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $cockpitGroups
Copy-FreeflightSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $freeflightGroups
Copy-ObservedReviewSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $observedGroups
Copy-WindSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $windGroups
Copy-GroundMaterialSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $groundGroups
Copy-PointerSourceGroups -RepoRoot $repo -DestinationRoot $source -Groups $pointerGroups
if($includePiston){Copy-PistonSourceSnapshot -RepoRoot $repo -DestinationRoot $source -Snapshot $pistonSnapshot}
Copy-Item -LiteralPath (Join-Path $project 'wire_fixtures'),(Join-Path $project 'sim_loop_checks.gd'),(Join-Path $project 'sim_loop_checks.tscn'),(Join-Path $project 'pointer_checks.gd') -Destination $source -Recurse
Copy-PreviewNativeIdentityResource -Identity $nativeIdentity -DestinationRoot $source
& $environment.python_executable -B (Join-Path $PSScriptRoot 'native-identity.py') --repository-root $repo --build-root $build --evidence (Join-Path $evidence 'native-build-identity.json') --staged-root $project --staged-root $source --reconstruction-root $source
if($LASTEXITCODE -ne 0){throw 'Corresponding-source identity reconstruction rejected'}
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
 if($includePiston){
  $pointerResult=Invoke-ProofProcess -Executable (Join-Path $target.path 'WholeFlightPreview.exe') -Arguments @('--headless','--','--pointer-checks') -WorkingDirectory $root -Log (Join-Path $evidence ($target.name+'-pointer.log')) -CleanEnvironment -ProfileRoot (Join-Path $root ('pointer-userdata-'+$target.name)) -TimeoutSeconds $FacadeCheckTimeoutSeconds
  Assert-PreviewPointerResult -Result $pointerResult -TargetPath $target.path -Evidence $evidence -Name $target.name
 }
 $groundResult=Invoke-ProofProcess -Executable (Join-Path $target.path 'WholeFlightPreview.exe') -Arguments @('--headless','--','--facade-checks','--ground-material-checks') -WorkingDirectory $root -Log (Join-Path $evidence ($target.name+'-ground.log')) -CleanEnvironment -ProfileRoot (Join-Path $root ('ground-userdata-'+$target.name)) -TimeoutSeconds 120
 Assert-PreviewGroundResult -Result $groundResult -TargetPath $target.path -Evidence $evidence -Name $target.name
 $result=Invoke-ProofProcess -Executable (Join-Path $target.path 'WholeFlightPreview.exe') -Arguments @('--headless','--','--facade-checks') -WorkingDirectory $root -Log (Join-Path $evidence ($target.name+'-facade.log')) -CleanEnvironment -ProfileRoot (Join-Path $root ('facade-userdata-'+$target.name)) -TimeoutSeconds $FacadeCheckTimeoutSeconds
 Save-PreviewFacadeObservation -TargetPath $target.path -Evidence $evidence -Name $target.name
 Assert-PreviewProcessResult $result ($target.name+'-facade')
 if($result.text -notmatch 'SIM_LOOP_CHECKS_PASSED' -or $result.text -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED'){throw 'Exported actual facade checks failed'}
 $receipt=Get-Content (Join-Path $target.path 'facade-check-receipt.json') -Raw | ConvertFrom-Json
 Assert-PreviewFacadeReceipt -Receipt $receipt
 $identityReceipt=Get-Content -LiteralPath (Join-Path $target.path 'native-identity-receipt.json') -Raw | ConvertFrom-Json
 Assert-PreviewNativeResourceReceipt -Receipt $identityReceipt -Identity $nativeIdentity
 Move-Item -LiteralPath (Join-Path $target.path 'native-identity-receipt.json') -Destination (Join-Path $evidence ($target.name+'-native-identity-receipt.json'))
 Move-Item -LiteralPath (Join-Path $target.path 'facade-check-receipt.json') -Destination (Join-Path $evidence ($target.name+'-facade-receipt.json'))
 if($includePiston){
  $coldReceipt=Get-Content -LiteralPath (Join-Path $target.path 'piston-check-receipt.json') -Raw|ConvertFrom-Json
  Assert-PreviewPistonReceipt -Receipt $coldReceipt
  Move-Item -LiteralPath (Join-Path $target.path 'piston-check-receipt.json') -Destination (Join-Path $evidence ($target.name+'-piston-receipt.json'))
 }
}
Write-ProofDependencyReport -Payload $payload -BuildManifest (Join-Path $build 'toolchain-build-manifest.txt') -Output (Join-Path $evidence 'native-dependencies.json')
& node (Join-Path $PSScriptRoot 'package.mjs') audit $root $proof $build $environment.python_executable
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
Assert-FreeflightSourceGroups -DestinationRoot $repo -Groups $freeflightGroups -Authoring
Assert-FreeflightSourceGroups -DestinationRoot $project -Groups $freeflightGroups -AllowGeneratedUIDs
Assert-FreeflightSourceGroups -DestinationRoot $source -Groups $freeflightGroups
Assert-ObservedReviewSourceGroups -DestinationRoot $repo -Groups $observedGroups -Authoring
Assert-ObservedReviewSourceGroups -DestinationRoot $project -Groups $observedGroups -AllowGeneratedUIDs
Assert-ObservedReviewSourceGroups -DestinationRoot $source -Groups $observedGroups
Assert-WindSourceGroups -DestinationRoot $repo -Groups $windGroups -Authoring
Assert-WindSourceGroups -DestinationRoot $project -Groups $windGroups -AllowGeneratedUIDs
Assert-WindSourceGroups -DestinationRoot $source -Groups $windGroups
Assert-GroundMaterialSourceGroups -DestinationRoot $repo -Groups $groundGroups -Authoring
Assert-GroundMaterialSourceGroups -DestinationRoot $project -Groups $groundGroups -AllowGeneratedUIDs
Assert-GroundMaterialSourceGroups -DestinationRoot $source -Groups $groundGroups
Assert-PointerSourceGroups -Root $repo -Groups $pointerGroups -Authoring
Assert-PointerSourceGroups -Root $project -Groups $pointerGroups -AllowGeneratedUIDs
Assert-PointerSourceGroups -Root $source -Groups $pointerGroups
if($includePiston){
 Assert-PistonSourceSnapshot -Root $repo -Snapshot $pistonSnapshot -Authoring
 Assert-PistonSourceSnapshot -Root $project -Snapshot $pistonSnapshot -AllowGeneratedUIDs
 Assert-PistonSourceSnapshot -Root $source -Snapshot $pistonSnapshot
 $payloadModel=@($pistonSnapshot|Where-Object {$_.destination.StartsWith('piston-models/')}|ForEach-Object {[pscustomobject]@{path=$_.destination.Substring(14);bytes=$_.bytes;sha256=$_.sha256}}|Sort-Object path)
 Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $payload 'piston-models') -Snapshot $payloadModel -RequiredEntries @($payloadModel.path)
}
Assert-PreviewNativeIdentityResource -Identity $nativeIdentity -DestinationRoot $project -AllowGeneratedUIDs
Assert-PreviewNativeIdentityResource -Identity $nativeIdentity -DestinationRoot $source
$finalNativeIdentity=Get-PreviewNativeBuildIdentity -RepoRoot $repo -NativeBuildRoot $build -Python $environment.python_executable
if(($nativeIdentity | ConvertTo-Json -Depth 10 -Compress) -cne ($finalNativeIdentity | ConvertTo-Json -Depth 10 -Compress)){throw 'Selected native build/source changed during proof'}
if((Get-FileHash $bridge).Hash -ne $initialBridgeHash){throw 'Native bridge changed during proof'}
foreach($input in $inputs){if((Get-FileHash (Join-Path $repo $input.path)).Hash.ToLowerInvariant() -ne $input.sha256){throw 'Authoring source changed during proof'}}
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins-final.json')
if($LASTEXITCODE -ne 0){throw 'Toolchain drift detected'}
if((Get-FileHash (Join-Path $evidence 'tool-pins.json')).Hash -ne (Get-FileHash (Join-Path $evidence 'tool-pins-final.json')).Hash){throw 'Selected tool identities changed during proof'}
$inventory=@(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {@{path=[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}} | Sort-Object {$_.path})
$uidRoots=@((Join-Path $project 'simulation'),(Join-Path $project 'sim_loop_tests'),(Join-Path $project 'input'),(Join-Path $project 'ui/controls'),(Join-Path $project 'input_tests'),(Join-Path $project 'cockpit'),(Join-Path $project 'instrument_tests'),(Join-Path $project 'ui/freeflight'),(Join-Path $project 'freeflight_tests'),(Join-Path $project 'replay/observed'),(Join-Path $project 'ui/debrief/observed'),(Join-Path $project 'observed_tests'),(Join-Path $project 'replay/observed_archive'),(Join-Path $project 'observed_archive_tests'),(Join-Path $project 'world/wind'),(Join-Path $project 'ui/wind'),(Join-Path $project 'wind_tests'),(Join-Path $project 'wind_scene_tests'))
$uidRoots+=Join-Path $project 'ground_material_tests'
$uidRoots+=Join-Path $project 'cockpit_tests'
$uidRoots+=Join-Path $project 'pointer_scene_tests'
if($includePiston){$uidRoots+=Join-Path $project 'engine_tests'}
$manifest=@{schema_version=1;kind='original-whole-flight-preview';passed=$true;scope='Windows original model, actual functional headless proof; GPU/human acceptance separate';git_head=(& git -c "safe.directory=$repo" -C $repo rev-parse HEAD);powershell=$PSVersionTable.PSVersion.ToString();authoring_sources=$inputs;observed_sources=$observedGroups;wind_sources=$windGroups;ground_sources=$groundGroups;pointer_sources=$pointerGroups;pointer_checks_enabled=$includePiston;staged_pointer_harness_sha256=(Get-FileHash (Join-Path $project 'pointer_checks.gd')).Hash.ToLowerInvariant();piston_sources=$pistonSnapshot;piston_checks_enabled=$includePiston;native_build_identity=$nativeIdentity;selected_library=$selectedLibrary;staged_compile_sha256=(Get-FileHash (Join-Path $project 'compile-all.gd')).Hash.ToLowerInvariant();staged_generated_uid_metadata=@(Get-ChildItem -LiteralPath $uidRoots -Recurse -File -Filter '*.gd.uid'|ForEach-Object {@{path=[IO.Path]::GetRelativePath($project,$_.FullName).Replace([char]92,[char]47);sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}});staged_facade_harness_sha256=(Get-FileHash (Join-Path $project 'sim_loop_checks.gd')).Hash.ToLowerInvariant();staged_project_sha256=(Get-FileHash (Join-Path $project 'project.godot')).Hash.ToLowerInvariant();tool_pins=$pins;godot_version=$version.text.Trim();accepted_native_export_root=$proof;accepted_package_inventory_sha256=(Get-FileHash (Join-Path $proof 'evidence/package-inventory.json')).Hash.ToLowerInvariant();files=$inventory}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $evidence 'manifest.json')
@{root=$root;project=$project;payload=$payload;evidence=$evidence;passed=$true} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $repo '.local/interactive-preview/latest-run.json')
Write-Output $root


