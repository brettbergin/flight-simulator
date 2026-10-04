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
        $file = $null
        try {
            $file = [IO.FileStream]::new((ChildPath 'locked.json'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            [IO.File]::WriteAllText((ChildPath 'lock-ready'),'READY')
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while (-not [IO.File]::Exists((ChildPath 'lock-release'))) {
                if ($timer.ElapsedMilliseconds -gt 15000) { throw 'Fixture release timeout' }
                Start-Sleep -Milliseconds 10
            }
        } finally {
            if ($null -ne $file) { $file.Dispose() }
            [IO.File]::WriteAllText((ChildPath 'lock-closed'),'CLOSED')
        }
        [Environment]::Exit(0)
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
