#Requires -Version 7.0
param([string]$Python='python')
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

# Exercise recursive landmark staging without loading Godot or native code.
$freeflightFixture=Join-Path $testRoot 'freeflight-repo'
foreach($entry in @('app/ui/freeflight/landmark_board.gd','app/ui/freeflight/nested/resource.txt','tests/ui/freeflight/landmark_checks.gd','tests/ui/freeflight/scene_checks.gd','tests/ui/freeflight/reference.json','tests/ui/freeflight/reference-generator.py')){
 $file=Join-Path $freeflightFixture $entry
 New-Item -ItemType Directory -Path (Split-Path $file) -Force|Out-Null
 [IO.File]::WriteAllText($file,'bound fixture '+$entry)
}
$freeflightGroups=@(Get-FreeflightSourceGroups $freeflightFixture)
$freeflightProject=Join-Path $testRoot 'freeflight-project'
$freeflightSource=Join-Path $testRoot 'freeflight-source'
Copy-FreeflightSourceGroups $freeflightFixture $freeflightProject $freeflightGroups
Copy-FreeflightSourceGroups $freeflightFixture $freeflightSource $freeflightGroups
Assert-FreeflightSourceGroups $freeflightFixture $freeflightGroups -Authoring
Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups
Assert-FreeflightSourceGroups $freeflightSource $freeflightGroups
if(-not (Test-Path -LiteralPath (Join-Path $freeflightProject 'ui/freeflight/nested/resource.txt')) -or -not (Test-Path -LiteralPath (Join-Path $freeflightSource 'freeflight_tests/reference-generator.py'))){throw 'Freeflight recursive resources/reference missing'}
$referenceFile=Join-Path $freeflightProject 'freeflight_tests/reference.json'
$referenceOriginal=[IO.File]::ReadAllText($referenceFile)
[IO.File]::WriteAllText($referenceFile,'tampered reference')
Must-Reject {Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups} 'changed landmark reference'
[IO.File]::WriteAllText($referenceFile,$referenceOriginal)
$sceneFile=Join-Path $freeflightFixture 'tests/ui/freeflight/scene_checks.gd'
$sceneOriginal=[IO.File]::ReadAllText($sceneFile)
Remove-Item -LiteralPath $sceneFile
Must-Reject {Get-FreeflightSourceGroups $freeflightFixture} 'missing actual landmark scene driver'
[IO.File]::WriteAllText($sceneFile,$sceneOriginal)
$extraFile=Join-Path $freeflightProject 'ui/freeflight/unbound.txt'
[IO.File]::WriteAllText($extraFile,'unbound')
Must-Reject {Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups} 'unbound landmark resource'
Remove-Item -LiteralPath $extraFile
$freeflightUID=Join-Path $freeflightProject 'ui/freeflight/landmark_board.gd.uid'
[IO.File]::WriteAllText($freeflightUID,"uid://c6ia3qumfvccx`n")
Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups -AllowGeneratedUIDs
Must-Reject {Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups} 'landmark import UID in exact corresponding source'
[IO.File]::WriteAllText($freeflightUID,'invalid')
Must-Reject {Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups -AllowGeneratedUIDs} 'malformed landmark UID'
[IO.File]::WriteAllText($freeflightUID,"uid://c6ia3qumfvccx`n")
$orphan=Join-Path $freeflightProject 'freeflight_tests/orphan.gd.uid'
[IO.File]::WriteAllText($orphan,"uid://c6ia3qumfvccx`n")
Must-Reject {Assert-FreeflightSourceGroups $freeflightProject $freeflightGroups -AllowGeneratedUIDs} 'orphan landmark driver UID'
Write-Output 'PASS landmark recursive source/reference staging and changed/missing/unbound/UID negatives.'

