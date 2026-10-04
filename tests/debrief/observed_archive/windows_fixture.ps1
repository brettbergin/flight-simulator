# Original MIT. Independent fixed proof actor: synthetic test paths only.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$taskData = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:FS_ARCHIVE_TEST_DATA)) | ConvertFrom-Json
$taskRoot = [IO.Path]::GetFullPath($taskData.root)
if ([IO.Path]::GetFileName($taskRoot) -notmatch '^\.observed-archive-test-[a-f0-9]{32}$' -or -not [IO.Directory]::Exists($taskRoot)) { throw 'Test root' }
function ChildPath([string]$name) {
    if ($name -notmatch '^[a-z0-9.-]+$') { throw 'Test leaf' }
    return [IO.Path]::Combine($taskRoot,$name)
}
switch ($taskData.mode) {
    'lock' {
        # Closed fixed test hooks only; bounds concern actor lifecycle, not physics.
        if ($taskData.nonce -isnot [string] -or $taskData.lock_case -isnot [string] -or $taskData.nonce -notmatch '^[a-f0-9]{32}$' -or $taskData.nonce -ne [IO.Path]::GetFileName($taskRoot).Substring(23) -or $taskData.lock_case -notin @('','delayed-ready','expiry','early-exit')) { throw 'Lock data' }
        $actorPid = [Diagnostics.Process]::GetCurrentProcess().Id
        $utf8 = [Text.UTF8Encoding]::new($false)
        function LockMarker([string]$name,[string]$phase,[string]$reason) {
            $marker = @{ phase=$phase; nonce=$taskData.nonce; pid=$actorPid; reason=$reason } | ConvertTo-Json -Compress
            [IO.File]::WriteAllText((ChildPath $name),$marker,$utf8)
        }
        $file = $null
        $reason = 'failed'
        $exitCode = 2
        try {
            if ($taskData.lock_case -eq 'early-exit') {
                $reason = 'early_exit'
                $exitCode = 125
            } else {
                if ($taskData.lock_case -eq 'delayed-ready') { Start-Sleep -Milliseconds 6000 }
                $file = [IO.FileStream]::new((ChildPath 'locked.json'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                LockMarker 'lock-ready' 'LOCKED' 'held'
                # Lifetime begins after actual lock acquisition/readiness. This
                # covers the production actor's85s watchdog/caller100s deadline.
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $lease = if ($taskData.lock_case -eq 'expiry') { 1000 } else { 120000 }
                while ($true) {
                    if ($timer.ElapsedMilliseconds -ge $lease) {
                        $reason = 'expired'
                        $exitCode = 124
                        break
                    }
                    if ([IO.File]::Exists((ChildPath 'lock-release'))) {
                        try {
                            $release = [IO.File]::ReadAllText((ChildPath 'lock-release'),$utf8) | ConvertFrom-Json
                            $keys = @($release.PSObject.Properties.Name | Sort-Object)
                            if (($keys -join ',') -eq 'nonce,phase,pid,reason' -and $release.phase -is [string] -and $release.reason -is [string] -and $release.nonce -is [string] -and ($release.pid -is [int] -or $release.pid -is [long]) -and $release.phase -ceq 'RELEASE' -and $release.reason -ceq 'requested' -and $release.nonce -ceq $taskData.nonce -and $release.pid -eq $actorPid) {
                                $reason = 'released'
                                $exitCode = 0
                                break
                            }
                        } catch {} # Partial/foreign requests cannot release the lock.
                    }
                    Start-Sleep -Milliseconds 10
                }
            }
        } finally {
            if ($null -ne $file) { $file.Dispose() }
            LockMarker 'lock-closed' 'CLOSED' $reason
        }
        # Disposal acknowledgement is not process retirement; caller observes exit.
        [Environment]::Exit($exitCode)
    }
    'junction-create' {
        $target = ChildPath 'junction-real'
        $link = ChildPath 'junction-link'
        $null = [IO.Directory]::CreateDirectory($target)
        $null = New-Item -ItemType Junction -Path $link -Target $target
        if (([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'No actual reparse point' }
        Write-Output 'JUNCTION_READY'
    }
    'junction-remove' {
        $link = ChildPath 'junction-link'
        if (([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'Refuse ordinary root removal' }
        # Only this owned link, never recurse/follow into its target.
        Remove-Item -LiteralPath $link -Force
        if ([IO.Directory]::Exists($link)) { throw 'Link remains' }
        [IO.Directory]::Delete((ChildPath 'junction-real'),$false)
        Write-Output 'JUNCTION_REMOVED'
    }
    'move-collision' {
        $source = ChildPath 'move-source'
        $target = ChildPath 'move-existing'
        $sourceBytes = [byte[]](1,2,3,4)
        $targetBytes = [byte[]](9,8,7,6)
        [IO.File]::WriteAllBytes($source,$sourceBytes)
        [IO.File]::WriteAllBytes($target,$targetBytes)
        $refused = $false
        try { [IO.File]::Move($source,$target) }
        catch [IO.IOException] { $refused = $true }
        if (-not $refused -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($source)) -ne [Convert]::ToBase64String($sourceBytes) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -ne [Convert]::ToBase64String($targetBytes)) { throw 'Move replaced/lost bytes' }
        Write-Output 'MOVE_REFUSED_BYTES_UNCHANGED'
    }
    default { throw 'Unknown fixed proof mode' }
}
