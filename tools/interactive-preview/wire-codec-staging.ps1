# ADR023 exact numeric test resources; source qualification is separate from execution.
function Get-WireCodecSourceDefinitions {
 @(
  @{source='tests/wire_codec/checks.gd';destination='wire_codec_tests/checks.gd'},
  @{source='docs/evidence/P2/native-wire-number-reference.json';destination='wire_codec_tests/reference.json'}
 )
}
function Get-WireCodecSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot)
 @(Get-WireCodecSourceDefinitions|ForEach-Object {
  $path=Join-Path $RepoRoot $_.source
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -LiteralPath $path -Force
  if($item.PSIsContainer){throw 'Wire-codec source must be an ordinary file'}
  [pscustomobject]@{source=$_.source;destination=$_.destination;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
 })
}
function Assert-WireCodecSourceGroups {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Groups,[switch]$Authoring,[switch]$AllowGeneratedUIDs)
 $definitions=@(Get-WireCodecSourceDefinitions)
 if($Groups.Count -ne $definitions.Count){throw 'Complete wire-codec source roster required'}
 for($i=0;$i -lt $definitions.Count;$i++){
  $row=$Groups[$i];$expected=$definitions[$i]
  if((($row.PSObject.Properties.Name|Sort-Object)-join "`n") -cne "bytes`ndestination`nsha256`nsource" -or $row.source -cne $expected.source -or $row.destination -cne $expected.destination -or ($row.bytes -isnot [int] -and $row.bytes -isnot [long]) -or $row.bytes -le 0 -or $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Wire-codec source descriptor rejected'}
  $path=Join-Path $Root $(if($Authoring){$row.source}else{$row.destination})
  Assert-PreviewOrdinaryAncestors -Path $path
  $item=Get-Item -LiteralPath $path -Force
  if($item.PSIsContainer -or $item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $row.sha256){throw 'Wire-codec source bytes changed'}
 }
 if(-not $Authoring){
  $snapshot=@($Groups|ForEach-Object {[pscustomobject]@{path=$_.destination.Substring(17);bytes=$_.bytes;sha256=$_.sha256}}|Sort-Object path)
  Assert-SimulationSourceSnapshot -SourceRoot (Join-Path $Root 'wire_codec_tests') -Snapshot $snapshot -RequiredEntries @('checks.gd','reference.json') -AllowGeneratedUIDs:$AllowGeneratedUIDs
 }
}
function Copy-WireCodecSourceGroups {
 param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$DestinationRoot,[Parameter(Mandatory)][object[]]$Groups)
 Assert-WireCodecSourceGroups -Root $RepoRoot -Groups $Groups -Authoring
 foreach($row in $Groups){
  $destination=Join-Path $DestinationRoot $row.destination
  New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent)|Out-Null
  Copy-Item -LiteralPath (Join-Path $RepoRoot $row.source) -Destination $destination
 }
 Assert-WireCodecSourceGroups -Root $DestinationRoot -Groups $Groups
}
function Assert-PreviewWireCodecReceipt {
 param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][bool]$IncludePiston,[Parameter(Mandatory)][string]$ExpectedSourceFingerprint)
 if((($Receipt.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'checks,evidence,failures,passed,scope' -or $Receipt.passed -isnot [bool] -or -not $Receipt.passed -or ($Receipt.checks -isnot [int] -and $Receipt.checks -isnot [long]) -or $Receipt.checks -le 0 -or $Receipt.failures -isnot [array] -or $Receipt.failures.Count -ne 0 -or $Receipt.scope -isnot [string] -or $Receipt.scope.Length -lt 1 -or $Receipt.scope.Length -gt 1024){throw 'Actual wire-codec receipt failed'}
 if($Receipt.evidence -isnot [pscustomobject] -or $Receipt.evidence.oracle -isnot [pscustomobject]){throw 'Wire-codec oracle object absent'}
 $oracle=$Receipt.evidence.oracle
 if((($oracle.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'actual_classdb,cases,sha256' -or ($oracle.cases -isnot [int] -and $oracle.cases -isnot [long]) -or $oracle.cases -ne 49 -or $oracle.sha256 -isnot [string] -or $oracle.sha256 -cne '1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6' -or $oracle.actual_classdb -isnot [bool] -or -not $oracle.actual_classdb){throw 'Actual frozen wire oracle qualification missing'}
 if($IncludePiston){
  $native=$Receipt.evidence.native
  $adjacent=$Receipt.evidence.adjacent_fault
  if($native -isnot [pscustomobject] -or $adjacent -isnot [pscustomobject] -or $native.tick -isnot [string] -or $native.tick -cne '1' -or $native.source_fingerprint -isnot [string] -or $native.source_fingerprint -cne $ExpectedSourceFingerprint -or $adjacent.mutated -isnot [bool] -or -not $adjacent.mutated){throw 'Actual cold wire witness missing'}
 }elseif($Receipt.evidence.native_witness -isnot [string] -or $Receipt.evidence.native_witness.Length -eq 0 -or $Receipt.evidence.PSObject.Properties.Name -ccontains 'native'){throw 'Upstream wire-codec scope must remain explicit'}
}
