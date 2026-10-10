[CmdletBinding()]
param(
    [string]$Python = "python", [switch]$Offline, [switch]$WithGodot, [switch]$WithExportTemplates,
    [switch]$UseEventAwareJSBSim,
    [ValidateSet("event-aware-constant-power-v1", "event-aware-coupled-midpoint-v1")][string]$PatchedSourceVariant,
    [switch]$ConfigureAndBuildOnly, [switch]$RunTestsOnly,
    [string]$BuildDirectory, [string]$SourceBundleRoot, [string]$SourcePreparationDirectory,
    [string]$PretrialRatification, [string]$ExecutionRatification,
    [string]$ProbeExecutionRatification, [switch]$HeadlessNative
)
$ErrorActionPreference = "Stop"
if ($UseEventAwareJSBSim -and $PatchedSourceVariant -and $PatchedSourceVariant -ne "event-aware-constant-power-v1") { throw "Conflicting patched variant and legacy held-power selector" }
$useModifiedSource = $UseEventAwareJSBSim -or -not [String]::IsNullOrEmpty($PatchedSourceVariant)
$selectedVariant = if ($PatchedSourceVariant) { $PatchedSourceVariant } else { "event-aware-constant-power-v1" }
$sourceSelector = if ($selectedVariant -eq "event-aware-coupled-midpoint-v1") { "tools/bootstrap/coupled-source-variant.py" } else { "tools/bootstrap/source-variant.py" }
$sourceValidationFlag = if ($selectedVariant -eq "event-aware-coupled-midpoint-v1") { "--coupled-midpoint" } else { "--event-aware" }
$isCoupledVariant = $useModifiedSource -and $selectedVariant -eq "event-aware-coupled-midpoint-v1"
if ($HeadlessNative -and ($WithGodot -or $WithExportTemplates)) { throw "Headless native stage cannot request Godot tools/exports" }
if ($ProbeExecutionRatification -and -not $isCoupledVariant) { throw "Probe authorization applies only to the coupled midpoint route" }
$numericalUnits = if ($selectedVariant -eq "event-aware-coupled-midpoint-v1") { @("FGPiston.cpp", "FGPropeller.cpp") } else { @("FGPropeller.cpp") }
$env:PYTHONDONTWRITEBYTECODE = "1"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
function Full-Path([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Value))
}
function File-Sha([string]$Value) { return (Get-FileHash -LiteralPath $Value -Algorithm SHA256).Hash.ToLowerInvariant() }
function Write-NewJson([string]$Path, $Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 12) + "`n")
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}
function Assert-StrictFpText([string]$CommandText, [string]$Label) {
    if (-not $CommandText) { throw "$Label command absent" }
    if ($env:OS -eq "Windows_NT") {
        if ($CommandText -notmatch '(^|[\s"])/fp:strict($|[\s"])' -or $CommandText -match '(^|[\s"])/fp:(fast|precise)($|[\s"])') { throw "$Label lacks unambiguous /fp:strict" }
    } else {
        foreach ($flag in @("-fno-fast-math", "-ffp-contract=off", "-frounding-math")) {
            if ($CommandText -notmatch ('(^|[\s"])' + [regex]::Escape($flag) + '($|[\s"])')) { throw "$Label lacks $flag" }
        }
        if ($CommandText -match '(^|[\s"])(-ffast-math|-Ofast|-ffp-contract=(fast|on)|-fno-rounding-math)($|[\s"])') { throw "$Label contains conflicting FP flags" }
    }
}
function Assert-BindingRoute([string]$BuildRoot) {
    $expected = if ($HeadlessNative) { "OFF" } else { "ON" }
    $actual = @(Get-Content -LiteralPath (Join-Path $BuildRoot "CMakeCache.txt") | Where-Object { $_ -cmatch '^FLIGHT_BUILD_GODOT_BINDINGS:BOOL=(ON|OFF)$' })
    if ($actual.Count -ne 1 -or $actual[0] -cne ("FLIGHT_BUILD_GODOT_BINDINGS:BOOL=" + $expected)) { throw "Actual Godot bindings cache differs from the recorded headless route" }
}
function Assert-NumericalCompileCommands([string]$BuildRoot, [string]$SelectedSourceRoot, [switch]$CheckActualBuild) {
    $commands = @(Get-Content -LiteralPath (Join-Path $BuildRoot "compile_commands.json") -Raw | ConvertFrom-Json)
    foreach ($unit in $numericalUnits) {
        $expectedFile = [IO.Path]::GetFullPath((Join-Path $SelectedSourceRoot ("src/models/propulsion/" + $unit)))
        $entries = @($commands | Where-Object {
            $sourceFile = if ([IO.Path]::IsPathRooted($_.file)) { $_.file } else { Join-Path $_.directory $_.file }
            [IO.Path]::GetFullPath($sourceFile) -eq $expectedFile
        })
        if ($entries.Count -ne 1) { throw "Expected exactly one actual selected $unit compile command" }
        $command = if ($entries[0].arguments) { $entries[0].arguments -join " " } else { $entries[0].command }
        Assert-StrictFpText $command "Configured $unit"
        if ($CheckActualBuild) {
            $needle = $expectedFile.Replace([char]92, [char]47)
            $actual = @(Get-Content -LiteralPath (Join-Path $BuildRoot "native-verbose-build.log") | Where-Object {
                $line = $_.Replace([char]92, [char]47)
                $line.Contains($needle) -and $line -match '(^|[\s"])(/c|-c)($|[\s"])'
            })
            if ($actual.Count -ne 1) { throw "Expected exactly one actual verbose $unit compiler invocation" }
            Assert-StrictFpText $actual[0] "Actual $unit"
        }
        Write-Output "Verified actual selected $unit compiler declaration"
    }
}

