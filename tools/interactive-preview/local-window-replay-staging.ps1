#Requires -Version 7.0
# Original MIT. Shared snapshot/ordinary-ancestor helpers supplied by simulation-staging.
function Get-LocalWindowReplaySourceDefinitions {
 @('recipe.json','argument-binary64.json','checks.gd','README.md')|ForEach-Object {
  @{source=('tests/engine/local-window-replay/'+$_);destination=('local_window_replay_tests/'+$_)}
 }
}
function Get-LocalWindowReplaySourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(Get-LocalWindowReplaySourceDefinitions|ForEach-Object {
  $path=Join-Path $RepoRoot $_.source
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -LiteralPath $path -Force
  if($item.PSIsContainer){throw 'Local-window replay source must be an ordinary file'}
  [pscustomobject]@{source=$_.source;destination=$_.destination;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
 })
}
function Assert-LocalWindowReplaySourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-LocalWindowReplaySourceDefinitions)
 $frozen=@{'recipe.json'='2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1';'argument-binary64.json'='ffb39073782ac1226795df39b0b95512e0f444a4f2284224c9c34af4a5ef9b76';'checks.gd'='5689a75e0868067d04b22cd8cfde61f75f0d83d78b5f9a6a1cd37848e34636b8';'README.md'='9a333bcce0d17202e9ec2818f7a13227a522764063da7a6a2cd028f38b20a949'}
 if($Groups.Count -ne 4){throw 'Complete four-file local-window replay roster required'}
 for($i=0;$i -lt 4;$i++){
  $row=$Groups[$i];$expected=$definitions[$i]
  if((($row.PSObject.Properties.Name|Sort-Object)-join "`n") -cne "bytes`ndestination`nsha256`nsource" -or $row.source -cne $expected.source -or $row.destination -cne $expected.destination -or ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -le 0 -or $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Local-window replay source descriptor rejected'}
  if($row.sha256 -cne $frozen[$row.source.Substring('tests/engine/local-window-replay/'.Length)]){throw 'Replay immutable reference/driver source identity changed'}
  $path=Join-Path $Root $(if($Authoring){$row.source}else{$row.destination})
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -LiteralPath $path -Force
  if($item.PSIsContainer -or $item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw 'Local-window replay source bytes changed'}
 }
 $prefix=if($Authoring){'tests/engine/local-window-replay/'}else{'local_window_replay_tests/'}
 $snapshot=@($Groups|ForEach-Object {[pscustomobject]@{path=$_.source.Substring('tests/engine/local-window-replay/'.Length);bytes=$_.bytes;sha256=$_.sha256}}|Sort-Object path)
 # Root roster is recursively exact. Only imported checks.gd.uid is permitted
 # outside authored files; authoring/corresponding copies always reject UIDs.
 Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root $prefix) -Snapshot $snapshot -RequiredEntries @('recipe.json','argument-binary64.json','checks.gd','README.md') -AllowGeneratedUIDs:($AllowGeneratedUIDs -and -not $Authoring)
}
function Copy-LocalWindowReplaySourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-LocalWindowReplaySourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 $target=Join-Path $DestinationRoot 'local_window_replay_tests'
 if(Test-Path -LiteralPath $target){throw 'Local-window replay destination must be fresh'}
 New-Item -ItemType Directory -Path $target -Force|Out-Null
 foreach($row in $Groups){Copy-Item -LiteralPath (Join-Path $RepoRoot $row.source) -Destination (Join-Path $DestinationRoot $row.destination)}
 Assert-LocalWindowReplaySourceGroups -Root $DestinationRoot -Groups $Groups
 Assert-LocalWindowReplaySourceGroups -Root $RepoRoot -Groups $Groups -Authoring
}
function Assert-PreviewLocalWindowReplayReceipt {
 param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$ExpectedSourceFingerprint,[Parameter(Mandatory)][string]$SourceVariant)
 $wanted=@('passed','checks','failures','scope','recipe_sha256','argument_binary64_sha256','source_fingerprint','source_variant','angular_integration_method','argument_float_fields','schema_integer_fields','step_integer_fields','final_tick','continuation_completed','joined','calls','publications')
 if((($Receipt.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($wanted|Sort-Object)-join ',') -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [int] -and $Receipt.checks -isnot [long]) -or $Receipt.checks -le 0 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0 -or $Receipt.scope -isnot [string] -or $Receipt.scope.Length -lt 1 -or $Receipt.scope.Length -gt 1024){throw 'Actual local-window replay receipt rejected'}
 if($SourceVariant -cne 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2' -or $ExpectedSourceFingerprint -cnotmatch '^[a-f0-9]{64}$' -or $Receipt.source_variant -isnot [string] -or $Receipt.source_variant -cne $SourceVariant -or $Receipt.source_fingerprint -isnot [string] -or $Receipt.source_fingerprint -cne $ExpectedSourceFingerprint -or $Receipt.angular_integration_method -cne 'event_aware_coupled_midpoint_v1' -or $Receipt.recipe_sha256 -cne '2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1' -or $Receipt.argument_binary64_sha256 -cne 'ffb39073782ac1226795df39b0b95512e0f444a4f2284224c9c34af4a5ef9b76'){throw 'Replay source/fixture identity rejected'}
 foreach($pair in @(@('argument_float_fields',138),@('schema_integer_fields',31),@('step_integer_fields',265),@('continuation_completed',28))){$value=$Receipt.($pair[0]);if(($value -isnot [int] -and $value -isnot [long]) -or $value -ne $pair[1]){throw 'Replay exact restoration/completion counter rejected'}}
 if($Receipt.final_tick -isnot [string] -or $Receipt.final_tick -cne '1607' -or $Receipt.joined -isnot [bool] -or -not $Receipt.joined -or $Receipt.calls -isnot [array] -or $Receipt.calls.Count -ne 298 -or $Receipt.publications -isnot [array] -or $Receipt.publications.Count -ne 3){throw 'Replay actual history/checkpoints/join rejected'}
 # This is an early closed-shape guard only. Always run the Node validator below
 # against the raw receipt before counting this as an admitted mandatory result.
}
function Assert-PreviewLocalWindowReplayReceiptFile {
 param([Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Node,[Parameter(Mandatory)][string]$ExpectedSourceFingerprint,[Parameter(Mandatory)][string]$SourceVariant,[Parameter(Mandatory)][string]$ModelRoot)
 Assert-PreviewOrdinaryAncestors -Path $ReceiptPath
 $item=Get-Item -LiteralPath $ReceiptPath -Force
 if($item.PSIsContainer -or $item.Length -le 0 -or $item.Length -gt 16777216){throw 'Replay receipt byte bound rejected'}
 $receipt=[IO.File]::ReadAllText($ReceiptPath)|ConvertFrom-Json -Depth 64
 Assert-PreviewLocalWindowReplayReceipt -Receipt $receipt -ExpectedSourceFingerprint $ExpectedSourceFingerprint -SourceVariant $SourceVariant
 & $Node (Join-Path $PSScriptRoot 'local-window-replay.mjs') receipt $ReceiptPath $RepoRoot $ExpectedSourceFingerprint $SourceVariant $ModelRoot
 if($LASTEXITCODE -ne 0){throw 'Full local-window replay history/schema/bit validation failed'}
}
