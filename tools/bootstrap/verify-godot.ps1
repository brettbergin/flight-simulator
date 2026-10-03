[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$environment = Get-Content (Join-Path $repoRoot ".local/toolchain/environment.json") -Raw | ConvertFrom-Json
if (-not $environment.tools.godot) { throw "Fetch the pinned editor with --with-godot first" }
$probeRoot = Join-Path $repoRoot ".local/godot-binding-probe"
New-Item -ItemType Directory -Force -Path (Join-Path $probeRoot "bin") | Out-Null
$libraryName = if ($env:OS -eq "Windows_NT") { "toolchain_binding_probe.dll" } else { "libtoolchain_binding_probe.so" }
Copy-Item -LiteralPath (Join-Path $repoRoot ".local/build/native-release/bin/$libraryName") -Destination (Join-Path $probeRoot "bin/$libraryName")
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "smoke/binding_test.gd") -Destination (Join-Path $probeRoot "binding_test.gd")
@"
config_version=5
[application]
config/name="Toolchain binding proof"
[rendering]
renderer/rendering_method="gl_compatibility"
"@ | Set-Content -LiteralPath (Join-Path $probeRoot "project.godot")
@"
[configuration]
entry_symbol="toolchain_probe_init"
compatibility_minimum="4.5"
[libraries]
windows.debug.x86_64="res://bin/toolchain_binding_probe.dll"
windows.release.x86_64="res://bin/toolchain_binding_probe.dll"
linux.debug.x86_64="res://bin/libtoolchain_binding_probe.so"
linux.release.x86_64="res://bin/libtoolchain_binding_probe.so"
"@ | Set-Content -LiteralPath (Join-Path $probeRoot "probe.gdextension")
$result = & $environment.tools.godot --headless --path $probeRoot --script res://binding_test.gd 2>&1
$exitCode = $LASTEXITCODE
$result | Set-Content -LiteralPath (Join-Path $repoRoot ".local/build/native-release/godot-binding-load.txt")
$result | Write-Output
if ($exitCode -ne 0 -or -not ($result -match "TOOLCHAIN_BINDING_LOAD_OK") -or ($result -match "ERROR:|FATAL:") -or -not ($result -match "TOOLCHAIN_NATIVE_INITIALIZER_OK")) {
    throw "Godot binding-load proof failed; inspect the recorded log"
}

