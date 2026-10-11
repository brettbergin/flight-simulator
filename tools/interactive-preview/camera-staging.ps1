# Original MIT. Additive ADR025 source staging; no native/library selection changes.
function Get-CameraSourceDefinitions {
 @(
  @{source='app/camera';destination='camera';required=@('view_policy.gd')},
  @{source='app/ui/camera';destination='ui/camera';required=@('views_panel.gd')},
  @{source='tests/camera';destination='camera_tests';required=@('.gitattributes','README.md','expected-v1.json','generate.py','root-ratification-v1.json','source-binding-v1.json','policy_checks.gd','panel_checks.gd','scene_checks.gd')}
 )
}
function Get-CameraSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(Get-CameraSourceDefinitions|ForEach-Object {
  $_.snapshot=@(Get-SimulationSourceSnapshot -SourceRoot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required)
  if((($_.snapshot.path|Sort-Object)-join "`n") -cne (($_.required|Sort-Object)-join "`n")){throw 'Closed camera source roster required'}
  $_
 })
}
function Assert-CameraSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-CameraSourceDefinitions)
 if($Groups.Count -ne $definitions.Count){throw 'Complete three-group camera roster required'}
 for($i=0;$i -lt $definitions.Count;$i++){
  $group=$Groups[$i];$expected=$definitions[$i]
  if($group.source -cne $expected.source -or $group.destination -cne $expected.destination -or (($group.required|Sort-Object)-join "`n") -cne (($expected.required|Sort-Object)-join "`n") -or (($group.snapshot.path|Sort-Object)-join "`n") -cne (($expected.required|Sort-Object)-join "`n")){throw 'Camera group descriptor rejected'}
  $folder=if($Authoring){$group.source}else{$group.destination}
  Assert-PreviewOrdinaryAncestors -Path (Join-Path $Root $folder)
  Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root $folder) -Snapshot $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:($AllowGeneratedUIDs -and -not $Authoring)
 }
}
function Copy-CameraSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-CameraSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 foreach($group in $Groups){Copy-SimulationSourceSnapshot -SourceRoot (Join-Path $RepoRoot $group.source) -DestinationRoot (Join-Path $DestinationRoot $group.destination) -Snapshot $group.snapshot -RequiredEntries $group.required}
 Assert-CameraSourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-CameraSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
