#Requires -Version 7.0
. (Join-Path $PSScriptRoot 'wire-codec-staging.ps1')
. (Join-Path $PSScriptRoot 'camera-staging.ps1')
. (Join-Path $PSScriptRoot 'local-window-replay-staging.ps1')
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
# The flight-only proof carries frontend scripts, never the shipping storage
# registration. Native storage and the 12-role package aggregate are separate.
function Assert-KawoOrdinaryAncestors {
 param([Parameter(Mandatory)][string]$Path)
 $candidate=[IO.Path]::GetFullPath($Path)
 while($true){
  $item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'KAWO staging path contains a reparse point'}
  $parent=[IO.Path]::GetDirectoryName($candidate)
  if([string]::IsNullOrEmpty($parent) -or $parent -ceq $candidate){break}
  $candidate=$parent
 }
}
function Get-KawoRuntimeSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 Assert-KawoOrdinaryAncestors $RepoRoot
 @(
  @{source='app/world';destination='world';selected=$true;required=@('world_admission.gd')},
  @{source='app/world/terrain';destination='world/terrain';selected=$false;required=@('resident_grid_reader.gd','kawo_world.gd')},
  @{source='content/world/catalog';destination='content/world/catalog';selected=$false;required=@('kawo-runtime-v1.json')},
  @{source='content/world/airports/kawo/runtime-v1';destination='worlds/kawo-prototype-v1';selected=$false;required=@('world.json','ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt')}
 )|ForEach-Object {
  $group=$_
  $folder=Join-Path $RepoRoot $group.source
  Assert-KawoOrdinaryAncestors $folder
  $snapshot=@(Get-SimulationSourceSnapshot $folder -RequiredEntries $group.required)
  if($group.selected){
   $snapshot=@($snapshot|Where-Object {$_.path -ceq 'world_admission.gd'})
   if($snapshot.Count -ne 1){throw 'Exact KAWO registry filename is required'}
  }
  else{
   # Exactly the fixed authored roster; generated Godot UIDs are never authoring
   # inputs and are admitted only after import on a staged script sibling.
   $authored=@($snapshot|Where-Object {-not $_.path.EndsWith('.gd.uid')})
   if(($authored.path -join "`n") -cne (($group.required|Sort-Object) -join "`n")){throw 'KAWO authored file roster differs'}
   foreach($entry in $snapshot){
    if($entry.path.EndsWith('.gd.uid') -and -not ($group.required -ccontains $entry.path.Substring(0,$entry.path.Length-4))){throw 'Unbound KAWO UID'}
   }
   $snapshot=$authored
  }
  if($group.destination -ceq 'worlds/kawo-prototype-v1' -and ($snapshot|Measure-Object -Property bytes -Sum).Sum -gt 301989888){throw 'KAWO pack exceeds288MiB'}
  [pscustomobject]@{source=$group.source;destination=$group.destination;selected=$group.selected;required=$group.required;snapshot=$snapshot}
 }
}
function Assert-KawoRuntimeSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 Assert-KawoOrdinaryAncestors $Root
 foreach($group in $Groups){
  $folder=Join-Path $Root $(if($Authoring){$group.source}else{$group.destination})
  Assert-KawoOrdinaryAncestors $folder
  if($group.selected){
   foreach($entry in $group.snapshot){
    $file=Join-Path $folder $entry.path
    Assert-KawoOrdinaryAncestors $file
    $item=Get-Item -LiteralPath $file -Force
    if($item.PSIsContainer -or $item.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256){throw 'KAWO selected registry bytes changed'}
   }
  }else{Assert-SimulationSourceSnapshot $folder $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:($AllowGeneratedUIDs -or $Authoring)}
 }
}
function Copy-KawoRuntimeSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-KawoRuntimeSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 Assert-KawoOrdinaryAncestors $DestinationRoot
 foreach($group in $Groups){
  $destination=Join-Path $DestinationRoot $group.destination
  if(-not $group.selected -and (Test-Path -LiteralPath $destination)){throw 'KAWO staging group must be fresh'}
  $ancestor=$destination
  while($null -eq (Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue)){$ancestor=[IO.Path]::GetDirectoryName($ancestor)}
  Assert-KawoOrdinaryAncestors $ancestor
  New-Item -ItemType Directory -Path $destination -Force|Out-Null
  Assert-KawoOrdinaryAncestors $destination
  foreach($entry in $group.snapshot){
   $file=Join-Path $destination $entry.path
   if(Test-Path -LiteralPath $file){throw 'KAWO staging file must be fresh'}
   Copy-Item -LiteralPath (Join-Path $RepoRoot ($group.source+'/'+$entry.path)) -Destination $file
  }
 }
 Assert-KawoRuntimeSourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-KawoRuntimeSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
function Get-LocalPlayerSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/persistence';destination='persistence';required=@('local_players_controller.gd')},
  @{source='app/ui/profiles';destination='ui/profiles';required=@('player_options.gd','players_panel.gd','player_name_panel.gd')},
  @{source='app/ui/history';destination='ui/history';required=@('practice_panel.gd','practice_details.gd','player_export_panel.gd','recovery_panel.gd')},
  @{source='tests/ui/profiles';destination='player_tests';required=@('local_players_ui_checks.gd','local_players_controller_checks.gd','local_players_ui_checks_runner.gd','local_players_scene_checks.gd','local_players_journey_checks.gd','local_players_journey_runner.gd','local_players_journey_first.gd','local_players_journey_resume.gd','local_players_integrated_checks.gd','local_players_integrated_runner.gd')}
 )|ForEach-Object {
  $_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required)
  if($_.source -ceq 'app/persistence'){$_.snapshot=@($_.snapshot|Where-Object {$_.path -ceq 'local_players_controller.gd'})}
  $_
 }
}
function Assert-LocalPlayerSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){
  $folder=if($Authoring){$group.source}else{$group.destination}
  $path=Join-Path $Root $folder
  if($Authoring -and $group.source -ceq 'app/persistence'){
   $actual=@(Get-SimulationSourceSnapshot $path -RequiredEntries $group.required|Where-Object {$_.path -ceq 'local_players_controller.gd'})
   if($actual.Count -ne $group.snapshot.Count){throw 'Players persistence script set changed'}
   for($i=0;$i -lt $actual.Count;$i++){
    if($actual[$i].path -cne $group.snapshot[$i].path -or $actual[$i].bytes -ne $group.snapshot[$i].bytes -or $actual[$i].sha256 -cne $group.snapshot[$i].sha256){throw 'Players persistence source bytes changed'}
   }
  }else{Assert-SimulationSourceSnapshot $path $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs}
 }
}
function Copy-LocalPlayerSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-LocalPlayerSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 foreach($group in $Groups){
  $destination=Join-Path $DestinationRoot $group.destination
  if(Test-Path -LiteralPath $destination){throw 'Players staging destination must be fresh'}
  New-Item -ItemType Directory -Path $destination -Force|Out-Null
  foreach($file in $group.snapshot){
   $target=Join-Path $destination $file.path
   New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force|Out-Null
   Copy-Item -LiteralPath (Join-Path $RepoRoot ($group.source+'/'+$file.path)) -Destination $target
  }
 }
 Assert-LocalPlayerSourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-LocalPlayerSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
