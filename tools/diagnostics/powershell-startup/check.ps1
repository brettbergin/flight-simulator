#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolchainRoot)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'The standalone exported startup diagnostic requires Windows'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
$toolchain=(Resolve-Path -LiteralPath $ToolchainRoot).Path
$root=Join-Path $repo ('.local/powershell-startup/run-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
$payload=Join-Path $root 'payload'
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Path $project,$payload,$evidence | Out-Null
$environment=Get-Content -LiteralPath (Join-Path $toolchain 'environment.json') -Raw | ConvertFrom-Json
$priorBytecode=[Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE','Process')
try{
 [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE','1','Process')
 & $environment.python_executable (Join-Path $repo 'tools/interactive-preview/verify-pins.py') --toolchain $toolchain --output (Join-Path $evidence 'tool-pins.json')
 if($LASTEXITCODE -ne 0){throw 'Editor/export template pins rejected'}
}finally{[Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE',$priorBytecode,'Process')}
$pins=Get-Content -LiteralPath (Join-Path $evidence 'tool-pins.json') -Raw | ConvertFrom-Json
$godot=$pins.tools.godot.executable
$template=$pins.tools.'godot-templates'.executable
$source=Join-Path $PSScriptRoot 'probe.gd'
$initialHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
Copy-Item -LiteralPath $source -Destination (Join-Path $project 'probe.gd')
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $project 'project.godot'),@"
config_version=5
[application]
config/name="PowerShell Startup Diagnostic"
run/main_scene="res://probe.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
"@,$utf8)
[IO.File]::WriteAllText((Join-Path $project 'probe.tscn'),@"
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="StartupDiagnostic" type="Node"]
script=ExtResource("1")
"@,$utf8)
$presets=@"
[preset.0]
name="Windows Startup"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="startup-receipt.json"
script_export_mode=0
[preset.0.options]
custom_template/release="__TEMPLATE__"
binary_format/embed_pck=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
debug/export_console_wrapper=0
texture_format/bptc=true
texture_format/s3tc=true
"@
[IO.File]::WriteAllText((Join-Path $project 'export_presets.cfg'),$presets.Replace('__TEMPLATE__',$template.Replace('\','/')),$utf8)
function Check-Process($result,[string]$label){
 if($result.exit_code -ne 0 -or $result.text -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked'){
  throw "Standalone diagnostic $label failed; source/logs retained at $root"
 }
}
# Import/export do not run the probe scene. Every profile/cache write is isolated.
$result=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--editor','--path',$project,'--import','--quit') -WorkingDirectory $root -Log (Join-Path $evidence 'import.log') -CleanEnvironment -ProfileRoot (Join-Path $root 'import-profile') -TimeoutSeconds 120
Check-Process $result 'import'
$executable=Join-Path $payload 'PowerShellStartup.exe'
$result=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project,'--export-release','Windows Startup',$executable) -WorkingDirectory $root -Log (Join-Path $evidence 'export.log') -CleanEnvironment -ProfileRoot (Join-Path $root 'export-profile') -TimeoutSeconds 120
Check-Process $result 'export'
$inputs=@()
foreach($path in @($source,(Join-Path $PSScriptRoot 'check.ps1'),(Join-Path $repo 'tools/export/common.ps1'),(Join-Path $repo 'tools/interactive-preview/verify-pins.py'),(Join-Path $repo 'third_party/dependencies.lock.json'))){
 $item=Get-Item -LiteralPath $path
 $inputs+=@{path=[IO.Path]::GetRelativePath($repo,$path).Replace('\','/');bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$manifest=[ordered]@{schema_version=1;scope='Standalone GUI export ABBA startup diagnostic; no simulation or native extension';source_inputs=$inputs;tool_pins=$pins;exported_executable_sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant();pck_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'PowerShellStartup.pck') -Algorithm SHA256).Hash.ToLowerInvariant();environment_policy='Existing common.ps1 CleanEnvironment; only PSModulePath varied and immediately restored inside one exported host';speed_assertion=$false;causation_claim=$false}
[IO.File]::WriteAllText((Join-Path $evidence 'source-identity.json'),($manifest | ConvertTo-Json -Depth 12)+"`n",$utf8)
$result=Invoke-ProofProcess -Executable $executable -Arguments @('--headless') -WorkingDirectory $root -Log (Join-Path $evidence 'portable.log') -CleanEnvironment -ProfileRoot (Join-Path $root 'portable-profile') -TimeoutSeconds 120
$raw=Join-Path $payload 'startup-receipt.json'
if(Test-Path -LiteralPath $raw -PathType Leaf){Copy-Item -LiteralPath $raw -Destination (Join-Path $evidence 'startup-receipt.json')}
Check-Process $result 'portable'
if(-not (Test-Path -LiteralPath $raw -PathType Leaf)){throw "Diagnostic receipt missing; inspect $root"}
$receipt=Get-Content -LiteralPath $raw -Raw | ConvertFrom-Json
if($receipt.schema_version -ne 1 -or $receipt.passed -ne $true -or @($receipt.observations).Count -ne 4 -or @($receipt.failures).Count -ne 0 -or ($receipt.order -join '') -cne 'ABBA' -or $result.text -notmatch 'POWERSHELL_STARTUP_DIAGNOSTIC_PASSED'){throw "Diagnostic incomplete; inspect $root"}
for($i=0;$i -lt 4;$i++){
 $row=$receipt.observations[$i]
 if($row.treatment -cne $receipt.order[$i] -or $row.passed -ne $true -or $row.joined -ne $true -or $row.environment_restored -ne $true -or $row.readers_joined -ne $true -or $row.output_bound_exceeded -ne $false -or $row.timeout -ne $false -or $row.exit_code -ne 0 -or $null -eq $row.launch_to_entry_ms -or $null -eq $row.launch_to_exit_ms){throw "Diagnostic observation invalid; inspect $root"}
 Write-Output "PSSTARTUP treatment=$($row.treatment) create_ms=$($row.create_return_ms) entry_ms=$($row.launch_to_entry_ms) exit_ms=$($row.launch_to_exit_ms) inner_ms=$($row.metadata.inner_ms) joined=$($row.joined) readers_joined=$($row.readers_joined)"
}
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $initialHash -or (Get-FileHash -LiteralPath (Join-Path $project 'probe.gd') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $initialHash){throw 'Diagnostic source changed during capture'}
Write-Output "Standalone PowerShell ABBA startup observations retained: $root"
