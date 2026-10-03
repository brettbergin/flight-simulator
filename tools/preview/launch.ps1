#Requires -Version 7.0
[CmdletBinding()]
param([switch]$HeadlessSmoke,[switch]$VisualSmoke)
$ErrorActionPreference='Stop'
if($HeadlessSmoke -and $VisualSmoke){throw 'Choose one smoke mode'}
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=Join-Path $PSScriptRoot 'AirbornePreview.exe'
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
$process=[Diagnostics.Process]::new()
$process.StartInfo=$info
if(!$process.Start()){throw 'Preview did not start'}
$stdout=$process.StandardOutput.ReadToEndAsync()
$stderr=$process.StandardError.ReadToEndAsync()
if($HeadlessSmoke -or $VisualSmoke) {
 if(!$process.WaitForExit(30000)){ $process.Kill($true); throw 'Preview smoke exceeded30seconds' }
} else { $process.WaitForExit() }
$log=if($VisualSmoke){'visual-smoke.log'}elseif($HeadlessSmoke){'portable-smoke.log'}else{'interactive.log'}
$output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
$output | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot $log)
$exit=$process.ExitCode
$process.Dispose()
Write-Output $output
if($exit -ne 0 -or $output -match 'ERROR:|SCRIPT ERROR:|FATAL|ObjectDB instance[s]? leaked|RID allocations leaked|resources still in use|Assertion failed') {throw "Preview exited witherrors ($exit); inspect $log"}
if($HeadlessSmoke -or $VisualSmoke) {
 $marker=if($VisualSmoke){'AIRBORNE_PREVIEW_VISUAL'}else{'AIRBORNE_PREVIEW_SMOKE'}
 $receiptName=if($VisualSmoke){'visual-receipt.json'}else{'smoke-receipt.json'}
 if($output -notmatch $marker -or $output -notmatch 'FLIGHT_BRIDGE_TERMINATED_JOINED') {throw 'Missing smoke/termination sentinel'}
 $receipt=Get-Content (Join-Path $PSScriptRoot $receiptName) -Raw | ConvertFrom-Json
 if($receipt.passed -ne $true -or $receipt.failures.Count -ne 0){throw 'Actual smoke assertions failed'}
}