function Save-PreviewCameraObservation {
 param([Parameter(Mandatory)][string]$TargetPath,[Parameter(Mandatory)][string]$Evidence,[Parameter(Mandatory)][string]$Name)
 $raw=Join-Path $TargetPath 'camera-check-receipt.json'
 if(Test-Path -LiteralPath $raw -PathType Leaf){
  $destination=Join-Path $Evidence ($Name+'-camera-observed-receipt.json')
  if(Test-Path -LiteralPath $destination){throw 'Camera raw observation destination must be fresh'}
  Copy-Item -LiteralPath $raw -Destination $destination
 }
}
function Save-ValidatedPreviewCameraReceipt {
 param([Parameter(Mandatory)][string]$TargetPath,[Parameter(Mandatory)][string]$Evidence,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$NativeIdentityPath,[bool]$RequireFullSupported=$false)
 $raw=Join-Path $TargetPath 'camera-check-receipt.json'
 & node (Join-Path $PSScriptRoot 'camera-receipt.mjs') receipt $raw $RepoRoot $ProjectRoot $NativeIdentityPath $RequireFullSupported.ToString().ToLowerInvariant()
 if($LASTEXITCODE -ne 0){throw 'Actual camera receipt/reference/source/start coverage rejected'}
 $destination=Join-Path $Evidence ($Name+'-camera-receipt.json')
 if(Test-Path -LiteralPath $destination){throw 'Camera validated receipt destination must be fresh'}
 Move-Item -LiteralPath $raw -Destination $destination
}
function Get-PreviewCameraHarnessClass {
 @'
class CameraCheckHost extends Node:
 var checks: int=0
 var failures: Array[String]=[]
 func check(value: bool,label: String)->void:
  checks+=1
  if not value: failures.append(label)

'@
}
function Get-PreviewCameraHarnessChecks {
 param([Parameter(Mandatory)][object[]]$Groups,[Parameter(Mandatory)][bool]$IncludePiston)
 $sourceFiles=[ordered]@{}
 # Literal source-only transport exception: Godot does not export dotfiles.
 foreach($group in $Groups){foreach($file in $group.snapshot){if($group.source -ceq 'tests/camera' -and $file.path -ceq '.gitattributes'){continue};$sourceFiles[$group.destination+'/'+$file.path]=@{bytes=$file.bytes;sha256=$file.sha256}}}
 $sourceLiteral=$sourceFiles|ConvertTo-Json -Depth 8 -Compress
 $coldLiteral=$IncludePiston.ToString().ToLowerInvariant()
 @"
 stage("begin","camera")
 var camera_sources: Dictionary=$sourceLiteral
 var camera_source_ok: bool=true
 for relative in camera_sources:
  var camera_path: String="res://"+relative
  if not FileAccess.file_exists(camera_path) or FileAccess.get_file_as_bytes(camera_path).size()!=camera_sources[relative].bytes or FileAccess.get_sha256(camera_path)!=camera_sources[relative].sha256:
   check(false,"camera_resource_"+relative)
   camera_source_ok=false
 if not camera_source_ok:
  get_tree().quit(1)
  return
 var camera_reference_hash: String=FileAccess.get_sha256("res://camera_tests/expected-v1.json")
 if camera_reference_hash!="d3ee38b2a2455e7a21c61ae46f01461dd901663c3743581059e19c5193f513cd":
  check(false,"camera_frozen_reference")
  get_tree().quit(1)
  return
 var camera_identity: Script=load("res://build/native_identity.gd")
 var camera_host=CameraCheckHost.new()
 add_child(camera_host)
 var camera_groups: Dictionary={}
 camera_groups.policy=load("res://camera_tests/policy_checks.gd").run()
 camera_groups.panel=await load("res://camera_tests/panel_checks.gd").new().run(camera_host)
 camera_groups.scene=await load("res://camera_tests/scene_checks.gd").new().run(camera_host,$coldLiteral)
 var camera_failures: Array=Array(camera_host.failures)
 var camera_checks: int=0
 for group_name in ["policy","panel","scene"]:
  var camera_group: Dictionary=camera_groups[group_name]
  if typeof(camera_group.get("checks"))!=TYPE_INT or camera_group.checks<=0:
   camera_failures.append(group_name+"_inactive_checks")
  else: camera_checks+=camera_group.checks
  if typeof(camera_group.get("passed"))!=TYPE_BOOL or not camera_group.passed or not camera_group.get("failures") is Array or not camera_group.failures.is_empty():
   camera_failures.append(group_name+"_failed")
 camera_host.free()
 var camera_harness: Dictionary={}
 for relative in ["camera_checks.gd","camera_checks.tscn"]:
  var raw: PackedByteArray=FileAccess.get_file_as_bytes("res://"+relative)
  camera_harness[relative]={"bytes":raw.size(),"sha256":FileAccess.get_sha256("res://"+relative)}
 var camera_execution: Dictionary={"display_backend":DisplayServer.get_name(),"capture_observed":capture_observed,"harness_files":camera_harness}
 var camera_report: Dictionary={"execution":camera_execution,"schema":"CameraChecks/v1","passed":camera_failures.is_empty(),"checks":camera_checks,"failures":camera_failures,"scope":"Actual camera policy, paused page and native Scene checks; original presentation only, GPU/hardware/pilot acceptance separate","reference":{"cases":132,"sha256":camera_reference_hash},"groups":camera_groups,"source_files":camera_sources,"native_identity":{"source_variant":camera_identity.SOURCE_VARIANT,"source_fingerprint":camera_identity.SOURCE_FINGERPRINT}}
 var camera_output: String=ProjectSettings.globalize_path("res://camera-check-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("camera-check-receipt.json")
 if FileAccess.file_exists(camera_output):
  check(false,"camera_receipt_fresh")
  get_tree().quit(1)
  return
 var camera_file=FileAccess.open(camera_output,FileAccess.WRITE)
 check(camera_file!=null,"camera_receipt_saved")
 if camera_file!=null:
  camera_file.store_string(JSON.stringify(camera_report,"  ",false,true))
  camera_file.close()
 checks+=camera_checks
 for camera_failure in camera_failures: failures.append("camera:"+str(camera_failure))
 check(camera_report.passed,"actual_camera_policy_panel_scene_checks")
 stage("end","camera")

"@
}

function Write-PreviewCameraCheckHarness {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][object[]]$Groups,[Parameter(Mandatory)][bool]$IncludePiston)
 $class=Get-PreviewCameraHarnessClass
 $checks=Get-PreviewCameraHarnessChecks -Groups $Groups -IncludePiston $IncludePiston
 $script=@"
