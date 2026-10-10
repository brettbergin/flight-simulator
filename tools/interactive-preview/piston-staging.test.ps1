# Offline cold-profile source staging and receipt admission checks.
# Synthetic fixtures only; no compiler, native engine, Godot or pilot evidence.
#Requires -Version 7.0
param([Parameter(Mandatory)][string]$StagingScript,[Parameter(Mandatory)][string]$RepoRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. $StagingScript
$checks=0
$failures=[Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name){
 $script:checks++
 if(-not $Condition){$script:failures.Add($Name)}
}
function Reject([scriptblock]$Action,[string]$Name){
 $rejected=$false
 try{& $Action|Out-Null}catch{$rejected=$true}
 Check $rejected $Name
}
function Clone($Value){$Value|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function PassingReceipt {
 $groups=[ordered]@{}
 foreach($name in @('bridge','facade','pacing','input','panel','status','wind')){
  $groups[$name]=@{passed=$true;checks=3;failures=@();result=@{passed=$true;checks=2;failures=@()}}
 }
 $profiles=@(foreach($cadence in @('30','60','144','240','jitter')){foreach($scale in @('1/4','1/2','1','2','4')){
  @{cadence=$cadence;scale=$scale;completed_profile=$true;final_tick='120';final_debt_quanta=0}
 }})
 $groups.pacing.result.native_profiles=$profiles
 $groups.scene=@{passed=$true;checks=2;failures=@();result=@{initialized=$true;cold_initial_tick='0';cold_reset_tick='0'}}
 Clone @{schema='PistonFlightChecks/v1';passed=$true;checks=23;failures=@();scope='Synthetic receipt admission test only';groups=$groups}
}
$root=Join-Path $RepoRoot ('.local/resume/issue127-staging-test-'+[Guid]::NewGuid().ToString('N'))
$authoring=Join-Path $root 'authoring'
$staged=Join-Path $root 'staged'
try{
 New-Item -ItemType Directory -Path $authoring,$staged|Out-Null
 # Real unchanged public seven-file model; synthetic test scripts need no runtime.
 $modelDestination=Join-Path $authoring 'native/fdm_jsbsim/models/original-piston-prop'
 New-Item -ItemType Directory -Path (Split-Path -Parent $modelDestination) -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $RepoRoot 'native/fdm_jsbsim/models/original-piston-prop') -Destination $modelDestination -Recurse
 foreach($definition in @(Get-PistonSourceDefinitions|Where-Object {-not $_.destination.StartsWith('piston-models/')})){
  $path=Join-Path $authoring $definition.source
  New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force|Out-Null
  if($path.EndsWith('.gd')){[IO.File]::WriteAllText($path,"extends RefCounted`n")}else{Copy-Item -LiteralPath (Join-Path $RepoRoot $definition.source) -Destination $path}
 }
 $snapshot=@(Get-PistonSourceSnapshot -RepoRoot $authoring)
 Check ($snapshot.Count -eq 14) 'closed_fourteen_source_rows'
 Copy-PistonSourceSnapshot -RepoRoot $authoring -DestinationRoot $staged -Snapshot $snapshot
 Assert-PistonSourceSnapshot -Root $staged -Snapshot $snapshot
 Check $true 'fresh_exact_copy_admitted'
 Reject {Assert-PistonSourceSnapshot -Root $staged -Snapshot @($snapshot|Select-Object -Skip 1)} 'omitted_source_rejected'
 $bad=@(Clone $snapshot);$bad[0].destination='engine_tests/foreign.gd'
 Reject {Assert-PistonSourceSnapshot -Root $staged -Snapshot $bad} 'foreign_mapping_rejected'
 $bad=@(Clone $snapshot);$bad[0].source='../foreign.gd'
 Reject {Assert-PistonSourceSnapshot -Root $authoring -Snapshot $bad -Authoring} 'escape_mapping_rejected'
 $extra=Join-Path $staged 'engine_tests/extra.gd'
 [IO.File]::WriteAllText($extra,"extends RefCounted`n")
 Reject {Assert-PistonSourceSnapshot -Root $staged -Snapshot $snapshot} 'extra_staged_source_rejected'
 Remove-Item -LiteralPath $extra
 $model=Join-Path $staged 'piston-models/engine/original-piston.xml'
 $original=[IO.File]::ReadAllBytes($model)
 [IO.File]::AppendAllText($model,"`n")
 Reject {Assert-PistonSourceSnapshot -Root $staged -Snapshot $snapshot} 'mutated_model_rejected'
 [IO.File]::WriteAllBytes($model,$original)
 $extra=Join-Path $modelDestination 'extra.xml'
 [IO.File]::WriteAllText($extra,'<extra/>')
 Reject {Get-PistonSourceSnapshot -RepoRoot $authoring} 'eighth_model_file_rejected'
 Remove-Item -LiteralPath $extra
 $receipt=PassingReceipt
 Assert-PreviewPistonReceipt -Receipt $receipt
 Check $true 'complete_eight_group_receipt_admitted'
 $bad=Clone $receipt;$bad.groups.PSObject.Properties.Remove('wind')
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'omitted_group_rejected'
 $bad=Clone $receipt;$bad.checks++
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'aggregate_count_rejected'
 $bad=Clone $receipt;$bad.groups.bridge.result.passed=$false
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'failed_child_rejected'
 $bad=Clone $receipt;$bad.groups.input.result.checks=0
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'vacuous_child_rejected'
 $bad=Clone $receipt;$bad.groups.pacing.result.native_profiles=@($bad.groups.pacing.result.native_profiles|Select-Object -Skip 1)
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'twenty_four_profiles_rejected'
 $bad=Clone $receipt;$bad.groups.pacing.result.native_profiles[1]=$bad.groups.pacing.result.native_profiles[0]
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'duplicate_profile_rejected'
 $bad=Clone $receipt;$bad.groups.pacing.result.native_profiles[0].final_tick=120
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'numeric_tick_rejected'
 $bad=Clone $receipt;$bad.groups.pacing.result.native_profiles[0].final_debt_quanta='0'
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'string_debt_rejected'
 $bad=Clone $receipt;$bad.groups.scene.result.initialized=$false
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'uninitialized_scene_rejected'
 $bad=Clone $receipt;$bad.groups.scene.result.cold_reset_tick=0
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'numeric_reset_tick_rejected'
 $bad=Clone $receipt;$bad.scope='x'*1025
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'oversized_scope_rejected'
 $bad=Clone $receipt;$bad|Add-Member -NotePropertyName unexpected -NotePropertyValue $true
 Reject {Assert-PreviewPistonReceipt -Receipt $bad} 'unknown_top_field_rejected'
}finally{
 # Absolute workspace-local UUID target is checked before recursive cleanup.
 $resolved=[IO.Path]::GetFullPath($root)
 $parent=[IO.Path]::GetFullPath((Join-Path $RepoRoot '.local/resume'))+[IO.Path]::DirectorySeparatorChar
 if(-not $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'Test cleanup escaped private workspace'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
@{passed=($failures.Count -eq 0);checks=$checks;failures=@($failures)}|ConvertTo-Json -Depth 20
if($failures.Count -ne 0){exit 1}