# Closed wind groups must remain nonempty/distinct and carry their actual entrypoints.
$windFixture=Join-Path $testRoot 'wind-repo'
foreach($definition in Get-WindSourceDefinitions){
 foreach($entry in @($definition.required)+@('nested/original.txt')){
  $file=Join-Path $windFixture ($definition.source+'/'+$entry)
  New-Item -ItemType Directory -Path (Split-Path $file) -Force|Out-Null
  [IO.File]::WriteAllText($file,'bound wind fixture '+$definition.source+'/'+$entry)
 }
}
$windGroups=@(Get-WindSourceGroups $windFixture)
$windProject=Join-Path $testRoot 'wind-project'
$windSource=Join-Path $testRoot 'wind-source'
Copy-WindSourceGroups $windFixture $windProject $windGroups
Copy-WindSourceGroups $windFixture $windSource $windGroups
Assert-WindSourceGroups $windFixture $windGroups -Authoring
Assert-WindSourceGroups $windProject $windGroups
Assert-WindSourceGroups $windSource $windGroups
if(-not (Test-Path -LiteralPath (Join-Path $windSource 'wind_scene_tests/visual_checks.gd')) -or -not (Test-Path -LiteralPath (Join-Path $windProject 'world/wind/nested/original.txt'))){throw 'Wind visual/nested corresponding-source missing'}
Must-Reject {Copy-WindSourceGroups $windFixture (Join-Path $testRoot 'wind-empty') @()} 'missing all wind groups'
Must-Reject {Assert-WindSourceGroups $windProject @($windGroups[0],$windGroups[1],$windGroups[2])} 'missing wind scene group'
foreach($field in @('snapshot','required')){
 $empty=@($windGroups|ForEach-Object {$copy=$_.Clone();$copy[$field]=@();$copy})
 $fresh=Join-Path $testRoot ('wind-empty-'+$field)
 Must-Reject {Copy-WindSourceGroups $windFixture $fresh $empty} ('empty wind '+$field+' before copy')
 if(Test-Path -LiteralPath $fresh){throw 'Wind invalid descriptor created a destination'}
 Must-Reject {Assert-WindSourceGroups $windProject $empty} ('empty wind '+$field+' assertion')
}
$duplicated=@($windGroups[0],$windGroups[1],$windGroups[2],$windGroups[2])
Must-Reject {Copy-WindSourceGroups $windFixture (Join-Path $testRoot 'wind-duplicate') $duplicated} 'duplicated wind group before copy'
Must-Reject {Assert-WindSourceGroups $windProject $duplicated} 'duplicated wind group assertion'
foreach($field in @('source','destination','required')){
 $changed=@($windGroups|ForEach-Object {$_.Clone()})
 if($field -eq 'required'){$changed[3][$field]=@('scene_checks.gd')}else{$changed[3][$field]='unknown/alias'}
 Must-Reject {Assert-WindSourceGroups $windProject $changed} ('unknown/omitted wind '+$field+' roster')
}
$windVisual=Join-Path $windFixture 'tests/integration/wind/visual_checks.gd'
$visualBytes=[IO.File]::ReadAllBytes($windVisual)
Remove-Item -LiteralPath $windVisual
Must-Reject {Get-WindSourceGroups $windFixture} 'missing mandatory wind visual driver'
[IO.File]::WriteAllBytes($windVisual,$visualBytes)
$windBound=Join-Path $windProject 'wind_tests/reference/expected-v1.json'
$windBoundBytes=[IO.File]::ReadAllBytes($windBound)
[IO.File]::WriteAllText($windBound,'tampered')
Must-Reject {Assert-WindSourceGroups $windProject $windGroups} 'changed wind reference bytes'
[IO.File]::WriteAllBytes($windBound,$windBoundBytes)
$windUID=Join-Path $windProject 'world/wind/wind_cue.gd.uid'
[IO.File]::WriteAllText($windUID,"uid://c6ia3qumfvccx`n")
Assert-WindSourceGroups $windProject $windGroups -AllowGeneratedUIDs
Must-Reject {Assert-WindSourceGroups $windProject $windGroups} 'wind UID in exact corresponding source'
[IO.File]::WriteAllText($windUID,'malformed UID')
Must-Reject {Assert-WindSourceGroups $windProject $windGroups -AllowGeneratedUIDs} 'malformed wind generated UID'
[IO.File]::WriteAllText($windUID,"uid://c6ia3qumfvccx`n")
[IO.File]::WriteAllText((Join-Path $windProject 'wind_scene_tests/orphan.gd.uid'),"uid://c6ia3qumfvccx`n")
Must-Reject {Assert-WindSourceGroups $windProject $windGroups -AllowGeneratedUIDs} 'orphan wind driver UID'
Write-Output 'PASS closed four wind groups; recursive source/visual binding and empty/duplicate/alias/missing/drift/UID negatives.'

