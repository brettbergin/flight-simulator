#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$testRoot=Join-Path $repo ('.local/simulation-staging-test/'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $testRoot 'source'
New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $source 'session_facade.gd'),'extends RefCounted')
[IO.File]::WriteAllText((Join-Path $source 'render_origin.gd'),'extends RefCounted')
[IO.File]::WriteAllText((Join-Path $source 'nested/original.txt'),'original nested source bytes')
function Must-Reject([scriptblock]$Action,[string]$Label){
 $rejected=$false
 try{& $Action|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Packaging accepted $Label"}
}
$snapshot=@(Get-SimulationSourceSnapshot -SourceRoot $source)
$project=Join-Path $testRoot 'project/simulation'
Copy-SimulationSourceSnapshot -SourceRoot $source -DestinationRoot $project -Snapshot $snapshot
Assert-SimulationSourceSnapshot -SourceRoot $project -Snapshot $snapshot
$authoring=Join-Path $testRoot 'payload/source/whole-flight-preview/simulation'
Copy-SimulationSourceSnapshot -SourceRoot $source -DestinationRoot $authoring -Snapshot $snapshot
if($snapshot.Count -ne 3 -or -not (@($snapshot.path) -ccontains 'nested/original.txt') -or (Get-Content (Join-Path $project 'nested/original.txt') -Raw) -cne 'original nested source bytes'){throw 'Nested resource staging failed'}
[IO.File]::WriteAllText((Join-Path $project 'nested/original.txt'),'tampered nested source bytes')
Must-Reject {Assert-SimulationSourceSnapshot -SourceRoot $project -Snapshot $snapshot} 'staged same-length byte tampering'
$missing=Join-Path $testRoot 'missing'
New-Item -ItemType Directory -Path $missing -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $missing 'session_facade.gd'),'extends RefCounted')
Must-Reject {Get-SimulationSourceSnapshot -SourceRoot $missing} 'missing required render-origin entry point'
[IO.File]::WriteAllText((Join-Path $source 'nested/original.txt'),'source changed during proof')
Must-Reject {Assert-SimulationSourceSnapshot -SourceRoot $source -Snapshot $snapshot} 'concurrent source byte drift'
Must-Reject {Copy-SimulationSourceSnapshot -SourceRoot $source -DestinationRoot (Join-Path $testRoot 'drift-stage') -Snapshot $snapshot} 'drifted source before copying'
[IO.File]::WriteAllText((Join-Path $source 'nested/original.txt'),'original nested source bytes')
[IO.File]::WriteAllText((Join-Path $source 'new-resource.gd'),'extends RefCounted')
Must-Reject {Assert-SimulationSourceSnapshot -SourceRoot $source -Snapshot $snapshot} 'new unbound source resource'
Must-Reject {Copy-SimulationSourceSnapshot -SourceRoot $authoring -DestinationRoot $authoring -Snapshot $snapshot} 'nonfresh destination'
$driver=Join-Path $testRoot 'driver'
New-Item -ItemType Directory -Path $driver -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $driver 'facade_checks.gd'),'extends RefCounted')
[IO.File]::WriteAllText((Join-Path $driver 'independent-reference.json'),'{}')
$driverEntries=@('facade_checks.gd','independent-reference.json')
$driverSnapshot=@(Get-SimulationSourceSnapshot -SourceRoot $driver -RequiredEntries $driverEntries)
Copy-SimulationSourceSnapshot -SourceRoot $driver -DestinationRoot (Join-Path $testRoot 'sim_loop_tests') -Snapshot $driverSnapshot -RequiredEntries $driverEntries
Write-Output 'PASS simulation recursive project/corresponding-source staging; missing resource, byte drift, set drift and staging negatives.'
$settings=Join-Path $testRoot 'project.godot'
[IO.File]::WriteAllText($settings,'[application]'+"`n"+'run/main_scene="res://interactive/preview.tscn"')
Set-SimulationMainScene -ProjectFile $settings
if([IO.File]::ReadAllText($settings) -notmatch 'res://simulation/flight_scene.tscn'){throw 'Normal runtime facade main scene not selected'}
Must-Reject {Set-SimulationMainScene -ProjectFile $settings} 'unexpected or already overridden main scene'
[IO.File]::WriteAllText($settings,'[application]')
Must-Reject {Set-SimulationMainScene -ProjectFile $settings} 'missing main scene'
[IO.File]::WriteAllText($settings,'run/main_scene="res://interactive/preview.tscn"'+"`n"+'run/main_scene="res://interactive/preview.tscn"')
Must-Reject {Set-SimulationMainScene -ProjectFile $settings} 'duplicate main scene'
Write-Output 'PASS staged normal runtime selection and missing/duplicate/unexpected settings negatives.'
$uidStage=Join-Path $testRoot 'uid-stage'
Copy-SimulationSourceSnapshot -SourceRoot $authoring -DestinationRoot $uidStage -Snapshot $snapshot
[IO.File]::WriteAllText((Join-Path $uidStage 'session_facade.gd.uid'),"uid://c6ia3qumfvccx`n")
Must-Reject {Assert-SimulationSourceSnapshot $uidStage $snapshot} 'import metadata in an exact source copy'
Assert-SimulationSourceSnapshot $uidStage $snapshot -AllowGeneratedUIDs
[IO.File]::WriteAllText((Join-Path $uidStage 'session_facade.gd.uid'),'unrelated arbitrary bytes')
Must-Reject {Assert-SimulationSourceSnapshot $uidStage $snapshot -AllowGeneratedUIDs} 'malformed generated UID metadata'
[IO.File]::WriteAllText((Join-Path $uidStage 'session_facade.gd.uid'),"uid://c6ia3qumfvccx`n")
[IO.File]::WriteAllText((Join-Path $uidStage 'orphan.gd.uid'),"uid://c6ia3qumfvccx`n")
Must-Reject {Assert-SimulationSourceSnapshot $uidStage $snapshot -AllowGeneratedUIDs} 'UID metadata without a bound script'
$uidCleanStage=Join-Path $testRoot 'uid-clean-stage'
Copy-SimulationSourceSnapshot -SourceRoot $authoring -DestinationRoot $uidCleanStage -Snapshot $snapshot
[IO.File]::WriteAllText((Join-Path $uidCleanStage 'session_facade.gd.uid'),"uid://c6ia3qumfvccx`n")
[IO.File]::WriteAllText((Join-Path $uidCleanStage 'session_facade.gd'),'tampered script')
Must-Reject {Assert-SimulationSourceSnapshot $uidCleanStage $snapshot -AllowGeneratedUIDs} 'changed authored script with valid UID metadata'
Write-Output 'PASS destination-only generated UID sidecars; exact-source, malformed/orphan UID and script-tampering negatives.'
