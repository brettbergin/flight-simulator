[CmdletBinding()]
param([string]$Python = "python", [switch]$Offline, [switch]$WithGodot, [switch]$WithExportTemplates)
$ErrorActionPreference = "Stop"
$env:PYTHONDONTWRITEBYTECODE = "1"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
Push-Location $repoRoot
try {
    $bootstrapArgs = @("tools/bootstrap/bootstrap.py")
    if ($Offline) { $bootstrapArgs += "--offline" }
    if ($WithGodot) { $bootstrapArgs += "--with-godot" }
    if ($WithExportTemplates) { $bootstrapArgs += "--with-export-templates" }
    & $Python @bootstrapArgs
    if ($LASTEXITCODE -ne 0) { throw "Dependency bootstrap failed" }
    $environment = Get-Content ".local/toolchain/environment.json" -Raw | ConvertFrom-Json
    if ($env:OS -eq "Windows_NT") {
        $vswherePath = Join-Path ([Environment]::GetEnvironmentVariable("ProgramFiles(x86)")) "Microsoft Visual Studio/Installer/vswhere.exe"
        $installation = & $vswherePath -version "[17.0,18.0)" -latest -products "*" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $installation) { throw "MSVC 2022 x64 Build Tools not found" }
        $vcvars = Join-Path $installation "VC/Auxiliary/Build/vcvars64.bat"
        $compilerEnvironment = & $env:ComSpec /d /c ('"' + $vcvars + '" >nul && set')
        if ($LASTEXITCODE -ne 0) { throw "MSVC developer environment failed" }
        foreach ($line in $compilerEnvironment) {
            if ($line -match "^([^=]+)=(.*)$") { [Environment]::SetEnvironmentVariable($matches[1],$matches[2],"Process") }
        }
    }
    $env:PATH = (Split-Path $environment.tools.ninja) + [IO.Path]::PathSeparator + $env:PATH
    $cmake = $environment.tools.cmake
    $ctest = Join-Path (Split-Path $cmake) $(if ($env:OS -eq "Windows_NT") { "ctest.exe" } else { "ctest" })
    & $cmake --version
    & $environment.tools.ninja --version
    & $Python --version
    & $cmake --preset native-release "-DCMAKE_MAKE_PROGRAM=$($environment.tools.ninja)" "-DPython3_EXECUTABLE=$($environment.python_executable)"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
    & $cmake --build --preset native-release
    if ($LASTEXITCODE -ne 0) { throw "Native build failed" }
    & $ctest --preset native-release
    if ($LASTEXITCODE -ne 0) { throw "Native tests failed" }
    if ($env:OS -eq "Windows_NT") {
        $dependencies = & dumpbin /dependents ".local/build/native-release/bin/toolchain_smoke.exe"
        if ($LASTEXITCODE -ne 0 -or -not ($dependencies -match "JSBSim.dll")) { throw "Missing replaceable JSBSim DLL dependency" }
    } else {
        $dependencies = & ldd ".local/build/native-release/bin/toolchain_smoke"
        if ($LASTEXITCODE -ne 0 -or -not ($dependencies -match "libJSBSim.so")) { throw "Missing replaceable JSBSim shared dependency" }
    }
    $dependencies | Set-Content ".local/build/native-release/dynamic-dependencies.txt"
        $verifyArgs = @("tools/bootstrap/bootstrap.py", "--offline")
    if ($WithGodot) { $verifyArgs += "--with-godot" }
    if ($WithExportTemplates) { $verifyArgs += "--with-export-templates" }
    & $Python @verifyArgs
    if ($LASTEXITCODE -ne 0) { throw "Build modified a verified source/tool tree" }
    Get-Content ".local/build/native-release/toolchain-build-manifest.txt"
    if ($WithGodot) {
        & $environment.tools.godot --headless --version
        if ($LASTEXITCODE -ne 0) { throw "Pinned Godot executable failed" }
    }
} finally { Pop-Location }