extends Node
# Original MIT. Separate graphical qualification; never part of Facade/v1.
$class
var checks: int=0
var failures: Array=[]
var capture_observed: bool=false
func check(value: bool,label: String)->void:
 checks+=1
 if not value: failures.append(label)
func stage(boundary: String,label: String)->void:
 print("CAMERA_STAGE "+boundary+" "+label+" ms="+str(Time.get_ticks_msec()))
func _ready()->void:
 call_deferred("execute")
func execute()->void:
 # An unavailable display is a missing mandatory gate, never a headless pass.
 if OS.get_name()!="Windows" or DisplayServer.get_name()=="headless":
  push_error("CAMERA_GRAPHICAL_GATE_UNAVAILABLE: Windows graphical display required")
  get_tree().quit(1)
  return
 # Qualify the actual driver, not only requested CLI or a successful fallback.
 var camera_args: PackedStringArray=OS.get_cmdline_args()
 var method_index: int=camera_args.find("--rendering-method")
 var driver_index: int=camera_args.find("--rendering-driver")
 if camera_args.count("--rendering-method")!=1 or camera_args.count("--rendering-driver")!=1 or method_index<0 or driver_index<0 or method_index+1>=camera_args.size() or driver_index+1>=camera_args.size():
  push_error("CAMERA_RENDERING_REQUEST_INVALID")
  get_tree().quit(1)
  return
 var actual_method: String=RenderingServer.get_current_rendering_method()
 var actual_driver: String=RenderingServer.get_current_rendering_driver_name()
 if actual_method!=camera_args[method_index+1] or actual_driver!=camera_args[driver_index+1]:
  push_error("CAMERA_RENDERING_DRIVER_MISMATCH: requested driver cannot silently fallback")
  get_tree().quit(1)
  return
 print("CAMERA_RENDERING method="+actual_method+" driver="+actual_driver)
 var previous_mouse: int=Input.mouse_mode
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 await get_tree().process_frame
 await get_tree().process_frame
 capture_observed=Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
 Input.mouse_mode=previous_mouse
 await get_tree().process_frame
 if not capture_observed or Input.mouse_mode!=previous_mouse:
  push_error("CAMERA_GRAPHICAL_GATE_UNAVAILABLE: real capture/restore required")
  get_tree().quit(1)
  return
$checks
 print("CAMERA_CHECKS_PASSED" if failures.is_empty() else "CAMERA_CHECKS_FAILED "+JSON.stringify(failures))
 await get_tree().process_frame
 await get_tree().process_frame
 get_tree().quit(0 if failures.is_empty() else 1)
"@
 $scene=@'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://camera_checks.gd" id="1"]

