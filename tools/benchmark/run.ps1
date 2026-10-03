[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ExportProofRoot,
  [Parameter(Mandatory)][string]$ToolchainRoot,
  [ValidateSet('clear','dusk','overcast')][string]$Fixture='overcast',
  [ValidateRange(1,600)][int]$Duration=600,
  [ValidateRange(640,3840)][int]$Width=2560,
  [ValidateRange(480,2160)][int]$Height=1440,
  [ValidateRange(45,90)][int]$Fov=70,
  [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/export/common.ps1')
$proof=(Resolve-Path -LiteralPath $ExportProofRoot).Path
$toolchain=(Resolve-Path -LiteralPath $ToolchainRoot).Path
$godot=(Get-Content (Join-Path $toolchain 'environment.json') -Raw | ConvertFrom-Json).tools.godot
$template=Join-Path $toolchain 'godot-templates/windows_release_x86_64.exe'
if(-not (Test-Path -LiteralPath $template)) { throw 'Pinned Windows export template required' }
$snapshotGitHead=(& git -c "safe.directory=$repo" -C $repo rev-parse HEAD)
$root=Join-Path $repo ('.local/benchmark/run-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $root 'project'
$payload=Join-Path $root 'payload'
$evidence=Join-Path $root 'evidence'
New-Item -ItemType Directory -Force -Path $project,$payload,$evidence | Out-Null
$verificationTools=Join-Path $evidence 'verification-tools'
New-Item -ItemType Directory -Force -Path $verificationTools | Out-Null
$benchmarkToolInventory=@()
foreach($name in @('run.ps1','reduce.mjs','png.mjs','recipe.json')) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $verificationTools $name)
  $benchmarkToolInventory+=@{path=('tools/benchmark/'+$name);sha256=(Get-FileHash -LiteralPath (Join-Path $verificationTools $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
Get-ChildItem -LiteralPath (Join-Path $repo 'app/proof') | Where-Object { $_.Name -notin @('.godot','bin','models','initializer.bin') } | Copy-Item -Destination $project -Recurse
Copy-Item -LiteralPath (Join-Path $proof 'project/bin') -Destination (Join-Path $project 'bin') -Recurse
Copy-Item -LiteralPath (Join-Path $proof 'project/models') -Destination (Join-Path $project 'models') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'tests/export/initializer.bin') -Destination (Join-Path $project 'initializer.bin')
# Official release templates disable command-line scene path overrides. Set
# the isolated project's main scene; preserve the native proof source project.
$projectConfig=Get-Content (Join-Path $project 'project.godot') -Raw
$projectConfig=$projectConfig.Replace('run/main_scene="res://proof.tscn"','run/main_scene="res://render/render.tscn"')
Set-Content -LiteralPath (Join-Path $project 'project.godot') -Value $projectConfig -Encoding utf8
$preset=Get-Content (Join-Path $project 'export_presets.cfg') -Raw
$preset=$preset.Replace('custom_template/release=""','custom_template/release="'+$template.Replace('\','/')+'"')
Set-Content -LiteralPath (Join-Path $project 'export_presets.cfg') -Value $preset -Encoding utf8
$inventory=@()
foreach($file in (Get-ChildItem -LiteralPath $project -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/](bin|models|\.godot)[\\/]' } | Sort-Object FullName)) {
  $inventory+=@{path=$file.FullName.Substring($project.Length+1).Replace('\','/');bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$import=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project,'--editor','--quit-after','120','--frame-delay','100') -WorkingDirectory $root -Log (Join-Path $evidence 'import.log')
if($import.exit_code -ne 0 -or $import.text -match 'ERROR:|SCRIPT ERROR:|FATAL:') { throw 'Cold renderer import failed; retain evidence/import.log' }
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $project 'pipeline') -File -Filter '*.import')) {
  $inventory+=@{path=$file.FullName.Substring($project.Length+1).Replace('\','/');bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();role='pinned-engine-generated-import-settings'}
}
$export=Invoke-ProofProcess -Executable $godot -Arguments @('--headless','--path',$project,'--export-release','Windows Proof',(Join-Path $payload 'flight-render.exe')) -WorkingDirectory $root -Log (Join-Path $evidence 'export.log')
if($export.exit_code -ne 0 -or $export.text -match 'ERROR:|SCRIPT ERROR:|FATAL:') { throw 'Renderer release export failed' }
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'bin') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $project 'bin') -File | Copy-Item -Destination (Join-Path $payload 'bin') -Force
Get-ChildItem -LiteralPath (Join-Path $project 'bin') -File | Copy-Item -Destination $payload -Force
Copy-Item -LiteralPath (Join-Path $project 'models') -Destination (Join-Path $payload 'models') -Recurse
Copy-Item -LiteralPath (Join-Path $verificationTools 'recipe.json') -Destination (Join-Path $evidence 'recipe.json')
$hardware=[ordered]@{
  os=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber)
  cpu=(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors)
  ram_bytes=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
  video=(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate)
}
$hardware | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence 'hardware.json') -Encoding utf8
foreach($source in $inventory) {
  if((Get-FileHash -LiteralPath (Join-Path $project $source.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256) { throw 'Staged source changed during export' }
}
$engine=Join-Path (Split-Path -Parent $godot) 'Godot_v4.7.2-stable_win64.exe'
$manifest=[ordered]@{
  schema_version=1; kind='synthetic-render-feasibility';fixture=$Fixture;duration_s=$Duration
  resolution=@($Width,$Height);fov_deg=$Fov;warmup_s=10
  git_head=$snapshotGitHead
  scene_sources=$inventory
  source_scope='immutable staged snapshot; isolated project main_scene differs from native proof; repository head is a parent identity, snapshot digests identify in-progress authored bytes'
  benchmark_tools=$benchmarkToolInventory
  engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash.ToLowerInvariant()
  engine_launcher_sha256=(Get-FileHash -LiteralPath $godot -Algorithm SHA256).Hash.ToLowerInvariant()
  template_sha256=(Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant()
  executable_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'flight-render.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
  pck_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'flight-render.pck') -Algorithm SHA256).Hash.ToLowerInvariant()
  bridge_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'bin/flight_godot_bridge.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
  jsbsim_sha256=(Get-FileHash -LiteralPath (Join-Path $payload 'bin/JSBSim.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
  recipe_sha256=(Get-FileHash -LiteralPath (Join-Path $evidence 'recipe.json') -Algorithm SHA256).Hash.ToLowerInvariant()
  scope='exported release; offscreen exact-size viewport and scaled window; callback intervals are not Windows present timing; no concurrent simulation'
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'manifest.json') -Encoding utf8
@{root=$root;project=$project;payload=$payload;evidence=$evidence} | ConvertTo-Json | Set-Content (Join-Path $repo '.local/benchmark/latest-run.json') -Encoding utf8
if($PrepareOnly) { Write-Output $root; return }
$startUtc=[DateTimeOffset]::UtcNow.ToString('o')
$arguments=@('--rendering-method','forward_plus','--rendering-driver','vulkan','--',"duration=$Duration","width=$Width","height=$Height","fov=$Fov","fixture=$Fixture",("output="+$evidence.Replace('\','/')))
# A task-owned helper runs without a console window. Godot creates its actual
# renderer surface; the runtime adapter/timestamps and capture prove GPU use.
$start=[Diagnostics.ProcessStartInfo]::new()
$start.FileName=Join-Path $payload 'flight-render.exe'
$start.WorkingDirectory=$root
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.RedirectStandardOutput=$true
$start.RedirectStandardError=$true
foreach($argument in $arguments) { $start.ArgumentList.Add($argument) }
$process=[Diagnostics.Process]::Start($start)
$stdout=$process.StandardOutput.ReadToEndAsync()
$stderr=$process.StandardError.ReadToEndAsync()
$memory=[IO.StreamWriter]::new((Join-Path $evidence 'working-set.csv'),$false)
$memory.WriteLine('elapsed_s,working_set_bytes')
$timer=[Diagnostics.Stopwatch]::StartNew()
while(-not $process.WaitForExit(1000)) {
  $process.Refresh()
  $memory.WriteLine(('{0:F6},{1}' -f $timer.Elapsed.TotalSeconds,$process.WorkingSet64))
  if($timer.Elapsed.TotalSeconds -gt ($Duration+180)) { $process.Kill($true); throw 'Bounded renderer watchdog expired; evidence retained' }
}
$memory.Dispose()
[IO.File]::WriteAllText((Join-Path $evidence 'runtime.log'),$stdout.Result+[Environment]::NewLine+$stderr.Result)
$manifest.start_utc=$startUtc
$manifest.end_utc=[DateTimeOffset]::UtcNow.ToString('o')
$manifest.wall_process_duration_s=$timer.Elapsed.TotalSeconds
$manifest.exit_code=$process.ExitCode
$manifest.arguments=$arguments | ForEach-Object { if($_ -like 'output=*') {'output=<task-evidence-directory>'} else {$_} }
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'manifest.json') -Encoding utf8
if($process.ExitCode -ne 0 -or ($stdout.Result+$stderr.Result) -match 'ERROR:|SCRIPT ERROR:|FATAL:|ObjectDB instance was leaked' -or $stdout.Result -notmatch 'RENDER_PROBE ') { throw 'Renderer failed; evidence retained' }
& node (Join-Path $verificationTools 'reduce.mjs') $evidence
if($LASTEXITCODE -ne 0) { throw 'Independent renderer evidence verification failed' }
Write-Output $root
