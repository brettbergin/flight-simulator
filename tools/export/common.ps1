$ErrorActionPreference='Stop'
function Invoke-ProofProcess {
  param([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[string]$Log,[switch]$CleanEnvironment,[string]$ProfileRoot,[ValidateRange(1,600)][int]$TimeoutSeconds=120)
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName=$Executable; $start.WorkingDirectory=$WorkingDirectory
  $start.UseShellExecute=$false; $start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
  foreach($argument in $Arguments) { $start.ArgumentList.Add($argument) }
  if($CleanEnvironment) {
    $start.Environment.Clear()
    $start.Environment['PATH']=''
    $start.Environment['SystemRoot']=$env:SystemRoot
    $start.Environment['WINDIR']=$env:WINDIR
    $start.Environment['JSBSIM_DEBUG']='0'
    foreach($name in @('TEMP','TMP','LOCALAPPDATA','APPDATA')) {
      $directory=Join-Path $ProfileRoot $name
      New-Item -ItemType Directory -Force -Path $directory | Out-Null
      $start.Environment[$name]=$directory
    }
  } else { $start.Environment['JSBSIM_DEBUG']='0' }
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
  if(-not $process.Start()) { throw 'Proof process failed to start' }
  $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
  $timedOut=-not $process.WaitForExit($TimeoutSeconds*1000)
  if($timedOut) {
    $terminationError=''
    try { $process.Kill($true) } catch { $terminationError=$_.Exception.Message }
    $joined=$process.WaitForExit(10000)
    $drainError=''; $drained=$false
    try { $drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),10000) } catch { $drainError=$_.Exception.Message }
    $text=if($stdout.IsCompletedSuccessfully) { $stdout.GetAwaiter().GetResult() } else { '[stdout did not finish draining]' }
    $text+=if($stderr.IsCompletedSuccessfully) { $stderr.GetAwaiter().GetResult() } else { '[stderr did not finish draining]' }
    $text+="`nProof watchdog: timeout_seconds=$TimeoutSeconds; joined=$joined; drained=$drained; termination_error=$terminationError; drain_error=$drainError"
    try { $text | Set-Content -LiteralPath $Log -Encoding utf8 } finally { $process.Dispose() }
    throw "Proof process exceeded $TimeoutSeconds-second watchdog; raw log retained; joined=$joined; drained=$drained"
  }
  $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  $text | Set-Content -LiteralPath $Log -Encoding utf8
  $exit=$process.ExitCode; $process.Dispose()
  return @{exit_code=$exit; text=$text}
}
function Assert-ProofSuccess {
  param($Result,[switch]$ExpectedRejection)
  $marker=if($ExpectedRejection) {'FLIGHT_PROOF_EXPECTED_REJECTION'} else {'FLIGHT_PROOF_OK'}
  if($Result.exit_code -ne 0 -or $Result.text -notmatch $marker -or $Result.text -notmatch 'FLIGHT_BRIDGE_INITIALIZED' -or $Result.text -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED' -or $Result.text -match 'ERROR:|FATAL:|SCRIPT ERROR:|ObjectDB instances leaked') { throw "Proof failed: required positive marker or clean shutdown missing; inspect log" }
}
function Write-ProofDependencyReport {
  param([string]$Payload,[string]$BuildManifest,[string]$Output)
  $compiler = (Get-Content -LiteralPath $BuildManifest | Where-Object { $_ -match '^Compiler path: ' }) -replace '^Compiler path: ',''
  if (-not $compiler) { throw 'Actual compiler identity missing for dependency inspection' }
  $dumpbin = Join-Path (Split-Path $compiler) 'dumpbin.exe'
  if (-not (Test-Path -LiteralPath $dumpbin)) { throw 'Actual compiler dependency inspector missing' }
  $records = @()
  foreach ($file in Get-ChildItem -LiteralPath $Payload -File -Recurse | Where-Object { $_.Extension -in @('.exe','.dll') }) {
    $outputText = & $dumpbin /dependents $file.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'PE dependency inspection failed' }
    $imports = @($outputText | ForEach-Object { if ($_ -match '^\s+([A-Za-z0-9_.-]+\.dll)\s*$') { $matches[1] } } | Sort-Object -Unique)
    $relative = [IO.Path]::GetRelativePath($Payload,$file.FullName).Replace('\','/')
    if ($file.Name -eq 'flight_godot_bridge.dll' -and 'JSBSim.dll' -notin $imports) { throw 'Bridge no longer imports replaceable JSBSim' }
    $records += [ordered]@{file=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();imports=$imports;inspection=($outputText -join "`n")}
  }
  [ordered]@{schema_version=1;architecture='x64';compiled_runtime='dynamic release MSVC /MD';files=$records;scope='PE import/deferred dependency inspection plus separate actual loaded JSBSim/CRT witnesses; GPU/render runtime closure is a later proof'} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Output -Encoding utf8
}
