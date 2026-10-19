[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Create', 'Qualify')][string]$Mode,
    [Parameter(Mandatory)][string]$BaselinePython,
    [Parameter(Mandatory)][string]$RuntimeManifest,
    [Parameter(Mandatory)][string]$Inputs,
    [Parameter(Mandatory)][string]$ToolRoot,
    [Parameter(Mandatory)][string]$ReceiptRoot,
    [string]$Raster
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$manifestPin = 'c29e5f964803bdaa81cf835ee47493cc50cc84712b4a13512f69c9fbfa62c8f7'
$exePin = 'd41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c'
$dllPin = '8bb70bceffd5877733a957b31c392ca027bd2f84230e00de1654f994422fa2af'
$licensePin = '886a0ead2d89030ee62dbff52b04e47ab91998341295bb9c56fb952b4e081c7a'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$localRoot = Join-Path $repoRoot '.local'

function Assert-PlainPath([string]$Candidate) {
    if (-not [IO.Path]::IsPathRooted($Candidate)) { throw 'An absolute path is required.' }
    $full = [IO.Path]::GetFullPath($Candidate)
    if ($full.StartsWith('\\') -or $full.Substring(2).Contains(':')) { throw 'UNC and alternate-stream paths are not accepted.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -Force -LiteralPath $cursor
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse path refused: $cursor" }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
    return $full
}
function Assert-LocalOutput([string]$Candidate) {
    $full = Assert-PlainPath $Candidate
    $prefix = [IO.Path]::GetFullPath($localRoot).TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Outputs must be inside this checkout .local directory.' }
    return $full
}
function Assert-Hash([string]$Path, [string]$Expected, [long]$Bytes = -1) {
    $actual = Get-Item -Force -LiteralPath (Assert-PlainPath $Path)
    if ($actual.PSIsContainer) { throw "File required: $Path" }
    if ($Bytes -ge 0 -and $actual.Length -ne $Bytes) { throw "Size mismatch: $Path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() -cne $Expected) { throw "SHA256 mismatch: $Path" }
}

function Assert-Disjoint([string]$Left, [string]$Right) {
    $a = $Left.TrimEnd('\')
    $b = $Right.TrimEnd('\')
    if ($a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Input/output roots must be disjoint.' }
}
$baseline = Assert-PlainPath $BaselinePython
$manifestPath = Assert-PlainPath $RuntimeManifest
$inputPath = Assert-PlainPath $Inputs
$tool = Assert-LocalOutput $ToolRoot
$receipt = Assert-LocalOutput $ReceiptRoot
foreach ($sourcePath in @([IO.Path]::GetDirectoryName($baseline), $manifestPath, $inputPath)) {
    Assert-Disjoint $receipt $sourcePath
    Assert-Disjoint $tool $sourcePath
}
Assert-Disjoint $receipt $tool
if ($Raster) {
    $rasterPath = Assert-PlainPath $Raster
    Assert-Disjoint $receipt $rasterPath
    Assert-Disjoint $tool $rasterPath
}
if (Test-Path -LiteralPath $receipt) { throw 'Receipt directory already exists; use a fresh path.' }
[IO.Directory]::CreateDirectory($receipt) | Out-Null
$report = [ordered]@{ schema = 'TerrainToolLauncher/v1'; mode = $Mode; started_utc = [DateTime]::UtcNow.ToString('o'); passed = $false }
$exitCode = 1
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
    Assert-Hash $manifestPath $manifestPin
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
    if ($manifest.schema -cne 'RootFrozenInstalledPythonToolRuntime/v1' -or $manifest.source_and_copy_raw_exact -ne $true) { throw 'Wrong retained-runtime manifest.' }
    $baseRoot = Assert-PlainPath ([IO.Path]::GetDirectoryName($baseline))
    if (-not $baseRoot.Equals([IO.Path]::GetFullPath($manifest.frozen_root), [StringComparison]::OrdinalIgnoreCase)) { throw 'Baseline must be the manifest frozen_root, not a PATH interpreter or unrecorded copy.' }
    Assert-Hash $baseline $exePin 107312
    Assert-Hash (Join-Path $baseRoot 'python312.dll') $dllPin
    Assert-Hash (Join-Path $baseRoot 'LICENSE.txt') $licensePin
    $expectedFiles = @{}
    $expectedDirs = @{}
    foreach ($entry in $manifest.files) {
        $name = [string]$entry.path
        if ($name -notmatch '^[^\\:]+$' -or $name.StartsWith('/') -or $name.Split('/') -contains '..' -or $expectedFiles.ContainsKey($name)) { throw 'Invalid baseline file roster.' }
        $expectedFiles.Add($name, $entry)
    }
    foreach ($name in $manifest.directories) {
        if ($expectedDirs.ContainsKey([string]$name)) { throw 'Duplicate baseline directory.' }
        $expectedDirs.Add([string]$name, $true)
    }
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($baseRoot)
    [long]$totalBytes = 0
    $seenFiles = 0
    $seenDirs = 0
    while ($pending.Count) {
        $directory = $pending.Dequeue()
        foreach ($item in Get-ChildItem -Force -LiteralPath $directory) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Baseline reparse member: $($item.FullName)" }
            $relative = $item.FullName.Substring($baseRoot.Length + 1).Replace('\', '/')
            if ($item.PSIsContainer) {
                if (-not $expectedDirs.ContainsKey($relative)) { throw "Unrecorded baseline directory: $relative" }
                $seenDirs++
                $pending.Enqueue($item.FullName)
            } else {
                if (-not $expectedFiles.ContainsKey($relative)) { throw "Unrecorded baseline file: $relative" }
                $entry = $expectedFiles[$relative]
                Assert-Hash $item.FullName ([string]$entry.sha256) ([long]$entry.bytes)
                $totalBytes += $item.Length
                $seenFiles++
            }
        }
    }
    if ($seenFiles -ne $expectedFiles.Count -or $seenDirs -ne $expectedDirs.Count) { throw 'Missing baseline file or directory.' }
    $report['baseline'] = [ordered]@{ executable = $baseline; manifest = $manifestPath; manifest_sha256 = $manifestPin; files = $seenFiles; directories = $seenDirs; bytes = $totalBytes; checked_before_python_process = $true }
    $report['source'] = [ordered]@{
        launcher_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        worker_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'terrain_tools.py') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $report['passed'] = $true
    $report['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $receipt 'launcher.json'), ($report | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $arguments = @('-I', '-B', '-S', (Join-Path $PSScriptRoot 'terrain_tools.py'), $Mode.ToLowerInvariant(), '--baseline', $baseline, '--runtime-manifest', $manifestPath, '--inputs', $inputPath, '--tool-root', $tool, '--receipt-root', $receipt)
    if ($Raster) { $arguments += @('--raster', (Assert-PlainPath $Raster)) }
    & $baseline @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "Terrain worker failed with exit code $exitCode; retain this receipt directory." }
} catch {
    $report['error'] = $_.Exception.Message
    $report['passed'] = $false
    $report['finished_utc'] = [DateTime]::UtcNow.ToString('o')
    # The directory is new and private to this attempt; preserve even pre-Python failure.
    $failurePath = Join-Path $receipt 'launcher-failure.json'
    if (-not (Test-Path -LiteralPath $failurePath)) {
        [IO.File]::WriteAllText($failurePath, ($report | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    }
    Write-Error -ErrorAction Continue $_.Exception.Message
    $exitCode = 1
}
exit $exitCode