# Real ratified public bytes are copied into a private fixture. Guard failures
# use an intentionally nonexistent executable: no unqualified generator runs.
$windReferences=Join-Path $testRoot 'wind-references'
$windReferenceRoot=Join-Path $windReferences 'tests/world/wind'
New-Item -ItemType Directory -Path $windReferenceRoot -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'tests/world/wind/reference') -Destination $windReferenceRoot -Recurse
$bindingPath=Join-Path $windReferenceRoot 'ratification-v1.json'
Copy-Item -LiteralPath (Join-Path $repo 'tests/world/wind/ratification-v1.json') -Destination $bindingPath
$bindingOriginal=[IO.File]::ReadAllBytes($bindingPath)
function Write-WindBinding($Binding){
 [IO.File]::WriteAllText($bindingPath,($Binding|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
function Must-RejectWindReference([string]$ExpectedMessage,[string]$Label){
 $observed=''
 try{Assert-WindReferences $windReferences 'NONEXISTENT-WIND-GENERATOR-EXECUTABLE'}catch{$observed=$_.Exception.Message}
 if($observed -cne $ExpectedMessage){throw "Wind guard failed to reject $Label before generator execution: $observed"}
}
foreach($mutation in @('empty','omitted','duplicate','changed-pin','escaped-path','extra-field','float-bytes')){
 $binding=[Text.Encoding]::UTF8.GetString($bindingOriginal)|ConvertFrom-Json
 if($mutation -eq 'empty'){$binding.published_files=@()}
 elseif($mutation -eq 'omitted'){$binding.published_files=@($binding.published_files|Where-Object path -ne 'reference/generate.py')}
 elseif($mutation -eq 'duplicate'){$binding.published_files[1]=$binding.published_files[0]}
 elseif($mutation -eq 'changed-pin'){$binding.published_files[1].sha256='a'*64}
 elseif($mutation -eq 'escaped-path'){$binding.published_files[1].path='../alternate.py'}
 elseif($mutation -eq 'extra-field'){$binding.published_files[1]|Add-Member -NotePropertyName other -NotePropertyValue 'unknown'}
 else{$binding.published_files[1].bytes=[double]9621}
 Write-WindBinding $binding
 $message=if($mutation -in @('empty','omitted')){'Frozen wind reference roster incomplete'}else{'Frozen wind reference roster differs from accepted pins'}
 Must-RejectWindReference $message ('reference roster '+$mutation)
}
[IO.File]::WriteAllBytes($bindingPath,$bindingOriginal)
foreach($entry in @('reference/generate.py','reference/expected-v1.json')){
 $file=Join-Path $windReferenceRoot $entry;$original=[IO.File]::ReadAllBytes($file)
 [IO.File]::WriteAllBytes($file,([byte[]]@($original[0..($original.Length-2)]+[byte]32)))
 Must-RejectWindReference 'Frozen wind reference bytes changed' ('changed same-length '+$entry)
 [IO.File]::WriteAllBytes($file,$original)
}
$binding=[Text.Encoding]::UTF8.GetString($bindingOriginal)|ConvertFrom-Json
$binding.original_ratification_sha256='a'*64
Write-WindBinding $binding
Must-RejectWindReference 'Accepted wind ratification required' 'wrong preconsumer ratification binding'
[IO.File]::WriteAllBytes($bindingPath,$bindingOriginal)
Assert-WindReferences $windReferences $Python
foreach($file in Get-ChildItem -LiteralPath $windReferenceRoot -Recurse -File){
 $relative=[IO.Path]::GetRelativePath($windReferenceRoot,$file.FullName)
 if((Get-FileHash -LiteralPath $file.FullName).Hash -cne (Get-FileHash -LiteralPath (Join-Path $repo ('tests/world/wind/'+$relative))).Hash){throw 'Readonly wind reference regeneration changed bytes'}
}
Write-Output 'PASS fixed accepted reference roster/hash/size/ratification admission before read-only generator execution.'
# All observed producer/UI/fixtures are mandatory, recursive and independently
# bound; these staging checks do not load Godot or execute any native code.
$observedFixture=Join-Path $testRoot 'observed-repo'
$observedEntries=@('app/replay/observed/recorder.gd','app/replay/observed/review.gd','app/replay/observed/tick_math.gd','app/replay/observed/values.gd','app/replay/observed/nested/original.txt','app/ui/debrief/observed/panel.gd','tests/debrief/observed/recorder_checks.gd','tests/debrief/observed/scene_checks.gd','tests/debrief/observed/expected-v1.json','tests/debrief/observed/generate.py','tests/debrief/observed/preparation-binding-v2.json','tests/debrief/observed/root-ratification-v1.json','tests/debrief/observed/README.md','tests/debrief/observed/.gitattributes')
$observedEntries+=@('app/replay/observed_archive/codec.gd','app/replay/observed_archive/strict_json.gd','app/replay/observed_archive/files.gd','app/replay/observed_archive/windows_io.ps1','tests/debrief/observed_archive/archive_checks.gd','tests/debrief/observed_archive/file_checks.gd','tests/debrief/observed_archive/scene_checks.gd','tests/debrief/observed_archive/visual_checks.gd','tests/debrief/observed_archive/windows_fixture.ps1','tests/debrief/observed_archive/generate.py','tests/debrief/observed_archive/source-binding-v1.json','tests/debrief/observed_archive/root-ratification-v1.json','tests/debrief/observed_archive/README.md','tests/debrief/observed_archive/.gitattributes','tests/debrief/observed_archive/reference/expected-text-v1.json','tests/debrief/observed_archive/reference/expected-binary64-v1.json')
foreach($entry in $observedEntries){
 $file=Join-Path $observedFixture $entry
 New-Item -ItemType Directory -Path (Split-Path $file) -Force|Out-Null
 [IO.File]::WriteAllText($file,'bound observed fixture '+$entry)
}
$observedGroups=@(Get-ObservedReviewSourceGroups $observedFixture)
$observedProject=Join-Path $testRoot 'observed-project'
$observedSource=Join-Path $testRoot 'observed-source'
Copy-ObservedReviewSourceGroups $observedFixture $observedProject $observedGroups
Copy-ObservedReviewSourceGroups $observedFixture $observedSource $observedGroups
Assert-ObservedReviewSourceGroups $observedFixture $observedGroups -Authoring
Assert-ObservedReviewSourceGroups $observedProject $observedGroups
Assert-ObservedReviewSourceGroups $observedSource $observedGroups
if(-not (Test-Path -LiteralPath (Join-Path $observedProject 'replay/observed/nested/original.txt')) -or -not (Test-Path -LiteralPath (Join-Path $observedSource 'observed_tests/preparation-binding-v2.json'))){throw 'Observed nested source/frozen bindings missing'}
Must-Reject {Copy-ObservedReviewSourceGroups $observedFixture (Join-Path $testRoot 'missing-observed') @()} 'empty observed source groups'
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject @($observedGroups[0],$observedGroups[1])} 'missing observed fixture group'
$emptyGroups=@($observedGroups|ForEach-Object {@{source=$_.source;destination=$_.destination;required=$_.required;snapshot=@()}})
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject $emptyGroups} 'empty observed snapshots'
$bound=Join-Path $observedProject 'observed_tests/expected-v1.json'
$boundBytes=[IO.File]::ReadAllBytes($bound)
[IO.File]::WriteAllText($bound,'tampered expected values')
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject $observedGroups} 'changed observed expected bytes'
[IO.File]::WriteAllBytes($bound,$boundBytes)
$driver=Join-Path $observedFixture 'tests/debrief/observed/scene_checks.gd'
$driverBytes=[IO.File]::ReadAllBytes($driver)
Remove-Item -LiteralPath $driver
Must-Reject {Get-ObservedReviewSourceGroups $observedFixture} 'missing actual observed scene driver'
[IO.File]::WriteAllBytes($driver,$driverBytes)
$uid=Join-Path $observedProject 'replay/observed/recorder.gd.uid'
[IO.File]::WriteAllText($uid,"uid://c6ia3qumfvccx`n")
Assert-ObservedReviewSourceGroups $observedProject $observedGroups -AllowGeneratedUIDs
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject $observedGroups} 'generated UID in exact observed source'
[IO.File]::WriteAllText($uid,'invalid UID')
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject $observedGroups -AllowGeneratedUIDs} 'malformed observed generated UID'
[IO.File]::WriteAllText($uid,"uid://c6ia3qumfvccx`n")
[IO.File]::WriteAllText((Join-Path $observedProject 'observed_tests/orphan.gd.uid'),"uid://c6ia3qumfvccx`n")
Must-Reject {Assert-ObservedReviewSourceGroups $observedProject $observedGroups -AllowGeneratedUIDs} 'orphan observed test UID'
Write-Output 'PASS observed recursive source/UI/reference binding and missing/empty/drift/UID negatives.'

