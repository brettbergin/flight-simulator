#Requires -Version 7.0
param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$WorkRoot)
# Original MIT. Disposable ordinary-file staging guards only; no simulator.
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/interactive-preview/simulation-staging.ps1')
. (Join-Path $PSScriptRoot 'local-window-replay-staging.ps1')
if(-not [IO.Path]::IsPathFullyQualified($WorkRoot)){throw 'Explicit absolute private test parent required'}
$parent=[IO.Path]::GetFullPath($WorkRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
Assert-PreviewOrdinaryAncestors -Path $parent
$root=Join-Path $parent ('local-window-staging-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$checks=0
function Check([bool]$Value,[string]$Label){$script:checks++;if(-not $Value){throw $Label}}
function Reject([scriptblock]$Action,[string]$Label){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $rejected $Label}
try{
 $repo=Join-Path $root 'author';$author=Join-Path $repo 'tests/engine/local-window-replay';$project=Join-Path $root 'project'
 New-Item -ItemType Directory -Path $author -Force|Out-Null
 foreach($name in @('recipe.json','argument-binary64.json','checks.gd','README.md')){Copy-Item -LiteralPath (Join-Path $FixtureRoot $name) -Destination (Join-Path $author $name)}
 $groups=@(Get-LocalWindowReplaySourceGroups -RepoRoot $repo)
 Check ($groups.Count -eq 4) 'Exactly four ordered definitions'
 Assert-LocalWindowReplaySourceGroups -Root $repo -Groups $groups -Authoring;$checks++
 Copy-LocalWindowReplaySourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $groups;$checks++
 Reject {Copy-LocalWindowReplaySourceGroups -RepoRoot $repo -DestinationRoot $project -Groups $groups} 'No staging into an existing destination'
 $mapped=Join-Path $project 'local_window_replay_tests';$uid=Join-Path $mapped 'checks.gd.uid'
 [IO.File]::WriteAllText($uid,"uid://abc123`n")
 Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups -AllowGeneratedUIDs;$checks++
 Reject {Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups} 'UID forbidden without import switch'
 [IO.File]::WriteAllText($uid,'arbitrary')
 Reject {Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups -AllowGeneratedUIDs} 'Malformed UID rejected'
 Remove-Item -LiteralPath $uid
 foreach($base in @($author,$mapped)){
  $extra=Join-Path $base 'extra.txt';[IO.File]::WriteAllText($extra,'x')
  if($base -eq $author){Reject {Assert-LocalWindowReplaySourceGroups -Root $repo -Groups $groups -Authoring} 'Extra authored source rejected'}else{Reject {Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups} 'Extra staged source rejected'}
  Remove-Item -LiteralPath $extra
 }
 $copy=Join-Path $mapped 'checks.gd';$bytes=[IO.File]::ReadAllBytes($copy)
 [IO.File]::AppendAllText($copy,"`n")
 Reject {Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups} 'Source byte drift rejected'
 [IO.File]::WriteAllBytes($copy,$bytes)
 $forged=@($groups|ForEach-Object {[pscustomobject]@{source=$_.source;destination=$_.destination;bytes=$_.bytes;sha256=$_.sha256}})
 $forged[0].sha256=('0'*64)
 Reject {Assert-LocalWindowReplaySourceGroups -Root $repo -Groups $forged -Authoring} 'Forged descriptor rejected'
 Reject {Assert-LocalWindowReplaySourceGroups -Root $repo -Groups @($groups[1],$groups[0],$groups[2],$groups[3]) -Authoring} 'Reordered definitions rejected'
 Reject {Assert-LocalWindowReplaySourceGroups -Root $repo -Groups @($groups[0..2]) -Authoring} 'Incomplete definitions rejected'
 $source=Join-Path $author 'checks.gd';[IO.File]::AppendAllText($source,"`n")
 $rehashed=@(Get-LocalWindowReplaySourceGroups -RepoRoot $repo)
 Reject {Assert-LocalWindowReplaySourceGroups -Root $repo -Groups $rehashed -Authoring} 'Rehashed nonfrozen driver rejected'
 [IO.File]::WriteAllBytes($source,$bytes)
 $nested=Join-Path $mapped 'nested';New-Item -ItemType Directory -Path $nested|Out-Null
 [IO.File]::WriteAllText((Join-Path $nested 'hidden.txt'),'x')
 Reject {Assert-LocalWindowReplaySourceGroups -Root $project -Groups $groups} 'Unexpected recursive resource rejected'
 Remove-Item -LiteralPath (Join-Path $nested 'hidden.txt');Remove-Item -LiteralPath $nested
 [pscustomobject]@{passed=$true;checks=$checks;scope='Disposable source staging/immutable hashes/closed roster/import-only UID. No replay or native execution.'}|ConvertTo-Json -Depth 4
}finally{
 $resolved=[IO.Path]::GetFullPath($root)
 if(-not $resolved.StartsWith($parent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Disposable cleanup escaped explicit parent'}
 Assert-PreviewOrdinaryAncestors -Path $resolved
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
