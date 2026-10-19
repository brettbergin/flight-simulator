#Requires -Version 7.0
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'simulation-staging.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$stage=Join-Path $repo ('.local/local-player-staging-test/'+[Guid]::NewGuid().ToString('N'))
$groups=@(Get-LocalPlayerSourceGroups -RepoRoot $repo)
$registration=Join-Path $repo 'app/persistence/local_players.gdextension'
if(-not (Test-Path -LiteralPath $registration -PathType Leaf)){throw 'Regression requires the actual authored shipping registration'}
Copy-LocalPlayerSourceGroups -RepoRoot $repo -DestinationRoot $stage -Groups $groups
if(Test-Path -LiteralPath (Join-Path $stage 'persistence/local_players.gdextension')){throw 'Flight-only staging included production storage registration'}
if(@(Get-ChildItem -LiteralPath (Join-Path $stage 'persistence') -Recurse -File).Count -ne 1){throw 'Flight-only persistence must contain exactly the controller script'}
function Must-Reject([scriptblock]$Action,[string]$Label){
 $rejected=$false
 try{& $Action|Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw "Players staging accepted $Label"}
}
$controller=Join-Path $stage 'persistence/local_players_controller.gd'
$original=[IO.File]::ReadAllBytes($controller)
[IO.File]::WriteAllText($controller,'extends RefCounted # changed')
Must-Reject {Assert-LocalPlayerSourceGroups -Root $stage -Groups $groups} 'changed controller bytes'
[IO.File]::WriteAllBytes($controller,$original)
[IO.File]::WriteAllText($controller+'.uid',"uid://abc123`n")
Assert-LocalPlayerSourceGroups -Root $stage -Groups $groups -AllowGeneratedUIDs
Copy-Item -LiteralPath $registration -Destination (Join-Path $stage 'persistence/local_players.gdextension')
Must-Reject {Assert-LocalPlayerSourceGroups -Root $stage -Groups $groups -AllowGeneratedUIDs} 'unbound production storage registration in flight-only runtime'
Assert-LocalPlayerSourceGroups -Root $repo -Groups $groups -Authoring
Write-Output 'PASS local-player frontend staging: actual shipping registration excluded, controller byte drift rejected, bound generated UID accepted, injected native registration rejected. No native or Godot execution.'