# A passing host marker cannot hide skipped or vacuous observed checks.
$receipt=[pscustomobject]@{schema_version=1;scope='fixture';passed=$true;checks=1;failures=@();facade=$null;origin=$null;participants=$null;wire=$null;scene=$null;input=$null;input_scene=$null;instruments=$null;cockpit=$null;freeflight=$null;observed=[pscustomobject]@{recorder=[pscustomobject]@{passed=$true;checks=1;failures=@();reference_cases=42;reference_sha256='a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844';scope='pure fixture'};scene=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='scene fixture'}}}
$receipt|Add-Member -NotePropertyName observed_archive -NotePropertyValue ([pscustomobject]@{codec=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='codec fixture';reference_cases=40;reference_sha256='961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e';binary64_cases=26;binary64_sha256='406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8'};files=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='files fixture'};scene=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='scene fixture'}})
function New-WindReceiptFixture {
 [pscustomobject]@{
  bridge=[pscustomobject]@{passed=$true;checks=1;failures=@()}
  cue=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='pure fixture';reference_cases=22;runway_expectations=8;reference_sha256='7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3'}
  scene=[pscustomobject]@{passed=$true;checks=1;failures=@();scope='actual scene fixture'}
 }
}
$receipt|Add-Member -NotePropertyName wind -NotePropertyValue (New-WindReceiptFixture)
Assert-PreviewFacadeReceipt $receipt
foreach($name in @('bridge','cue','scene')){
 foreach($wrong in @(0,-1,'1',[double]1)){
  $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name.checks=$wrong
  Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('zero/malformed wind '+$name+' checks')
 }
 foreach($wrong in @($false,'true')){
  $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name.passed=$wrong
  Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('failed/coerced wind '+$name+' marker')
 }
 $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name.failures=@('actual_failure')
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('failed wind '+$name+' assertions')
 $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name.failures=$null
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('null wind '+$name+' failure array')
 $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name|Add-Member -NotePropertyName other -NotePropertyValue $true
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('extra wind '+$name+' receipt key')
 $receipt.wind=New-WindReceiptFixture;$receipt.wind.PSObject.Properties.Remove($name)
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('missing wind '+$name+' result')
}
foreach($name in @('cue','scene')){
 foreach($wrong in @('',1,('x'*1025))){
  $receipt.wind=New-WindReceiptFixture;$receipt.wind.$name.scope=$wrong
  Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('malformed wind '+$name+' scope')
 }
}
foreach($field in @('reference_cases','runway_expectations')){
 $value=if($field -eq 'reference_cases'){22}else{8}
 foreach($wrong in @(($value-1),[double]$value,([string]$value))){
  $receipt.wind=New-WindReceiptFixture;$receipt.wind.cue.$field=$wrong
  Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('wind reference count/type '+$field)
 }
}
$receipt.wind=New-WindReceiptFixture;$receipt.wind.cue.reference_sha256='a'*64
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'wind wrong frozen reference identity'
$receipt.wind=[pscustomobject]@{}
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'empty wind result group'
$receipt.PSObject.Properties.Remove('wind')
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'missing wind top-level group'
$receipt|Add-Member -NotePropertyName wind -NotePropertyValue (New-WindReceiptFixture)
Assert-PreviewFacadeReceipt $receipt
Write-Output 'PASS closed mandatory wind cue/bridge/scene receipts and nonvacuous/failed/type/count/reference negatives.'
foreach($name in @('codec','files','scene')){
 $receipt.observed_archive.$name.checks=0
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('zero archive '+$name+' checks')
 $receipt.observed_archive.$name.checks=1
 $receipt.observed_archive.$name.passed='true'
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('string archive '+$name+' passing marker')
 $receipt.observed_archive.$name.passed=$true
 $receipt.observed_archive.$name.failures=@('failed')
 Must-Reject {Assert-PreviewFacadeReceipt $receipt} ('failed archive '+$name+' result')
 $receipt.observed_archive.$name.failures=@()
}
$receipt.observed_archive.codec.binary64_cases=25
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'archive binary64 case count drift'
$receipt.observed_archive.codec.binary64_cases=26
$receipt.observed_archive.codec.reference_sha256='a'*64
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'archive reference identity drift'
$receipt.observed_archive.codec.reference_sha256='961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e'
$fullArchive=$receipt.observed_archive
$receipt.observed_archive=[pscustomobject]@{}
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'missing archive children'
$receipt.observed_archive=$fullArchive
$receipt.observed.scene.checks=0
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'zero actual observed scene checks'
$receipt.observed.scene.checks=1
$receipt.observed.scene.passed='true'
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'String passing observed marker'
$receipt.observed.scene.passed=$true
$receipt.observed.scene.failures=@('actual_fixture_failure')
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'observed scene failed assertions'
$receipt.observed.scene.failures=@()
$receipt.observed.recorder.reference_sha256='a'*64
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'changed observed frozen reference identity'
$receipt.observed.recorder.reference_sha256='a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844'
$receipt.observed=[pscustomobject]@{}
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'empty observed result group'
$receipt.PSObject.Properties.Remove('observed')
Must-Reject {Assert-PreviewFacadeReceipt $receipt} 'missing observed result group'
Write-Output 'PASS fixed mandatory observed receipt groups and vacuous/failed/malformed controls.'

