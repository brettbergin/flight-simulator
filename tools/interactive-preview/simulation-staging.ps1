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
  @{source='tests/debrief/observed';destination='observed_tests';required=@('recorder_checks.gd','scene_checks.gd','expected-v1.json','generate.py','preparation-binding-v2.json','root-ratification-v1.json','README.md','.gitattributes')},
  @{source='app/replay/observed_archive';destination='replay/observed_archive';required=@('codec.gd','strict_json.gd','files.gd','windows_io.ps1')},
  @{source='tests/debrief/observed_archive';destination='observed_archive_tests';required=@('archive_checks.gd','file_checks.gd','scene_checks.gd','visual_checks.gd','windows_fixture.ps1','generate.py','source-binding-v1.json','root-ratification-v1.json','README.md','.gitattributes','reference/expected-text-v1.json','reference/expected-binary64-v1.json')}
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
function Assert-PreviewFacadeReceipt {
 param([Parameter(Mandatory)]$Receipt)
 $keys=@('schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind')
 if((($Receipt.PSObject.Properties.Name|Sort-Object) -join "`n") -cne (($keys|Sort-Object) -join "`n")){throw 'Facade receipt exact shape rejected'}
 if(($Receipt.schema_version -isnot [long] -and $Receipt.schema_version -isnot [int]) -or $Receipt.schema_version -ne 1 -or $Receipt.scope -isnot [string] -or [string]::IsNullOrWhiteSpace($Receipt.scope) -or $Receipt.scope.Length -gt 1024 -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [long] -and $Receipt.checks -isnot [int]) -or $Receipt.checks -le 0 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0){throw 'Facade receipt must contain actual passing checks'}
 if((($Receipt.observed.PSObject.Properties.Name|Sort-Object) -join "`n") -cne "recorder`nscene"){throw 'Both observed recorder and scene results are mandatory'}
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
# ADR016: build-side expectation qualification, never native self-report trust.
function Get-PreviewNativeBuildIdentity {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$NativeBuildRoot,[string]$Python='python')
 $raw=& $Python -B (Join-Path $PSScriptRoot 'native-identity.py') --repository-root $RepoRoot --build-root $NativeBuildRoot
 if($LASTEXITCODE -ne 0){throw 'Independent selected native build/resource qualification rejected'}
 $raw | ConvertFrom-Json -ErrorAction Stop
}
function Assert-PreviewOrdinaryAncestors {
 param([Parameter(Mandatory)][string]$Path)
 $item=Get-Item -LiteralPath $Path -ErrorAction Stop
 while($null -ne $item){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Generated resource path contains reparse point'}
  $parent=Split-Path -Parent $item.FullName
  if([string]::IsNullOrEmpty($parent) -or $parent -ceq $item.FullName){break}
  $item=Get-Item -LiteralPath $parent -ErrorAction Stop
 }
}
function Assert-PreviewNativeIdentityResource {
 param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][string]$DestinationRoot,[switch]$AllowGeneratedUIDs)
 if($Identity.schema -cne 'PreviewNativeBuildIdentity/v2' -or $Identity.resource.build_path -cne 'native-identity.gd' -or $Identity.resource.staged_path -cne 'build/native_identity.gd' -or
    ($Identity.resource.bytes -isnot [int] -and $Identity.resource.bytes -isnot [long]) -or $Identity.resource.bytes -lt 0 -or
    $Identity.resource.sha256 -isnot [string] -or $Identity.resource.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Generated resource declaration rejected'}
 Assert-PreviewOrdinaryAncestors -Path $DestinationRoot
 $root=Get-Item -LiteralPath $DestinationRoot -ErrorAction Stop
 $folder=Get-Item -LiteralPath (Join-Path $root.FullName 'build') -ErrorAction Stop
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
 $resource=Get-Item -LiteralPath (Join-Path $folder.FullName 'native_identity.gd') -ErrorAction Stop
 if($resource.Length -ne $Identity.resource.bytes -or (Get-FileHash -LiteralPath $resource.FullName).Hash.ToLowerInvariant() -cne $Identity.resource.sha256){throw 'Generated resource bytes changed'}
}
function Copy-PreviewNativeIdentityResource {
 param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][string]$DestinationRoot)
 $root=Get-Item -LiteralPath $DestinationRoot -ErrorAction Stop
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
func stage(boundary: String, name: String) -> void:
 print("PROOF_STAGE "+boundary+" "+name+" ms="+str(Time.get_ticks_msec()))
func execute() -> void:
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
 for folder in ["res://simulation","res://sim_loop_tests","res://interactive","res://input","res://ui/controls","res://input_tests","res://cockpit/instruments","res://instrument_tests","res://ui/freeflight","res://freeflight_tests","res://replay/observed","res://ui/debrief/observed","res://observed_tests","res://replay/observed_archive","res://observed_archive_tests","res://world/wind","res://ui/wind","res://wind_tests","res://wind_scene_tests"]:
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
 var cockpit_checks: Dictionary={}
 for name in ["adapter","scan","scene"]:
  var prior_failures: int=failures.size()
  stage("begin","cockpit."+name)
  var result: Dictionary=await load("res://instrument_tests/"+name+"_checks.gd").new().run(self)
  stage("end","cockpit."+name)
  check(failures.size()==prior_failures and result.get("passed",false) and result.get("checks",0)>0 and result.get("failures",["missing"]).is_empty(),"actual_cockpit_"+name+"_checks")
  cockpit_checks[name]=result
 var freeflight_checks: Dictionary={}
 for item in [{"name":"geometry","script":"landmark_checks.gd"},{"name":"scene","script":"scene_checks.gd"}]:
  var before: int=failures.size()
  stage("begin","freeflight."+item.name)
  var result: Dictionary=await load("res://freeflight_tests/"+item.script).new().run(self)
  stage("end","freeflight."+item.name)
  check(failures.size()==before and result.get("passed",false) and result.get("checks",0)>0 and result.get("failures",["missing"]).is_empty(),"actual_freeflight_"+item.name+"_checks")
  freeflight_checks[item.name]=result
 var observed_checks: Dictionary={}
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
 var report: Dictionary={"schema_version":1,"scope":"Headless actual-native facade and synthetic wire/render fixtures; GPU and pilot qualification separate","passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"facade":facade,"origin":origin,"participants":participants,"wire":wire,"scene":scene,"input":input,"input_scene":input_scene,"instruments":instruments,"cockpit":cockpit_checks,"freeflight":freeflight_checks,"observed":observed_checks,"observed_archive":archive_checks,"wind":wind_checks}
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
