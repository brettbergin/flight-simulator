[CmdletBinding()]
param(
    [string]$ToolchainRoot = '.local/toolchain',
    [string]$BuildDirectory = '.local/resident-grid-ci'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Absolute-Path([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}
$toolRoot = Absolute-Path $ToolchainRoot
$buildRoot = Absolute-Path $BuildDirectory
if (Test-Path -LiteralPath $buildRoot) { throw 'Use a fresh resident-grid build directory; preserve earlier evidence.' }
$environment = Get-Content -LiteralPath (Join-Path $toolRoot 'environment.json') -Raw | ConvertFrom-Json
if ($env:OS -eq 'Windows_NT') {
    foreach ($option in @('CL','_CL_')) {
        if ([Environment]::GetEnvironmentVariable($option,'Process')) { throw "Implicit compiler options are not admitted: $option" }
    }
    $vswhere = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -version '[17.0,18.0)' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $installation) { throw 'MSVC 2022 x64 tools missing' }
    $vcvars = Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
    $compilerEnvironment = & $env:ComSpec /d /c ('"' + $vcvars + '" >nul && set')
    if ($LASTEXITCODE -ne 0) { throw 'MSVC environment failed' }
    foreach ($line in $compilerEnvironment) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process') }
    }
}
$cmake = $environment.tools.cmake
$ctest = Join-Path (Split-Path $cmake) $(if ($env:OS -eq 'Windows_NT') { 'ctest.exe' } else { 'ctest' })
[IO.Directory]::CreateDirectory($buildRoot) | Out-Null
& $cmake -S (Join-Path $repoRoot 'tests/ground/grid') -B $buildRoot -G Ninja "-DCMAKE_MAKE_PROGRAM=$($environment.tools.ninja)" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'configure.log')
if ($LASTEXITCODE -ne 0) { throw 'Resident-grid configuration failed' }
& $cmake --build $buildRoot --verbose 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'build.log')
if ($LASTEXITCODE -ne 0) { throw 'Resident-grid compilation failed' }
& $ctest --test-dir $buildRoot --output-on-failure --no-tests=error --timeout 240 2>&1 | Tee-Object -FilePath (Join-Path $buildRoot 'ctest.log')
if ($LASTEXITCODE -ne 0) { throw 'Resident-grid tests failed' }
