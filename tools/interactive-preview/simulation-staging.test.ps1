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
Assert-PreviewFacadeReceipt $receipt
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

# A declared native build is admitted from its exact closed source set, facade
# pin and compiler definition; no fixture executes the fake binary.
$identityRepo=Join-Path $testRoot 'identity-repo'
$identityBuild=Join-Path $testRoot 'identity-build'
$identityPaths=@('native/fdm_jsbsim/interactive/src/session.cpp','native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp','native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp','tests/interactive/native.cpp','tests/interactive/negatives.hpp','native/fdm_jsbsim/interactive/src/model-pins.hpp')
$identityClosure=''
foreach($entry in $identityPaths){
 $file=Join-Path $identityRepo $entry
 New-Item -ItemType Directory -Path (Split-Path $file) -Force|Out-Null
 $body='bound source '+$entry+"`r`n"
 [IO.File]::WriteAllText($file,$body)
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($body.Replace("`r`n","`n")))).ToLowerInvariant()
 $identityClosure+=$entry+':'+$hash+"`n"
}
$identityHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identityClosure))).ToLowerInvariant()
$cmakeFile=Join-Path $identityRepo 'native/fdm_jsbsim/interactive/CMakeLists.txt'
$cmakeOriginal='set(INTERACTIVE_SOURCE_PATHS '+($identityPaths -join "`n")+")`n"
[IO.File]::WriteAllText($cmakeFile,$cmakeOriginal)
New-Item -ItemType Directory -Path (Join-Path $identityRepo 'app/simulation'),(Join-Path $identityBuild 'bin') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $identityRepo 'app/simulation/session_facade.gd'),'const NATIVE: String="'+$identityHash+'"')
$ninjaFile=Join-Path $identityBuild 'build.ninja'
$ninjaOriginal='DEFINES = -DFLIGHT_INTERACTIVE_SOURCE_SHA256=\\\"'+$identityHash+'\\\"'
[IO.File]::WriteAllText($ninjaFile,$ninjaOriginal)
$bridgeFile=Join-Path $identityBuild 'bin/flight_godot_bridge.dll'
[IO.File]::WriteAllText($bridgeFile,'not executable; declared identity '+$identityHash)
[IO.File]::WriteAllText((Join-Path $identityBuild 'CMakeCache.txt'),'fixture build configuration')
$manifestFile=Join-Path $identityBuild 'toolchain-build-manifest.txt'
[IO.File]::WriteAllText($manifestFile,'fixture declared build manifest')
$identity=Get-PreviewNativeBuildIdentity $identityRepo $identityBuild
if($identity.declared_source_fingerprint -cne $identityHash -or $identity.source_bindings.Count -ne 6 -or $identity.build_witnesses.Count -ne 4){throw 'Selected native identity witness incomplete'}
[IO.File]::WriteAllText($ninjaFile,$ninjaOriginal.Replace($identityHash,('a'*64)))
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'mismatched compiler identity'
[IO.File]::WriteAllText($ninjaFile,$ninjaOriginal+"`n"+$ninjaOriginal.Replace($identityHash,('a'*64)))
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'conflicting compiler identities'
[IO.File]::WriteAllText($ninjaFile,$ninjaOriginal)
[IO.File]::WriteAllText($bridgeFile,'no accepted identity')
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'bridge missing source identity'
[IO.File]::WriteAllText($bridgeFile,'not executable; declared identity '+$identityHash)
Remove-Item -LiteralPath $manifestFile
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'missing declared build witness'
[IO.File]::WriteAllText($manifestFile,'fixture declared build manifest')
$nativeFile=Join-Path $identityRepo $identityPaths[0]
$nativeOriginal=[IO.File]::ReadAllText($nativeFile)
[IO.File]::WriteAllText($nativeFile,$nativeOriginal+'changed')
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'authoring source differs from facade pin'
[IO.File]::WriteAllText($nativeFile,$nativeOriginal)
[IO.File]::WriteAllText($cmakeFile,$cmakeOriginal.Replace($identityPaths[5],'unknown/native.cpp'))
Must-Reject {Get-PreviewNativeBuildIdentity $identityRepo $identityBuild} 'unreviewed native closure'
[IO.File]::WriteAllText($cmakeFile,$cmakeOriginal)
Get-PreviewNativeBuildIdentity $identityRepo $identityBuild|Out-Null
Write-Output 'PASS selected native source/compile/bridge witnesses and identity/closure/missing-file negatives; no native execution.'

$runnerText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run.ps1'))
if($runnerText -notmatch 'exclude_filter="[^"\r\n]*landmark\*\.png,landmark\*-receipt\.json,observed\*\.png,observed\*-receipt\.json"'){throw 'Landmark/observed observer output must be excluded from PCK authoring'}
Write-Output 'PASS bounded landmark visual observer output exclusion; source/reference groups remain exact.'
