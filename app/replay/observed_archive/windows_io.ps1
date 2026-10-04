# Original MIT. ADR012 fixed private IO actor. All selected paths/bytes arrive as
# bounded binary stdin data, never executable PowerShell text. No overwrite/delete.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:inputStream = [Console]::OpenStandardInput()
$script:outputStream = [Console]::OpenStandardOutput()
$script:utf8 = [Text.UTF8Encoding]::new($false, $true)
$script:ownedTemp = $false
$script:target = ''
$script:temporary = ''
$script:installed = $false
$script:commitAttempted = $false
$script:file = $null
# Separate fixed runspace: timeout terminates this actor only. The caller observes
# actual process exit before returning; no OS.kill-as-join or detached writer.
$deadline = [PowerShell]::Create()
$null = $deadline.AddScript('Start-Sleep -Seconds 85; [Environment]::Exit(124)')
$deadlineRun = $deadline.BeginInvoke()

function Read-Exact([int]$count) {
    if ($count -lt 0 -or $count -gt 8388608) { throw 'Bound' }
    $bytes = [byte[]]::new($count)
    $offset = 0
    while ($offset -lt $count) {
        $task = $script:inputStream.ReadAsync($bytes, $offset, $count - $offset)
        if (-not $task.Wait(30000)) { throw 'Timeout' }
        $received = $task.Result
        if ($received -eq 0) { throw 'Truncated' }
        $offset += $received
    }
    return ,$bytes
}
function Read-UInt32 {
    return [BitConverter]::ToUInt32((Read-Exact 4), 0)
}
function Read-Text([int]$limit) {
    $count = Read-UInt32
    if ($count -gt $limit) { throw 'Bound' }
    return $script:utf8.GetString((Read-Exact ([int]$count)))
}
function Send-Frame([string]$code) {
    $temp = if ($script:ownedTemp -and -not $script:installed) { $script:temporary } else { '' }
    $text = @{ code = $code; path = $script:target; temp = $temp } | ConvertTo-Json -Compress
    $bytes = $script:utf8.GetBytes($text)
    if ($bytes.Length -gt 65536) { throw 'Receipt bound' }
    $script:outputStream.Write([BitConverter]::GetBytes([uint32]$bytes.Length), 0, 4)
    $script:outputStream.Write($bytes, 0, $bytes.Length)
    $script:outputStream.Flush()
}
function Guard-Path([string]$requested, [bool]$opening) {
    if ($requested.Length -eq 0 -or $requested.Length -gt 4096 -or $requested -notmatch '^[A-Za-z]:[\\/]') { throw 'Path' }
    if ($requested.Substring(2).Contains(':') -or $requested.Contains([char]0)) { throw 'Path' }
    $resolved = [IO.Path]::GetFullPath($requested)
    foreach ($part in $resolved.Substring(3).Split([char[]]@('\','/'))) {
        if ($part.Length -eq 0 -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'Path' }
    }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($resolved))
    if (-not $drive.IsReady -or $drive.DriveType -eq [IO.DriveType]::Network -or $drive.DriveFormat -ne 'NTFS') { throw 'Filesystem' }
    $parent = [IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($resolved))
    if (-not $parent.Exists) { throw 'Parent' }
    while ($null -ne $parent) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse' }
        $parent = $parent.Parent
    }
    # GetAttributes detects dangling reparse entries too; File.Exists alone doesn't.
    $present = $false
    try { $attributes = [IO.File]::GetAttributes($resolved); $present = $true }
    catch [IO.FileNotFoundException] {}
    catch [IO.DirectoryNotFoundException] {}
    if ($present -and (($attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0)) { throw 'Target kind' }
    if ($opening -and -not $present) { throw 'Missing' }
    if (-not $opening -and $present) { throw 'Collision' }
    return $resolved
}
try {
    if ($script:utf8.GetString((Read-Exact 7)) -ne 'FSAR001') { throw 'Magic' }
    $operation = (Read-Exact 1)[0]
    $fault = (Read-Exact 1)[0]
    if ($operation -notin @(1,2) -or $fault -gt 6) { throw 'Operation' }
    $requested = Read-Text 16384
    $temporaryName = Read-Text 80
    $size = Read-UInt32
    if ($size -gt 8388608 -or ($operation -eq 2 -and ($size -ne 0 -or $temporaryName -ne '' -or $fault -ne 0))) { throw 'Bound' }
    $script:target = Guard-Path $requested ($operation -eq 2)
    if ($operation -eq 2) {
        $script:file = [IO.FileStream]::new($script:target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $length = $script:file.Length
        if ($length -le 0 -or $length -gt 8388608) { throw 'Bound' }
        $bytes = [byte[]]::new([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $received = $script:file.Read($bytes, $offset, $bytes.Length-$offset)
            if ($received -eq 0) { throw 'Truncated' }
            $offset += $received
        }
        if ($script:file.ReadByte() -ne -1) { throw 'Changed' }
        $script:file.Dispose(); $script:file = $null
        Send-Frame 'OPEN'
        $script:outputStream.Write([BitConverter]::GetBytes([uint32]$bytes.Length), 0, 4)
        $script:outputStream.Write($bytes, 0, $bytes.Length)
        $script:outputStream.Flush()
        [Environment]::Exit(0)
    }
    if ($size -eq 0 -or $temporaryName -notmatch '^\.fsreview-[0-9a-f]{32}\.tmp$') { throw 'Temporary' }
    $script:temporary = [IO.Path]::Combine([IO.Path]::GetDirectoryName($script:target), $temporaryName)
    $script:file = [IO.FileStream]::new($script:temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $script:ownedTemp = $true
    Send-Frame 'READY'
    $bytes = Read-Exact ([int]$size)
    if ($fault -eq 1) { throw 'Write fixture' }
    $script:file.Write($bytes, 0, $bytes.Length)
    if ($fault -eq 2) { throw 'Flush fixture' }
    $script:file.Flush($true)
    $script:file.Dispose(); $script:file = $null
    Send-Frame 'PREPARED'
    # One explicit commit byte after caller's complete temp reread/decode.
    if ((Read-Exact 1)[0] -ne 67) { throw 'Commit' }
    if ($fault -eq 3) { throw 'Move fixture' }
    $again = Guard-Path $requested $false
    if (-not [String]::Equals($again,$script:target,[StringComparison]::Ordinal)) { throw 'Changed path' }
    if (([IO.File]::GetAttributes($script:temporary) -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) { throw 'Temporary kind' }
    # The no-overwrite OS call, not the guard check, protects target-creation races.
    $script:commitAttempted = $true
    [IO.File]::Move($script:temporary, $script:target)
    $script:installed = $true
    if ($fault -eq 4) { Send-Frame 'BROKEN'; [Environment]::Exit(3) }
    Send-Frame 'DONE'
    [Environment]::Exit(0)
} catch {
    if ($null -ne $script:file) { $script:file.Dispose(); $script:file = $null }
    try { Send-Frame $(if ($script:commitAttempted) { 'UNCERTAIN' } elseif ($script:ownedTemp) { 'FAILED' } else { 'REJECTED' }) } catch {}
    [Environment]::Exit(2)
}