[node name="CameraChecks" type="Node"]
script = ExtResource("1")
'@
 foreach($pair in @(@{name='camera_checks.gd';text=$script},@{name='camera_checks.tscn';text=$scene})){
  $file=Join-Path $ProjectRoot $pair.name
  if(Test-Path -LiteralPath $file){throw 'Generated camera harness destination must be fresh'}
  [IO.File]::WriteAllText($file,$pair.text,[Text.UTF8Encoding]::new($false))
 }
}
function Invoke-PreviewGraphicalCameraChecks {
 param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$TargetPath,[Parameter(Mandatory)][string]$Evidence,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$NativeIdentityPath,[ValidateRange(120,600)][int]$TimeoutSeconds=120,[bool]$RequireFullSupported=$false)
 if(-not $IsWindows){throw 'Mandatory camera graphical gate requires Windows; no headless substitution'}
 Assert-PreviewCameraHarnessFiles -ProjectRoot $ProjectRoot
 if($Arguments -contains '--headless'){throw 'Graphical camera invocation cannot be headless'}
 $methodIndex=[Array]::IndexOf($Arguments,'--rendering-method')
 $driverIndex=[Array]::IndexOf($Arguments,'--rendering-driver')
 if(@($Arguments|Where-Object {$_ -ceq '--rendering-method'}).Count -ne 1 -or @($Arguments|Where-Object {$_ -ceq '--rendering-driver'}).Count -ne 1 -or $methodIndex -lt 0 -or $driverIndex -lt 0 -or $methodIndex+1 -ge $Arguments.Count -or $driverIndex+1 -ge $Arguments.Count){throw 'Exactly one explicit camera method/driver pair required'}
 $requestedMethod=$Arguments[$methodIndex+1]
 $requestedDriver=$Arguments[$driverIndex+1]
 if($requestedMethod -cnotin @('gl_compatibility','mobile','forward_plus') -or $requestedDriver -cnotin @('opengl3','opengl3_angle','vulkan','d3d12') -or (($requestedMethod -ceq 'gl_compatibility') -ne ($requestedDriver -cin @('opengl3','opengl3_angle')))){throw 'Explicit camera method/driver pair rejected'}
 $renderingMarker='CAMERA_RENDERING method='+$requestedMethod+' driver='+$requestedDriver

 if(Test-Path -LiteralPath (Join-Path $TargetPath 'camera-check-receipt.json')){throw 'Camera receipt destination must be fresh'}
 try {
  $result=Invoke-ProofProcess -Executable $Executable -Arguments $Arguments -WorkingDirectory $Root -Log (Join-Path $Evidence ($Name+'-camera.log')) -CleanEnvironment -ProfileRoot (Join-Path $Root ('camera-userdata-'+$Name)) -TimeoutSeconds $TimeoutSeconds
 } finally {Save-PreviewCameraObservation -TargetPath $TargetPath -Evidence $Evidence -Name $Name}
 if($result.exit_code -ne 0 -or $result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed' -or $result.text -notmatch 'CAMERA_CHECKS_PASSED' -or $result.text -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED' -or $result.text -cnotmatch ('(?m)^'+[Regex]::Escape($renderingMarker)+'\r?$')){throw 'Mandatory graphical camera gate failed or unavailable; raw evidence retained'}
 Save-ValidatedPreviewCameraReceipt -TargetPath $TargetPath -Evidence $Evidence -Name $Name -RepoRoot $RepoRoot -ProjectRoot $ProjectRoot -NativeIdentityPath $NativeIdentityPath -RequireFullSupported $RequireFullSupported
}
function Assert-PreviewCameraHarnessFiles {
 param([Parameter(Mandatory)][string]$ProjectRoot,[string]$SourceRoot='')
 foreach($name in @('camera_checks.gd','camera_checks.tscn')){
  $file=Join-Path $ProjectRoot $name
  Assert-PreviewOrdinaryAncestors -Path $file
  $item=Get-Item -LiteralPath $file
  if($item.PSIsContainer -or $item.Length -le 0 -or $item.Length -gt 65536){throw 'Bounded ordinary generated camera resource required'}
  if($SourceRoot){
   $copy=Join-Path $SourceRoot $name
   Assert-PreviewOrdinaryAncestors -Path $copy
   if((Get-Item -LiteralPath $copy).PSIsContainer -or (Get-FileHash -LiteralPath $copy).Hash -cne (Get-FileHash -LiteralPath $file).Hash){throw 'Generated camera corresponding source changed'}
  }
 }
 $uid=Join-Path $ProjectRoot 'camera_checks.gd.uid'
 if(Test-Path -LiteralPath $uid){
  Assert-PreviewOrdinaryAncestors -Path $uid
  $item=Get-Item -LiteralPath $uid
  if($item.PSIsContainer -or $item.Length -gt 64 -or [IO.File]::ReadAllText($uid) -cnotmatch '^uid://[a-z0-9]{1,20}\r?\n?$'){throw 'Generated camera script UID rejected'}
 }
 if($SourceRoot -and (Test-Path -LiteralPath (Join-Path $SourceRoot 'camera_checks.gd.uid'))){throw 'Generated camera UID cannot enter corresponding source'}
}
