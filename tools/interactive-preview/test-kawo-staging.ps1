#Requires -Version 7.0
# Synthetic filesystem/snapshot cases only. No Godot, native flight, real content
# qualification or installed package claim. Retain the fresh tiny fixture tree.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$case=Join-Path $repository ('.local/kawo-staging-unit/'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $case 'synthetic-source'
$staged=Join-Path $case 'staged'
New-Item -ItemType Directory -Force -Path $source,$staged|Out-Null
$pack=@('world.json','ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt')
foreach($relative in @('app/world/world_admission.gd','app/world/terrain/resident_grid_reader.gd','app/world/terrain/kawo_world.gd','app/world/decoration/kawo_evergreens.gd','content/world/catalog/kawo-runtime-v1.json','third_party/licenses/notices/OriginalEvergreens-MIT.txt')+@('tall-narrow','broad-tiered','irregular-mature'|ForEach-Object {'assets_source/environment/original-evergreens-v1/exports/'+$_+'-lod1.glb'})+@($pack|ForEach-Object {'content/world/airports/kawo/runtime-v1/'+$_})){
 $file=Join-Path $source $relative
 New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent)|Out-Null
 [IO.File]::WriteAllText($file,'synthetic source closure token: '+$relative+"`n")
}
foreach($name in @('tall-narrow','broad-tiered','irregular-mature')){
 [IO.File]::WriteAllText((Join-Path $source ('assets_source/environment/original-evergreens-v1/exports/'+$name+'-lod0.glb')),'synthetic unselected original LOD0')
}
foreach($name in @('checks.gd','controls-v1.json','README.md','runner.gd','runner.tscn')){
 $file=Join-Path $source ('tests/world/runway-paint/'+$name)
 New-Item -ItemType Directory -Force -Path (Split-Path $file -Parent)|Out-Null
 [IO.File]::WriteAllText($file,'synthetic paint staging token: '+$name)
}
$groups=@(Get-KawoRuntimeSourceGroups -RepoRoot $source)
Copy-KawoRuntimeSourceGroups -RepoRoot $source -DestinationRoot $staged -Groups $groups
Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups
$script:checks=1
function Expect-Failure([scriptblock]$Action,[string]$Label){
 $failed=$false
 try{& $Action}catch{$failed=$true}
 if(-not $failed){throw "Expected refusal: $Label"}
 $script:checks++
}
$paint=Join-Path $staged 'runway_paint_tests/controls-v1.json'
$paintOriginal=[IO.File]::ReadAllBytes($paint)
[IO.File]::WriteAllText($paint,'changed synthetic controls')
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups} 'changed paint controls'
[IO.File]::WriteAllBytes($paint,$paintOriginal)
Remove-Item -LiteralPath $paint
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups} 'missing paint controls'
[IO.File]::WriteAllBytes($paint,$paintOriginal)
$paintExtra=Join-Path $staged 'runway_paint_tests/unbound.json'
[IO.File]::WriteAllText($paintExtra,'extra synthetic fixture')
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups} 'unbound paint fixture'
Remove-Item -LiteralPath $paintExtra
Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups
$script:checks++
# Literal scheduling/result controls only. These do not execute the paint suite.
$paintJson='{"mode":"geometry","checks":132,"failures":[],"groups":{"geometry":{"checks":132,"failures":[]},"material":{"checks":0,"failures":[]}},"material_readback_exercised":false,"shader_pixel_cases_exercised":false,"native_flight_exercised":false}'
$paintText='KAWO_RUNWAY_PAINT_RESULT='+$paintJson
Assert-PreviewRunwayPaintGeometryResult ([pscustomobject]@{exit_code=0;text=$paintText})
$script:checks++
foreach($bad in @(
 $paintText.Replace('"mode":"geometry"','"mode":"material"'),
 $paintText.Replace('"checks":132','"checks":131'),
 $paintText.Replace('"geometry":{"checks":132','"geometry":{"checks":131'),
 $paintText.Replace('"material":{"checks":0','"material":{"checks":1'),
 $paintText.Replace('"failures":[]','"failures":["literal_failure"]'),
 $paintText.Replace('"checks":132','"checks":"132"'),
 $paintText.Replace('"native_flight_exercised":false','"omitted_flag":false'),
 'KAWO_RUNWAY_PAINT_RESULT={malformed',
 'no completion terminal',
 $paintText.Replace('"material_readback_exercised":false','"material_readback_exercised":true'),
 $paintText.Replace('"shader_pixel_cases_exercised":false','"shader_pixel_cases_exercised":true'),
 $paintText.Replace('"native_flight_exercised":false','"native_flight_exercised":true'),
 $paintText.Replace('"native_flight_exercised":false','"native_flight_exercised":"false"'),
 ($paintText+[Environment]::NewLine+$paintText),
 ('ERROR: literal negative control'+[Environment]::NewLine+$paintText)
)){
 Expect-Failure {Assert-PreviewRunwayPaintGeometryResult ([pscustomobject]@{exit_code=0;text=$bad})} 'paint terminal refused'
}
Expect-Failure {Assert-PreviewRunwayPaintGeometryResult ([pscustomobject]@{exit_code=1;text=$paintText})} 'paint exit failure'
Set-KawoEvergreenImportRecipe -ProjectRoot $staged
Assert-KawoEvergreenImportRecipe -ProjectRoot $staged
$script:checks++
Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups -AllowGeneratedUIDs
foreach($name in @('rogue.glb','rogue.glb.import')){
 $rogue=Join-Path $staged ('environment/original-evergreens-v1/'+$name)
 [IO.File]::WriteAllText($rogue,'unbound synthetic asset or import sidecar')
 Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups -AllowGeneratedUIDs} ('unbound evergreen destination/'+$name)
 Remove-Item -LiteralPath $rogue
}
Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups -AllowGeneratedUIDs
Expect-Failure {Set-KawoEvergreenImportRecipe -ProjectRoot $staged} 'cannot overwrite existing import metadata'
$recipe=Join-Path $staged 'environment/original-evergreens-v1/tall-narrow-lod1.glb.import'
$recipeOriginal=[IO.File]::ReadAllBytes($recipe)
[IO.File]::WriteAllText($recipe,[IO.File]::ReadAllText($recipe).Replace('meshes/generate_lods=false','meshes/generate_lods=true'))
Expect-Failure {Assert-KawoEvergreenImportRecipe -ProjectRoot $staged} 'automatic tree LOD is not admitted'
[IO.File]::WriteAllBytes($recipe,$recipeOriginal)
[IO.File]::AppendAllText($recipe,"meshes/generate_lods=true`n")
Expect-Failure {Assert-KawoEvergreenImportRecipe -ProjectRoot $staged} 'duplicate import key cannot mask a changed value'
[IO.File]::WriteAllBytes($recipe,$recipeOriginal)
Assert-KawoEvergreenImportRecipe -ProjectRoot $staged
$script:checks++
$ground=Join-Path $source 'content/world/airports/kawo/runtime-v1/ground.fgrd'
$original=[IO.File]::ReadAllBytes($ground)
[IO.File]::WriteAllText($ground,'changed synthetic payload')
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $source -Groups $groups -Authoring} 'changed source before copy'
[IO.File]::WriteAllBytes($ground,$original)
$uid=Join-Path $staged 'world/terrain/kawo_world.gd.uid'
[IO.File]::WriteAllText($uid,"uid://abc123`n")
Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups -AllowGeneratedUIDs
$script:checks++
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups} 'source copy cannot grow generated UID'
$extra=Join-Path $staged 'worlds/kawo-prototype-v1/eighth-file.txt'
[IO.File]::WriteAllText($extra,'unadmitted extra')
Expect-Failure {Assert-KawoRuntimeSourceGroups -Root $staged -Groups $groups -AllowGeneratedUIDs} 'eighth physical pack file'
if($IsWindows){
 $blocked=Join-Path $case 'reparse-destination'
 $trap=Join-Path $case 'trap'
 New-Item -ItemType Directory -Force -Path $blocked,$trap|Out-Null
 New-Item -ItemType Junction -Path (Join-Path $blocked 'worlds') -Target $trap|Out-Null
 Expect-Failure {Copy-KawoRuntimeSourceGroups -RepoRoot $source -DestinationRoot $blocked -Groups $groups} 'existing intermediate junction before pack write'
 if(@(Get-ChildItem -LiteralPath $trap -Force).Count -ne 0){throw 'Staging wrote through the rejected junction'}
 $script:checks++
}
Write-Output "PASS $script:checks synthetic KAWO staging checks; fixture retained: $case"