# Input/UI/fixtures use the same exact recursive snapshot and import-only UID policy.
function Get-InputSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/input';destination='input';required=@('input_mapper.gd','input_preset.gd')},
  @{source='app/ui/controls';destination='ui/controls';required=@('controls_panel.gd')},
  @{source='tests/input';destination='input_tests';required=@('input_checks.gd','scene_checks.gd','piston_checks.gd','piston_panel_checks.gd','pointer_engine_checks.gd','reference.json')}
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
  @{source='app/cockpit';destination='cockpit';required=@('instruments/native_readings.gd','instruments/scan_panel.gd','instruments/engine_status.gd','engine_controls.gd','assets/original-cockpit.glb','assets/original_asset.gd')},
  @{source='tests/instruments';destination='instrument_tests';required=@('instrument_checks.gd','adapter_checks.gd','cockpit_geometry_checks.gd','cockpit_visual.gd','scan_checks.gd','scene_checks.gd','hud_caption_checks.gd','engine_status_checks.gd','reference.json','preparation-manifest.json','cockpit_asset_baseline.gd','cockpit_asset_checks.gd','cockpit_asset_visual.gd')},
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
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs,$ImportReceipt=$null)
 if($null -ne $ImportReceipt){
  if($Authoring){throw 'Generated cockpit import records cannot enter authoring source'}
  if($Groups.Count -ne 3 -or $Groups[0].source -cne 'app/cockpit' -or $Groups[0].destination -cne 'cockpit'){throw 'Original closed cockpit runtime groups required'}
  Assert-CockpitImportReceipt -ProjectRoot $DestinationRoot -CockpitGroups $Groups -Receipt $ImportReceipt
 }
 foreach($group in $Groups){
  $path=if($Authoring){$group.source}else{$group.destination}
  $snapshot=@($group.snapshot)
  if($null -ne $ImportReceipt -and $group.source -ceq 'app/cockpit'){
   # Only the five individually bound fixed-resource outputs join this snapshot.
   $snapshot+=@(0..4|ForEach-Object {$file=$ImportReceipt.files[$_];[pscustomobject]@{path=[IO.Path]::GetRelativePath((Join-Path $DestinationRoot 'cockpit'),$file.path).Replace([char]92,[char]47);bytes=$file.bytes;sha256=$file.sha256}})
   $snapshot=@($snapshot|Sort-Object path)
  }
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Get-CockpitImportRecipes {
 @(
  [pscustomobject]@{path='cockpit/assets/original-cockpit.glb.import';text=@'
[remap]

importer="scene"
importer_version=1
type="PackedScene"
path="res://.godot/imported/original-cockpit.glb-382397f0d6316786c39bbefa92a42ce9.scn"

[deps]

source_file="res://cockpit/assets/original-cockpit.glb"
dest_files=["res://.godot/imported/original-cockpit.glb-382397f0d6316786c39bbefa92a42ce9.scn"]

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
'@
  },
  [pscustomobject]@{path='cockpit/assets/original-cockpit_original-surface-albedo.png.import';text=@'
[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/original-cockpit_original-surface-albedo.png-88caf3cdbed4794a12a850ca1e6b1798.ctex"
metadata={
"vram_texture": false
}
generator_parameters={
"md5": ""
}

[deps]

source_file="res://cockpit/assets/original-cockpit_original-surface-albedo.png"
dest_files=["res://.godot/imported/original-cockpit_original-surface-albedo.png-88caf3cdbed4794a12a850ca1e6b1798.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
'@
  },
  [pscustomobject]@{path='cockpit/assets/original-cockpit_original-surface-roughness.png.import';text=@'
[remap]

importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/original-cockpit_original-surface-roughness.png-5b25a9a450515bf31d8a916c2e373bd3.ctex"
metadata={
"vram_texture": false
}
generator_parameters={
"md5": ""
}

[deps]

source_file="res://cockpit/assets/original-cockpit_original-surface-roughness.png"
dest_files=["res://.godot/imported/original-cockpit_original-surface-roughness.png-5b25a9a450515bf31d8a916c2e373bd3.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
'@
  }
 )
}
# Original cockpit import records have one fixed recipe and a closed artifact roster.
# No extension-based exception is added to the generic script UID policy.
function Get-CockpitAuthoringSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $required=@('cockpit-reference-v1.json','generate_cockpit.py','original-cockpit.blend','cockpit-source.json','README.md','textures/original-surface-albedo.png','textures/original-surface-roughness.png')
 $group=@{source='assets_source/c172/original-prototype';destination='assets_source/c172/original-prototype';required=$required}
 $group.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) -RequiredEntries $required)
 if((($group.snapshot.path|Sort-Object) -join "`n") -cne (($required|Sort-Object) -join "`n")){throw 'Exactly seven original cockpit authoring files required'}
 @($group)
}
function Assert-CockpitAuthoringSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups)
 $expected=@('cockpit-reference-v1.json','generate_cockpit.py','original-cockpit.blend','cockpit-source.json','README.md','textures/original-surface-albedo.png','textures/original-surface-roughness.png')
 if(($Groups.Count -ne 1) -or $Groups[0].required -isnot [array] -or $Groups[0].snapshot -isnot [array] -or $Groups[0].snapshot.Count -ne 7 -or $Groups[0].source -cne 'assets_source/c172/original-prototype' -or $Groups[0].destination -cne 'assets_source/c172/original-prototype' -or ($Groups[0].required -join "`n") -cne ($expected -join "`n") -or (($Groups[0].snapshot.path|Sort-Object) -join "`n") -cne (($expected|Sort-Object) -join "`n")){throw 'Closed original cockpit authoring descriptor required'}
 $groupKeys=if($Groups[0] -is [Collections.IDictionary]){@($Groups[0].Keys)}else{@($Groups[0].PSObject.Properties.Name)}
 if((($groupKeys|Sort-Object) -join "`n") -cne "destination`nrequired`nsnapshot`nsource"){throw 'Closed original authoring group keys required'}
 foreach($relative in $expected){Get-CockpitBoundFilePin (Join-Path $Root ($Groups[0].source+'/'+$relative))|Out-Null}
 foreach($row in $Groups[0].snapshot){if((($row.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`npath`nsha256" -or ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -le 0 -or $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Closed nonempty original authoring source pin required'}}
 Assert-SimulationSourceSnapshot (Join-Path $Root $Groups[0].source) $Groups[0].snapshot -RequiredEntries $expected
}
function Copy-CockpitAuthoringSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$CorrespondingSourceRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-CockpitAuthoringSourceGroups $RepoRoot $Groups
 Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $Groups[0].source) (Join-Path $CorrespondingSourceRoot $Groups[0].destination) $Groups[0].snapshot -RequiredEntries $Groups[0].required
 Assert-CockpitAuthoringSourceGroups $CorrespondingSourceRoot $Groups
 Assert-CockpitAuthoringSourceGroups $RepoRoot $Groups
}
function Get-CockpitBoundFilePin {
 param([Parameter(Mandatory)][string]$Path)
 $file=Get-Item -Force -LiteralPath $Path -ErrorAction Stop
 if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.LinkType -eq 'HardLink'){throw 'Cockpit import pin must be an ordinary unaliased file'}
 $parent=$file.Directory
 while($null -ne $parent){if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Cockpit import ancestor is a reparse point'};$parent=$parent.Parent}
 [pscustomobject]@{path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Assert-CockpitBoundFilePin {
 param([Parameter(Mandatory)]$Pin)
 if((($Pin.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`npath`nsha256" -or $Pin.path -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($Pin.path) -or ($Pin.bytes -isnot [long] -and $Pin.bytes -isnot [int]) -or $Pin.bytes -lt 0 -or $Pin.sha256 -isnot [string] -or $Pin.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Closed absolute cockpit import pin required'}
 $actual=Get-CockpitBoundFilePin $Pin.path
 if($actual.path -cne $Pin.path -or $actual.bytes -ne $Pin.bytes -or $actual.sha256 -cne $Pin.sha256){throw 'Cockpit import input, producer or output bytes drifted'}
}
function Read-CockpitImportMap {
 param([Parameter(Mandatory)][string]$Text)
 if($Text.Length -gt 65536){throw 'Cockpit import metadata exceeds fixed bound'}
 $map=@{};$sections=@();$section='';$pending='';$key=''
 foreach($line in ($Text -split '\r?\n')){
  if($line.Length -eq 0){continue}
  if($pending){
   $pending+=$line
   if($line -ceq '}'){$map[$key]=$pending;$pending=''}
   continue
  }
  if($line -cmatch '^\[(remap|deps|params)\]$'){if($sections -ccontains $Matches[1]){throw 'Duplicate cockpit import section'};$section=$Matches[1];$sections+=$section;continue}
  if(-not $section -or $line -cnotmatch '^([A-Za-z0-9_/]+)=(.*)$'){throw 'Closed cockpit import syntax required'}
  $key=$section+'/'+$Matches[1];$value=$Matches[2]
  if($map.ContainsKey($key)){throw 'Duplicate cockpit import key'}
  if($value -ceq '{'){$pending='{'}else{$map[$key]=$value}
 }
 if($pending -or -not $map.Count){throw 'Truncated cockpit import metadata'}
 $map
}
function Assert-CockpitImportMap {
 param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)]$Recipe)
 $expected=Read-CockpitImportMap $Recipe.text;$actual=Read-CockpitImportMap $Text
 $keys=@($expected.Keys)+@('remap/uid')
 if((($actual.Keys|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n")){throw 'Cockpit import metadata keys differ from fixed recipe'}
 foreach($key in $expected.Keys){
  if($key -ceq 'remap/generator_parameters'){
   if($actual[$key] -cnotmatch '^\{"md5": "[0-9a-f]{32}"\}$'){throw 'Actual GLB-owned texture generator identity required'}
  }elseif($actual[$key] -cne $expected[$key]){throw "Cockpit import recipe changed: $key"}
 }
 if($actual['remap/uid'] -cnotmatch '^"uid://[a-z0-9]{1,20}"$'){throw 'Actual generated cockpit resource UID required'}
}
function Get-CockpitImportArtifactPaths {
 @(
  'cockpit/assets/original-cockpit.glb.import',
  'cockpit/assets/original-cockpit_original-surface-albedo.png',
  'cockpit/assets/original-cockpit_original-surface-albedo.png.import',
  'cockpit/assets/original-cockpit_original-surface-roughness.png',
  'cockpit/assets/original-cockpit_original-surface-roughness.png.import',
  '.godot/imported/original-cockpit.glb-382397f0d6316786c39bbefa92a42ce9.scn',
  '.godot/imported/original-cockpit.glb-382397f0d6316786c39bbefa92a42ce9.md5',
  '.godot/imported/original-cockpit_original-surface-albedo.png-88caf3cdbed4794a12a850ca1e6b1798.ctex',
  '.godot/imported/original-cockpit_original-surface-albedo.png-88caf3cdbed4794a12a850ca1e6b1798.md5',
  '.godot/imported/original-cockpit_original-surface-roughness.png-5b25a9a450515bf31d8a916c2e373bd3.ctex',
  '.godot/imported/original-cockpit_original-surface-roughness.png-5b25a9a450515bf31d8a916c2e373bd3.md5'
 )
}
function Set-CockpitImportRecipe {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][object[]]$CockpitGroups)
 Assert-CockpitSourceGroups $ProjectRoot $CockpitGroups
 foreach($path in Get-CockpitImportArtifactPaths){if(Test-Path -LiteralPath (Join-Path $ProjectRoot $path)){throw 'Cockpit import recipe requires fresh original resource artifacts'}}
 foreach($recipe in Get-CockpitImportRecipes){[IO.File]::WriteAllText((Join-Path $ProjectRoot $recipe.path),$recipe.text,[Text.UTF8Encoding]::new($false))}
}
function Assert-CockpitImportProducer {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Producer)
 if((($Producer.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "arguments`nexecutable`nexit_code`nlog" -or ($Producer.exit_code -isnot [int] -and $Producer.exit_code -isnot [long]) -or $Producer.exit_code -ne 0 -or $Producer.arguments -isnot [array]){throw 'Actual completed pinned cockpit editor import required'}
 Assert-CockpitBoundFilePin $Producer.executable;Assert-CockpitBoundFilePin $Producer.log
 $windowsProducer=$Producer.executable.bytes -eq 198152 -and $Producer.executable.sha256 -ceq 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
 # Linux hash is the exact bootstrap-qualified 4.7.2 executable from hosted evidence.
 # The actual ordinary-file length remains recorded; no unobserved size is invented.
 $linuxProducer=$Producer.executable.bytes -gt 0 -and $Producer.executable.bytes -le 512MB -and $Producer.executable.sha256 -ceq '8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e'
 if(-not ($windowsProducer -or $linuxProducer)){throw 'Existing pinned Godot 4.7.2 Windows console or Linux producer required'}
 $expected=@('--headless','--path',$ProjectRoot,'--editor','--quit-after','120','--frame-delay','100')
 if(($Producer.arguments -join "`n") -cne ($expected -join "`n")){throw 'Actual cockpit import arguments differ from fixed editor producer'}
 $log=[IO.File]::ReadAllText($Producer.log.path)
 if($log -notmatch 'Godot Engine v4\.7\.2\.stable' -or $log -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed'){throw 'Pinned actual cockpit import did not finish cleanly'}
}
function Get-CockpitImportReceipt {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][object[]]$CockpitGroups,[Parameter(Mandatory)][object[]]$AuthoringGroups,[Parameter(Mandatory)]$Producer)
 Assert-CockpitImportProducer $ProjectRoot $Producer
 Assert-CockpitAuthoringSourceGroups $RepoRoot $AuthoringGroups
 $glb=@($CockpitGroups[0].snapshot|Where-Object path -CEQ 'assets/original-cockpit.glb')
 if($glb.Count -ne 1){throw 'Actual bound original GLB input required'}
 $input=Get-CockpitBoundFilePin ([IO.Path]::GetFullPath((Join-Path $ProjectRoot 'cockpit/assets/original-cockpit.glb')))
 if($input.bytes -ne $glb[0].bytes -or $input.sha256 -cne $glb[0].sha256){throw 'Imported cockpit GLB input drifted'}
 foreach($recipe in Get-CockpitImportRecipes){Assert-CockpitImportMap ([IO.File]::ReadAllText((Join-Path $ProjectRoot $recipe.path))) $recipe}
 $tiles=@()
 foreach($name in @('albedo','roughness')){
  $source=@($AuthoringGroups[0].snapshot|Where-Object path -CEQ ('textures/original-surface-'+$name+'.png'))
  $generated=Get-CockpitBoundFilePin (Join-Path $ProjectRoot ('cockpit/assets/original-cockpit_original-surface-'+$name+'.png'))
  if($source.Count -ne 1 -or $generated.bytes -ne $source[0].bytes -or $generated.sha256 -cne $source[0].sha256){throw 'Actual extracted texture is not the exact bound original PNG'}
  $tiles+=[pscustomobject]@{source=$source[0];generated=$generated}
 }
 $artifacts=@(Get-CockpitImportArtifactPaths|ForEach-Object {Get-CockpitBoundFilePin (Join-Path $ProjectRoot $_)})
 [pscustomobject]@{schema_version=1;kind='original-cockpit-import-artifacts';project_root=$ProjectRoot;authoring_root=$RepoRoot;authoring_groups=$AuthoringGroups;producer=$Producer;input_glb=$input;input_tiles=$tiles;files=$artifacts;scope='Actual pinned editor producer and fixed import artifacts only; real geometry/RGBA8/full-mips/material/runtime/pixel checks remain required.'}
}
function Assert-CockpitImportReceipt {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][object[]]$CockpitGroups,[Parameter(Mandatory)]$Receipt)
 $keys=@('schema_version','kind','project_root','authoring_root','authoring_groups','producer','input_glb','input_tiles','files','scope')
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n") -or ($Receipt.schema_version -isnot [int] -and $Receipt.schema_version -isnot [long]) -or $Receipt.schema_version -ne 1 -or $Receipt.kind -cne 'original-cockpit-import-artifacts' -or $Receipt.project_root -cne $ProjectRoot -or $Receipt.files -isnot [array] -or $Receipt.input_tiles -isnot [array] -or $Receipt.input_tiles.Count -ne 2 -or $Receipt.authoring_groups -isnot [array] -or $Receipt.authoring_root -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($Receipt.authoring_root) -or $Receipt.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.scope) -or $Receipt.scope.Length -gt 1024){throw 'Closed actual cockpit import receipt required'}
 Assert-CockpitImportProducer $ProjectRoot $Receipt.producer;Assert-CockpitBoundFilePin $Receipt.input_glb
 Assert-CockpitAuthoringSourceGroups $Receipt.authoring_root $Receipt.authoring_groups
 $glb=@($CockpitGroups[0].snapshot|Where-Object path -CEQ 'assets/original-cockpit.glb')
 if($glb.Count -ne 1 -or $Receipt.input_glb.path -cne ([IO.Path]::GetFullPath((Join-Path $ProjectRoot 'cockpit/assets/original-cockpit.glb'))) -or $Receipt.input_glb.bytes -ne $glb[0].bytes -or $Receipt.input_glb.sha256 -cne $glb[0].sha256){throw 'Receipt original GLB input no longer bound'}
 $paths=@(Get-CockpitImportArtifactPaths|ForEach-Object {[IO.Path]::GetFullPath((Join-Path $ProjectRoot $_))})
 if(($Receipt.files.path -join "`n") -cne ($paths -join "`n")){throw 'Exact ordered eleven cockpit import artifacts required'}
 foreach($file in $Receipt.files){Assert-CockpitBoundFilePin $file}
 foreach($recipe in Get-CockpitImportRecipes){Assert-CockpitImportMap ([IO.File]::ReadAllText((Join-Path $ProjectRoot $recipe.path))) $recipe}
 for($i=0;$i -lt 2;$i++){
  $tile=$Receipt.input_tiles[$i];$name=@('albedo','roughness')[$i]
  $bound=@($Receipt.authoring_groups[0].snapshot|Where-Object path -CEQ ('textures/original-surface-'+$name+'.png'))
  if($bound.Count -ne 1 -or (($tile.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "generated`nsource" -or (($tile.source.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`npath`nsha256" -or ($tile.source.bytes -isnot [int] -and $tile.source.bytes -isnot [long]) -or $tile.source.sha256 -isnot [string] -or $tile.source.bytes -cne $bound[0].bytes -or $tile.source.sha256 -cne $bound[0].sha256 -or $tile.source.path -cne ('textures/original-surface-'+$name+'.png') -or $tile.generated.path -cne [IO.Path]::GetFullPath((Join-Path $ProjectRoot ('cockpit/assets/original-cockpit_original-surface-'+$name+'.png'))) -or $tile.source.bytes -ne $tile.generated.bytes -or $tile.source.sha256 -cne $tile.generated.sha256){throw 'Exact original source/generated texture correspondence required'}
  Assert-CockpitBoundFilePin $tile.generated
 }
}

# Session-local landmark UI and frozen geometry use the same exact source policy.
function Get-FreeflightSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/ui/freeflight';destination='ui/freeflight';required=@('landmark_board.gd')},
  @{source='tests/ui/freeflight';destination='freeflight_tests';required=@('landmark_checks.gd','scene_checks.gd','reference.json','reference-generator.py')}
 )|ForEach-Object {$_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required);$_}
}
function Copy-FreeflightSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-FreeflightSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){$path=if($Authoring){$group.source}else{$group.destination};Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs}
}
# Recorded observations, view-only UI and independently frozen fixtures are
# mandatory exact recursive groups in editor, export and corresponding source.
function Get-WindSourceDefinitions {
 @(
  @{source='app/world/wind';destination='world/wind';required=@('wind_cue.gd')},
  @{source='app/ui/wind';destination='ui/wind';required=@('panel.gd')},
  @{source='tests/world/wind';destination='wind_tests';required=@('wind_checks.gd','ratification-v1.json','reference/expected-v1.json','reference/generate.py','reference/manifest-v1.json','reference/NOTICE-MIT.txt')},
  @{source='tests/integration/wind';destination='wind_scene_tests';required=@('scene_checks.gd','visual_checks.gd')}
 )
}
function Get-WindSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 Get-WindSourceDefinitions | ForEach-Object {$_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required);$_}
}
function Assert-WindSourceDescriptors {
 param([Parameter(Mandatory)][object[]]$Groups)
 $definitions=@(Get-WindSourceDefinitions)
 if($Groups.Count -ne $definitions.Count){throw 'All four wind source groups are mandatory'}
 $seen=@()
 foreach($group in $Groups){
  if($group.source -isnot [string] -or $group.destination -isnot [string] -or $group.required -isnot [array] -or $group.snapshot -isnot [array] -or $group.required.Count -eq 0 -or $group.snapshot.Count -eq 0){throw 'Wind source groups must have nonempty snapshots and required entrypoints'}
  $matching=@($definitions|Where-Object {$_.source -ceq $group.source})
  if($matching.Count -ne 1 -or $seen -ccontains $group.source){throw 'Wind source group roster unknown or duplicated'}
  $definition=$matching[0]
  if($group.destination -cne $definition.destination -or ($group.required -join "`n") -cne ($definition.required -join "`n")){throw 'Wind source group destination/entrypoints differ from closed roster'}
  $seen+=$group.source
 }
}
function Copy-WindSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-WindSourceDescriptors -Groups $Groups
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-WindSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 Assert-WindSourceDescriptors -Groups $Groups
 foreach($group in $Groups){$path=if($Authoring){$group.source}else{$group.destination};Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs}
}
function Assert-WindReferences {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Python)
 $binding=Get-Content (Join-Path $RepoRoot 'tests/world/wind/ratification-v1.json') -Raw | ConvertFrom-Json
 if($binding.status -cne 'ratified-before-consumer-and-backend-observations' -or $binding.accepted_contract_sha256 -cne '64548f1c876f77d635bd116710fcd5ca44d27e436b8b6b105d0c66406ea20e8f' -or $binding.accepted_contract_merge -cne '265a604257292728a47e38f744aa396e09b2ab58' -or $binding.original_ratification_sha256 -cne 'd00105f6bf7e1214bef4bfcf7e00a07e95726880fe99f73ebfacd9a9c123b6fe'){throw 'Accepted wind ratification required'}
 # Fixed accepted LF-byte roster: metadata cannot omit or replace a generator
 # pin and thereby authorize executing changed reference-generation code.
 $frozen=@(
  @{path='reference/expected-v1.json';bytes=71446;sha256='7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3'},
  @{path='reference/generate.py';bytes=9621;sha256='6a66257c468846caab502e1b7681c16ad00a09e5380d95266c082ab0ff5c263c'},
  @{path='reference/manifest-v1.json';bytes=1848;sha256='a0391a9b0535c6910a9acdfb5d0b2082d5ef9db8e46676e98967b79c772e03b2'},
  @{path='reference/NOTICE-MIT.txt';bytes=1092;sha256='2cc02afe02dd0ffa0ca25e51b8a1fb2fe4a9f0adb95bf768031abd24c8da9c16'},
  @{path='reference/preparation-receipt.json';bytes=1876;sha256='be841b0d8cbebbc02dfd20af155b1f0ed8af2e65988d562e9df48f2c6aecedd7'},
  @{path='reference/README.md';bytes=2650;sha256='815b2dcbacaa6ef886bfacef593b90e41a4087a04d86277914b797d84b32b048'}
 )
 if($binding.published_files -isnot [array] -or $binding.published_files.Count -ne $frozen.Count){throw 'Frozen wind reference roster incomplete'}
 for($i=0;$i -lt $frozen.Count;$i++){
  $file=$binding.published_files[$i];$pin=$frozen[$i]
  if((($file.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`npath`nsha256" -or $file.path -isnot [string] -or $file.path -cne $pin.path -or ($file.bytes -isnot [long] -and $file.bytes -isnot [int]) -or $file.bytes -ne $pin.bytes -or $file.sha256 -isnot [string] -or $file.sha256 -cne $pin.sha256){throw 'Frozen wind reference roster differs from accepted pins'}
  $path=Join-Path $RepoRoot ('tests/world/wind/'+$pin.path)
  $actual=Get-Item -LiteralPath $path -ErrorAction Stop
  if($actual.PSIsContainer -or ($actual.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $actual.Length -ne $pin.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $pin.sha256){throw 'Frozen wind reference bytes changed'}
 }
 & $Python (Join-Path $RepoRoot 'tests/world/wind/reference/generate.py') --check
 if($LASTEXITCODE -ne 0){throw 'Independent wind reference reproduction rejected'}
}
function Get-ObservedReviewSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(
  @{source='app/replay/observed';destination='replay/observed';required=@('recorder.gd','review.gd','tick_math.gd','values.gd')},
  @{source='app/ui/debrief/observed';destination='ui/debrief/observed';required=@('panel.gd')},
  @{source='tests/debrief/observed';destination='observed_tests';required=@('recorder_checks.gd','scene_checks.gd','piston_checks.gd','piston_panel_checks.gd','piston_scene_checks.gd','expected-v1.json','generate.py','preparation-binding-v2.json','root-ratification-v1.json','README.md','.gitattributes')},
  @{source='app/replay/observed_archive';destination='replay/observed_archive';required=@('codec.gd','strict_json.gd','files.gd','windows_io.ps1')},
  @{source='tests/debrief/observed_archive';destination='observed_archive_tests';required=@('archive_checks.gd','file_checks.gd','scene_checks.gd','visual_checks.gd','piston_checks.gd','windows_fixture.ps1','generate.py','source-binding-v1.json','root-ratification-v1.json','README.md','.gitattributes','reference/expected-text-v1.json','reference/expected-binary64-v1.json','reference/piston-small.fsreview.json')}
 )|ForEach-Object {$_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required);$_}
}
function Copy-ObservedReviewSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 if($Groups.Count -ne 5){throw 'All five observed review/archive source groups are mandatory'}
 foreach($group in $Groups){
  if($group.snapshot.Count -le 0 -or $group.required.Count -le 0){throw 'Observed source group snapshots and entrypoints cannot be empty'}
  Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required
 }
}
function Assert-ObservedReviewSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 if($Groups.Count -ne 5){throw 'All five observed review/archive source groups are mandatory'}
 foreach($group in $Groups){
  if($group.snapshot.Count -le 0 -or $group.required.Count -le 0){throw 'Observed source group snapshots and entrypoints cannot be empty'}
  $path=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Assert-ObservedReviewReferences {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Python)
 # Execute only packet(), never the generator's write-if-missing main path.
 $generator=Join-Path $RepoRoot 'tests/debrief/observed/generate.py'
 $expected=Join-Path $RepoRoot 'tests/debrief/observed/expected-v1.json'
 $script=@'
import hashlib,json,runpy,sys
from pathlib import Path
generator,expected=map(Path,sys.argv[1:])
assert expected.is_file(), 'Mandatory frozen observed fixture missing'
encoded=(json.dumps(runpy.run_path(str(generator))['packet'](),indent=2,ensure_ascii=True)+'\n').encode('utf-8')
assert expected.read_bytes()==encoded, 'Frozen observed fixture drift'
assert hashlib.sha256(encoded).hexdigest()=='a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844', 'Frozen observed identity drift'
print('PASS readonly observed reference regeneration:42 cases')
'@
 & $Python -c $script $generator $expected
 if($LASTEXITCODE -ne 0){throw 'Readonly observed reference regeneration rejected'}
}
# ADR020 audio is always delivered, including upstream-native legacy exports.
function Get-AudioSourceDefinitions {
 @(
  @{source='app/audio';destination='audio';required=@('audio_cues.gd','audio_options.gd','sample_renderer.gd')},
  @{source='app/ui/audio';destination='ui/audio';required=@('audio_panel.gd')},
  @{source='tests/audio';destination='audio_tests';required=@('audio_cues_checks.gd','audio_options_checks.gd','audio_panel_checks.gd','sample_renderer_checks.gd')}
 )
}
function Assert-AudioSourceDescriptors {
 param([Parameter(Mandatory)][object[]]$Groups)
 $definitions=@(Get-AudioSourceDefinitions)
 if($Groups.Count -ne 3){throw 'All three audio source groups are mandatory'}
 $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($group in $Groups){
  $keys=if($group -is [System.Collections.IDictionary]){@($group.Keys)}else{@($group.PSObject.Properties.Name)}
  if((($keys|Sort-Object) -join "`n") -cne "destination`nrequired`nsnapshot`nsource" -or $group.source -isnot [string] -or $group.destination -isnot [string] -or $group.required -isnot [array] -or $group.snapshot -isnot [array]){throw 'Audio source descriptor closed shape rejected'}
  $matching=@($definitions|Where-Object {$_.source -ceq $group.source})
  if($matching.Count -ne 1 -or -not $seen.Add($group.source)){throw 'Audio source group unknown or duplicated'}
  $definition=$matching[0]
  if($group.destination -cne $definition.destination -or ($group.required -join "`n") -cne ($definition.required -join "`n")){throw 'Audio source destination/entrypoints differ'}
  if($group.snapshot.Count -ne $definition.required.Count -or ($group.snapshot.path -join "`n") -cne (($definition.required|Sort-Object) -join "`n")){throw 'Audio recursive source roster must be exact'}
  foreach($file in $group.snapshot){
   if((($file.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`npath`nsha256" -or $file.path -isnot [string] -or ($file.bytes -isnot [long] -and $file.bytes -isnot [int]) -or $file.bytes -lt 0 -or $file.bytes -gt 9007199254740991 -or $file.sha256 -isnot [string] -or $file.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Audio source snapshot pin rejected'}
  }
 }
}
function Get-AudioSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $groups=@(Get-AudioSourceDefinitions|ForEach-Object {$_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required);$_})
 Assert-AudioSourceDescriptors -Groups $groups
 $groups
}
function Copy-AudioSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-AudioSourceDescriptors -Groups $Groups
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-AudioSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 Assert-AudioSourceDescriptors -Groups $Groups
 foreach($group in $Groups){
  $folder=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $folder) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Assert-PreviewAudioReceipt {
 param([Parameter(Mandatory)]$Receipt)
 if($Receipt -isnot [pscustomobject] -or (($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "cues`nlifecycle`noptions`npanel`nrenderer"){throw 'All five audio check groups are mandatory'}
 $total=[long]0
 foreach($name in @('cues','options','renderer','panel','lifecycle')){
  $item=$Receipt.$name
  $keys=@('passed','checks','failures');if($name -eq 'panel'){$keys+='scope'}
  if($item -isnot [pscustomobject] -or (($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n")){throw "Audio $name result closed shape rejected"}
  if($item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.checks -gt 9007199254740991 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0){throw "Audio $name checks missing, vacuous or failed"}
  if($name -eq 'panel' -and ($item.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($item.scope) -or $item.scope.Length -gt 1024)){throw 'Bounded audio panel scope required'}
  $total+=$item.checks
  if($total -gt 9007199254740991){throw 'Audio check total exceeds safe integer range'}
 }
}
function Assert-PreviewFacadeReceipt {
 param([Parameter(Mandatory)]$Receipt,[bool]$IncludePiston=$true,[string]$ExpectedSourceFingerprint='')
 $keys=@('schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind','first_flight','audio')
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n")){throw 'Facade receipt exact shape rejected'}
 if(($Receipt.schema_version -isnot [long] -and $Receipt.schema_version -isnot [int]) -or $Receipt.schema_version -ne 1 -or $Receipt.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.scope) -or $Receipt.scope.Length -gt 1024 -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [long] -and $Receipt.checks -isnot [int]) -or $Receipt.checks -le 0 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0){throw 'Facade receipt must contain actual passing checks'}
 Assert-PreviewAudioReceipt -Receipt $Receipt.audio
 if((($Receipt.cockpit.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "adapter`nasset`nhud_caption`nscan`nscene"){throw 'All five cockpit test groups are mandatory'}
 $asset=$Receipt.cockpit.asset
 if($null -eq $asset -or (($asset.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "baseline_sha256`nchecks`nfailures`npassed`nschema`nscope"){throw 'Mandatory closed actual imported cockpit result required'}
 if($asset.schema -isnot [string] -or $asset.schema -cne 'OriginalCockpitActualImportChecks/v1' -or $asset.baseline_sha256 -isnot [string] -or $asset.baseline_sha256 -cne 'fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba' -or $asset.passed -isnot [bool] -or -not $asset.passed -or ($asset.checks -isnot [long] -and $asset.checks -isnot [int]) -or $asset.checks -le 0 -or $asset.checks -gt 9007199254740991 -or $asset.failures -isnot [array] -or $asset.failures.Count -ne 0 -or $asset.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($asset.scope) -or $asset.scope.Length -gt 1024){throw 'Actual original baseline geometry/material/RGBA8/full-mips checks required'}
 $hud=$Receipt.cockpit.hud_caption
 if($null -eq $hud -or (($hud.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "checks`nfailures`npassed`nscope"){throw 'Mandatory closed HUD-caption result required'}
 if($hud.passed -isnot [bool] -or -not $hud.passed -or ($hud.checks -isnot [long] -and $hud.checks -isnot [int]) -or $hud.checks -le 0 -or $hud.checks -gt 9007199254740991 -or $hud.failures -isnot [array] -or $hud.failures.Count -ne 0 -or $hud.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($hud.scope) -or $hud.scope.Length -gt 1024){throw 'Actual passing HUD-caption checks required'}
 if((($Receipt.first_flight.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bindings`nbriefing`ncard`ngeometry`nmap`nscene"){throw 'All six first-flight test groups are mandatory'}
 # Match the package validator: selected-source groups and lifecycle evidence
 # are closed, typed and nonvacuous on upstream CI as well as the coupled route.
 $firstFlightTotal=[long]0
 foreach($name in @('briefing','bindings','geometry','card','map','scene')){
  $item=$Receipt.first_flight.$name
  $diagnostic=if(@($item.PSObject.Properties.Name) -ccontains 'scope'){'scope'}else{'limits'}
  $childKeys=@('passed','checks','failures',$diagnostic)
  if($name -eq 'geometry'){$childKeys+=@('fixture_sha256','captured_readback_sha256','baseline_origin','baseline_source_fingerprint')}
  if($name -eq 'scene'){$childKeys+=@('adoptions','include_piston','route_scope')}
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($childKeys|Sort-Object) -join "`n")){throw "First-flight $name exact shape rejected"}
  if($item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.checks -gt 9007199254740991 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0){throw "First-flight $name checks missing, vacuous or failed"}
  $firstFlightTotal+=$item.checks
  if($firstFlightTotal -gt 9007199254740991){throw 'First-flight check total exceeds safe integer range'}
  $description=$item.$diagnostic
  if($description -isnot [string] -or [string]::IsNullOrWhiteSpace($description) -or $description.Length -gt 1024){throw "First-flight $name evidence scope missing or malformed"}
 }
 if($Receipt.first_flight.geometry.fixture_sha256 -cne '2a4540d99d4500e326a1b1f0673583bd6f8ea99d430b991fcca1130befbbddcc' -or $Receipt.first_flight.geometry.captured_readback_sha256 -cne '58b1a7b0ec46161357c1268dbaeeaab27f84bbbd4de70def35571fd45ddb67f9'){throw 'First-flight frozen fixture/source identity rejected'}
 $baseline=$Receipt.first_flight.geometry
 $origin=if($ExpectedSourceFingerprint -ceq '5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5'){'saved-capture'}else{'observed-native'}
 if($ExpectedSourceFingerprint -cnotmatch '^[0-9a-f]{64}$' -or $baseline.baseline_origin -cne $origin -or $baseline.baseline_source_fingerprint -cne $ExpectedSourceFingerprint){throw 'First-flight actual selected native baseline binding rejected'}
 $scene=$Receipt.first_flight.scene
 $routeScope=if($IncludePiston){'coupled: all six same/cross-profile choices and three advanced confirmations'}else{'upstream: four legacy start mappings, two advanced confirmations and explicit cold admission rejection; cold runtime is not qualified'}
 if($scene.include_piston -isnot [bool] -or $scene.include_piston -ne $IncludePiston -or $scene.route_scope -isnot [string] -or $scene.route_scope -cne $routeScope){throw 'First-flight selected-source mode or route coverage rejected'}
 $choices=@(
  @{id='cold-familiarization';start='piston-cold-ground';profile=@{id='original-piston-prop-v1';version='0.1.0-prototype';backend_model='original-piston-prop'}},
  @{id='ready-flight';start='ground-ready';profile=@{id='original-interactive-prototype';version='0.1.0-prototype';backend_model='original-interactive'}},
  @{id='airborne-orientation';start='airborne-prepared';profile=@{id='original-interactive-prototype';version='0.1.0-prototype';backend_model='original-interactive'}}
 )
 $selected=if($IncludePiston){$choices}else{@($choices[1],$choices[2])}
 $oldSources=if($IncludePiston){@(@{profile='original-interactive-prototype';start='ground-ready'},@{profile='original-piston-prop-v1';start='piston-cold-ground'})}else{@(@{profile='original-interactive-prototype';start='ground-ready'},@{profile='original-interactive-prototype';start='airborne-prepared'})}
 $expected=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 foreach($old in $oldSources){foreach($choice in $selected){$expected.Add(('immediate_'+$old.profile+'_'+$old.start+'_'+$choice.id),$choice)}}
 foreach($choice in $selected){$expected.Add(('confirmed_'+$choice.id),$choice)}
 $expected.Add('joined_failure_explicit_recovery',$choices[1])
 if($scene.adoptions -isnot [array] -or $scene.adoptions.Count -ne $expected.Count){throw 'All actual first-flight adoptions required'}
 $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($row in $scene.adoptions){
  $rowKeys=@('label','model_identity','start','tick','pause_attempts','native_calls','completed')
  if((($row.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($rowKeys|Sort-Object) -join "`n")){throw 'First-flight adoption exact shape rejected'}
  if($row.label -isnot [string] -or -not $expected.ContainsKey($row.label) -or -not $seen.Add($row.label)){throw 'Missing, unknown or duplicate first-flight mapping'}
  $choice=$expected[$row.label]
  if((($row.model_identity.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "backend_model`nid`nversion"){throw 'First-flight complete profile shape rejected'}
  foreach($key in @('id','version','backend_model')){if($row.model_identity.$key -isnot [string] -or $row.model_identity.$key -cne $choice.profile[$key]){throw 'Exact adopted first-flight profile rejected'}}
  if($row.start -isnot [string] -or $row.start -cne $choice.start -or $row.tick -isnot [string] -or $row.tick -cne '0'){throw 'First-flight adopted start or paused tick0 rejected'}
  if($row.pause_attempts -isnot [array] -or $row.pause_attempts.Count -le 0 -or $row.pause_attempts.Count -gt 128){throw 'First-flight pause attempts must be nonempty and bounded'}
  foreach($paused in $row.pause_attempts){if($paused -isnot [bool] -or -not $paused){throw 'No hidden first-flight Resume is allowed'}}
  if(($row.native_calls -isnot [long] -and $row.native_calls -isnot [int]) -or $row.native_calls -le 0 -or $row.native_calls -gt 9007199254740991 -or ($row.completed -isnot [long] -and $row.completed -isnot [int]) -or $row.completed -ne 0){throw 'First-flight native calls or completed count rejected'}
 }
 if((($Receipt.observed.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "piston`nrecorder`nscene"){throw 'Observed recorder, scene and piston results are mandatory'}
 Assert-ObservedPistonReceipt $Receipt.observed.piston
 foreach($name in @('recorder','scene')){
  $item=$Receipt.observed.$name
  $names=if($name -eq 'recorder'){@('passed','checks','failures','reference_cases','reference_sha256','scope')}else{@('passed','checks','failures','scope')}
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($names|Sort-Object) -join "`n")){throw "Observed $name receipt shape rejected"}
  if($item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0 -or $item.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($item.scope) -or $item.scope.Length -gt 1024){throw "Observed $name checks did not execute successfully"}
 }
 if(($Receipt.observed.recorder.reference_cases -isnot [long] -and $Receipt.observed.recorder.reference_cases -isnot [int]) -or $Receipt.observed.recorder.reference_cases -ne 42 -or $Receipt.observed.recorder.reference_sha256 -isnot [string] -or $Receipt.observed.recorder.reference_sha256 -cne 'a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844'){throw 'Observed frozen reference receipt identity rejected'}
 if((($Receipt.observed_archive.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "codec`nfiles`nscene"){throw 'All archive codec/files/scene results are mandatory'}
 foreach($name in @('codec','files','scene')){
  $item=$Receipt.observed_archive.$name
  $names=@('passed','checks','failures','scope')
  if($name -eq 'codec'){$names+=@('reference_cases','reference_sha256','binary64_cases','binary64_sha256')}
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($names|Sort-Object) -join "`n")){throw "Archive $name receipt exact shape rejected"}
  if($item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0 -or $item.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($item.scope) -or $item.scope.Length -gt 1024){throw "Archive $name checks missing, vacuous or failed"}
 }
 $codec=$Receipt.observed_archive.codec
 foreach($count in @(@{key='reference_cases';value=40},@{key='binary64_cases';value=26})){
  if(($codec.($count.key) -isnot [long] -and $codec.($count.key) -isnot [int]) -or $codec.($count.key) -ne $count.value){throw 'Archive frozen case count rejected'}
 }
 if($codec.reference_sha256 -isnot [string] -or $codec.reference_sha256 -cne '961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e' -or $codec.binary64_sha256 -isnot [string] -or $codec.binary64_sha256 -cne '406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8'){throw 'Archive frozen reference identity rejected'}
 if((($Receipt.wind.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bridge`ncue`nscene"){throw 'All wind cue/bridge/scene results are mandatory'}
 foreach($name in @('cue','bridge','scene')){
  $item=$Receipt.wind.$name
  $names=@('passed','checks','failures')
  if($name -ne 'bridge'){$names+=@('scope')}
  if($name -eq 'cue'){$names+=@('reference_cases','runway_expectations','reference_sha256')}
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($names|Sort-Object) -join "`n")){throw "Wind $name receipt exact shape rejected"}
  if($item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0){throw "Wind $name checks missing, vacuous or failed"}
  if($name -ne 'bridge' -and ($item.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($item.scope) -or $item.scope.Length -gt 1024)){throw "Wind $name scope malformed"}
 }
 $cue=$Receipt.wind.cue
 foreach($count in @(@{key='reference_cases';value=22},@{key='runway_expectations';value=8})){
  if(($cue.($count.key) -isnot [long] -and $cue.($count.key) -isnot [int]) -or $cue.($count.key) -ne $count.value){throw 'Wind frozen case count rejected'}
 }
 if($cue.reference_sha256 -isnot [string] -or $cue.reference_sha256 -cne '7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3'){throw 'Wind frozen reference identity rejected'}
}
# ADR010 opt-in cold fixtures: selective roster, never the entire engine test tree.
function Get-PistonSourceDefinitions {
 @(
  @{source='tests/engine/facade_checks.gd';destination='engine_tests/facade_checks.gd'},
  @{source='tests/engine/pacing_checks.gd';destination='engine_tests/pacing_checks.gd'},
  @{source='tests/engine/wind_profile_checks.gd';destination='engine_tests/wind_profile_checks.gd'},
  @{source='tests/engine/scene_checks.gd';destination='engine_tests/scene_checks.gd'},
  @{source='tests/engine/visual_checks.gd';destination='engine_tests/visual_checks.gd'},
  @{source='tests/interactive/bridge_profile_checks.gd';destination='engine_tests/bridge_profile_checks.gd'},
  @{source='tests/debrief/observed_archive/reference/minimal.fsreview.json';destination='engine_tests/reference/minimal.fsreview.json'}
 )
 foreach($name in @('inventory.json','aircraft/original-piston-prop/original-piston-prop.xml','engine/original-piston.xml','engine/original-fixed-prop.xml','parameter-ledger.json','NOTICE-MIT.txt','README.md')){
  @{source=('native/fdm_jsbsim/models/original-piston-prop/'+$name);destination=('piston-models/'+$name)}
 }
}
function Get-PistonSourceSnapshot {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $modelRoot=Join-Path $RepoRoot 'native/fdm_jsbsim/models/original-piston-prop'
 $modelEntries=@('inventory.json','aircraft/original-piston-prop/original-piston-prop.xml','engine/original-piston.xml','engine/original-fixed-prop.xml','parameter-ledger.json','NOTICE-MIT.txt','README.md')
 $model=@(Get-SimulationSourceSnapshot $modelRoot -RequiredEntries $modelEntries)
 if($model.Count -ne 7){throw 'Original piston model requires exactly seven ordinary files'}
 $inventory=Join-Path $modelRoot 'inventory.json'
 if((Get-FileHash -LiteralPath $inventory).Hash.ToLowerInvariant() -cne 'f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a'){throw 'Accepted original piston inventory changed'}
 $manifest=Get-Content -LiteralPath $inventory -Raw|ConvertFrom-Json
 foreach($pin in @($manifest.files)+@($manifest.metadata)){
  $row=@($model|Where-Object {$_.path -ceq $pin.path})
  if($row.Count -ne 1 -or $row[0].bytes -ne $pin.bytes -or $row[0].sha256 -cne $pin.sha256){throw 'Accepted original piston payload changed'}
 }
 @(Get-PistonSourceDefinitions|ForEach-Object {
  $file=Join-Path $RepoRoot $_.source
  Assert-PreviewOrdinaryAncestors -Path $file
  $item=Get-Item -Force -LiteralPath $file -ErrorAction Stop
  if($item.PSIsContainer){throw 'Piston source must be an ordinary file'}
  [pscustomobject]@{source=$_.source;destination=$_.destination;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant()}
 })
}
function Assert-PistonSourceSnapshot {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Snapshot,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-PistonSourceDefinitions)
 if($Snapshot.Count -ne $definitions.Count -or $Snapshot.Count -ne 14){throw 'Complete fourteen-file piston staging roster required'}
 for($i=0;$i -lt $definitions.Count;$i++){
  $file=$Snapshot[$i];$definition=$definitions[$i]
  if((($file.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "bytes`ndestination`nsha256`nsource" -or $file.source -cne $definition.source -or $file.destination -cne $definition.destination -or ($file.bytes -isnot [long] -and $file.bytes -isnot [int]) -or $file.bytes -lt 0 -or $file.sha256 -isnot [string] -or $file.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Piston staging source/destination/identity declaration rejected'}
  $path=Join-Path $Root $(if($Authoring){$file.source}else{$file.destination})
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -Force -LiteralPath $path -ErrorAction Stop
  if($item.PSIsContainer -or $item.Length -ne $file.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $file.sha256){throw 'Piston staging source bytes changed'}
 }
 if($Authoring){
  # Recheck the closed pinned model tree, including unexpected file additions.
  $actual=@(Get-PistonSourceSnapshot -RepoRoot $Root)
  if(($actual|ConvertTo-Json -Depth 5 -Compress) -cne ($Snapshot|ConvertTo-Json -Depth 5 -Compress)){throw 'Piston authoring roster changed'}
 }else{
  foreach($folder in @('engine_tests','piston-models')){
   $expected=@($Snapshot|Where-Object {$_.destination.StartsWith($folder+'/')}|ForEach-Object {[pscustomobject]@{path=$_.destination.Substring($folder.Length+1);bytes=$_.bytes;sha256=$_.sha256}}|Sort-Object path)
   Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root $folder) -Snapshot $expected -RequiredEntries @($expected.path) -AllowGeneratedUIDs:$AllowGeneratedUIDs
  }
 }
}
function Copy-PistonSourceSnapshot {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Snapshot)
 Assert-PistonSourceSnapshot -Root $RepoRoot -Snapshot $Snapshot -Authoring
 Assert-PreviewOrdinaryAncestors -Path $DestinationRoot
 foreach($folder in @('engine_tests','piston-models')){if(Test-Path -LiteralPath (Join-Path $DestinationRoot $folder)){throw 'Piston staging destinations must be fresh'}}
 foreach($file in $Snapshot){
  $target=Join-Path $DestinationRoot $file.destination
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $RepoRoot $file.source) -Destination $target
 }
 Assert-PistonSourceSnapshot -Root $DestinationRoot -Snapshot $Snapshot
 Assert-PistonSourceSnapshot -Root $RepoRoot -Snapshot $Snapshot -Authoring
}
function Assert-ObservedPistonReceipt {
 param([Parameter(Mandatory)]$Receipt)
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "archive`npanel`nrecorder"){throw 'All three piston observed leaves are mandatory'}
 $total=[long]0
 foreach($name in @('recorder','archive','panel')){
  $item=$Receipt.$name
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "checks`nfailures`npassed`nscope" -or $item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [int] -and $item.checks -isnot [long]) -or $item.checks -le 0 -or $item.checks -gt 9007199254740991 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0 -or $item.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($item.scope) -or $item.scope.Length -gt 1024){throw 'Piston observed leaf missing, vacuous or failed'}
  $total+=$item.checks
  if($total -gt 9007199254740991){throw 'Piston observed aggregate is not a safe integer'}
 }
}
function Assert-ObservedPistonSceneReceipt {
 param([Parameter(Mandatory)]$Receipt)
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "checks`nfailures`npassed`nscope" -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [int] -and $Receipt.checks -isnot [long]) -or $Receipt.checks -le 0 -or $Receipt.checks -gt 9007199254740991 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0 -or $Receipt.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.scope) -or $Receipt.scope.Length -gt 1024){throw 'Actual piston observed scene missing, vacuous or failed'}
}
function Assert-PreviewPistonReceipt {
 param([Parameter(Mandatory)]$Receipt)
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "checks`nfailures`ngroups`npassed`nschema`nscope" -or $Receipt.schema -cne 'PistonFlightChecks/v1' -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [long] -and $Receipt.checks -isnot [int]) -or $Receipt.checks -le 0 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0 -or $Receipt.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.scope) -or $Receipt.scope.Length -gt 1024){throw 'Cold-flight receipt shape or active checks rejected'}
 $groups=@('bridge','facade','pacing','input','panel','status','wind','scene')
 if((($Receipt.groups.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($groups|Sort-Object) -join "`n")){throw 'All eight cold-flight test groups are mandatory'}
 $total=0
 foreach($name in $groups){
  $item=$Receipt.groups.$name
  if((($item.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "checks`nfailures`npassed`nresult" -or $item.passed -isnot [bool] -or -not $item.passed -or ($item.checks -isnot [long] -and $item.checks -isnot [int]) -or $item.checks -le 0 -or $item.failures -isnot [array] -or $item.failures.Count -ne 0 -or $item.result -isnot [pscustomobject]){throw "Cold-flight $name group omitted, vacuous or failed"}
  if($name -ne 'scene'){
   $raw=$item.result
   if($raw.passed -isnot [bool] -or -not $raw.passed -or ($raw.checks -isnot [long] -and $raw.checks -isnot [int]) -or $raw.checks -le 0 -or $raw.failures -isnot [array] -or $raw.failures.Count -ne 0 -or $item.checks -ne ($raw.checks+1)){throw "Cold-flight $name source result/count differs"}
  }
  $total+=$item.checks
 }
 if($total -ne $Receipt.checks){throw 'Cold-flight group check total mismatch'}
 $pacing=$Receipt.groups.pacing.result
 if($pacing.native_profiles -isnot [array] -or $pacing.native_profiles.Count -ne 25){throw 'All twenty-five cold pacing profiles are mandatory'}
 $covered=@()
 foreach($row in $pacing.native_profiles){
  $key=$row.cadence+':'+$row.scale
  if($row.cadence -isnot [string] -or $row.scale -isnot [string] -or $row.cadence -cnotin @('30','60','144','240','jitter') -or $row.scale -cnotin @('1/4','1/2','1','2','4') -or $covered -ccontains $key -or $row.completed_profile -isnot [bool] -or -not $row.completed_profile -or $row.final_tick -isnot [string] -or $row.final_tick -cne '120' -or ($row.final_debt_quanta -isnot [long] -and $row.final_debt_quanta -isnot [int]) -or $row.final_debt_quanta -ne 0){throw 'Cold pacing profile roster or completion rejected'}
  $covered+=$key
 }
 if($Receipt.groups.scene.result.initialized -isnot [bool] -or -not $Receipt.groups.scene.result.initialized -or $Receipt.groups.scene.result.cold_initial_tick -isnot [string] -or $Receipt.groups.scene.result.cold_initial_tick -cne '0' -or $Receipt.groups.scene.result.cold_reset_tick -isnot [string] -or $Receipt.groups.scene.result.cold_reset_tick -cne '0'){throw 'Actual cold scene adoption/reset evidence required'}
 Assert-ObservedPistonSceneReceipt $Receipt.groups.scene.result.observed_review
}

# ADR016: build-side expectation qualification, never native self-report trust.
function Get-PreviewNativeBuildIdentity {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$NativeBuildRoot,[string]$Python='python')
 $raw=& $Python -B (Join-Path $PSScriptRoot 'native-identity.py') --repository-root $RepoRoot --build-root $NativeBuildRoot
 if($LASTEXITCODE -ne 0){throw 'Independent selected native build/resource qualification rejected'}
 $raw | ConvertFrom-Json -ErrorAction Stop
}
function Assert-PreviewOrdinaryAncestors {
 param([Parameter(Mandatory)][string]$Path)
 $item=Get-Item -Force -LiteralPath $Path -ErrorAction Stop
 while($null -ne $item){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Generated resource path contains reparse point'}
  $parent=Split-Path -Parent $item.FullName
  if([string]::IsNullOrEmpty($parent) -or $parent -ceq $item.FullName){break}
  $item=Get-Item -Force -LiteralPath $parent -ErrorAction Stop
 }
}
function Assert-PreviewNativeIdentityResource {
 param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][string]$DestinationRoot,[switch]$AllowGeneratedUIDs)
 if($Identity.schema -cne 'PreviewNativeBuildIdentity/v2' -or $Identity.resource.build_path -cne 'native-identity.gd' -or $Identity.resource.staged_path -cne 'build/native_identity.gd' -or
    ($Identity.resource.bytes -isnot [int] -and $Identity.resource.bytes -isnot [long]) -or $Identity.resource.bytes -lt 0 -or
    $Identity.resource.sha256 -isnot [string] -or $Identity.resource.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Generated resource declaration rejected'}
 Assert-PreviewOrdinaryAncestors -Path $DestinationRoot
 $root=Get-Item -Force -LiteralPath $DestinationRoot -ErrorAction Stop
 $folder=Get-Item -Force -LiteralPath (Join-Path $root.FullName 'build') -ErrorAction Stop
 foreach($item in @($root,$folder)+@(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force)){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Generated resource path contains reparse point'}
 }
 $files=@(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force)
 foreach($file in $files){
  $name=[IO.Path]::GetRelativePath($folder.FullName,$file.FullName).Replace([char]92,[char]47)
  if($name -ceq 'native_identity.gd' -and -not $file.PSIsContainer){continue}
  if($AllowGeneratedUIDs -and $name -ceq 'native_identity.gd.uid' -and -not $file.PSIsContainer -and $file.Length -le 64 -and [IO.File]::ReadAllText($file.FullName) -cmatch '^uid://[a-z0-9]{1,20}\r?\n?$'){continue}
  throw 'Undeclared generated build resource'
 }
 $resource=Get-Item -Force -LiteralPath (Join-Path $folder.FullName 'native_identity.gd') -ErrorAction Stop
 if($resource.Length -ne $Identity.resource.bytes -or (Get-FileHash -LiteralPath $resource.FullName).Hash.ToLowerInvariant() -cne $Identity.resource.sha256){throw 'Generated resource bytes changed'}
}
function Copy-PreviewNativeIdentityResource {
 param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][string]$DestinationRoot)
 $root=Get-Item -Force -LiteralPath $DestinationRoot -ErrorAction Stop
 Assert-PreviewOrdinaryAncestors -Path $DestinationRoot
 Assert-PreviewOrdinaryAncestors -Path (Join-Path $Identity.root 'native-identity.gd')
 if(-not $root.PSIsContainer -or $root.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Generated resource destination must be an ordinary directory'}
 $folder=Join-Path $root.FullName 'build'
 if(Test-Path -LiteralPath $folder){throw 'Generated resource directory must be fresh'}
 New-Item -ItemType Directory -Path $folder|Out-Null
 Copy-Item -LiteralPath (Join-Path $Identity.root 'native-identity.gd') -Destination (Join-Path $folder 'native_identity.gd')
 Assert-PreviewNativeIdentityResource -Identity $Identity -DestinationRoot $DestinationRoot
}
function Assert-PreviewNativeResourceReceipt {
 param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Identity)
 $keys=@('schema','path','bytes','sha256')
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n")){throw 'Runtime generated resource receipt exact shape rejected'}
 if($Receipt.schema -cne 'PreviewNativeResource/v1' -or $Receipt.path -cne 'build/native_identity.gd' -or
    ($Receipt.bytes -isnot [long] -and $Receipt.bytes -isnot [int]) -or $Receipt.bytes -ne $Identity.resource.bytes -or
    $Receipt.sha256 -isnot [string] -or $Receipt.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $Receipt.sha256 -cne $Identity.resource.sha256){throw 'Actual runtime generated resource differs from independently qualified bytes'}
}
# Issue160 has a dedicated test namespace, separate from wind and facade groups.
function Get-GroundMaterialSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $group=@{source='tests/world/ground-materials';destination='ground_material_tests';required=@('checks.gd')}
 $group.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) -RequiredEntries $group.required)
 if($group.snapshot.Count -ne 1 -or $group.snapshot[0].path -cne 'checks.gd'){throw 'Ground-material test roster must contain exactly checks.gd'}
 @($group)
}
function Copy-GroundMaterialSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
}
function Assert-GroundMaterialSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){
  $path=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
# ADR027 tools-only source groups; this does not assert native start support.
function Assert-TaxiLayoutContent {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $path=Join-Path $RepoRoot 'content/world/synthetic/taxi-layout-v1.json'
 Assert-PreviewOrdinaryAncestors -Path $path
 $item=Get-Item -Force -LiteralPath $path -ErrorAction Stop
 if($item.PSIsContainer -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'd8668af407885949a4eb05fbe170d41fe6c6752d3ce15670f9879a36063d355c'){throw 'Exact original taxi layout content required'}
}
function Get-TaxiSourceDefinitions {
 @(
  @{source='app/world/taxi';destination='world/taxi';required=@('taxi_layout.gd','taxi_navigation.gd')},
  @{source='app/ui/taxi';destination='ui/taxi';required=@('taxi_panel.gd')},
  @{source='tests/world/taxi';destination='taxi_tests';required=@('shipping_probe.gd','shipping_observer.gd','pilot_journey.gd','layout_checks.gd','navigation_checks.gd','panel_checks.gd','map_checks.gd','reference/expected-v1.json','reference/generate.py','reference/source-binding-v1.json','reference/README.md','start-reference/expected-v1.json','start-reference/generate.py','start-reference/source-binding-v1.json','start-reference/README.md','start-reference/prop-disk-v1.json','start-reference/generate-prop-disk.py','compatibility-reference/expected-v1.json','compatibility-reference/generate.py','compatibility-reference/source-binding-v1.json','compatibility-reference/README.md')},
  @{source='tests/integration/taxi';destination='taxi_scene_tests';required=@('scene_checks.gd')}
 )
}
function Get-TaxiReferencePins {
 @{
  'reference/expected-v1.json'='9b9579b18c38ba3c1393af76798fa39b8683229fdf2eff553b1c12e0fd3ae37c'
  'reference/generate.py'='799fbcc5fc2144e713d295559e961d1614e245b7bf2a003135ce1234eedec558'
  'reference/source-binding-v1.json'='1366d0484be3eb6a6ca13028f7f431894d6c879c01dbe2a04f3107a7a7678c8b'
  'reference/README.md'='dd070ab6dcfcd45de6c2dd26129b2402c045cc7eb0b5ebfa6dd2a8ceee81df41'
  'start-reference/expected-v1.json'='fb543ddd1681c3cb040cdfd1c65ff404eb9409e73bb6f613c225a3a501f2e333'
  'start-reference/generate.py'='da0e7b91bd3a3ea7df60f80b01b75df209bc4271950f6458fa462da4efba2645'
  'start-reference/source-binding-v1.json'='5b097ee7c6b727e0f19fe4079913c1e0c4ad6453de9628d01a9bc9588c08c230'
  'start-reference/README.md'='4eb067f2cf2d7bae258984704685578a672be0cae697b6af0b1212bca980eeb6'
  'start-reference/prop-disk-v1.json'='545c0dc04dfa8e5d10eebaef0458dbfb46bb12f53d2d5ab05cf02004bcfe6537'
  'start-reference/generate-prop-disk.py'='dd9aa4014416a2871cb13239fc74c29b1ff21c7d6f26e158ff0ad8bfcc02d8ff'
  'compatibility-reference/expected-v1.json'='0ae22514067840455e4e01fb65cde1c39015e731937ff6971df030ce81a0d811'
  'compatibility-reference/generate.py'='c7dca2b57ef8ed9d7f0922b8abc7916632cffe6adbecadb40b8b2cbefa40a263'
  'compatibility-reference/source-binding-v1.json'='92944cb006c2497211c5dec3fa847e17dd52b6dd46df085c6c8bc7864378603c'
  'compatibility-reference/README.md'='453c91177bb7549b6fb16b30634b7c08fcebd4af79a5c5f2d8e7853a210a35b9'
 }
}
function Get-TaxiSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 $groups=@(Get-TaxiSourceDefinitions|ForEach-Object {$_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required);$_})
 Assert-TaxiSourceGroups -Root $RepoRoot -Groups $groups -Authoring
 $groups
}
function Assert-TaxiSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-TaxiSourceDefinitions)
 if($Groups.Count -ne $definitions.Count){throw 'Complete taxi source group roster required'}
 for($i=0;$i -lt $definitions.Count;$i++){
  $group=$Groups[$i];$definition=$definitions[$i]
  if($group.source -cne $definition.source -or $group.destination -cne $definition.destination -or ($group.required -join "`n") -cne ($definition.required -join "`n") -or (($group.snapshot.path|Sort-Object) -join "`n") -cne (($definition.required|Sort-Object) -join "`n")){throw 'Closed taxi source descriptor/roster rejected'}
  if($group.source -ceq 'tests/world/taxi'){foreach($entry in (Get-TaxiReferencePins).GetEnumerator()){ $rows=@($group.snapshot|Where-Object {$_.path -ceq $entry.Key});if($rows.Count -ne 1 -or $rows[0].sha256 -cne $entry.Value){throw 'Frozen taxi reference bytes changed'} }}
  $folder=if($Authoring){$group.source}else{$group.destination}
  Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root $folder) -Snapshot $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Copy-TaxiSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-TaxiSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 foreach($group in $Groups){Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
 Assert-TaxiSourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-TaxiSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
function Test-PreviewApronStartSourceBindings {
 param([Parameter(Mandatory)]$NativeIdentity)
 # Caller supplies Get-PreviewNativeBuildIdentity's already independently closed
 # 25-row identity. These three raw pins additionally bind the new start code.
 $pins=@{
  'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp'='40511064929f717e57ed3ff084a3aad0f9af6c406bb50ba74ec1a4fdbe5fcd8f'
  'native/fdm_jsbsim/interactive/src/session.cpp'='272edf5984dc9205c75f7103546b0312c78ba43f05f416dad929172b8ef6fbeb'
  'native/godot_bridge/src/interactive_bridge.cpp'='0ebe3a59122368733745f05d82204a2e5a2b9187e985c89bff7b59a6f5e9dcd3'
 }
 foreach($path in $pins.Keys){
  $rows=@($NativeIdentity.source_bindings|Where-Object {$_.path -ceq $path})
  if($rows.Count -ne 1 -or $rows[0].raw_sha256 -cne $pins[$path]){return $false}
 }
 return $true
}
function Test-PreviewTaxiStartSource {
 param([Parameter(Mandatory)]$NativeIdentity)
 return ($NativeIdentity.source_variant -ceq 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2' -and (Test-PreviewApronStartSourceBindings -NativeIdentity $NativeIdentity))
}

# ADR018 leaves remain exact; ADR027 adds one explicitly bound composite file.
function Get-FirstFlightSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 Assert-TaxiLayoutContent -RepoRoot $RepoRoot
 @(
  @{source='app/ui/first_flight';destination='ui/first_flight';required=@('briefing_panel.gd','binding_help.gd','circuit_guide.gd')},
  @{source='app/world/synthetic';destination='world/synthetic';required=@('circuit_geometry.gd')},
  @{source='content/scenarios/first-flight';destination='content/scenarios/first-flight';required=@('briefing.json')},
  @{source='content/world/synthetic';destination='content/world/synthetic';required=@('practice-circuit.json','taxi-layout-v1.json')},
  @{source='tests/scenarios/first-flight';destination='scenario_tests/first-flight';required=@('briefing_checks.gd','circuit_checks.gd')},
  @{source='tests/ui/first_flight';destination='first_flight_ui_tests';required=@('briefing_checks.gd')},
  @{source='tests/world/synthetic';destination='world_tests/synthetic';required=@('circuit_checks.gd')},
  @{source='tests/integration/first_flight';destination='first_flight_scene_tests';required=@('scene_checks.gd','map_checks.gd','visual_checks.gd','layout_visual_checks.gd','hud_caption_visual_checks.gd')}
 )|ForEach-Object {
  $_.snapshot=@(Get-SimulationSourceSnapshot (Join-Path $RepoRoot $_.source) -RequiredEntries $_.required)
  if($_.source -ceq 'app/world/synthetic'){
   if(@($_.snapshot.path) -ccontains 'taxi-layout-v1.json'){throw 'Taxi layout is owned by content, never a duplicate authored world file'}
   $layout=Get-Item -LiteralPath (Join-Path $RepoRoot 'content/world/synthetic/taxi-layout-v1.json')
   $_.snapshot=@($_.snapshot)+@([pscustomobject]@{path='taxi-layout-v1.json';bytes=$layout.Length;sha256='d8668af407885949a4eb05fbe170d41fe6c6752d3ce15670f9879a36063d355c'})
   $_.snapshot=@($_.snapshot|Sort-Object path)
   $_.required+=@('taxi-layout-v1.json')
  }
  $_
 }
}
function Copy-FirstFlightSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-FirstFlightSourceGroups -DestinationRoot $RepoRoot -Groups $Groups -Authoring
 foreach($group in $Groups){
  if($group.source -ceq 'app/world/synthetic'){
   $authored=@($group.snapshot|Where-Object {$_.path -cne 'taxi-layout-v1.json'})
   Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $authored -RequiredEntries @('circuit_geometry.gd')
   Copy-Item -LiteralPath (Join-Path $RepoRoot 'content/world/synthetic/taxi-layout-v1.json') -Destination (Join-Path $DestinationRoot 'world/synthetic/taxi-layout-v1.json')
  }else{Copy-SimulationSourceSnapshot (Join-Path $RepoRoot $group.source) (Join-Path $DestinationRoot $group.destination) $group.snapshot -RequiredEntries $group.required}
 }
 Assert-FirstFlightSourceGroups -DestinationRoot $DestinationRoot -Groups $Groups
 Assert-FirstFlightSourceGroups -DestinationRoot $RepoRoot -Groups $Groups -Authoring
}
function Assert-FirstFlightSourceGroups {
 param([Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 foreach($group in $Groups){
  if($Authoring -and $group.source -ceq 'app/world/synthetic'){
   Assert-TaxiLayoutContent -RepoRoot $DestinationRoot
   $layout=@($group.snapshot|Where-Object {$_.path -ceq 'taxi-layout-v1.json'})
   $actual=Get-Item -LiteralPath (Join-Path $DestinationRoot 'content/world/synthetic/taxi-layout-v1.json')
   if($layout.Count -ne 1 -or $layout[0].bytes -ne $actual.Length -or $layout[0].sha256 -cne 'd8668af407885949a4eb05fbe170d41fe6c6752d3ce15670f9879a36063d355c'){throw 'Composite taxi layout descriptor rejected'}
   Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $group.source) @($group.snapshot|Where-Object {$_.path -cne 'taxi-layout-v1.json'}) -RequiredEntries @('circuit_geometry.gd')
  }else{
   $path=if($Authoring){$group.source}else{$group.destination}
   Assert-SimulationSourceSnapshot (Join-Path $DestinationRoot $path) $group.snapshot -RequiredEntries $group.required -AllowGeneratedUIDs:$AllowGeneratedUIDs
  }
 }
}

function Write-SimulationCheckHarness {
 param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RepoRoot,[switch]$IncludePiston,$NativeIdentity=$null)
 $taxiGroups=@(Get-TaxiSourceGroups -RepoRoot $RepoRoot)
 Copy-TaxiSourceGroups -RepoRoot $RepoRoot -DestinationRoot $ProjectRoot -Groups $taxiGroups
 $taxiFullSupported='false'
 $apronCameraCoverage=$false
 if($null -ne $NativeIdentity){$apronCameraCoverage=Test-PreviewApronStartSourceBindings -NativeIdentity $NativeIdentity}
 if($IncludePiston){
  if($null -eq $NativeIdentity){throw 'Actual independently qualified native identity required'}
  if($NativeIdentity.source_variant -ceq 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'){
   if(-not (Test-PreviewTaxiStartSource -NativeIdentity $NativeIdentity)){throw 'Mandatory actual source-qualified apron starts absent'}
   $taxiFullSupported='true'
  }
 }
 $taxiPairs=@(foreach($group in $taxiGroups){foreach($file in $group.snapshot){,@(($group.source+'/'+$file.path),('res://'+$group.destination+'/'+$file.path))}})
 $taxiPairs+=,@('content/world/synthetic/taxi-layout-v1.json','res://world/synthetic/taxi-layout-v1.json')
 $taxiSourcePairs=ConvertTo-Json -InputObject $taxiPairs -Depth 5 -Compress
 $cameraGroups=@(Get-CameraSourceGroups -RepoRoot $RepoRoot)
 Copy-CameraSourceGroups -RepoRoot $RepoRoot -DestinationRoot $ProjectRoot -Groups $cameraGroups
 Write-PreviewCameraCheckHarness -ProjectRoot $ProjectRoot -Groups $cameraGroups -IncludePiston ([bool]$IncludePiston) -IncludeApron $apronCameraCoverage
 $wireGroups=@(Get-WireCodecSourceGroups -RepoRoot $RepoRoot)
 Copy-WireCodecSourceGroups -RepoRoot $RepoRoot -DestinationRoot $ProjectRoot -Groups $wireGroups
 # Staging applicability follows the already verified generated identity resource.
 $replayIdentity=Join-Path $ProjectRoot 'build/native_identity.gd'
 $includeLocalWindowReplay=$false
 if(Test-Path -LiteralPath $replayIdentity -PathType Leaf){
  $identityText=[IO.File]::ReadAllText($replayIdentity)
  $variantLine=[regex]::Match($identityText,'(?m)^const SOURCE_VARIANT: String = "([a-z0-9.-]+)"\r?$')
  if(-not $variantLine.Success){throw 'Generated native identity source selector absent'}
  $includeLocalWindowReplay=$variantLine.Groups[1].Value -ceq 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'
 }
 $localWindowReplayChecks=''
 $localWindowReplayCompileFolder=''
 if($includeLocalWindowReplay){
  if(-not $IncludePiston){throw 'Exact local-window v2 must include existing cold groups'}
  $replayGroups=@(Get-LocalWindowReplaySourceGroups -RepoRoot $RepoRoot)
  Copy-LocalWindowReplaySourceGroups -RepoRoot $RepoRoot -DestinationRoot $ProjectRoot -Groups $replayGroups
  $localWindowReplayCompileFolder=',"res://local_window_replay_tests"'
  $localWindowReplayChecks=@'
 stage("begin","local_window_replay")
 var replay_identity=load("res://build/native_identity.gd")
 if replay_identity.SOURCE_VARIANT!="jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2":
  check(false,"local_window_replay_exact_source_variant")
  get_tree().quit(1)
  return
 var replay_pins: Dictionary={"recipe.json":"2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1","argument-binary64.json":"ffb39073782ac1226795df39b0b95512e0f444a4f2284224c9c34af4a5ef9b76","checks.gd":"5689a75e0868067d04b22cd8cfde61f75f0d83d78b5f9a6a1cd37848e34636b8","README.md":"9a333bcce0d17202e9ec2818f7a13227a522764063da7a6a2cd028f38b20a949"}
 for name in replay_pins:
  if FileAccess.get_sha256("res://local_window_replay_tests/"+name)!=replay_pins[name]:
   check(false,"local_window_replay_resource_"+name)
   get_tree().quit(1)
   return
  check(true,"local_window_replay_resource_"+name)
 var replay_root: String=(ProjectSettings.globalize_path("res://piston-models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("piston-models")).replace("\\","/")
 var replay_result: Dictionary=load("res://local_window_replay_tests/checks.gd").run(replay_root)
 check(typeof(replay_result.get("passed"))==TYPE_BOOL and replay_result.passed and typeof(replay_result.get("checks"))==TYPE_INT and replay_result.checks>0 and replay_result.get("failures") is Array and replay_result.failures.is_empty(),"actual_local_window_replay_checks")
 if typeof(replay_result.get("checks"))==TYPE_INT and replay_result.checks>0: checks+=replay_result.checks
 if replay_result.get("failures") is Array:
  for failure in replay_result.failures: failures.append("local_window_replay:"+str(failure))
 var replay_output: String=ProjectSettings.globalize_path("res://local-window-replay-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("local-window-replay-receipt.json")
 if FileAccess.file_exists(replay_output):
  check(false,"local_window_replay_receipt_fresh")
  get_tree().quit(1)
  return
 var replay_file=FileAccess.open(replay_output,FileAccess.WRITE)
 check(replay_file!=null,"local_window_replay_receipt_saved")
 if replay_file!=null:
  replay_file.store_string(JSON.stringify(replay_result,"  ",false,true))
  replay_file.close()
 stage("end","local_window_replay")

'@
 }
 $pistonChecks=if($IncludePiston){@'
 var piston_start_checks: int=checks
 var piston_start_failures: int=failures.size()
 var piston_groups: Dictionary={}
 for name in ["bridge","facade","pacing","input","panel","status","wind","scene"]:
  var group_checks: int=checks
  var group_failures: int=failures.size()
  stage("begin","piston."+name)
  var cold_result: Dictionary
  match name:
   "bridge": cold_result=load("res://engine_tests/bridge_profile_checks.gd").new().run(ProjectSettings.globalize_path("res://models"),ProjectSettings.globalize_path("res://piston-models"))
   "facade": cold_result=load("res://engine_tests/facade_checks.gd").run(ProjectSettings.globalize_path("res://piston-models"))
   "pacing": cold_result=load("res://engine_tests/pacing_checks.gd").run(ProjectSettings.globalize_path("res://piston-models"))
   "input": cold_result=load("res://input_tests/piston_checks.gd").new().run()
   "panel": cold_result=await load("res://input_tests/piston_panel_checks.gd").new().run(self)
   "status": cold_result=load("res://instrument_tests/engine_status_checks.gd").run()
   "wind": cold_result=load("res://engine_tests/wind_profile_checks.gd").run(ProjectSettings.globalize_path("res://piston-models"))
   "scene": cold_result=await load("res://engine_tests/scene_checks.gd").new().run(self)
  stage("end","piston."+name)
  if name!="scene":
   var active_count: Variant=cold_result.get("checks")
   check(typeof(active_count)==TYPE_INT and active_count>0 and typeof(cold_result.get("passed"))==TYPE_BOOL and cold_result.passed and cold_result.get("failures") is Array and cold_result.failures.is_empty(),"actual_piston_"+name+"_checks")
   if typeof(active_count)==TYPE_INT and active_count>0: checks+=active_count
  else:
   check(cold_result.get("initialized")==true and checks>group_checks and failures.size()==group_failures,"actual_piston_scene_checks")
  var failed: Array=failures.slice(group_failures)
  piston_groups[name]={"passed":failed.is_empty(),"checks":checks-group_checks,"failures":failed,"result":cold_result}
 var piston_report: Dictionary={"schema":"PistonFlightChecks/v1","passed":failures.size()==piston_start_failures,"checks":checks-piston_start_checks,"failures":failures.slice(piston_start_failures),"scope":"Actual opt-in original cold profile bridge/facade/pacing/scene; synthetic input/status/display fixtures. No aircraft, pilot, phase, GPU or sound calibration qualification.","groups":piston_groups}
 var piston_output: String=ProjectSettings.globalize_path("res://piston-check-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("piston-check-receipt.json")
 var piston_file=FileAccess.open(piston_output,FileAccess.WRITE)
 check(piston_file!=null,"cold_flight_receipt_saved")
 if piston_file!=null:
  piston_file.store_string(JSON.stringify(piston_report,"  "))
  piston_file.close()

'@}else{''}
 $pistonCompileFolder=if($IncludePiston){',"res://engine_tests"'}else{''}
 $firstFlightPiston=if($IncludePiston){'true'}else{'false'}
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
func stage(boundary: String, name: String) -> void:
 print("PROOF_STAGE "+boundary+" "+name+" ms="+str(Time.get_ticks_msec()))
func ground_material_checks() -> void:
 # Only the test's temporary Node3D/ground is created; no flight session.
 var driver: Script=load("res://ground_material_tests/checks.gd") as Script
 if driver==null or not driver.can_instantiate():
  push_error("Ground-material checks unavailable")
  get_tree().quit(1)
  return
 var result: Dictionary=driver.run()
 var source_files: Dictionary={}
 for item in [
  ["app/proof/interactive/flight_world.gd","res://interactive/flight_world.gd"],
  ["tests/world/ground-materials/checks.gd","res://ground_material_tests/checks.gd"],
  ["content/aircraft/prototype/ground-presentation.json","res://content/aircraft/prototype/ground-presentation.json"]]:
  var raw: PackedByteArray=FileAccess.get_file_as_bytes(item[1])
  source_files[item[0]]={"bytes":raw.size(),"sha256":FileAccess.get_sha256(item[1])}
 var world: Script=load("res://interactive/flight_world.gd") as Script
 var shader_constants: Dictionary=world.get_script_constant_map()
 var shader_code: String=shader_constants["GROUND_SHADER"]
 var report: Dictionary={"result":result,"source_files":source_files,"shader_code_utf8_sha256":shader_code.sha256_text()}
 var output: String=ProjectSettings.globalize_path("res://ground-material-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("ground-material-receipt.json")
 if FileAccess.file_exists(output):
  push_error("Ground-material receipt must be fresh")
  get_tree().quit(1)
  return
 var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
 if file==null:
  push_error("Ground-material receipt cannot be saved")
  get_tree().quit(1)
  return
 file.store_string(JSON.stringify(report,"  "));file.close()
 print("GROUND_MATERIALS_CHECKS ",JSON.stringify(report))
 get_tree().quit(0 if result.get("passed",false) else 1)
func observed_first_flight_baseline() -> Dictionary:
 # Every native build observes its own source-qualified truth; never patch a saved
 # capture fingerprint to impersonate another native build. No Run is needed.
 var facade=load("res://simulation/session_facade.gd").new()
 var started: Dictionary=facade.start(ProjectSettings.globalize_path("res://models"),"ground-ready","calm","original-interactive-prototype")
 var value: Dictionary={}
 if started.ok:
  var paused: Dictionary=facade.set_paused(true)
  if paused.ok: value=facade.readback().duplicate(true)
 var stopped: Dictionary=facade.close()
 check(stopped.ok and not stopped.readback.native_live,"first_flight_observed_baseline_joined")
 var admitted: Dictionary=load("res://world/synthetic/circuit_geometry.gd").view(value,"calm",36)
 check(admitted.available and value.get("tick")=="0" and value.get("debt_quanta")==0,"first_flight_observed_full_paused_source_baseline")
 return value if stopped.ok and not stopped.readback.native_live and admitted.available and value.get("tick")=="0" and value.get("debt_quanta")==0 else {}
func audio_lifecycle_checks() -> Dictionary:
 # Observe a real facade publication; never rewrite a captured fixture as live.
 var owner=load("res://simulation/session_facade.gd").new()
 var started: Dictionary=owner.start(ProjectSettings.globalize_path("res://models"),"ground-ready","calm","original-interactive-prototype")
 var resumed: Dictionary=owner.set_paused(false) if started.ok else started
 var source: Dictionary=owner.readback()
 var cues: Dictionary=load("res://audio/audio_cues.gd").from_readback(source)
 var eligible: bool=started.ok and resumed.ok and cues.state=="live" and cues.session_id==source.get("session_id") and source.get("native_source_fingerprint")==load("res://build/native_identity.gd").SOURCE_FINGERPRINT
 check(eligible,"audio_actual_live_source_required")
 var result: Dictionary={"passed":false,"checks":1,"failures":["actual_live_source_unavailable"]}
 if eligible: result=await load("res://audio_tests/sample_renderer_checks.gd").run_sound(self,source)
 var stopped: Dictionary=owner.close()
 check(stopped.ok and stopped.readback.native_live==false,"audio_actual_source_worker_joined")
 return result
func execute() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--hud-caption-visual-output="):
   var output: String=argument.trim_prefix("--hud-caption-visual-output=")
   var hud: Dictionary=await load("res://first_flight_scene_tests/hud_caption_visual_checks.gd").new().run_hud(self,output)
   print("HUD_CAPTION_VISUAL ",JSON.stringify({"passed":hud.get("passed",false),"checks":hud.get("checks",0),"failures":hud.get("failures",[]),"views":hud.get("views",[]).size(),"native_joined":hud.get("native_joined",false),"audio_joined":hud.get("audio_joined",false)}))
   var valid_hud: bool=typeof(hud.get("passed"))==TYPE_BOOL and hud.get("passed")==true and typeof(hud.get("checks"))==TYPE_INT and hud.get("checks",0)>0 and hud.checks<=9007199254740991 and hud.get("failures") is Array and hud.failures.is_empty() and hud.get("native_joined")==true and hud.get("audio_joined")==true and hud.get("views") is Array and hud.views.size()==12
   get_tree().quit(0 if valid_hud else 1)
   return
  if argument.begins_with("--ordinary-flight-layout-output="):
   var output: String=argument.trim_prefix("--ordinary-flight-layout-output=")
   var layout: Dictionary=await load("res://first_flight_scene_tests/layout_visual_checks.gd").new().run_layout(self,output)
   print("ORDINARY_FLIGHT_LAYOUT_VISUAL ",JSON.stringify({"passed":layout.get("passed",false),"checks":layout.get("checks",0),"failures":layout.get("failures",[]),"views":layout.get("views",[]).size(),"native_joined":layout.get("native_joined",false),"audio_joined":layout.get("audio_joined",false)}))
   get_tree().quit(0 if layout.get("passed")==true and layout.get("native_joined")==true and layout.get("audio_joined")==true and layout.get("views",[]).size()==29 else 1)
   return
  if argument.begins_with("--first-flight-interaction-output="):
   var output: String=argument.trim_prefix("--first-flight-interaction-output=")
   var interaction: Dictionary=await load("res://first_flight_scene_tests/visual_checks.gd").new().run_interaction(self,output)
   print("FIRST_FLIGHT_INTERACTION ",JSON.stringify({"passed":interaction.get("passed",false),"checks":interaction.get("checks",0),"failures":interaction.get("failures",[]),"views":interaction.get("views",[]).size()}))
   get_tree().quit(0 if interaction.get("passed")==true else 1)
   return
  if argument.begins_with("--first-flight-visual-output="):
   var output: String=argument.trim_prefix("--first-flight-visual-output=")
   var visual: Dictionary=await load("res://first_flight_scene_tests/visual_checks.gd").new().run(self,output)
   print("FIRST_FLIGHT_VISUAL ",JSON.stringify({"passed":visual.get("passed",false),"checks":visual.get("checks",0),"failures":visual.get("failures",[]),"views":visual.get("views",[]).size()}))
   get_tree().quit(0 if visual.get("passed")==true else 1)
   return
 if "--ground-material-checks" in OS.get_cmdline_user_args():
  ground_material_checks()
  return
 var identity_bytes: PackedByteArray=FileAccess.get_file_as_bytes("res://build/native_identity.gd")
 var identity_hash: String=FileAccess.get_sha256("res://build/native_identity.gd")
 var identity_receipt: Dictionary={"schema":"PreviewNativeResource/v1","path":"build/native_identity.gd","bytes":identity_bytes.size(),"sha256":identity_hash}
 var identity_output: String=ProjectSettings.globalize_path("res://native-identity-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("native-identity-receipt.json")
 var identity_file=FileAccess.open(identity_output,FileAccess.WRITE)
 if identity_file==null:
  push_error("Native resource receipt cannot be saved")
  get_tree().quit(1)
  return
 identity_file.store_string(JSON.stringify(identity_receipt))
 identity_file.close()
 for kawa_path in ["res://world/world_admission.gd","res://world/terrain/resident_grid_reader.gd","res://world/terrain/kawo_world.gd"]:
  var kawa_script=load(kawa_path) as Script
  check(kawa_script!=null and kawa_script.can_instantiate(),"explicit_compile_"+kawa_path)
 for folder in ["res://simulation","res://sim_loop_tests","res://interactive","res://input","res://ui/controls","res://input_tests","res://cockpit/instruments","res://cockpit/assets","res://instrument_tests","res://ui/freeflight","res://freeflight_tests","res://replay/observed","res://ui/debrief/observed","res://observed_tests","res://replay/observed_archive","res://observed_archive_tests","res://world/wind","res://ui/wind","res://wind_tests","res://wind_scene_tests","res://audio","res://ui/audio","res://audio_tests","res://ui/first_flight","res://world/synthetic","res://world/taxi","res://ui/taxi","res://taxi_tests","res://taxi_scene_tests","res://scenario_tests/first-flight","res://first_flight_ui_tests","res://world_tests/synthetic","res://first_flight_scene_tests","res://wire_codec_tests","res://camera","res://ui/camera","res://camera_tests","res://persistence","res://ui/profiles","res://ui/history","res://player_tests"$pistonCompileFolder$localWindowReplayCompileFolder]:
  for name in DirAccess.get_files_at(folder):
   if name.ends_with(".gd"):
    var script=load(folder.path_join(name)) as Script
    check(script!=null and script.can_instantiate(),"explicit_compile_"+folder.path_join(name))
 var camera_compile: Script=load("res://camera_checks.gd") as Script
 check(camera_compile!=null and camera_compile.can_instantiate(),"explicit_compile_camera_checks")
 for path in ["res://camera_checks.tscn","res://simulation/flight_scene.tscn","res://interactive/preview.tscn"]:
  check(load(path) is PackedScene,"explicit_scene_compile_"+path)
 if not failures.is_empty():
  push_error("Simulation resource compilation rejected")
  get_tree().quit(1)
  return
 var facade_script=load("res://sim_loop_tests/facade_checks.gd") as Script
 stage("begin","facade")
 var facade: Dictionary=facade_script.run(ProjectSettings.globalize_path("res://models"))
 stage("end","facade")
 check(facade.get("checks",0)>0 and facade.get("failures",["missing"]).is_empty(),"actual_native_facade_checks")
 var wind_checks: Dictionary={}
 for name in ["cue","bridge","scene"]:
  var before_wind: int=failures.size()
  stage("begin","wind."+name)
  var wind_result: Dictionary
  if name=="cue": wind_result=load("res://wind_tests/wind_checks.gd").run()
  elif name=="bridge": wind_result=load("res://simulation/steady_wind_bridge_checks.gd").new().run(ProjectSettings.globalize_path("res://models"))
  else: wind_result=await load("res://wind_scene_tests/scene_checks.gd").new().run(self)
  stage("end","wind."+name)
  check(failures.size()==before_wind and wind_result.get("passed",false) and wind_result.get("checks",0)>0 and wind_result.get("failures",["missing"]).is_empty(),"actual_wind_"+name+"_checks")
  wind_checks[name]=wind_result
 stage("begin","origin")
 var origin: Dictionary=load("res://simulation/render_origin_checks.gd").new().run(self)
 stage("end","origin")
 stage("begin","participants")
 var participants: Dictionary=load("res://simulation/origin_participant_checks.gd").new().run(self)
 stage("end","participants")
 var fixtures: Dictionary={}
 for kind in ["AircraftSnapshot","AtmosphereSample","ControlCommand","OperationalEvent"]:
  fixtures[kind]=JSON.parse_string(FileAccess.get_file_as_string("res://wire_fixtures/"+kind+".json"))
 stage("begin","wire")
 var wire: Dictionary=load("res://simulation/wire_validation_checks.gd").run(fixtures)
 stage("end","wire")
 check(wire.get("passed",false) and wire.get("checks",0)>0,"full_v1_wire_checks")
 stage("begin","input")
 var input: Dictionary=load("res://input_tests/input_checks.gd").run()
 stage("end","input")
 check(input.get("passed",false) and input.get("checks",0)>0 and input.get("failures",["missing"]).is_empty(),"actual_input_mapper_codec_checks")
 var input_scene_failures: int=failures.size()
 stage("begin","input.scene")
 var input_scene: Dictionary=await load("res://input_tests/scene_checks.gd").new().run(self)
 stage("end","input.scene")
 check(failures.size()==input_scene_failures and input_scene.has("initial_tick"),"actual_input_scene_checks")
 stage("begin","instruments")
 var instruments: Dictionary=load("res://instrument_tests/instrument_checks.gd").run()
 stage("end","instruments")
 check(instruments.get("passed",false) and instruments.get("checks",0)>0 and instruments.get("failures",["missing"]).is_empty(),"native_truth_reading_checks")
 var audio_checks: Dictionary={}
 for name in ["cues","options","renderer","panel","lifecycle"]:
  stage("begin","audio."+name)
  var result: Dictionary
  match name:
   "cues": result=load("res://audio_tests/audio_cues_checks.gd").run()
   "options": result=load("res://audio_tests/audio_options_checks.gd").run()
   "renderer": result=load("res://audio_tests/sample_renderer_checks.gd").run()
   "panel": result=await load("res://audio_tests/audio_panel_checks.gd").new().run(self)
   "lifecycle": result=await audio_lifecycle_checks()
  stage("end","audio."+name)
  check(result.get("passed")==true and typeof(result.get("checks"))==TYPE_INT and result.checks>0 and result.get("failures") is Array and result.failures.is_empty(),"actual_audio_"+name+"_checks")
  audio_checks[name]=result
 var cockpit_checks: Dictionary={}
 for name in ["adapter","scan","scene","hud_caption"]:
  var prior_failures: int=failures.size()
  stage("begin","cockpit."+name)
  var result: Dictionary=await load("res://instrument_tests/"+name+"_checks.gd").new().run(self)
  stage("end","cockpit."+name)
  check(failures.size()==prior_failures and result.get("passed",false) and result.get("checks",0)>0 and result.get("failures",["missing"]).is_empty(),"actual_cockpit_"+name+"_checks")
  cockpit_checks[name]=result
 var asset_prior_failures: int=failures.size()
 stage("begin","cockpit.asset")
 var asset_result: Dictionary=await load("res://instrument_tests/cockpit_asset_checks.gd").new().run(self)
 stage("end","cockpit.asset")
 check(failures.size()==asset_prior_failures and asset_result.get("passed")==true and typeof(asset_result.get("checks"))==TYPE_INT and asset_result.checks>0 and asset_result.get("failures") is Array and asset_result.failures.is_empty(),"actual_cockpit_asset_checks")
 cockpit_checks.asset=asset_result
 var freeflight_checks: Dictionary={}
 for item in [{"name":"geometry","script":"landmark_checks.gd"},{"name":"scene","script":"scene_checks.gd"}]:
  var before: int=failures.size()
  stage("begin","freeflight."+item.name)
  var result: Dictionary=await load("res://freeflight_tests/"+item.script).new().run(self)
  stage("end","freeflight."+item.name)
  check(failures.size()==before and result.get("passed",false) and result.get("checks",0)>0 and result.get("failures",["missing"]).is_empty(),"actual_freeflight_"+item.name+"_checks")
  freeflight_checks[item.name]=result
 var observed_checks: Dictionary={}
 var piston_observed: Dictionary={}
 stage("begin","observed.piston")
 piston_observed.recorder=load("res://observed_tests/piston_checks.gd").new().run(self)
 piston_observed.archive=load("res://observed_archive_tests/piston_checks.gd").run()
 var piston_fixture: Dictionary=load("res://replay/observed_archive/codec.gd").decode(FileAccess.get_file_as_bytes("res://observed_archive_tests/reference/piston-small.fsreview.json"))
 var legacy_fixture: Dictionary=load("res://replay/observed_archive/codec.gd").decode(FileAccess.get_file_as_bytes("res://observed_archive_tests/reference/minimal.fsreview.json"))
 check(piston_fixture.ok and legacy_fixture.ok,"piston_review_independent_ui_fixtures_admitted")
 piston_observed.panel=await load("res://observed_tests/piston_panel_checks.gd").new().run(self,piston_fixture.value if piston_fixture.ok else {},legacy_fixture.value if legacy_fixture.ok else {})
 for name in ["recorder","archive","panel"]:
  var child: Dictionary=piston_observed[name]
  check(child.get("passed")==true and typeof(child.get("checks"))==TYPE_INT and child.checks>0 and child.get("failures") is Array and child.failures.is_empty(),"actual_piston_observed_"+name+"_checks")
  if name in ["archive","panel"] and typeof(child.get("checks"))==TYPE_INT: checks+=child.checks
 observed_checks.piston=piston_observed
 stage("end","observed.piston")
 var observed_before: int=failures.size()
 stage("begin","observed.recorder")
 var recorded: Dictionary=load("res://observed_tests/recorder_checks.gd").new().run(self)
 stage("end","observed.recorder")
 check(failures.size()==observed_before and recorded.get("passed",false) and recorded.get("checks",0)>0 and recorded.get("failures",["missing"]).is_empty(),"actual_observed_recorder_checks")
 observed_checks["recorder"]=recorded
 observed_before=failures.size()
 stage("begin","observed.scene")
 var observed_scene: Dictionary=await load("res://observed_tests/scene_checks.gd").new().run(self)
 stage("end","observed.scene")
 check(failures.size()==observed_before and observed_scene.get("passed",false) and observed_scene.get("checks",0)>0 and observed_scene.get("failures",["missing"]).is_empty(),"actual_observed_scene_checks")
 observed_checks["scene"]=observed_scene
 var archive_checks: Dictionary={}
 for name in ["codec","files","scene"]:
  var before_archive: int=failures.size()
  var driver: Script=load("res://observed_archive_tests/"+("archive" if name=="codec" else "file" if name=="files" else "scene")+"_checks.gd")
  stage("begin","archive."+name)
  var archive_result: Dictionary=driver.run() if name=="codec" else driver.new().run() if name=="files" else await driver.new().run(self)
  stage("end","archive."+name)
  check(failures.size()==before_archive and archive_result.get("passed",false) and archive_result.get("checks",0)>0 and archive_result.get("failures",["missing"]).is_empty(),"actual_archive_"+name+"_checks")
  archive_checks[name]=archive_result
 stage("begin","simulation.scene")
 var scene: Dictionary=await load("res://sim_loop_tests/scene_checks.gd").new().run(self)
 stage("end","simulation.scene")
$pistonChecks
 var first_flight_checks: Dictionary={}
 var first_flight_sources: Script=load("res://world_tests/synthetic/circuit_checks.gd")
 var current_first_flight: Dictionary=observed_first_flight_baseline()
 var captured_first_flight: Dictionary=first_flight_sources.captured_readback()
 var observed_first_flight: Dictionary={}
 if not current_first_flight.is_empty() and not captured_first_flight.is_empty() and current_first_flight.native_source_fingerprint!=captured_first_flight.native_source_fingerprint:
  observed_first_flight=current_first_flight.duplicate(true)
 var first_flight_baseline: Dictionary=first_flight_sources.reference_readback() if observed_first_flight.is_empty() and not current_first_flight.is_empty() else observed_first_flight.duplicate(true)
 if first_flight_baseline.is_empty():
  push_error("Required first-flight complete source baseline unavailable")
  get_tree().quit(1)
  return
 for name in ["briefing","bindings","geometry","card","map","scene"]:
  stage("begin","first_flight."+name)
  var result: Dictionary
  match name:
   "briefing": result=load("res://scenario_tests/first-flight/briefing_checks.gd").new().run(self,first_flight_baseline)
   "bindings": result=await load("res://first_flight_ui_tests/briefing_checks.gd").new().run(self,first_flight_baseline)
   "geometry": result=first_flight_sources.run(observed_first_flight)
   "card": result=load("res://scenario_tests/first-flight/circuit_checks.gd").run(observed_first_flight)
   "map": result=load("res://first_flight_scene_tests/map_checks.gd").new().run(observed_first_flight)
   "scene": result=await load("res://first_flight_scene_tests/scene_checks.gd").new().run(self,$firstFlightPiston)
  stage("end","first_flight."+name)
  check(result.get("passed")==true and typeof(result.get("checks"))==TYPE_INT and result.checks>0 and result.get("failures") is Array and result.failures.is_empty(),"actual_first_flight_"+name+"_checks")
  first_flight_checks[name]=result
 stage("begin","wire_codec")
 var numeric: Dictionary=load("res://wire_codec_tests/checks.gd").run(ProjectSettings.globalize_path("res://piston-models"),$firstFlightPiston)
 check(numeric.get("passed")==true and typeof(numeric.get("checks"))==TYPE_INT and numeric.checks>0 and numeric.get("failures") is Array and numeric.failures.is_empty(),"actual_native_wire_codec_checks")
 if typeof(numeric.get("checks"))==TYPE_INT and numeric.checks>0: checks+=numeric.checks
 var numeric_output: String=ProjectSettings.globalize_path("res://wire-codec-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("wire-codec-receipt.json")
 var numeric_file=FileAccess.open(numeric_output,FileAccess.WRITE)
 check(numeric_file!=null,"wire_codec_receipt_saved")
 if numeric_file!=null:
  numeric_file.store_string(JSON.stringify(numeric,"  "))
  numeric_file.close()
 stage("end","wire_codec")
 var taxi_groups: Dictionary={}
 stage("begin","taxi.layout")
 taxi_groups.layout=load("res://taxi_tests/layout_checks.gd").run()
 stage("end","taxi.layout")
 stage("begin","taxi.panel")
 taxi_groups.panel=await load("res://taxi_tests/panel_checks.gd").new().run(self)
 stage("end","taxi.panel")
 stage("begin","taxi.map")
 taxi_groups.map=load("res://taxi_tests/map_checks.gd").new().run(self)
 stage("end","taxi.map")
 taxi_groups.scene=null
 if ${taxiFullSupported}:
  stage("begin","taxi.scene")
  taxi_groups.scene=await load("res://taxi_scene_tests/scene_checks.gd").new().run(self)
  stage("end","taxi.scene")
 var taxi_failures: Array[String]=[]
 var taxi_checks: int=0
 for name in taxi_groups:
  if name=="scene" and not ${taxiFullSupported}: continue
  var child: Variant=taxi_groups[name]
  var child_ok: bool=typeof(child)==TYPE_DICTIONARY
  if child_ok:
   child_ok=child.keys().size()==4 and child.has("passed") and child.has("checks") and child.has("failures") and child.has("scope")
  if child_ok:
   child_ok=typeof(child.passed)==TYPE_BOOL and child.passed and typeof(child.checks)==TYPE_INT and child.checks>0 and typeof(child.failures)==TYPE_ARRAY and child.failures.is_empty() and typeof(child.scope)==TYPE_STRING and not child.scope.is_empty()
  check(child_ok,"actual_taxi_"+name+"_checks")
  if not child_ok: taxi_failures.append("taxi_"+name+"_failed_or_vacuous")
  if typeof(child)==TYPE_DICTIONARY and typeof(child.get("checks"))==TYPE_INT and child.checks>0:
   taxi_checks+=child.checks
   checks+=child.checks
 if not ${taxiFullSupported}: taxi_failures.append("taxi_full_start_domain_unavailable")
 var taxi_source_files: Dictionary={}
 var taxi_pairs: Array=$taxiSourcePairs
 for item in taxi_pairs:
  var raw: PackedByteArray=FileAccess.get_file_as_bytes(item[1])
  taxi_source_files[item[0]]={"bytes":raw.size(),"sha256":FileAccess.get_sha256(item[1])}
 var taxi_harness_raw: PackedByteArray=FileAccess.get_file_as_bytes("res://sim_loop_checks.gd")
 var taxi_report: Dictionary={"schema":"TaxiNavigationChecks/v1","passed":taxi_failures.is_empty(),"checks":taxi_checks,"failures":taxi_failures,"scope":"Actual pure layout, copied paused panel and synthetic map checks; full_supported adds actual source-qualified apron adoption/page modal/lifecycle/navigation checks. No moving taxi journey, rendered legibility, C172, pilot or phase acceptance.","full_supported":${taxiFullSupported},"groups":taxi_groups,"source_files":taxi_source_files,"native_identity":identity_receipt.duplicate(true),"harness_file":{"path":"sim_loop_checks.gd","bytes":taxi_harness_raw.size(),"sha256":FileAccess.get_sha256("res://sim_loop_checks.gd")}}
 var taxi_output: String=ProjectSettings.globalize_path("res://taxi-check-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("taxi-check-receipt.json")
 var taxi_file=FileAccess.open(taxi_output,FileAccess.WRITE)
 check(taxi_file!=null,"taxi_receipt_saved")
 if taxi_file!=null:
  taxi_file.store_string(JSON.stringify(taxi_report,"  ",false,true))
  taxi_file.close()
 print("TAXI_NAVIGATION_CHECKS_PASSED" if taxi_report.passed else ("TAXI_NAVIGATION_FULL_GATE_UNAVAILABLE" if not ${taxiFullSupported} and taxi_failures==["taxi_full_start_domain_unavailable"] else "TAXI_NAVIGATION_CHECKS_FAILED"))

$localWindowReplayChecks
 var report: Dictionary={"schema_version":1,"scope":"Headless actual-native facade and synthetic wire/render fixtures; GPU and pilot qualification separate","passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"facade":facade,"origin":origin,"participants":participants,"wire":wire,"scene":scene,"input":input,"input_scene":input_scene,"instruments":instruments,"cockpit":cockpit_checks,"freeflight":freeflight_checks,"observed":observed_checks,"observed_archive":archive_checks,"wind":wind_checks,"first_flight":first_flight_checks,"audio":audio_checks}
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

# ADR017 pointer proof is separate from unchanged facade/cold receipt schemas.
function Get-PointerSourceDefinitions {
 @(
  @{source='tests/cockpit/engine_controls_checks.gd';destination='cockpit_tests/engine_controls_checks.gd'},
  @{source='tests/integration/input/pointer_engine_scene_checks.gd';destination='pointer_scene_tests/pointer_engine_scene_checks.gd'},
  @{source='tests/integration/input/pointer_flight_checks.gd';destination='pointer_scene_tests/pointer_flight_checks.gd'},
  @{source='tests/integration/input/pointer_visual.gd';destination='pointer_scene_tests/pointer_visual.gd'},
  @{source='tests/engine/native-limits.json';destination='pointer_scene_tests/native-limits.json'}
 )
}
function Get-PointerSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(Get-PointerSourceDefinitions|ForEach-Object {
  $file=Join-Path $RepoRoot $_.source
  Assert-PreviewOrdinaryAncestors -Path $file
  $item=Get-Item -Force -LiteralPath $file -ErrorAction Stop
  if($item.PSIsContainer){throw 'Pointer source must be an ordinary file'}
  [pscustomobject]@{source=$_.source;destination=$_.destination;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant()}
 })
}
function Assert-PointerSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-PointerSourceDefinitions)
 if($Groups.Count -ne $definitions.Count){throw 'Complete pointer source roster required'}
 for($i=0;$i -lt $definitions.Count;$i++){
  $file=$Groups[$i];$expected=$definitions[$i]
  if((($file.PSObject.Properties.Name|Sort-Object)-join "`n") -cne "bytes`ndestination`nsha256`nsource" -or $file.source -cne $expected.source -or $file.destination -cne $expected.destination -or ($file.bytes -isnot [int] -and $file.bytes -isnot [long]) -or $file.bytes -le 0 -or $file.sha256 -isnot [string] -or $file.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Pointer source descriptor rejected'}
  $path=Join-Path $Root $(if($Authoring){$file.source}else{$file.destination})
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -Force -LiteralPath $path -ErrorAction Stop
  if($item.PSIsContainer -or $item.Length -ne $file.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $file.sha256){throw 'Pointer source bytes changed'}
 }
 if(-not $Authoring){
  foreach($folder in @('cockpit_tests','pointer_scene_tests')){
   $snapshot=@($Groups|Where-Object {$_.destination.StartsWith($folder+'/')}|ForEach-Object {[pscustomobject]@{path=$_.destination.Substring($folder.Length+1);bytes=$_.bytes;sha256=$_.sha256}}|Sort-Object path)
   Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root $folder) -Snapshot $snapshot -RequiredEntries @($snapshot.path) -AllowGeneratedUIDs:$AllowGeneratedUIDs
  }
 }
}
function Copy-PointerSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-PointerSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 Assert-PreviewOrdinaryAncestors -Path $DestinationRoot
 foreach($folder in @('cockpit_tests','pointer_scene_tests')){if(Test-Path -LiteralPath (Join-Path $DestinationRoot $folder)){throw 'Pointer destinations must be fresh'}}
 foreach($file in $Groups){
  $target=Join-Path $DestinationRoot $file.destination
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
  Copy-Item -LiteralPath (Join-Path $RepoRoot $file.source) -Destination $target
 }
 Assert-PointerSourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-PointerSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
function Get-PointerRuntimeSourceDefinitions {
 @(
  @{source='app/input/input_mapper.gd';destination='input/input_mapper.gd'},
  @{source='app/input/input_preset.gd';destination='input/input_preset.gd'},
  @{source='app/cockpit/engine_controls.gd';destination='cockpit/engine_controls.gd'},
  @{source='app/cockpit/instruments/engine_status.gd';destination='cockpit/instruments/engine_status.gd'},
  @{source='app/simulation/flight_scene.gd';destination='simulation/flight_scene.gd'},
  @{source='app/simulation/session_facade.gd';destination='simulation/session_facade.gd'},
  @{source='tests/input/pointer_engine_checks.gd';destination='input_tests/pointer_engine_checks.gd'}
 )
 Get-PointerSourceDefinitions
 @{source='generated/pointer_checks.gd';destination='pointer_checks.gd'}
 Get-PistonSourceDefinitions|Where-Object {$_.destination.StartsWith('piston-models/')}
}
function Write-PointerCheckHarness {
 param([Parameter(Mandatory)][string]$ProjectRoot)
 $sources=ConvertTo-Json -InputObject @(Get-PointerRuntimeSourceDefinitions|ForEach-Object {,@($_.source,('res://'+$_.destination))}) -Depth 5 -Compress
 [IO.File]::WriteAllText((Join-Path $ProjectRoot 'pointer_checks.gd'),@"
extends Node
var _driver_failures: Array[String]=[]
func _ready() -> void:
 call_deferred("run")
func check(ok: bool,label: String) -> void:
 if not ok: _driver_failures.append(label)
func _output(name: String) -> String:
 return ProjectSettings.globalize_path("res://"+name) if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join(name)
func run() -> void:
 if "--pointer-visual-smoke" in OS.get_cmdline_user_args():
  var visual: Dictionary=await load("res://pointer_scene_tests/pointer_visual.gd").new().run(self)
  print("POINTER_VISUAL_CHECKS "+JSON.stringify({"passed":visual.get("passed",false),"views":visual.get("views",[]).size(),"failures":visual.get("failures",[])}))
  get_tree().quit(0 if visual.get("passed")==true and _driver_failures.is_empty() else 1)
  return
 var groups: Dictionary={}
 groups.mapper=load("res://input_tests/pointer_engine_checks.gd").new().run()
 groups.panel=await load("res://cockpit_tests/engine_controls_checks.gd").new().run(self)
 groups.host=await load("res://pointer_scene_tests/pointer_engine_scene_checks.gd").new().run(self)
 var flight: Dictionary=await load("res://pointer_scene_tests/pointer_flight_checks.gd").new().run(self)
 var trace_path: String=_output("pointer-flight-trace.json")
 var trace: FileAccess=FileAccess.open(trace_path,FileAccess.WRITE)
 if trace==null:
  push_error("Pointer trace could not be persisted")
  get_tree().quit(1)
  return
 trace.store_string(JSON.stringify(flight));trace.close()
 groups.flight={"passed":flight.get("passed",false),"checks":flight.get("checks",0),"failures":flight.get("failures",["flight result absent"]),"scope":flight.get("scope",""),"rows":flight.get("rows",[]).size(),"initialized":flight.get("initialized",false),"native_joined":flight.get("native_joined",false),"audio_joined":flight.get("audio_joined",false),"limits_sha256":flight.get("limits_sha256",""),"first_running_tick":flight.get("first_running_tick",-1),"first_stopped_tick":flight.get("first_stopped_tick",-1),"trace":{"path":"pointer-flight-trace.json","bytes":FileAccess.get_file_as_bytes(trace_path).size(),"sha256":FileAccess.get_sha256(trace_path)}}
 var failures: Array=_driver_failures.duplicate()
 var checks: int=0
 for name in groups:
  var item: Dictionary=groups[name]
  if typeof(item.get("checks"))==TYPE_INT: checks+=item.checks
  if item.get("passed")!=true or int(item.get("checks",0))<=0 or not item.get("failures",["absent"]).is_empty(): failures.append("pointer_"+name+"_failed_or_vacuous")
 var source_files: Dictionary={}
 var source_paths: Array=$sources
 for item in source_paths:
  var raw: PackedByteArray=FileAccess.get_file_as_bytes(item[1])
  source_files[item[0]]={"bytes":raw.size(),"sha256":FileAccess.get_sha256(item[1])}
 var resource_path: String="res://build/native_identity.gd"
 var native_identity: Dictionary={"schema":"PreviewNativeResource/v1","path":"build/native_identity.gd","bytes":FileAccess.get_file_as_bytes(resource_path).size(),"sha256":FileAccess.get_sha256(resource_path)}
 var receipt: Dictionary={"schema":"PointerEngineChecks/v1","passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Actual separately identified pointer mapper/panel/host/native flight checks; original prototype only, no hardware/pilot/GPU or training qualification","groups":groups,"source_files":source_files,"native_identity":native_identity}
 var output: FileAccess=FileAccess.open(_output("pointer-check-receipt.json"),FileAccess.WRITE)
 if output==null:
  push_error("Pointer summary could not be persisted")
  get_tree().quit(1)
  return
 output.store_string(JSON.stringify(receipt));output.close()
 print("POINTER_ENGINE_CHECKS "+str(checks)+" "+str(failures.size()))
 get_tree().quit(0 if failures.is_empty() else 1)
"@)
}