if ($useModifiedSource) {
    if ([bool]$ConfigureAndBuildOnly -eq [bool]$RunTestsOnly) { throw "Choose exactly one ON stage: -ConfigureAndBuildOnly or -RunTestsOnly" }
    if (-not $PretrialRatification -or -not $ExecutionRatification) { throw "ON requires explicit pretrial and execution authorization paths" }
    $pretrialPath = (Resolve-Path -LiteralPath (Full-Path $PretrialRatification)).Path
    if (-not (Test-Path -LiteralPath $pretrialPath -PathType Leaf)) { throw "Pretrial authorization must be a file" }
    $executionPath = Full-Path $ExecutionRatification
    $probeExecutionPath = if ($isCoupledVariant) {
        if (-not $ProbeExecutionRatification) { throw "Coupled route requires explicit -ProbeExecutionRatification" }
        Full-Path $ProbeExecutionRatification
    } else { "" }
    if ($RunTestsOnly -and $isCoupledVariant -and -not (Test-Path -LiteralPath $probeExecutionPath -PathType Leaf)) { throw "Unit execution identity must exist before coupled test stage" }
    if ($RunTestsOnly -and -not (Test-Path -LiteralPath $executionPath -PathType Leaf)) { throw "Execution authorization must exist before the test stage" }
    if ($SourceBundleRoot -and $SourcePreparationDirectory) { throw "Choose readonly source reuse or fresh preparation, not both" }
    if ($RunTestsOnly -and (-not $BuildDirectory -or $SourcePreparationDirectory)) { throw "Test stage requires the existing explicit build directory and cannot prepare new source" }
    $chosenBuildRoot = if ($BuildDirectory) { Full-Path $BuildDirectory } else { Join-Path $repoRoot (".local/build/event-aware-" + [Guid]::NewGuid().ToString("N")) }
    if ($ConfigureAndBuildOnly -and (Test-Path -LiteralPath $chosenBuildRoot)) { throw "ON compilation requires a fresh build directory; preserve previous builds" }
    if ($RunTestsOnly -and -not (Test-Path -LiteralPath $chosenBuildRoot -PathType Container)) { throw "Existing ON build directory missing" }
} elseif ($ConfigureAndBuildOnly -or $RunTestsOnly -or $BuildDirectory -or $SourceBundleRoot -or $SourcePreparationDirectory -or $PretrialRatification -or $ExecutionRatification -or $ProbeExecutionRatification -or $HeadlessNative) {
    throw "Staged/source/auth options require an explicit patched source selector; OFF retains its existing preset route"
} else { $chosenBuildRoot = Join-Path $repoRoot ".local/build/native-release" }
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
    if ($useModifiedSource -and $env:OS -eq "Windows_NT") {
        # MSVC applies these outside compile_commands.json; do not silently
        # clear user options or let an implicit /fp mode override qualification.
        foreach ($implicitOptions in @("CL", "_CL_")) {
            if (-not [String]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($implicitOptions, "Process"))) { throw "Event-aware qualification requires unset $implicitOptions; implicit compiler options are not admitted" }
        }
    }
    $env:PATH = (Split-Path $environment.tools.ninja) + [IO.Path]::PathSeparator + $env:PATH
    $cmake = $environment.tools.cmake
    $ctest = Join-Path (Split-Path $cmake) $(if ($env:OS -eq "Windows_NT") { "ctest.exe" } else { "ctest" })
    & $cmake --version
    & $environment.tools.ninja --version
    & $Python --version
    if ($useModifiedSource) {
        $routeFile = Join-Path $chosenBuildRoot "event-aware-route.json"
        $buildResultFile = Join-Path $chosenBuildRoot "event-aware-build-result.json"
        if ($RunTestsOnly) {
            $route = Get-Content -LiteralPath $routeFile -Raw | ConvertFrom-Json
            $buildResult = Get-Content -LiteralPath $buildResultFile -Raw | ConvertFrom-Json
            if ($route.schema_version -ne 1 -or $buildResult.schema_version -ne 1 -or $buildResult.status -ne "COMPILED_NOT_TESTED") { throw "A completed staged build receipt is required" }
            if ($route.repository_root -ne $repoRoot -or $route.build_directory -ne $chosenBuildRoot -or $buildResult.route_sha256 -ne (File-Sha $routeFile)) { throw "Build route differs from the recorded repository/directory" }
            if ($route.pretrial_sha256 -ne (File-Sha $pretrialPath) -or $route.pretrial_path -ne $pretrialPath -or $route.execution_path -ne $executionPath) { throw "Authorization identities/paths differ from the compiled route" }
            if ([bool]$route.headless_native -ne [bool]$HeadlessNative -or $route.probe_execution_path -ne $probeExecutionPath) { throw "Headless/probe route differs from compilation" }
            if ($route.build_entry_sha256 -ne (File-Sha $PSCommandPath)) { throw "Build entry changed after the staged compilation" }
            if ($buildResult.cmake_cache_sha256 -ne (File-Sha (Join-Path $chosenBuildRoot "CMakeCache.txt")) -or $buildResult.compile_commands_sha256 -ne (File-Sha (Join-Path $chosenBuildRoot "compile_commands.json"))) { throw "Build configuration/commands changed after compilation" }
            if ($SourceBundleRoot -and (Full-Path $SourceBundleRoot) -ne $route.source_bundle_root) { throw "Requested source differs from the compiled route" }
            $SourceBundleRoot = $route.source_bundle_root
        }
        if ($SourceBundleRoot) {
            $bundleRoot = (Resolve-Path -LiteralPath (Full-Path $SourceBundleRoot)).Path
            $sourceArguments = @($sourceSelector, $sourceValidationFlag, "--source-root", (Join-Path $bundleRoot "vendor"))
        } else {
            $preparationRoot = if ($SourcePreparationDirectory) { Full-Path $SourcePreparationDirectory } else { Join-Path $repoRoot (".local/event-aware-source/" + [Guid]::NewGuid().ToString("N")) }
            if (Test-Path -LiteralPath $preparationRoot) { throw "Source preparation output must be fresh; use -SourceBundleRoot for readonly reuse" }
            New-Item -ItemType Directory -Force -Path (Split-Path $preparationRoot) | Out-Null
            $sourceArguments = @($sourceSelector, "--source-root", (Join-Path $repoRoot ".local/deps/jsbsim"), "--prepare", $preparationRoot)
            $bundleRoot = Join-Path $preparationRoot "source"
        }
        $selectionOutput = & $Python @sourceArguments
        if ($LASTEXITCODE -ne 0) { throw "Reviewed source preparation/readonly verification failed" }
        $selection = ($selectionOutput -join "`n") | ConvertFrom-Json
        if ($selection.source_variant -ne ("jsbsim-1.3.1-" + $selectedVariant)) { throw "Wrong selected source variant" }
        if ($ConfigureAndBuildOnly) {
            New-Item -ItemType Directory -Path $chosenBuildRoot | Out-Null
            $route = [ordered]@{ schema_version=1; status="PRETRIAL_BUILD_ROUTE"; repository_root=$repoRoot; build_directory=$chosenBuildRoot; source_bundle_root=$bundleRoot; backend_identity_sha256=$selection.backend_identity_sha256; source_variant=$selection.source_variant; pretrial_path=$pretrialPath; pretrial_sha256=(File-Sha $pretrialPath); execution_path=$executionPath; probe_execution_path=$probeExecutionPath; headless_native=[bool]$HeadlessNative; build_entry_sha256=(File-Sha $PSCommandPath) }
            Write-NewJson $routeFile $route
            $coupledConfigure = @()
            if ($isCoupledVariant) { $coupledConfigure += "-DFLIGHT_COUPLED_PROBE_EXECUTION_RATIFICATION=$probeExecutionPath" }
            if ($HeadlessNative) { $coupledConfigure += "-DFLIGHT_BUILD_GODOT_BINDINGS=OFF" }
            & $cmake --preset native-release -B $chosenBuildRoot "-DCMAKE_MAKE_PROGRAM=$($environment.tools.ninja)" "-DPython3_EXECUTABLE=$($environment.python_executable)" -DFLIGHT_USE_EVENT_AWARE_JSBSIM=OFF "-DFLIGHT_JSBSIM_VARIANT=$selectedVariant" "-DFLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT=$bundleRoot" "-DFLIGHT_PISTON_PRETRIAL_RATIFICATION=$pretrialPath" "-DFLIGHT_PISTON_EXECUTION_RATIFICATION=$executionPath" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON @coupledConfigure
            if ($LASTEXITCODE -ne 0) { throw "Event-aware CMake configure failed; preserve this directory" }
            Assert-BindingRoute $chosenBuildRoot
            Assert-NumericalCompileCommands $chosenBuildRoot $selection.source_root
            & $cmake --build $chosenBuildRoot --parallel 8 --verbose 2>&1 | Tee-Object -FilePath (Join-Path $chosenBuildRoot "native-verbose-build.log")
            if ($LASTEXITCODE -ne 0) { throw "Event-aware build failed; preserve this directory" }
            Assert-BindingRoute $chosenBuildRoot
            Assert-NumericalCompileCommands $chosenBuildRoot $selection.source_root -CheckActualBuild
        } else {
            if ($route.source_variant -ne $selection.source_variant) { throw "Requested source variant differs from the compiled route" }
            if ($buildResult.verbose_build_sha256 -ne (File-Sha (Join-Path $chosenBuildRoot "native-verbose-build.log"))) { throw "Actual compiler evidence changed after compilation" }
            if ($route.backend_identity_sha256 -ne $selection.backend_identity_sha256) { throw "Readonly selected source differs from the compiled backend" }
            Assert-BindingRoute $chosenBuildRoot
            Assert-NumericalCompileCommands $chosenBuildRoot $selection.source_root -CheckActualBuild
            $discoveryOutput = & $ctest --test-dir $chosenBuildRoot --show-only=json-v1
            if ($LASTEXITCODE -ne 0) { throw "CTest discovery failed" }
            $discovery = ($discoveryOutput -join "`n") | ConvertFrom-Json
            if (-not ($discovery.tests.name -contains "piston_engine_lifecycle")) { throw "Required actual coupled test is missing; no test bypass permitted" }
            if ($isCoupledVariant) {
                foreach ($name in @("coupled_shaft_math", "coupled_shaft_native")) {
                    if (-not ($discovery.tests.name -contains $name)) { throw "Mandatory coupled qualification test missing: $name" }
                }
            }
            # Later read-only CTest discovery can replace LastTest.log. Retain
            # the full invocation separately, including failed test output.
            & $ctest --test-dir $chosenBuildRoot --output-on-failure --no-tests=error 2>&1 | Tee-Object -FilePath (Join-Path $chosenBuildRoot "native-ctest.log")
            if ($LASTEXITCODE -ne 0) { throw "Event-aware tests failed; preserve all suite output" }
        }
    } else {
        & $cmake --preset native-release "-DCMAKE_MAKE_PROGRAM=$($environment.tools.ninja)" "-DPython3_EXECUTABLE=$($environment.python_executable)" -DFLIGHT_USE_EVENT_AWARE_JSBSIM=OFF -DFLIGHT_JSBSIM_VARIANT=upstream
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
        & $cmake --build --preset native-release
        if ($LASTEXITCODE -ne 0) { throw "Native build failed" }
        & $ctest --preset native-release
        if ($LASTEXITCODE -ne 0) { throw "Native tests failed" }
    }
    if ($env:OS -eq "Windows_NT") {
        $dependencies = & dumpbin /dependents (Join-Path $chosenBuildRoot "bin/toolchain_smoke.exe")
        if ($LASTEXITCODE -ne 0 -or -not ($dependencies -match "JSBSim.dll")) { throw "Missing replaceable JSBSim DLL dependency" }
    } else {
        $dependencies = & ldd (Join-Path $chosenBuildRoot "bin/toolchain_smoke")
        if ($LASTEXITCODE -ne 0 -or -not ($dependencies -match "libJSBSim.so")) { throw "Missing replaceable JSBSim shared dependency" }
    }
    if (-not $RunTestsOnly) { $dependencies | Set-Content (Join-Path $chosenBuildRoot "dynamic-dependencies.txt") }
    $verifyArgs = @("tools/bootstrap/bootstrap.py", "--offline")
    if ($WithGodot) { $verifyArgs += "--with-godot" }
    if ($WithExportTemplates) { $verifyArgs += "--with-export-templates" }
    & $Python @verifyArgs
    if ($LASTEXITCODE -ne 0) { throw "Build modified a verified source/tool tree" }
    if ($useModifiedSource) {
        & $Python $sourceSelector $sourceValidationFlag --source-root (Join-Path $bundleRoot "vendor")
        if ($LASTEXITCODE -ne 0) { throw "Build/test modified the reviewed selected source bundle" }
    }
    Get-Content (Join-Path $chosenBuildRoot "toolchain-build-manifest.txt")
    if ($WithGodot) {
        & $environment.tools.godot --headless --version
        if ($LASTEXITCODE -ne 0) { throw "Pinned Godot executable failed" }
    }
    if ($useModifiedSource) {
        if ($route.pretrial_sha256 -ne (File-Sha $pretrialPath)) { throw "Pretrial authorization changed during this stage" }
        if ($ConfigureAndBuildOnly) {
            Write-NewJson $buildResultFile ([ordered]@{ schema_version=1; status="COMPILED_NOT_TESTED"; route_sha256=(File-Sha $routeFile); cmake_cache_sha256=(File-Sha (Join-Path $chosenBuildRoot "CMakeCache.txt")); compile_commands_sha256=(File-Sha (Join-Path $chosenBuildRoot "compile_commands.json")); verbose_build_sha256=(File-Sha (Join-Path $chosenBuildRoot "native-verbose-build.log")) })
            Write-Output "COMPILED_NOT_TESTED: $chosenBuildRoot"
            Write-Output "Inspect both declared and actual modified-unit compiler commands and create the measured execution authorization externally before -RunTestsOnly."
        } else {
            Write-Output "CTest completed successfully for the explicit event-aware build; aircraft/pilot/phase gates remain separate."
        }
    }
} finally { Pop-Location }

