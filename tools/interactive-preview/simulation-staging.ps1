#Requires -Version 7.0
# Recursive authoring snapshot shared by project staging and corresponding source.
function Get-SimulationSourceSnapshot {
 param([Parameter(Mandatory)][string]$SourceRoot,[string[]]$RequiredEntries=@('session_facade.gd','render_origin.gd'))
 $root=(Get-Item -LiteralPath $SourceRoot -ErrorAction Stop)
 if(-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Simulation source must be an ordinary directory'}
 foreach($entry in $RequiredEntries){
  if(-not (Test-Path -LiteralPath (Join-Path $root.FullName $entry) -PathType Leaf)){throw "Missing simulation resource: $entry"}
 }
 $items=@(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force)
 if(@($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Simulation source contains a reparse point'}
 @($items|Where-Object {-not $_.PSIsContainer}|ForEach-Object {
  [pscustomobject]@{path=[IO.Path]::GetRelativePath($root.FullName,$_.FullName).Replace([char]92,[char]47);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
 }|Sort-Object path)
}
function Assert-SimulationSourceSnapshot {
 param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][object[]]$Snapshot,[string[]]$RequiredEntries=@('session_facade.gd','render_origin.gd'),[switch]$AllowGeneratedUIDs)
 $actual=@(Get-SimulationSourceSnapshot -SourceRoot $SourceRoot -RequiredEntries $RequiredEntries)
 if($AllowGeneratedUIDs){
  # Godot writes script UID sidecars during import. Only these generated siblings
  # of already-bound scripts are permitted; source/corresponding-source stay exact.
  $actual=@($actual|Where-Object {
   $generated=$false
   if($_.path.EndsWith('.gd.uid') -and -not (@($Snapshot.path) -ccontains $_.path)){
    $script=$_.path.Substring(0,$_.path.Length-4)
    $text=[IO.File]::ReadAllText((Join-Path $SourceRoot $_.path))
    $generated=(@($Snapshot.path) -ccontains $script) -and $_.bytes -le 64 -and $text -cmatch '^uid://[a-z0-9]{1,20}\r?\n?$'
   }
   -not $generated
  })
 }
 if($actual.Count -ne $Snapshot.Count){throw 'Simulation resource set changed'}
 for($i=0;$i -lt $actual.Count;$i++){
  if($actual[$i].path -cne $Snapshot[$i].path -or $actual[$i].bytes -ne $Snapshot[$i].bytes -or $actual[$i].sha256 -cne $Snapshot[$i].sha256){throw "Simulation source bytes changed: $($actual[$i].path)"}
 }
}
function Copy-SimulationSourceSnapshot {
 param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Snapshot,[string[]]$RequiredEntries=@('session_facade.gd','render_origin.gd'))
 Assert-SimulationSourceSnapshot -SourceRoot $SourceRoot -Snapshot $Snapshot -RequiredEntries $RequiredEntries
 if(Test-Path -LiteralPath $DestinationRoot){throw 'Simulation staging destination must be fresh'}
 New-Item -ItemType Directory -Path $DestinationRoot -Force|Out-Null
 foreach($file in $Snapshot){
  $destination=Join-Path $DestinationRoot $file.path
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceRoot $file.path) -Destination $destination
 }
 Assert-SimulationSourceSnapshot -SourceRoot $DestinationRoot -Snapshot $Snapshot -RequiredEntries $RequiredEntries
 Assert-SimulationSourceSnapshot -SourceRoot $SourceRoot -Snapshot $Snapshot -RequiredEntries $RequiredEntries
}
function Set-SimulationMainScene {
 param([Parameter(Mandatory)][string]$ProjectFile)
 $text=[IO.File]::ReadAllText($ProjectFile)
 $old='run/main_scene="res://interactive/preview.tscn"'
 if(([regex]::Matches($text,[regex]::Escape($old))).Count -ne 1){throw 'Expected one legacy main-scene setting before staging facade'}
 [IO.File]::WriteAllText($ProjectFile,$text.Replace($old,'run/main_scene="res://simulation/flight_scene.tscn"'))
}
# Input/UI/fixtures use the same exact recursive snapshot and import-only UID policy.
function Get-InputSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/input';destination='input';required=@('input_mapper.gd','input_preset.gd')},
  @{source='app/ui/controls';destination='ui/controls';required=@('controls_panel.gd')},
  @{source='tests/input';destination='input_tests';required=@('input_checks.gd','scene_checks.gd','reference.json')}
 )|ForEach-Object {
  $_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required)
  $_
 }
}
function Copy-InputSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-InputSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){
  $path=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
# Cockpit leaves, original fixtures and prototype provenance share exact snapshots.
function Get-CockpitSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/cockpit';destination='cockpit';required=@('instruments/native_readings.gd','instruments/scan_panel.gd')},
  @{source='tests/instruments';destination='instrument_tests';required=@('instrument_checks.gd','adapter_checks.gd','scan_checks.gd','scene_checks.gd','reference.json','preparation-manifest.json')},
  @{source='content/aircraft/prototype';destination='content/aircraft/prototype';required=@('cockpit-presentation.json')}
 )|ForEach-Object {
  $_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required)
  $_
 }
}
function Copy-CockpitSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-CockpitSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){
  $path=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Write-SimulationCheckHarness {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RepoRoot)
 $fixtures=Join-Path $ProjectRoot 'wire_fixtures'
 New-Item -ItemType Directory -Path $fixtures -Force|Out-Null
 foreach($name in @('AircraftSnapshot','AtmosphereSample','ControlCommand','OperationalEvent')){
  Copy-Item -LiteralPath (Join-Path $RepoRoot "tests/contracts/fixtures/$name.json") -Destination $fixtures
 }
 [IO.File]::WriteAllText((Join-Path $ProjectRoot 'sim_loop_checks.gd'),@"
extends Node
# Original MIT. Active headless fixtures; no owner profile or training evidence.
var checks: int=0
var failures: Array=[]
func check(ok: bool, label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
func _ready() -> void:
 call_deferred("execute")
func execute() -> void:
 for folder in ["res://simulation","res://sim_loop_tests","res://interactive","res://input","res://ui/controls","res://input_tests","res://cockpit/instruments","res://instrument_tests","res://engine_tests"]:
  for name in DirAccess.get_files_at(folder):
   if name.ends_with(".gd"):
    var script=load(folder.path_join(name)) as Script
    check(script!=null and script.can_instantiate(),"explicit_compile_"+folder.path_join(name))
 for path in ["res://simulation/flight_scene.tscn","res://interactive/preview.tscn"]:
  check(load(path) is PackedScene,"explicit_scene_compile_"+path)
 if not failures.is_empty():
  push_error("Simulation resource compilation rejected")
  get_tree().quit(1)
  return
 var facade_script=load("res://sim_loop_tests/facade_checks.gd") as Script
 var facade: Dictionary=facade_script.run(ProjectSettings.globalize_path("res://models"))
 check(facade.get("checks",0)>0 and facade.get("failures",["missing"]).is_empty(),"actual_native_facade_checks")
 var origin: Dictionary=load("res://simulation/render_origin_checks.gd").new().run(self)
 var participants: Dictionary=load("res://simulation/origin_participant_checks.gd").new().run(self)
 var fixtures: Dictionary={}
 for kind in ["AircraftSnapshot","AtmosphereSample","ControlCommand","OperationalEvent"]:
  fixtures[kind]=JSON.parse_string(FileAccess.get_file_as_string("res://wire_fixtures/"+kind+".json"))
 var wire: Dictionary=load("res://simulation/wire_validation_checks.gd").run(fixtures)
 check(wire.get("passed",false) and wire.get("checks",0)>0,"full_v1_wire_checks")
 var input: Dictionary=load("res://input_tests/input_checks.gd").run()
 check(input.get("passed",false) and input.get("checks",0)>0 and input.get("failures",["missing"]).is_empty(),"actual_input_mapper_codec_checks")
 var input_scene_failures: int=failures.size()
 var input_scene: Dictionary=await load("res://input_tests/scene_checks.gd").new().run(self)
 check(failures.size()==input_scene_failures and input_scene.has("initial_tick"),"actual_input_scene_checks")
 var instruments: Dictionary=load("res://instrument_tests/instrument_checks.gd").run()
 check(instruments.get("passed",false) and instruments.get("checks",0)>0 and instruments.get("failures",["missing"]).is_empty(),"native_truth_reading_checks")
 var engine_status: Dictionary=load("res://engine_tests/status_checks.gd").new().run()
 check(engine_status.get("passed",false) and engine_status.get("checks",0)>0,"synthetic_engine_status_checks")
 var engine_facade: Dictionary=load("res://engine_tests/facade_checks.gd").new().run(ProjectSettings.globalize_path("res://piston-models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("piston-models"))
 check(engine_facade.get("passed",false) and engine_facade.get("checks",0)>0,"synthetic_engine_intent_checks")
 var engine_input: Dictionary=load("res://engine_tests/input_boundary_checks.gd").new().run()
 check(engine_input.get("passed",false) and engine_input.get("checks",0)>0,"independent_synthetic_piston_input_checks")
 var piston_input: Dictionary=load("res://input_tests/piston_checks.gd").new().run()
 check(piston_input.get("passed",false) and piston_input.get("checks",0)>0,"synthetic_piston_mapper_codec_checks")
 var piston_panel: Dictionary=await load("res://input_tests/piston_panel_checks.gd").new().run(self)
 check(piston_panel.get("passed",false) and piston_panel.get("checks",0)>0,"synthetic_paused_piston_editor_checks")
 var piston_presentation: Dictionary=await load("res://engine_tests/presentation_checks.gd").new().run(self)
 check(piston_presentation.get("passed",false) and piston_presentation.get("checks",0)>0,"synthetic_piston_menu_layout_checks")
 var cockpit_checks: Dictionary={}
 for name in ["adapter","scan","scene"]:
  var prior_failures: int=failures.size()
  var result: Dictionary=await load("res://instrument_tests/"+name+"_checks.gd").new().run(self)
  check(failures.size()==prior_failures and result.get("passed",false) and result.get("checks",0)>0 and result.get("failures",["missing"]).is_empty(),"actual_cockpit_"+name+"_checks")
  cockpit_checks[name]=result
 var scene: Dictionary=await load("res://sim_loop_tests/scene_checks.gd").new().run(self)
 var report: Dictionary={"schema_version":1,"scope":"Headless actual-native facade and synthetic wire/render fixtures; GPU and pilot qualification separate","passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"facade":facade,"origin":origin,"participants":participants,"wire":wire,"scene":scene,"input":input,"input_scene":input_scene,"instruments":instruments,"cockpit":cockpit_checks,"synthetic_engine_status":engine_status,"synthetic_engine_facade":engine_facade,"independent_piston_input":engine_input,"synthetic_piston_input":piston_input,"synthetic_piston_panel":piston_panel,"synthetic_piston_presentation":piston_presentation}
 var output: String=ProjectSettings.globalize_path("res://facade-check-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("facade-check-receipt.json")
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--facade-receipt="): output=argument.trim_prefix("--facade-receipt=")
 var file=FileAccess.open(output,FileAccess.WRITE)
 if file==null:
  push_error("Simulation check receipt cannot be saved")
  get_tree().quit(1)
  return
 file.store_string(JSON.stringify(report,"  "))
 file.close()
 print("SIM_LOOP_CHECKS_PASSED" if report.passed else "SIM_LOOP_CHECKS_FAILED")
 await get_tree().process_frame
 await get_tree().process_frame
 get_tree().quit(0 if report.passed else 1)
"@)
 [IO.File]::WriteAllText((Join-Path $ProjectRoot 'sim_loop_checks.tscn'),"[gd_scene load_steps=2 format=3]`n[ext_resource type=`"Script`" path=`"res://sim_loop_checks.gd`" id=`"1`"]`n[node name=`"SimulationChecks`" type=`"Node`"]`nscript=ExtResource(`"1`")`n")
}
