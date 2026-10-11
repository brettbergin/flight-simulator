#Requires -Version 7.0
[CmdletBinding()]
param([switch]$HeadlessSmoke,[switch]$VisualSmoke,[switch]$Airborne,[ValidateRange(1,600)][int]$SmokeTimeoutSeconds=120)
$ErrorActionPreference='Stop'
if($HeadlessSmoke -and $VisualSmoke){throw 'Choose one smoke mode'}
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=Join-Path $PSScriptRoot 'WholeFlightPreview.exe'
$info.WorkingDirectory=$PSScriptRoot
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$info.Environment.Clear()
$info.Environment['PATH']=''
$info.Environment['SystemRoot']=$env:SystemRoot
$info.Environment['WINDIR']=$env:WINDIR
$info.Environment['JSBSIM_DEBUG']='0'
$profile=Join-Path (Split-Path $PSScriptRoot -Parent) 'userdata'
$info.Environment['FLIGHT_PREVIEW_PROFILE_ROOT']=$profile.Replace('\','/')
foreach($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) {
 $directory=Join-Path $profile $name
 New-Item -ItemType Directory -Force $directory | Out-Null
 $info.Environment[$name]=$directory
}
if($HeadlessSmoke) { $info.ArgumentList.Add('--headless');$info.ArgumentList.Add('--');$info.ArgumentList.Add('--smoke') }
if($VisualSmoke) { $info.ArgumentList.Add('--');$info.ArgumentList.Add('--visual-smoke') }
if($Airborne){if(!$HeadlessSmoke -and !$VisualSmoke){$info.ArgumentList.Add('--');$info.ArgumentList.Add('--airborne')}else{throw 'Airborne is for human mode only'}}
$process=[Diagnostics.Process]::new()
$process.StartInfo=$info
$elapsed=[Diagnostics.Stopwatch]::StartNew()
if(!$process.Start()){throw 'Preview did not start'}
$stdout=$process.StandardOutput.ReadToEndAsync()
$stderr=$process.StandardError.ReadToEndAsync()
$log=if($VisualSmoke){'visual-smoke.log'}elseif($HeadlessSmoke){'portable-smoke.log'}else{'interactive.log'}
if($HeadlessSmoke -or $VisualSmoke) {
 if(!$process.WaitForExit($SmokeTimeoutSeconds*1000)){
  $terminationError=''
  try { $process.Kill($true) } catch { $terminationError=$_.Exception.Message }
  $joined=$process.WaitForExit(10000)
  $drained=$false; $drainError=''
  try { $drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),10000) } catch { $drainError=$_.Exception.Message }
  $output=if($stdout.IsCompletedSuccessfully){$stdout.GetAwaiter().GetResult()}else{'[stdout did not finish draining]'}
  $output+=if($stderr.IsCompletedSuccessfully){$stderr.GetAwaiter().GetResult()}else{'[stderr did not finish draining]'}
  $elapsed.Stop()
  $output+="`nPreview watchdog: elapsed_ms=$($elapsed.ElapsedMilliseconds); timeout_seconds=$SmokeTimeoutSeconds; joined=$joined; drained=$drained; termination_error=$terminationError; drain_error=$drainError"
  try { $output | Set-Content -LiteralPath (Join-Path $PSScriptRoot $log) -Encoding utf8 } finally { $process.Dispose() }
  Write-Output $output
  throw "Preview smoke exceeded $SmokeTimeoutSeconds seconds; raw log retained; joined=$joined; drained=$drained"
 }
} else { $process.WaitForExit() }
$elapsed.Stop()
$output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
if($HeadlessSmoke -or $VisualSmoke){$output+="`nPreview supervisor: elapsed_ms=$($elapsed.ElapsedMilliseconds); timeout_seconds=$SmokeTimeoutSeconds"}
$output | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot $log)
$exit=$process.ExitCode
$process.Dispose()
Write-Output $output
if($exit -ne 0 -or $output -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instances? (?:(?:was|were) )?leaked|RID allocations leaked|resources still in use|Assertion failed') {throw "Preview exited witherrors ($exit); inspect $log"}
if($HeadlessSmoke -or $VisualSmoke) {
 $marker=if($VisualSmoke){'WHOLE_FLIGHT_PREVIEW_VISUAL'}else{'WHOLE_FLIGHT_PREVIEW_SMOKE'}
 $receiptName=if($VisualSmoke){'visual-receipt.json'}else{'smoke-receipt.json'}
 if($output -notmatch $marker -or $output -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED') {throw 'Missing smoke/termination sentinel'}
 $receipt=Get-Content (Join-Path $PSScriptRoot $receiptName) -Raw | ConvertFrom-Json
 if($receipt.passed -ne $true -or $receipt.failures.Count -ne 0){throw 'Actual smoke assertions failed'}
}
