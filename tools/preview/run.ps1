#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ExportProofRoot,[Parameter(Mandatory)][string]$ToolchainRoot)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Airborne portable preview currently targets Windows x64'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
& (Join-Path $PSScriptRoot 'check-guards.ps1')
$proof=(Resolve-Path -LiteralPath $ExportProofRoot).Path
$toolchain=(Resolve-Path -LiteralPath $ToolchainRoot).Path
$root=Join-Path $repo ('.local/preview/run-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
$payload=Join-Path $root 'payload'
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Force $project,$payload,$evidence | Out-Null
$environment=Get-Content (Join-Path $toolchain 'environment.json') -Raw | ConvertFrom-Json
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins.json')
if($LASTEXITCODE -ne 0){throw 'Actual editor/template pins rejected'}
$pins=Get-Content (Join-Path $evidence 'tool-pins.json') -Raw | ConvertFrom-Json
$godot=$pins.tools.godot.executable
$template=$pins.tools.'godot-templates'.executable
$version=Invoke-ProofProcess -Executable $godot -Arguments @('--version') -WorkingDirectory $root -Log (Join-Path $evidence 'godot-version.log')
if($version.exit_code -ne 0 -or $version.text.Trim() -ne '4.7.2.stable.official.ed1daf0bf'){throw 'Actual engine version differs from pin'}
# Verify every accepted package component before reusing any payload bytes.
$audit=Get-Content (Join-Path $proof 'evidence/package-audit.json') -Raw | ConvertFrom-Json
$accepted=Get-Content (Join-Path $proof 'evidence/package-inventory.json') -Raw | ConvertFrom-Json
if($audit.rights_integrity_passed -ne $true -or $audit.actual_replacement_passed -ne $true){throw 'Accepted native export audit/replacement evidence required'}
foreach($component in $accepted.components){foreach($file in $component.files){
 $candidate=Join-Path $proof ('payload/'+$file.path)
 if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw "Accepted package changed: $($file.path)"}
}}
$inputs=@()
foreach($directory in @('app/proof/airborne','tools/preview')){
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File){
  $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$file.FullName).Replace('\','/');sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant();bytes=$file.Length}
 }
}
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/airborne') -Destination (Join-Path $project 'airborne') -Recurse
# ADR023: bind only this stateless resource; no interactive scene dependency.
$wireDecoderRoot=Join-Path $repo 'app/simulation'
$wireDecoderNames=@('native_wire_decoder.gd')
if(Test-Path -LiteralPath (Join-Path $wireDecoderRoot 'native_wire_decoder.gd.uid')){$wireDecoderNames+=@('native_wire_decoder.gd.uid')}
$wireDecoderSnapshot=@(foreach($name in $wireDecoderNames){
 $file=Get-Item -LiteralPath (Join-Path $wireDecoderRoot $name) -ErrorAction Stop
 if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Decoder input must be an ordinary file'}
 @{path=$name;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$wireDecoderStage=Join-Path $project 'simulation'
New-Item -ItemType Directory -Path $wireDecoderStage | Out-Null
foreach($file in $wireDecoderSnapshot){Copy-Item -LiteralPath (Join-Path $wireDecoderRoot $file.path) -Destination (Join-Path $wireDecoderStage $file.path)}
function Assert-AirborneWireDecoder {
 param([string]$SourceRoot,[string]$StageRoot,[object[]]$Snapshot)
 $sourceNames=@('native_wire_decoder.gd')
 if(Test-Path -LiteralPath (Join-Path $SourceRoot 'native_wire_decoder.gd.uid')){$sourceNames+=@('native_wire_decoder.gd.uid')}
 if(($sourceNames -join "`n") -cne (@($Snapshot.path) -join "`n")){throw 'Decoder authoring UID roster changed'}
 foreach($root in @($SourceRoot,$StageRoot)){
  foreach($file in $Snapshot){
   $actual=Get-Item -LiteralPath (Join-Path $root $file.path) -ErrorAction Stop
   if($actual.PSIsContainer -or ($actual.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $actual.Length -ne $file.bytes -or (Get-FileHash -LiteralPath $actual.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256){throw 'Bound decoder resource changed'}
  }
 }
 foreach($actual in Get-ChildItem -LiteralPath $StageRoot -Force){
  if($actual.PSIsContainer -or ($actual.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unexpected decoder stage entry'}
  if($actual.Name -cnotin @($Snapshot.path)){
   if($actual.Name -cne 'native_wire_decoder.gd.uid' -or $actual.Length -gt 64 -or (Get-Content -LiteralPath $actual.FullName -Raw).Trim() -cnotmatch '^uid://[a-z0-9]{1,20}$'){throw 'Unexpected generated decoder resource'}
  }
 }
}
Assert-AirborneWireDecoder $wireDecoderRoot $wireDecoderStage $wireDecoderSnapshot
$wireDecoderSnapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'wire-decoder-resource.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/airborne/project-settings.cfg') -Destination (Join-Path $project 'project.godot')
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/flight.gdextension'),(Join-Path $repo 'app/proof/export_presets.cfg'),(Join-Path $repo 'tests/export/initializer.bin') -Destination $project
Copy-Item -LiteralPath (Join-Path $proof 'payload/models'),(Join-Path $proof 'payload/bin') -Destination $project -Recurse
$preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
$preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template.Replace('\','/')+'"').Replace('exclude_filter=""','exclude_filter="smoke-receipt.json"')
$preset | Set-Content -Encoding utf8 (Join-Path $project 'export_presets.cfg')
foreach($file in $wireDecoderSnapshot){$inputs+=@{path=('app/simulation/'+$file.path);sha256=$file.sha256;bytes=$file.bytes}}
# Keep engine/profile/cache writes within this fresh run even during authoring.
$prior=@{}
foreach($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP','FLIGHT_PREVIEW_PROFILE_ROOT')){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
 $profile=Join-Path $root 'userdata'
 $env:FLIGHT_PREVIEW_PROFILE_ROOT=$profile.Replace('\','/')
 foreach($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')){
  $directory=Join-Path $profile $name
  New-Item -ItemType Directory -Force $directory | Out-Null
  [Environment]::SetEnvironmentVariable($name,$directory,'Process')
 }
 foreach($operation in @(
  @{name='import';args=@('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100')},
  @{name='editor-smoke';args=@('--headless','--path',$project,'--','--smoke')},
  @{name='export';args=@('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $payload 'AirbornePreview.exe'))}
 )){
  $result=Invoke-ProofProcess -Executable $godot -Arguments $operation.args -WorkingDirectory $root -Log (Join-Path $evidence ($operation.name+'.log'))
  if($result.exit_code -ne 0 -or $result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed'){throw "Preview $($operation.name) failed; raw evidence retained"}
  if($operation.name -eq 'editor-smoke'){
   $receipt=Get-Content (Join-Path $project 'smoke-receipt.json') -Raw | ConvertFrom-Json
   if($result.text -notmatch 'AIRBORNE_PREVIEW_SMOKE' -or $receipt.passed -ne $true -or $receipt.failures.Count -ne 0){throw 'Actual editor smoke assertions failed'}
   Copy-Item -LiteralPath (Join-Path $project 'smoke-receipt.json') -Destination (Join-Path $evidence 'editor-smoke-receipt.json')
  }
 }
} finally {foreach($name in $prior.Keys){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}}
foreach($name in @('models','bin','notices','source')){Copy-Item -LiteralPath (Join-Path $proof "payload/$name") -Destination (Join-Path $payload $name) -Recurse}
foreach($name in @('flight_godot_bridge.dll','JSBSim.dll','msvcp140.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','vcruntime140.dll','vcruntime140_1.dll')){
 $original=Join-Path $proof "payload/$name"
 Copy-Item -LiteralPath $original -Destination (Join-Path $payload $name) -Force
 foreach($copy in @($name,"bin/$name")){if((Get-FileHash (Join-Path $payload $copy)).Hash -ne (Get-FileHash $original).Hash){throw "Dependency copy changed: $copy"}}
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launch.ps1'),(Join-Path $PSScriptRoot 'README.md') -Destination $payload
$source=Join-Path $payload 'source/airborne-preview'
New-Item -ItemType Directory -Force $source | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'app/proof/airborne'),$PSScriptRoot -Destination $source -Recurse
Assert-AirborneWireDecoder $wireDecoderRoot $wireDecoderStage $wireDecoderSnapshot
$decoderSource=Join-Path $source 'simulation'
New-Item -ItemType Directory -Path $decoderSource | Out-Null
foreach($file in $wireDecoderSnapshot){Copy-Item -LiteralPath (Join-Path $wireDecoderStage $file.path) -Destination (Join-Path $decoderSource $file.path)}
Assert-AirborneWireDecoder $wireDecoderRoot $decoderSource $wireDecoderSnapshot
& (Join-Path $payload 'launch.ps1') -HeadlessSmoke
Copy-Item -LiteralPath (Join-Path $payload 'smoke-receipt.json'),(Join-Path $payload 'portable-smoke.log') -Destination $evidence
# Detect concurrent source/toolchain drift before publishing a successful receipt.
foreach($input in $inputs){if((Get-FileHash (Join-Path $repo $input.path)).Hash.ToLowerInvariant() -ne $input.sha256){throw 'Authoring source changed during proof'}}
& $environment.python_executable (Join-Path $PSScriptRoot 'verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins-final.json')
if($LASTEXITCODE -ne 0){throw 'Toolchain drift detected'}
if((Get-FileHash (Join-Path $evidence 'tool-pins.json')).Hash -ne (Get-FileHash (Join-Path $evidence 'tool-pins-final.json')).Hash){throw 'Selected tool identities changed during proof'}
Assert-AirborneWireDecoder $wireDecoderRoot $wireDecoderStage $wireDecoderSnapshot
Assert-AirborneWireDecoder $wireDecoderRoot $decoderSource $wireDecoderSnapshot
$inventory=@(Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {@{path=[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}} | Sort-Object {$_.path})
$manifest=@{wire_decoder_resource=$wireDecoderSnapshot;schema_version=1;kind='original-airborne-preview';passed=$true;scope='Windows original model, actual functional headless proof; GPU/human acceptance separate';git_head=(& git -c "safe.directory=$repo" -C $repo rev-parse HEAD);powershell=$PSVersionTable.PSVersion.ToString();authoring_sources=$inputs;tool_pins=$pins;godot_version=$version.text.Trim();accepted_native_export_root=$proof;accepted_package_inventory_sha256=(Get-FileHash (Join-Path $proof 'evidence/package-inventory.json')).Hash.ToLowerInvariant();files=$inventory}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 (Join-Path $evidence 'manifest.json')
@{root=$root;project=$project;payload=$payload;evidence=$evidence;passed=$true} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $repo '.local/preview/latest-run.json')
Write-Output $root


