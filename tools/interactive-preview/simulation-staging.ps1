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
 for folder in ["res://simulation","res://sim_loop_tests","res://interactive"]:
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
 var scene: Dictionary=await load("res://sim_loop_tests/scene_checks.gd").new().run(self)
 var report: Dictionary={"schema_version":1,"scope":"Headless actual-native facade and synthetic wire/render fixtures; GPU and pilot qualification separate","passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"facade":facade,"origin":origin,"participants":participants,"wire":wire,"scene":scene}
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