# Synthetic Windows/Linux v2 qualifier and staging negatives; no real build.
& $Python -B (Join-Path $PSScriptRoot 'test_native_identity.py')
if($LASTEXITCODE -ne 0){throw 'Independent ADR016 identity fixtures failed'}
# Separately bound generated resource, exact set, narrow UID and runtime receipt.
$identityBuild=Join-Path $testRoot 'v2-build'
$identityStage=Join-Path $testRoot 'v2-project'
New-Item -ItemType Directory -Path $identityBuild,$identityStage|Out-Null
$identityRaw='extends RefCounted'+"`n"+'const SCHEMA: String = "flight-native-build-identity-v1"'+"`n"+'const SOURCE_VARIANT: String = "jsbsim-1.3.1-upstream"'+"`n"+'const BACKEND_IDENTITY_SHA256: String = "'+('a'*64)+'"'+"`n"+'const BUILD_CONTROL_SHA256: String = "'+('b'*64)+'"'+"`n"+'const SOURCE_FINGERPRINT: String = "'+('c'*64)+'"'+"`n"
[IO.File]::WriteAllText((Join-Path $identityBuild 'native-identity.gd'),$identityRaw,[Text.UTF8Encoding]::new($false))
$identity=[pscustomobject]@{schema='PreviewNativeBuildIdentity/v2';root=$identityBuild;resource=[pscustomobject]@{build_path='native-identity.gd';staged_path='build/native_identity.gd';bytes=[Text.Encoding]::UTF8.GetByteCount($identityRaw);sha256=(Get-FileHash (Join-Path $identityBuild 'native-identity.gd')).Hash.ToLowerInvariant()}}
Copy-PreviewNativeIdentityResource $identity $identityStage
Assert-PreviewNativeIdentityResource $identity $identityStage
Must-Reject {Copy-PreviewNativeIdentityResource $identity $identityStage} 'reuse generated resource directory'
$runtime=[pscustomobject]@{schema='PreviewNativeResource/v1';path='build/native_identity.gd';bytes=$identity.resource.bytes;sha256=$identity.resource.sha256}
Assert-PreviewNativeResourceReceipt $runtime $identity
$runtime.bytes=$true
Must-Reject {Assert-PreviewNativeResourceReceipt $runtime $identity} 'boolean resource byte count'
$runtime.bytes=$identity.resource.bytes
$runtime.sha256='d'*64
Must-Reject {Assert-PreviewNativeResourceReceipt $runtime $identity} 'wrong runtime resource hash'
$uid=Join-Path $identityStage 'build/native_identity.gd.uid'
[IO.File]::WriteAllText($uid,"uid://c6ia3qumfvccx`n")
Assert-PreviewNativeIdentityResource $identity $identityStage -AllowGeneratedUIDs
Must-Reject {Assert-PreviewNativeIdentityResource $identity $identityStage} 'UID in exact corresponding source'
[IO.File]::WriteAllText($uid,'arbitrary source')
Must-Reject {Assert-PreviewNativeIdentityResource $identity $identityStage -AllowGeneratedUIDs} 'unbound generated UID'
Remove-Item -LiteralPath $uid
[IO.File]::WriteAllText((Join-Path $identityStage 'build/extra.gd'),'extra resource')
Must-Reject {Assert-PreviewNativeIdentityResource $identity $identityStage} 'extra generated resource'
Remove-Item -LiteralPath (Join-Path $identityStage 'build/extra.gd')
[IO.File]::WriteAllText((Join-Path $identityStage 'build/native_identity.gd'),'changed')
Must-Reject {Assert-PreviewNativeIdentityResource $identity $identityStage} 'changed generated resource'
Write-Output 'PASS separately bound generated resource staging and exact-byte/set/receipt/UID negatives.'

$runnerText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run.ps1'))
if($runnerText -notmatch 'exclude_filter="[^"\r\n]*landmark\*\.png,landmark\*-receipt\.json,observed\*\.png,observed\*-receipt\.json,wind\*\.png,wind\*-receipt\.json"'){throw 'Landmark/observed/wind observer output must be excluded from PCK authoring'}
Write-Output 'PASS bounded landmark/observed/wind visual observer output exclusion; source/reference groups remain exact.'
