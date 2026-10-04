#Requires -Version 7.0
$ErrorActionPreference='Stop'
# Extract the actual predicates used by both process guards; do not copy a test
# regex that could pass while a production guard drifts. These singular/plural
# messages are the known Godot shutdown warnings covered by renderer review.
foreach($name in @('run.ps1','launch.ps1')){
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw "Invalid PowerShell source: $name"}
 $matches=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.BinaryExpressionAst] -and
  $node.Operator -eq [Management.Automation.Language.TokenKind]::Imatch -and
  $node.Right -is [Management.Automation.Language.StringConstantExpressionAst] -and
  $node.Right.Value.Contains('ObjectDB')
 },$true))
 if($matches.Count -ne 1){throw "Expected one actual process guard in $name"}
 $pattern=$matches[0].Right.Value
 foreach($warning in @(
  'WARNING: 1 ObjectDB instance was leaked at exit',
  'WARNING: 2 ObjectDB instances were leaked at exit',
  'WARNING: ObjectDB instance leaked at exit',
  'WARNING: ObjectDB instances leaked at exit',
  'ERROR: fixture failure','SCRIPT ERROR: fixture parse failure','FATAL: fixture native failure'
 )){if($warning -notmatch $pattern){throw "$name accepted known failure: $warning"}}
 if('WHOLE_FLIGHT_PREVIEW_SMOKE {"passed":true,"failures":[]}' -match $pattern){throw "$name rejects a clean positive marker"}
}
Write-Output 'Preview actual guard negative controls passed (both helpers, known singular/plural shutdown warnings).'

# Exercise actual input source groups, not a parallel packaging implementation.
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$groups=@(Get-InputSourceGroups $repo)
$stage=Join-Path $repo ('.local/input-staging-test/'+[Guid]::NewGuid().ToString('N'))
Copy-InputSourceGroups $repo $stage $groups
Assert-InputSourceGroups $stage $groups
$changed=Join-Path $stage 'ui/controls/controls_panel.gd'
[IO.File]::WriteAllText($changed,'extends Control # mutated stage')
$rejected=$false
try{Assert-InputSourceGroups $stage $groups}catch{$rejected=$true}
if(-not $rejected){throw 'Input/UI staging accepted changed panel bytes'}
$fixture=Join-Path $stage 'input_tests/reference.json'
Move-Item -LiteralPath $fixture -Destination ($fixture+'.unbound')
$rejected=$false
try{Get-SimulationSourceSnapshot (Join-Path $stage 'input_tests') -RequiredEntries @('input_checks.gd','scene_checks.gd','reference.json')|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Input staging accepted missing analytic reference'}
Write-Output 'Input/UI/tests exact recursive staging and changed/missing source negatives passed.'

# Bound cockpit views, independent reading references and original provenance.
$cockpitGroups=@(Get-CockpitSourceGroups $repo)
$cockpitStage=Join-Path $repo ('.local/cockpit-staging-test/'+[Guid]::NewGuid().ToString('N'))
Copy-CockpitSourceGroups $repo $cockpitStage $cockpitGroups
Assert-CockpitSourceGroups $cockpitStage $cockpitGroups
$scan=Join-Path $cockpitStage 'cockpit/instruments/scan_panel.gd'
$scanBytes=[IO.File]::ReadAllBytes($scan)
[IO.File]::WriteAllText($scan,'extends Control # mutated cockpit stage')
$rejected=$false
try{Assert-CockpitSourceGroups $cockpitStage $cockpitGroups}catch{$rejected=$true}
if(-not $rejected){throw 'Cockpit staging accepted changed scan panel bytes'}
[IO.File]::WriteAllBytes($scan,$scanBytes)
$reference=Join-Path $cockpitStage 'instrument_tests/reference.json'
Move-Item -LiteralPath $reference -Destination ($reference+'.unbound')
$rejected=$false
try{Assert-CockpitSourceGroups $cockpitStage $cockpitGroups}catch{$rejected=$true}
if(-not $rejected){throw 'Cockpit staging accepted missing frozen reading reference'}
Move-Item -LiteralPath ($reference+'.unbound') -Destination $reference
$provenance=Join-Path $cockpitStage 'content/aircraft/prototype/cockpit-presentation.json'
[IO.File]::WriteAllText($provenance,'{}')
$rejected=$false
try{Assert-CockpitSourceGroups $cockpitStage $cockpitGroups}catch{$rejected=$true}
if(-not $rejected){throw 'Cockpit staging accepted changed original provenance'}
Write-Output 'Cockpit/readings/provenance exact recursive staging and changed/missing source negatives passed.'
