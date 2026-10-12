# SPDX-License-Identifier: MIT
# Root source proposal: one-configure Windows Build and independent witness closure.
# PrepareIdentity/Header remain publication-only. Build never starts CTest,
# Godot, storage actors, player code or a database. NativeChecks/BridgeChecks
# are explicit separately authorized focused stages; source is not execution evidence.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("PrepareIdentity", "PrepareHeader", "Build", "BuildTests", "NativeChecks", "BridgeChecks")][string]$Stage,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$DependencyRoot,
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")][string]$Configuration,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$ConfigureControlsSha256,
    [Parameter(Mandatory)][string]$PythonExecutable,
    [Parameter(Mandatory)][ValidatePattern("^[0-9a-f]{64}$")][string]$PythonSha256,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$QualifierSha256,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$IdentityManifestSha256,
    [string]$CmakeExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$CmakeSha256,
    [string]$NinjaExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$NinjaSha256,
    [string]$CCompilerExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$CCompilerSha256,
    [string]$CxxCompilerExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$CxxCompilerSha256,
    [string]$TestBuildManifest,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$TestBuildManifestSha256,
    [string]$ExecutionAuthorization,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$ExecutionAuthorizationSha256,
    [string]$CtestExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$CtestSha256,
    [string]$NativeChecksReceipt,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$NativeChecksReceiptSha256,
    [string]$GodotExecutable,
    [ValidatePattern("^[0-9a-f]{64}$")][string]$GodotSha256,
    [string]$ProofParent,
    [string]$CrtDirectory,
    [ValidateRange(1,16)][int]$Parallel = 2,
    [ValidateRange(1,7200)][int]$BuildTimeoutSeconds = 3600
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Assert-OrdinaryPath([string]$Value, [bool]$Directory) {
    if (-not [IO.Path]::IsPathRooted($Value)) { throw "Absolute Root path required" }
    $observedPath = [IO.Path]::GetFullPath($Value)
    $observedItem = Get-Item -LiteralPath $observedPath -Force -ErrorAction Stop
    if ([bool]$observedItem.PSIsContainer -ne $Directory) { throw "Wrong Root path kind" }
    while ($null -ne $observedPath) {
        $observedAttributes = [IO.File]::GetAttributes($observedPath)
        if (($observedAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Root path has a symlink/reparse component" }
        $observedParent = [IO.Directory]::GetParent($observedPath)
        $observedPath = if ($null -eq $observedParent) { $null } else { $observedParent.FullName }
    }
}
# Private authoring fragment; incorporated into the sole allocated run.ps1.
function Get-RootFilePin([string]$Path) {
    Assert-OrdinaryPath $Path $false
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [ordered]@{path = $item.FullName; bytes = [long]$item.Length;
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Write-RootJsonNew([string]$Path, $Value) {
    $raw = [Text.UTF8Encoding]::new($false, $true).GetBytes(($Value | ConvertTo-Json -Depth 100 -Compress) + "`n")
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($raw, 0, $raw.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Write-RootTextNew([string]$Path, [string]$Value) {
    # Generated private backend is already bound by the reviewed runner source.
    # Store it separately to avoid Windows' 32767-character process command cap.
    $raw = [Text.UTF8Encoding]::new($false,$true).GetBytes($Value.Replace("`r`n","`n") + "`n")
    $stream = [IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try {$stream.Write($raw,0,$raw.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
function Invoke-RootObservedProcess {
    param([string]$Name, [string]$Executable, [string]$ExpectedSha256,
          [string[]]$Arguments, [string]$WorkingDirectory,
          [string]$EvidenceParent, [int]$TimeoutSeconds)
    if ($Name -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $TimeoutSeconds -lt 1 -or ($TimeoutSeconds -gt 7200 -and -not ($Name -ceq 'native-checks' -and $TimeoutSeconds -eq 14400))) { throw 'Invalid Root process policy' }
    Assert-OrdinaryPath $WorkingDirectory $true
    Assert-OrdinaryPath $EvidenceParent $true
    $toolPin = Get-RootFilePin $Executable
    if ($toolPin.sha256 -cne $ExpectedSha256) { throw 'Root process tool differs from the reviewed pin' }
    if ($null -eq $Arguments -or @($Arguments | Where-Object { $null -eq $_ -or $_.Contains([char]0) }).Count -ne 0) {
        throw 'Invalid literal process argument'
    }
    $attempt = Join-Path $EvidenceParent $Name
    if (Test-Path -LiteralPath $attempt) { throw 'Root process evidence must be fresh; retain the old attempt' }
    New-Item -ItemType Directory -Path $attempt -ErrorAction Stop | Out-Null
    Assert-OrdinaryPath $attempt $true
    $before = [ordered]@{schema = 'LocalPlayersRootProcessBefore/v1'; name = $Name;
        tool = $toolPin; argv = @($Executable) + $Arguments;
        cwd = [IO.Path]::GetFullPath($WorkingDirectory); timeout_seconds = $TimeoutSeconds;
        child_environment = [ordered]@{PYTHONDONTWRITEBYTECODE = '1'}}
    Write-RootJsonNew (Join-Path $attempt 'before.json') $before
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # CMake/godot-cpp invokes non-isolated Python during configure and generation.
    # Keep locked dependency trees immutable; descendants inherit this child-only
    # setting. Do not ignore/delete bytecode or alter the caller environment.
    $info.Environment['PYTHONDONTWRITEBYTECODE'] = '1'
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    $stdout = [IO.FileStream]::new((Join-Path $attempt 'stdout.log'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $stderr = $null
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $info
    $clock = [Diagnostics.Stopwatch]::new()
    $started = $false; $joined = $false; $drained = $false; $expired = $false
    $observedPid = $null; $exitCode = $null; $failure = $null
    $stdoutTask = $null; $stderrTask = $null
    try {
        $stderr = [IO.FileStream]::new((Join-Path $attempt 'stderr.log'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $currentPin = Get-RootFilePin $Executable
        if ($currentPin.sha256 -cne $toolPin.sha256 -or $currentPin.bytes -ne $toolPin.bytes) { throw 'Root process tool changed before launch' }
        $clock.Start()
        $started = $child.Start()
        if (-not $started) { throw 'Root process did not start' }
        $observedPid = $child.Id
        $child.StandardInput.Close()
        # Binary async drains avoid unbounded in-memory output and callbacks on
        # worker threads requiring a PowerShell runspace.
        $stdoutTask = $child.StandardOutput.BaseStream.CopyToAsync($stdout)
        $stderrTask = $child.StandardError.BaseStream.CopyToAsync($stderr)
        if (-not $child.WaitForExit($TimeoutSeconds * 1000)) {
            $expired = $true
            $child.Kill($true)
            if (-not $child.WaitForExit(30000)) { throw 'Root process timeout: process tree exit not observed' }
        }
        $joined = $child.HasExited
        if ($joined) { $exitCode = $child.ExitCode }
        $drained = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 30000)
        if (-not $drained) { throw 'Root process output drain not observed' }
        if ($expired) { throw 'Root process watchdog expired; retained joined failure' }
        if (-not $joined -or $exitCode -ne 0) { throw 'Root process returned an observed failure' }
    } catch {
        $failure = $_.Exception.Message
        if ($started -and -not $child.HasExited) {
            try { $child.Kill($true); $joined = $child.WaitForExit(30000) } catch { $joined = $false }
        }
        if ($started -and $child.HasExited) { $joined = $true; $exitCode = $child.ExitCode }
        if ($null -ne $stdoutTask -and $null -ne $stderrTask) {
            try { $drained = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 30000) } catch { $drained = $false }
        }
    } finally {
        $clock.Stop()
        # Never dispose streams while a pending drain can still use them.
        # An unjoined/undrained failure throws and cannot qualify. The pending
        # stream/task ownership is retained until the runner process retires;
        # Root must retain its failed outer-process terminal, never infer join.
        if ($drained -or -not $started) {
            $stdout.Flush($true); $stdout.Dispose()
            if ($null -ne $stderr) { $stderr.Flush($true); $stderr.Dispose() }
        }
        if (-not $started -or ($joined -and $drained)) { $child.Dispose() }
    }
    $stable = $false
    try {
        $afterPin = Get-RootFilePin $Executable
        $stable = $afterPin.sha256 -ceq $toolPin.sha256 -and $afterPin.bytes -eq $toolPin.bytes
    } catch { if ($null -eq $failure) { $failure = 'Root process tool disappeared after invocation' } }
    $terminal = [ordered]@{schema = 'LocalPlayersRootProcessTerminal/v1'; name = $Name;
        before = Get-RootFilePin (Join-Path $attempt 'before.json'); pid = $observedPid;
        started = $started; exit_observed = $joined; exit_code = $exitCode;
        drained = $drained; timed_out = $expired; elapsed_ms = $clock.Elapsed.TotalMilliseconds;
        tool_unchanged = $stable; error = $failure;
        qualified_process = $started -and $joined -and $drained -and -not $expired -and $exitCode -eq 0 -and $stable -and $null -eq $failure}
    Write-RootJsonNew (Join-Path $attempt 'terminal.json') $terminal
    if (-not $terminal.qualified_process) { throw ('Root process rejected: ' + $Name) }
    return $attempt
}

$publish = @'
import importlib.util
import os
from pathlib import Path
import sys

repo_arg, deps_arg, build_arg, config, controls_sha = sys.argv[1:]
for value in (repo_arg, deps_arg, build_arg):
    if not Path(value).is_absolute():
        raise ValueError("absolute Root-declared input required")
repo = Path(repo_arg)
tool = repo / "tools/local-players/source-identity.py"
expected_tool_sha = "23b4494799d795b77bede1c0b4b4cf43421f5b592b312f1f8f60c3a0dd2965a3"
# Inspect every ancestor before importing the explicitly reviewed tool. No
# environment module path, source-root sys.path injection or unpinned helper.
import hashlib
import stat
for part in (*reversed(tool.parents), tool):
    info = part.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
        raise ValueError("reparse/symlink source tool rejected")
raw_tool = tool.read_bytes()
if hashlib.sha256(raw_tool).hexdigest() != expected_tool_sha:
    raise ValueError("reviewed source-identity tool bytes changed")
spec = importlib.util.spec_from_file_location("root_admitted_storage_identity", tool)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)
repo = identity.ordinary(repo, True)
deps = identity.ordinary(deps_arg, True)
build = identity.ordinary(build_arg, True)
identity.require(build != repo and build != deps and not build.is_relative_to(deps),
                 "build cannot be source root or dependency tree")
controls_path = build / ("local-players-configure-controls-" + config + ".json")
controls_record, controls_bytes = identity.file_record(controls_path, controls_sha)
controls = identity.load_json(controls_bytes)
identity.exact_keys(controls, ("schema", "compiled_build_scalars_without_include_digest",
                    "compiler_paths", "sqlite_include_directories"), "configure export")
identity.require(controls["schema"] == "LocalPlayersConfigureControls/v1", "configure export version")
scalars = controls["compiled_build_scalars_without_include_digest"]
identity.exact_keys(scalars, [key for key in identity.SCALARS
                            if key != "sqlite_include_directories_sha256"], "configure scalar facts")
identity.require(scalars["configuration"] == config, "configuration/export mismatch")
identity.exact_keys(controls["compiler_paths"], ("c", "cxx"), "configure compiler paths")
includes = controls["sqlite_include_directories"]
identity.require(type(includes) is list and len(includes) == 1
                 and type(includes[0]) is str and Path(includes[0]).is_absolute(), "one absolute SQLite include")
include = identity.ordinary(includes[0], True)
identity.require(include == identity.ordinary(deps / "sqlite", True), "actual verified SQLite include")
include_record = {"schema": "LocalPlayersSQLiteIncludeProvenance/v1", "directories": [{
    "path": identity.path_token(include, repo, build),
    "sqlite_header_sha256": identity.sha(identity.read(identity.ordinary(include / "sqlite3.h")))}]}
scalars["sqlite_include_directories_sha256"] = identity.sha(identity.canonical(include_record))
scalars = {key: scalars[key] for key in identity.SCALARS}
compilers = {}
for language in ("c", "cxx"):
    compiler = controls["compiler_paths"][language]
    identity.require(type(compiler) is str and Path(compiler).is_absolute(), "absolute actual compiler path")
    pin, raw = identity.file_record(compiler)
    compilers[language] = {"path": pin["path"], "sha256": pin["sha256"]}
cache_record, cache_bytes = identity.file_record(build / "CMakeCache.txt")
provenance = {"cache": {"path": cache_record["path"], "sha256": cache_record["sha256"]}}
for language, key in (("C", "c_compiler_record"), ("CXX", "cxx_compiler_record")):
    candidates = list((build / "CMakeFiles").glob("*/CMake" + language + "Compiler.cmake"))
    identity.require(len(candidates) == 1, "exact one configured compiler record")
    pin, raw = identity.file_record(candidates[0])
    provenance[key] = {"path": pin["path"], "sha256": pin["sha256"]}
plan = {"schema": "LocalPlayersPrecompilePlan/v1", "compiled_build_scalars": scalars,
        "compiler_files": compilers, "configure_provenance": provenance,
        "sqlite_include_directories": includes}
# Actual cache, compiler records/file formats, platform/runtime/binding constraints
# are checked before any output. This does not witness a compiler invocation.
identity.configure(plan, repo, deps)
plan_bytes = identity.canonical(plan)
for pin in (controls_record, cache_record, *provenance.values(), *compilers.values()):
    current, raw = identity.file_record(pin["path"], pin["sha256"])
    identity.require("bytes" not in pin or current["bytes"] == pin["bytes"], "input changed during publication")
identity.require(hashlib.sha256(tool.read_bytes()).hexdigest() == expected_tool_sha, "identity tool changed")
plan_path = build / "local-players-precompile-plan.json"
identity_output = build / "local-players-identity"
identity.require(not plan_path.exists() and not plan_path.is_symlink(), "precompile plan must be fresh")
identity.require(not identity_output.exists() and not identity_output.is_symlink(), "identity output must be fresh")
with plan_path.open("xb") as stream:
    stream.write(plan_bytes)
    stream.flush()
    os.fsync(stream.fileno())
print("LOCAL PLAYERS PRECOMPILE PLAN PUBLISHED; NO COMPILE/RUNTIME QUALIFICATION")
'@

$buildBackend = @'
# Private source-authoring fragment; embedded in the sole allocated run.ps1.
# No observed compiler/link command string supplies an expected argument.
import hashlib
import importlib.util
import json
import os
import ntpath
from pathlib import Path
import stat

TARGETS = {
    'flight_sqlite': ('C', ('sqlite3.c',)),
    'flight_local_players_core': ('CXX', ('records.cpp', 'codec.cpp', 'store.cpp', 'service.cpp', 'storage_identity.cpp')),
    'flight_local_players_windows': ('CXX', ('windows_filesystem.cpp',)),
    'flight_local_players_bridge': ('CXX', ('local_players.cpp', 'register_types.cpp')),
}

def reviewed_qualifier(repository, expected_sha):
    path = repository / 'tools/local-players/qualify.py'
    for item in (*reversed(path.parents), path):
        observed = item.lstat()
        if stat.S_ISLNK(observed.st_mode) or getattr(observed, 'st_file_attributes', 0) & 0x400:
            raise ValueError('nonordinary reviewed qualifier path')
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_sha:
        raise ValueError('reviewed qualifier changed')
    spec = importlib.util.spec_from_file_location('root_storage_build_witness', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def strings(q, value):
    q.require(type(value) is list and all(type(v) is str and v and not any(c in v for c in '\0\r\n') for v in value),
              'ordered literal token array')
    return value

def unique(values):
    return list(dict.fromkeys(values))

# Source-only future Build helpers. The offline fixtures do not call Win32.
def native_operand(value):
    return value.replace('/', '\\')


def ninja_relative_operand(q, value, build):
    path = Path(os.path.abspath(value))
    q.require(path.is_relative_to(build), 'contained top-build Ninja operand')
    return native_operand(str(path.relative_to(build)))


def native_path_identity(q, value, directory):
    # This is executed only by an explicitly authorized future Windows Build.
    # FILE_ID_INFO binds an 8.3 alias to the same physical ordinary file/dir.
    import ctypes
    from ctypes import wintypes
    q.require(os.name == 'nt', 'native CMake operand facts require Windows')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
        ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    kernel.GetFileInformationByHandleEx.restype = wintypes.BOOL
    kernel.GetFileAttributesW.argtypes = [wintypes.LPCWSTR]
    kernel.GetFileAttributesW.restype = wintypes.DWORD
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    class FileIdInfo(ctypes.Structure):
        _fields_ = [('volume', ctypes.c_ulonglong), ('identifier', ctypes.c_ubyte * 16)]
    class AttributeTagInfo(ctypes.Structure):
        _fields_ = [('attributes', wintypes.DWORD), ('reparse_tag', wintypes.DWORD)]
    q.ordinary(value, directory)
    attributes = kernel.GetFileAttributesW(str(value))
    q.require(attributes != 0xffffffff and not attributes & 0x400
              and bool(attributes & 0x10) == directory, 'ordinary native operand kind')
    handle = kernel.CreateFileW(str(value), 0x80, 7, None, 3, 0x02200000, None)
    q.require(handle not in (None, ctypes.c_void_p(-1).value), 'open physical operand identity')
    try:
        attributes = AttributeTagInfo()
        q.require(kernel.GetFileInformationByHandleEx(handle, 9, ctypes.byref(attributes), ctypes.sizeof(attributes))
                  and not attributes.attributes & 0x400 and bool(attributes.attributes & 0x10) == directory,
                  'actual opened operand is ordinary and has declared kind')
        info = FileIdInfo()
        q.require(kernel.GetFileInformationByHandleEx(handle, 18, ctypes.byref(info), ctypes.sizeof(info)),
                  'actual FILE_ID_INFO for operand')
        return {'volume_serial': str(info.volume), 'file_id_hex': bytes(info.identifier).hex()}
    finally:
        q.require(kernel.CloseHandle(handle), 'close operand identity handle')


def native_short_path(q, value):
    # CMake 3.31.8 kwsys::SystemTools::GetShortPath uses this exact two-call API.
    import ctypes
    from ctypes import wintypes
    q.require(os.name == 'nt', 'short operand query requires Windows')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetShortPathNameW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
    kernel.GetShortPathNameW.restype = wintypes.DWORD
    size = kernel.GetShortPathNameW(value, None, 0)
    if not size:
        return None
    q.require(size <= 32768, 'bounded native short operand')
    buffer = ctypes.create_unicode_buffer(size)
    result = kernel.GetShortPathNameW(value, buffer, size)
    if not result:
        return None
    q.require(result < size and buffer.value, 'stable native short operand length')
    return buffer.value


def existing_operand_fact(q, value, directory):
    # No command parser or observed argv is used. CMake shell escaping surrounds
    # these operands but is absent from the argv received by the Python launcher.
    q.require(type(value) is str and value and not any(c in value for c in '\0\r\n"'), 'literal CMake operand')
    long_path = q.ordinary(value, directory)
    identity = native_path_identity(q, value, directory)
    query = any(c in value for c in ' #')
    short = native_short_path(q, value) if query else None
    selected = short if short is not None else value
    q.require(native_path_identity(q, selected, directory) == identity, 'selected native alias must identify same physical operand')
    pin = None if directory else q.file_pin(long_path)
    selected_pin = None if directory else q.file_pin(selected)
    if not directory:
        q.require((pin['bytes'], pin['sha256']) == (selected_pin['bytes'], selected_pin['sha256']), 'same executable alias bytes')
    return {'path': value, 'directory': directory, 'existed': True,
            'short_path_status': 'not_needed' if not query else ('success' if short is not None else 'fallback'),
            'operand': native_operand(selected), 'physical_identity': identity,
            'long_pin': pin, 'selected_pin': selected_pin, 'ancestor': None}


def operand_roster(q, policy):
    values = [(policy['languages'][language]['compiler'], False) for language in ('C', 'CXX')]
    values += [(policy[name], False) for name in ('linker', 'librarian')]
    values += [(path, True) for target in policy['targets'] for path in strings(q, target['includes'])]
    return unique(values)


def publish_operand_facts(q, repo, deps, build, config, policy_sha, unused_manifest_sha):
    policy, policy_path = load_compile_policy(q, build, config, policy_sha)
    rows = []
    for value, directory in operand_roster(q, policy):
        path = Path(os.path.abspath(value))
        q.require(Path(value).is_absolute(), 'absolute exported operand')
        if directory:
            q.require(any(path.is_relative_to(root) for root in (repo, deps, build)), 'closed include operand roots')
        if path.exists():
            rows.append(existing_operand_fact(q, value, directory))
        else:
            # Preserve generation-time absence before the dependency build.
            # An include created later must not retroactively select an 8.3 name.
            q.require(directory and path.is_relative_to(build/'deps/godot-cpp/gen'), 'only generated include may be absent')
            ancestor = path.parent
            while not ancestor.exists():
                ancestor = ancestor.parent
            q.ordinary(ancestor, True)
            rows.append({'path': value, 'directory': True, 'existed': False,
                'short_path_status': 'absent', 'operand': native_operand(value),
                'physical_identity': None, 'long_pin': None, 'selected_pin': None,
                'ancestor': {'path': str(ancestor), 'physical_identity': native_path_identity(q, ancestor, True)}})
    q.write_new(build/'local-players-witness/cmake-operand-facts.json', q.json_bytes({
        'schema': 'LocalPlayersCMakeOperandFacts/v1', 'policy': q.file_pin(policy_path),
        'source_root': str(repo), 'build_root': str(build), 'dependency_root': str(deps), 'operands': rows}))


def admitted_operand_facts(q, repo, deps, build, policy, policy_path):
    facts, _ = q.load_json(build/'local-players-witness/cmake-operand-facts.json')
    q.exact_keys(facts, ['schema', 'policy', 'source_root', 'build_root', 'dependency_root', 'operands'])
    q.require(facts['schema'] == 'LocalPlayersCMakeOperandFacts/v1' and facts['policy'] == q.file_pin(policy_path)
              and [facts[k] for k in ('source_root', 'dependency_root', 'build_root')] == list(map(str, (repo, deps, build))),
              'frozen configure operand authority')
    q.require(type(facts['operands']) is list and [(r['path'], r['directory']) for r in facts['operands']] == operand_roster(q, policy),
              'closed configured operand roster')
    for row in facts['operands']:
        q.exact_keys(row, ['path', 'directory', 'existed', 'short_path_status', 'operand', 'physical_identity', 'long_pin', 'selected_pin', 'ancestor'])
        q.require(type(row['directory']) is bool and type(row['existed']) is bool, 'typed operand facts')
        if row['existed']:
            q.require(existing_operand_fact(q, row['path'], row['directory']) == row, 'configure alias/physical identity continuity')
        else:
            q.require(row['directory'] is True and Path(row['path']).is_relative_to(build/'deps/godot-cpp/gen')
                      and row['short_path_status'] == 'absent' and row['operand'] == native_operand(row['path'])
                      and row['physical_identity'] is row['long_pin'] is row['selected_pin'] is None, 'closed initially absent generated operand')
            ancestor = row['ancestor']
            q.exact_keys(ancestor, ['path', 'physical_identity'])
            q.require(Path(row['path']).is_relative_to(Path(ancestor['path'])) and Path(ancestor['path']).is_relative_to(build)
                      and native_path_identity(q, ancestor['path'], True) == ancestor['physical_identity'], 'generation ancestor continuity')
            if Path(row['path']).exists():
                q.ordinary(row['path'], True)
    return facts['operands']


def frozen_operand(q, policy, value, directory):
    matches = [row for row in policy['_operands'] if row['path'] == value and row['directory'] is directory]
    q.require(len(matches) == 1, 'exact frozen configured operand')
    return matches[0]['operand']


def same_identity_roots(identity, repo, deps, build):
    return [identity[k] for k in ('source_root', 'dependency_root', 'build_root')] == [p.as_posix() for p in (repo, deps, build)]

def target_archive_witness(q, target, object_paths):
    archive_path = q.ordinary(target['output'])
    archive_pin = q.file_pin(archive_path)
    raw = archive_path.read_bytes()
    q.require(len(raw) == archive_pin['bytes'] and hashlib.sha256(raw).hexdigest() == archive_pin['sha256'], 'stable target archive read')
    members = q.read_msvc_archive(raw)
    q.require(len(members) == len(object_paths) and len(set(object_paths)) == len(object_paths), 'exact target archive COFF roster count')
    matched, objects = [], []
    for object_path in object_paths:
        pin = q.file_pin(object_path)
        object_raw = q.ordinary(object_path).read_bytes()
        q.require(len(object_raw) == pin['bytes'] and hashlib.sha256(object_raw).hexdigest() == pin['sha256'], 'stable measured object read')
        matches = [i for i, member in enumerate(members) if ntpath.basename(member['name']) == Path(object_path).name
                   and member['bytes'] == pin['bytes'] and member['sha256'] == pin['sha256'] and member['data'] == object_raw]
        q.require(len(matches) == 1 and matches[0] not in matched, 'unique exact measured object inside target archive')
        matched.append(matches[0]); objects.append(pin)
        q.require(q.file_pin(object_path) == pin, 'measured object continuity')
    q.require(set(matched) == set(range(len(members))) and q.file_pin(archive_path) == archive_pin, 'no extra or changed target archive member')
    roster = [{key: member[key] for key in ('offset', 'name', 'bytes', 'sha256')} for member in members]
    return {'target': target['target'], 'archive': archive_pin, 'objects': objects,
            'members': roster, 'object_roster_sha256': hashlib.sha256(q.json_bytes(roster)).hexdigest(),
            'scope': 'Exact measured COFF member bytes; no separately observed librarian command or runtime claim.'}


def production_archive_witnesses(q, policy, snapshot):
    result = []
    for name, count in (('flight_local_players_core', 5), ('flight_local_players_windows', 1)):
        targets = [target for target in policy['targets'] if target['target'] == name]
        objects = [row['object'] for row in snapshot['objects'] if row['target'] == name]
        q.require(len(targets) == 1 and len(objects) == count, 'closed measured core/windows target roster')
        result.append(target_archive_witness(q, targets[0], objects))
    return result


def admitted_link_plan_chain(q, before, prelink, repo, build):
    path = build/'local-players-witness/link-plan.json'
    digest_path = build/'local-players-witness/link-plan-digest.json'
    plan_pin, digest_pin = q.file_pin(path), q.file_pin(digest_path)
    q.require(before['plan'] == prelink['plan'] == plan_pin and before['plan_sha256'] == plan_pin['sha256'],
              'actual inner link must use exact object-bound prelink plan')
    q.require(before['plan_digest_file'] == prelink['plan_digest_file'] == digest_pin
              and q.resolve_plan_digest(path, digest_file=digest_path) == (plan_pin['sha256'], digest_pin),
              'actual inner link must use exact frozen raw plan-digest artifact')
    plan, _ = q.load_json(path, plan_pin['sha256'])
    q.exact_keys(plan, ['schema', 'kind', 'source_root', 'build_root', 'cwd', 'argv', 'tools', 'inputs', 'outputs'])
    q.require(plan['schema'] == 'LocalPlayersInvocationPlan/v1' and before['kind'] == plan['kind'] == 'link'
              and [before[k] for k in ('source_root', 'build_root', 'cwd')] == [str(repo), str(build), str(build)]
              and all(plan[k] == before[k] for k in ('kind', 'source_root', 'build_root', 'cwd', 'argv', 'tools', 'inputs'))
              and plan['outputs'] == before['expected_outputs'], 'declared link kind/roots/complete plan correspondence')
    return {'plan': plan_pin, 'plan_digest_file': digest_pin}

def compile_rows(q, database, build):
    rows, _ = q.load_json(database)
    q.require(type(rows) is list and rows, 'original compile database required')
    indexed = {}
    for row in rows:
        q.require(type(row) is dict and all(type(row.get(k)) is str for k in ('file', 'directory', 'output')),
                  'compile metadata needs file/directory/output')
        directory = q.ordinary(row['directory'], True)
        source = Path(os.path.abspath(directory / row['file']))
        # The output is not created yet. Inspect the existing nearest ancestor;
        # the launcher will require its exact ordinary parent before compilation.
        output = Path(os.path.abspath(directory / row['output']))
        q.require(output.is_relative_to(build), 'contained compile object metadata')
        indexed.setdefault(source, []).append((row, directory, output))
    return indexed

def expected_compile_argv(q, policy, target, source, row, directory, object_path):
    language = target['language']
    facts = policy['languages'][language]
    q.require(language in ('C', 'CXX') and target['cxx_modules'] == 'OFF', 'closed native language/modules')
    compiler = frozen_operand(q, policy, facts['compiler'], False)
    q.ordinary(compiler)
    # cmLocalGenerator::JoinDefines uses a sorted set, independently of the
    # order of target property collection. Preserve actual argv spelling.
    defines = strings(q, target['defines'])
    if target['export_define']:
        q.require(target['export_define'] == target['target'] + '_EXPORTS', 'closed production export define')
        defines = defines + [target['export_define']]
    defines = ['-D' + value for value in sorted(set(defines))]
    includes = unique(strings(q, target['includes']))
    system = unique(strings(q, target['system_includes']))
    q.require(all(value in includes for value in system), 'system include must belong to actual target includes')
    normal = [value for value in includes if value not in system]
    includes_argv = ['-I' + frozen_operand(q, policy, value, True) for value in normal]
    system_flag = facts['system_include_option']
    if system:
        q.require(system_flag in ('-external:I', '/external:I'), 'closed pinned MSVC system include option')
        includes_argv += [system_flag + frozen_operand(q, policy, value, True) for value in includes if value in system]
        warning = facts['system_include_warning_option']
        q.require(warning == '-external:W0 ', 'exact pinned CMake 3.31.8 MSVC raw external warning option')
        warning_tokens = q.windows_response_tokens(warning)
        q.require(warning_tokens == ['-external:W0'], 'one pinned MSVC external warning token')
        includes_argv += warning_tokens
    runtime = 'MultiThreadedDebugDLL' if policy['configuration'] == 'Debug' else 'MultiThreadedDLL'
    q.require(target['msvc_runtime'] == runtime, 'actual target dynamic CRT mismatch')
    runtime_flags = strings(q, facts['runtime_options'][runtime])
    q.require(runtime_flags == (['-MDd'] if runtime.endswith('DebugDLL') else ['-MD']), 'pinned dynamic CRT options')
    debug = target['debug_information_format']
    q.require(debug == ('ProgramDatabase' if policy['configuration'] in ('Debug', 'RelWithDebInfo') else ''),
              'closed actual debug-information selection')
    debug_flags = strings(q, facts['debug_options'][debug]) if debug else []
    q.require(not debug or debug_flags == ['-Zi'], 'pinned ProgramDatabase option')
    flags = strings(q, facts['global_flags']) + strings(q, facts['configuration_flags'])
    if language == 'CXX':
        q.require(policy['cxx_standard_option'] in ('-std:c++20', '/std:c++20'), 'exact C++20 option')
        flags.append(policy['cxx_standard_option'])
    flags += runtime_flags + debug_flags + unique(strings(q, target['options'])) + strings(q, source['options'])
    flags += strings(q, facts['depfile_flags'])
    name = Path(source['path']).name
    strict = name in ('records.cpp', 'codec.cpp', 'local_players.cpp')
    q.require(sum(value == '/fp:strict' for value in flags) == int(strict), 'source-specific strict FP policy')
    q.require(not any(value.startswith(('/fp:', '-fp:')) and value != '/fp:strict' for value in flags), 'no conflicting FP mode')
    # Rule spelling comes from pinned Windows-MSVC.cmake. No command parser is
    # used to recover definitions, flags, object or source arguments.
    expected_rule = ('<CMAKE_' + language + '_COMPILER>  /nologo' + (' /TP' if language == 'CXX' else '')
        + ' <DEFINES> <INCLUDES> <FLAGS> /Fo<OBJECT> /Fd<TARGET_COMPILE_PDB> /FS -c <SOURCE>')
    q.require(facts['rule'] == expected_rule, 'unsupported pinned compile rule; review generated rule before build')
    q.require(directory == q.ordinary(policy['_build_root'], True), 'Ninja compile cwd must be declared build root')
    output_arg = row['output'].replace('/', '\\')
    pdb_arg = ninja_relative_operand(q, target['compiler_pdb'], q.ordinary(policy['_build_root'], True))
    source_arg = source['path'].replace('/', '\\')
    argv = [compiler, '/nologo'] + (['/TP'] if language == 'CXX' else []) + defines + includes_argv + flags
    argv += ['/Fo' + output_arg, '/Fd' + pdb_arg, '/FS', '-c', source_arg]
    q.require(len(' '.join(argv)) < 7000 and not any(value.startswith('@') for value in argv),
              'unreviewed compiler response-file route required')
    return argv

def load_compile_policy(q, build, config, policy_sha):
    policy_path = build / ('local-players-compile-policy-' + config + '.json')
    policy, _ = q.load_json(policy_path, policy_sha)
    q.exact_keys(policy, ['schema','rule_policy','configuration','languages','targets','cxx_standard_option',
                          'linker','librarian','archive_rule','shared_rule','godot_cpp_archive','link_policy'])
    q.require(policy['schema'] == 'LocalPlayersCompilePolicy/v1' and policy['configuration'] == config
              and policy['rule_policy'] == 'cmake-3.31.8-msvc-ninja-x64/v1', 'closed generated compile policy')
    q.exact_keys(policy['languages'], ['C','CXX'])
    for language in policy['languages'].values():
        q.exact_keys(language, ['compiler','global_flags','configuration_flags','depfile_flags',
             'system_include_option','system_include_warning_option','runtime_options','debug_options','rule'])
        q.exact_keys(language['runtime_options'], ['MultiThreadedDLL','MultiThreadedDebugDLL'])
        q.exact_keys(language['debug_options'], ['Embedded','ProgramDatabase','EditAndContinue'])
        q.require(language['depfile_flags'] == ['/showIncludes'], 'pinned Ninja MSVC dependency flag')
    q.require(type(policy['targets']) is list and [t.get('target') for t in policy['targets']] == list(TARGETS),
              'closed four production targets')
    return policy, policy_path


def metadata(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy, policy_path = load_compile_policy(q, build, config, policy_sha)
    _, identity = q.identity_header(build/'local-players-identity/local-players-source-identity.json', manifest_sha)
    q.require(same_identity_roots(identity, repo, deps, build) and identity['compiled_build_scalars']['platform'] == 'Windows-x64',
              'independent source identity roots/platform')
    q.require(identity['compiled_build_scalars']['configuration'] == config, 'actual source configuration')
    expected_sources = {
        'flight_sqlite': [deps/'sqlite/sqlite3.c'],
        'flight_local_players_core': [repo/'native/persistence/local_players/src'/n for n in TARGETS['flight_local_players_core'][1]],
        'flight_local_players_windows': [repo/'native/persistence/local_players/src/windows_filesystem.cpp'],
        'flight_local_players_bridge': [repo/'native/persistence/godot_bridge/src'/n for n in TARGETS['flight_local_players_bridge'][1]],
    }
    for target in policy['targets']:
        q.exact_keys(target, ['target','language','defines','includes','system_includes','options','export_define',
                              'msvc_runtime','cxx_modules','debug_information_format','compiler_pdb','output','sources'])
        name = target['target']
        q.require(target['language'] == TARGETS[name][0], 'target language source allocation')
        q.require([q.ordinary(s['path']) for s in target['sources']] == expected_sources[name], 'exact allocated CPP/C source roster')
        for source in target['sources']:
            q.exact_keys(source, ['path','options'])
        includes = strings(q, target['includes'])
        q.require(all(Path(p).is_absolute() for p in includes), 'absolute actual target includes')
        q.require(all(q.ordinary(p,True).is_relative_to(repo) or q.ordinary(p,True).is_relative_to(deps)
                      or q.ordinary(p,True).is_relative_to(build) for p in includes), 'closed source/dependency/generated includes')
        if name == 'flight_sqlite':
            q.require(sorted(target['defines']) == ['SQLITE_OMIT_LOAD_EXTENSION=1','SQLITE_THREADSAFE=1']
                      and includes == [str(deps/'sqlite').replace('\\','/')], 'exact SQLite target settings')
        output = Path(os.path.abspath(target['output']))
        pdb = Path(os.path.abspath(target['compiler_pdb']))
        q.require(output.is_relative_to(build) and pdb.is_relative_to(build/'local-players-compiler-pdb'/name), 'target/PDB containment')
    policy['_operands'] = admitted_operand_facts(q, repo, deps, build, policy, policy_path)
    policy['_build_root'] = str(build)
    return policy, identity, policy_path

def frozen_inputs(q, repo, deps, build, identity, policy_path):
    paths = [repo/r['path'] for r in identity['source_bindings']]
    paths += [deps/name/r['path'] for name,d in identity['dependencies'].items() for r in d['files']]
    paths += [Path(d['archive']['path']) for d in identity['dependencies'].values()]
    paths += [deps/name/'.verified.json' for name in identity['dependencies']]
    paths += [Path(r['path']) for r in identity['configure_provenance'].values()]
    policy,_=q.load_json(policy_path)
    paths += [q.ordinary(policy['linker']),q.ordinary(policy['librarian'])]
    operands = admitted_operand_facts(q, repo, deps, build, policy, policy_path)
    paths += [build/'local-players-witness/cmake-operand-facts.json']
    paths += [Path(pin['path']) for row in operands for pin in (row['long_pin'], row['selected_pin']) if pin is not None]
    generated=q.ordinary(build/'deps/godot-cpp/gen',True)
    for current,dirs,files in os.walk(generated,followlinks=False):
        for name in dirs:q.ordinary(Path(current)/name,True)
        for name in files:paths.append(q.ordinary(Path(current)/name))
    paths += [Path(identity['build_plan']['path']), policy_path, build/'compile_commands.json',
              build/('local-players-configure-controls-'+identity['compiled_build_scalars']['configuration']+'.json'),
              build/'local-players-identity/local-players-source-identity.json',
              build/'local-players-identity/local-players-identity.gd',
              build/'local-players-generated/compiled_identity.hpp', repo/'third_party/dependencies.lock.json',
              build/'local-players-witness/root-inputs.json',build/'local-players-witness/build-backend.py',
              build/'.cmake/api/v1/query/client-flight-local-players/query.json']
    root_inputs,_=q.load_json(build/'local-players-witness/root-inputs.json')
    q.exact_keys(root_inputs,['schema','runner','tools','backend'])
    q.require(root_inputs['schema']=='LocalPlayersRootBuildInputs/v1'
              and root_inputs['backend']==q.file_pin(build/'local-players-witness/build-backend.py'),'generated backend raw binding')
    for pin in [root_inputs['runner'],*root_inputs['tools']]:
        q.require(q.file_pin(pin['path'])==pin,'Root source/tool raw continuity')
        paths.append(Path(pin['path']))
    return [q.file_pin(p) for p in unique(paths)]

def publish_digest(q, path, plan):
    return q.write_new(path, q.json_bytes({'schema':'LocalPlayersInvocationPlanDigest/v1',
                    'plan_path':str(plan), 'plan_sha256':q.file_pin(plan)['sha256']}))

def publish_compile_plans(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy, identity, policy_path = metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    inputs = frozen_inputs(q,repo,deps,build,identity,policy_path)
    indexed = compile_rows(q,build/'compile_commands.json',build)
    parent = q.ordinary(build/'local-players-witness/plans',True)
    plans, objects, targets = [], [], []
    for target in policy['targets']:
        target_objects = []
        for source in target['sources']:
            matches = indexed.get(q.ordinary(source['path']),[])
            q.require(len(matches)==1, 'one actual source/directory/output metadata row')
            row,cwd,obj = matches[0]
            q.require(not obj.exists() and not obj.is_symlink(), 'fresh unique compilation object')
            argv = expected_compile_argv(q,policy,target,source,row,cwd,obj)
            plan = {'schema':'LocalPlayersInvocationPlan/v1','kind':'compile','source_root':str(repo),
                    'build_root':str(build),'cwd':str(cwd),'argv':argv,'tools':[q.file_pin(argv[0])],
                    'inputs':inputs,'outputs':[str(obj)]}
            path = parent/(target['target']+'-'+Path(source['path']).name+'.json')
            plans.append(q.write_new(path,q.json_bytes(plan)))
            objects.append({'target':target['target'],'source':source['path'],'object':str(obj),'cwd':str(cwd),'plan':plans[-1]})
            target_objects.append(str(obj))
        targets.append({'target':target['target'],'objects':target_objects,'compiler_pdb':target['compiler_pdb'],'output':target['output']})
    q.require(len(plans)==9 and len({r['object'] for r in objects})==9,'exact nine unique compiled objects')
    index = build/'local-players-witness/compile-index.json'
    q.write_new(index,q.json_bytes({'schema':'LocalPlayersCompilePlanIndex/v1','source_root':str(repo),'build_root':str(build),'entries':plans}))
    publish_digest(q,build/'local-players-witness/compile-index-digest.json',index)
    snapshot = {'schema':'LocalPlayersBuildInputs/v1','policy':q.file_pin(policy_path),'inputs':inputs,
                'objects':objects,'targets':targets,'compile_index':q.file_pin(index)}
    q.write_new(build/'local-players-witness/build-inputs.json',q.json_bytes(snapshot))
    return snapshot

def verify_compiles(q, build, snapshot):
    root = q.ordinary(build/'local-players-witness/compile-receipts',True)
    children = list(root.iterdir())
    q.require(all(p.is_dir() and not p.is_symlink() for p in children), 'ordinary compile receipt directories')
    runs = [p for p in children if p.name.startswith('invocation-')]
    selections = [p for p in children if p.name.startswith('compile-selection-')]
    q.require(len(runs)==len(selections)==9 and len(children)==18,'exact nine invocation/selection pairs')
    observed={}
    for run in runs:
        before,terminal=q.read_invocation(run)
        q.require(before['kind']=='compile' and len(terminal['outputs'])==1,'one measured unique object')
        name=terminal['outputs'][0]['path'];q.require(name not in observed,'no duplicated object witness')
        observed[name]=(run,before,terminal)
    selection_plans=[]
    for selection in selections:
        before,_=q.load_json(selection/'before.json');terminal,_=q.load_json(selection/'terminal.json')
        q.exact_keys(before,['schema','index','digest_file','selected_plan','argv','cwd','launcher'])
        q.exact_keys(terminal,['schema','before','selected_plan','exit_code','error','qualified_selection'])
        q.require(before['schema']=='LocalPlayersCompilePlanSelection/v1'
                  and terminal['schema']=='LocalPlayersCompilePlanSelectionTerminal/v1'
                  and terminal['before']==q.file_pin(selection/'before.json')
                  and terminal['exit_code']==0 and type(terminal['exit_code']) is int
                  and terminal['qualified_selection'] is True and terminal['error'] is None
                  and terminal['selected_plan']==before['selected_plan'],'actual selection terminal')
        q.require(before['index']==snapshot['compile_index']==q.file_pin(before['index']['path'])
                  and before['digest_file']==q.file_pin(build/'local-players-witness/compile-index-digest.json')
                  and before['launcher']==q.file_pin(q.__file__),'exact frozen selection authority')
        q.require(before['selected_plan']==q.file_pin(before['selected_plan']['path']),'selected plan raw pin')
        selected,_=q.load_json(before['selected_plan']['path'])
        q.require(before['argv']==selected['argv'] and before['cwd']==selected['cwd'], 'selection actual argv/cwd equals its frozen plan')
        q.require(q.resolve_plan_digest(before['index']['path'], digest_file=before['digest_file']['path'])
                  == (before['index']['sha256'],before['digest_file']), 'current closed compile-index digest')
        selection_plans.append(before['selected_plan']['path'])
    q.require(sorted(selection_plans)==sorted(r['plan']['path'] for r in snapshot['objects']), 'closed unique selected plan roster')
    result=[]
    rows,_=q.load_json(build/'compile_commands.json')
    for entry in snapshot['objects']:
        run,before,terminal=observed[entry['object']]
        q.require(before['plan']==entry['plan'] and q.actual_source(before['expanded_argv'],before['cwd'],q.ordinary(entry['source'])), 'actual allocated source compile')
        candidates=[r for r in rows if Path(os.path.abspath(Path(r['directory'])/r['file']))==q.ordinary(entry['source'])]
        q.require(len(candidates)==1,'one original compile row')
        row=candidates[0]
        q.require(q.ordinary(row['directory'],True)==q.ordinary(before['cwd'],True)
                  and q.ordinary(Path(row['directory'])/row['output'])==q.ordinary(entry['object']), 'raw compile metadata/current object match')
        # command-only CMake rows are retained as evidence, NEVER parsed.
        if 'arguments' in row:q.require(row['arguments']==before['argv'],'optional actual array equality')
        else:q.require(type(row.get('command')) is str and row['command'],'original unparsed command evidence')
        result.append({'source':q.file_pin(entry['source']),'object':q.file_pin(entry['object']),
                      'invocation_before':q.file_pin(run/'before.json'),'invocation_terminal':q.file_pin(run/'terminal.json'),
                      'command_sha256':before['command_sha256']})
    return result,observed

def file_api_link(q, build, config):
    reply=q.ordinary(build/'.cmake/api/v1/reply',True)
    indexes=list(reply.glob('index-*.json'))
    q.require(len(indexes)==1,'fresh single CMake FileAPI index')
    index,_=q.load_json(indexes[0])
    q.require(index['cmake']['version']['string']=='3.31.8' and index['cmake']['generator']['name']=='Ninja', 'pinned actual FileAPI producer')
    responses=index['reply']['client-flight-local-players']['query.json']['responses']
    matches=[r for r in responses if r.get('kind')=='codemodel' and r.get('version',{}).get('major')==2]
    q.require(len(matches)==1,'one requested codemodel-v2 response')
    def read_reply(name):
        q.require(type(name) is str and Path(name).name==name and name.endswith('.json'),'closed reply filename')
        path=q.ordinary(reply/name);q.require(path.is_relative_to(reply),'reply containment')
        return q.load_json(path)[0],q.file_pin(path)
    model,model_pin=read_reply(matches[0]['jsonFile'])
    q.require(model['kind']=='codemodel' and model['version']['major']==2
              and q.ordinary(model['paths']['build'],True)==build,'actual codemodel root/version')
    configurations=[c for c in model['configurations'] if c['name']==config]
    q.require(len(configurations)==1,'one declared codemodel configuration')
    targets=[t for t in configurations[0]['targets'] if t['name']=='flight_local_players_bridge']
    q.require(len(targets)==1,'one production bridge codemodel target')
    target,target_pin=read_reply(targets[0]['jsonFile'])
    q.require(target['name']=='flight_local_players_bridge' and target['type']=='SHARED_LIBRARY'
              and target['link']['language']=='CXX','production shared CXX link metadata')
    parts=[]
    for item in target['link']['commandFragments']:
        q.require(item.get('role') in ('flags','libraries','libraryPath') and type(item.get('fragment')) is str,'configuration fragments only')
        values=q.windows_response_tokens(item['fragment']) if item['fragment'].strip() else []
        parts.append((item['role'],values))
    return parts,[q.file_pin(indexes[0]),model_pin,target_pin]

def publish_link_plan(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy,identity,policy_path=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    snapshot,_=q.load_json(build/'local-players-witness/build-inputs.json')
    compiles,observed=verify_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'frozen precompile input changed')
    sqlite=next(r for r in snapshot['objects'] if r['target']=='flight_sqlite')
    sqlite_compile=q.match_compile_database(build/'compile_commands.json',observed[sqlite['object']][0],sqlite['source'],sqlite['object'])
    sqlite_archive=next(t['output'] for t in policy['targets'] if t['target']=='flight_sqlite')
    archive_admission=q.sqlite_archive_witness(sqlite_archive,sqlite['object'])
    production_archives=production_archive_witnesses(q,policy,snapshot)
    identity_object=next(r for r in snapshot['objects'] if Path(r['source']).name=='storage_identity.cpp')
    header_admission=q.verify_header_compile(observed[identity_object['object']][0],build/'local-players-identity/local-players-source-identity.json',
                                           manifest_sha,build/'local-players-generated/compiled_identity.hpp')
    link=policy['link_policy']
    q.exact_keys(link,['schema','dll','import_library','link_pdb','map','global_flags','configuration_flags',
                        'target_options','supervisor_policy','manifest_inputs','supervisor_appended_options'])
    q.require(link['schema']=='LocalPlayersLinkPolicy/v1'
              and link['supervisor_policy']=='cmake-3.31.8-vs_link_dll-nonincremental-no-manifest-inputs/v1'
              and link['manifest_inputs']==[] and link['supervisor_appended_options']==['/MANIFEST:EMBED,ID=2'],
              'pinned no-input nonincremental manifest policy')
    bridge=[t for t in policy['targets'] if t['target']=='flight_local_players_bridge'][0]
    q.require(q.ordinary(Path(link['dll']).parent,True)==build/'bin'
              and Path(os.path.abspath(link['dll']))==Path(os.path.abspath(bridge['output'])), 'closed production DLL output')
    parts,reply_pins=file_api_link(q,build,config)
    actual_flags=[];libraries=[]
    for role,tokens in parts:
        if role=='flags':actual_flags+=tokens
        elif role=='libraries':libraries+=tokens
        else:q.require(not tokens,'no additional library search directory')
    expected_flags=strings(q,link['global_flags'])+strings(q,link['configuration_flags'])+strings(q,link['target_options'])
    q.require(actual_flags==expected_flags,'FileAPI resolved flags differ from independently exported target flags')
    # MSVC uses the last INCREMENTAL option, not the final unrelated option.
    # CMake's exact target options also append /DEBUG:FULL in this configuration.
    incremental=[v.upper() for v in expected_flags if v.upper().split(':',1)[0]=='/INCREMENTAL']
    q.require(incremental and incremental[-1]=='/INCREMENTAL:NO'
              and sum(v.upper().startswith('/MAP:') for v in expected_flags)==1,'exact nonincremental/map final link options')
    archives={Path(os.path.abspath(t['output'])) for t in policy['targets'] if t['target']!='flight_local_players_bridge'}
    archives.add(q.ordinary(policy['godot_cpp_archive']))
    selected_archives=[];system=[]
    allowed_system={'kernel32.lib','user32.lib','gdi32.lib','winspool.lib','shell32.lib','ole32.lib',
                    'oleaut32.lib','uuid.lib','comdlg32.lib','advapi32.lib','bcrypt.lib'}
    for value in libraries:
        path=Path(os.path.abspath(build/value))
        if path in archives:selected_archives.append(path)
        else:
            q.require(Path(value).name==value and value.lower() in allowed_system,'unallocated archive/system library')
            system.append(value.lower())
    q.require(set(selected_archives)==archives and set(system)==allowed_system
              and all(selected_archives.count(p)==1 for p in archives if p.name.lower()!='flight_local_players_core.lib')
              and 1<=sum(p.name.lower()=='flight_local_players_core.lib' for p in selected_archives)<=2,
              'closed actual storage/Godot/SQLite archive and Win32 library roster')
    for value in allowed_system:q.require(1<=system.count(value)<=2,'bounded actual Win32 library duplication')
    objects=[r for r in snapshot['objects'] if r['target']=='flight_local_players_bridge']
    q.require(len(objects)==2,'exact production bridge object roster')
    relative=lambda value:str(Path(os.path.abspath(value)).relative_to(build)).replace('/','\\')
    argv=[frozen_operand(q,policy,policy['linker'],False),'/nologo']+[relative(r['object']) for r in objects]
    argv+=['/out:'+relative(link['dll']),'/implib:'+relative(link['import_library']),
           '/pdb:'+relative(link['link_pdb']),'/dll','/version:0.0']+expected_flags+libraries+link['supervisor_appended_options']
    q.require(not any(v.startswith('@') for v in argv),'no expected link response-file route')
    input_paths=[Path(r['object']) for r in snapshot['objects']]+list(archives)
    inputs=snapshot['inputs']+reply_pins+[q.file_pin(p) for p in input_paths]
    # Compilation PDBs are shared within their target. They become evidence only
    # after all target object invocations have joined, never fresh child outputs.
    pdbs=[]
    for target in policy['targets']:
        pdb=Path(target['compiler_pdb'])
        if target['debug_information_format']:
            pdbs.append(q.file_pin(pdb));inputs.append(pdbs[-1])
        else:q.require(not pdb.exists(),'unexpected compiler PDB without debug information')
    outputs=[link[k] for k in ('dll','import_library','map')]
    if config in ('Debug','RelWithDebInfo'):outputs.append(link['link_pdb'])
    outputs=[str(Path(os.path.abspath(p))) for p in outputs]
    for output in outputs:q.require(not Path(output).exists() and Path(output).is_relative_to(build),'fresh final link outputs')
    plan={'schema':'LocalPlayersInvocationPlan/v1','kind':'link','source_root':str(repo),'build_root':str(build),
          'cwd':str(build),'argv':argv,'tools':[q.file_pin(argv[0])],'inputs':inputs,'outputs':outputs}
    path=build/'local-players-witness/link-plan.json';q.write_new(path,q.json_bytes(plan))
    digest_pin=publish_digest(q,build/'local-players-witness/link-plan-digest.json',path)
    q.write_new(build/'local-players-witness/prelink-admission.json',q.json_bytes({'schema':'LocalPlayersPrelinkAdmission/v1',
        'compiles':compiles,'compiler_pdbs':pdbs,'configuration_replies':reply_pins,'plan':q.file_pin(path),'plan_digest_file':digest_pin,
        'production_archives':production_archives,
        'sqlite_compile':sqlite_compile,'sqlite_archive':archive_admission,'forced_header':header_admission,
        'scope':'Measured compiler/archive inputs only; no native/SQLite/Godot execution qualification'}))

def final_build_evidence(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy,identity,policy_path=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    snapshot,_=q.load_json(build/'local-players-witness/build-inputs.json')
    compiles,observed=verify_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'final precompile input continuity')
    sqlite=next(r for r in snapshot['objects'] if r['target']=='flight_sqlite')
    sqlite_run=observed[sqlite['object']][0]
    compile_witness=q.match_compile_database(build/'compile_commands.json',sqlite_run,sqlite['source'],sqlite['object'])
    identity_object=next(r for r in snapshot['objects'] if Path(r['source']).name=='storage_identity.cpp')
    header=q.verify_header_compile(observed[identity_object['object']][0],build/'local-players-identity/local-players-source-identity.json',
                                   manifest_sha,build/'local-players-generated/compiled_identity.hpp')
    archive=next(t['output'] for t in policy['targets'] if t['target']=='flight_sqlite')
    archive_witness=q.sqlite_archive_witness(archive,sqlite['object'])
    link_root=q.ordinary(build/'local-players-witness/link-receipts',True)
    links=list(link_root.iterdir());q.require(len(links)==1 and links[0].is_dir() and links[0].name.startswith('invocation-'),'one actual final inner link')
    link=q.link_inclusion_witness(links[0],archive,sqlite['object'],policy['link_policy']['dll'],policy['link_policy']['map'])
    prelink,_=q.load_json(build/'local-players-witness/prelink-admission.json')
    q.exact_keys(prelink,['schema','compiles','compiler_pdbs','configuration_replies','plan','plan_digest_file',
                          'production_archives','sqlite_compile','sqlite_archive','forced_header','scope'])
    q.require(prelink['schema']=='LocalPlayersPrelinkAdmission/v1','closed prelink admission schema')
    before,terminal=q.read_invocation(links[0])
    link_chain=admitted_link_plan_chain(q,before,prelink,repo,build)
    production_archives=production_archive_witnesses(q,policy,snapshot)
    q.require(production_archives==prelink['production_archives'],'actual core/windows archives unchanged since object-bound prelink')
    q.require(compiles==prelink['compiles'] and archive_witness==prelink['sqlite_archive']
              and compile_witness==prelink['sqlite_compile'] and header==prelink['forced_header'],'complete prelink measured input continuity')
    for pin in prelink['compiler_pdbs']+prelink['configuration_replies']:q.require(q.file_pin(pin['path'])==pin,'post-link PDB/configuration continuity')
    processes=q.ordinary(build/'local-players-witness/processes',True)
    expected_processes=['configure','publish-operand-facts','publish-identity-plan','publish-identity','publish-header','build-godot-cpp',
                        'publish-compile-plans','build-storage-objects','publish-link-plan','build-storage-dll']
    # Aggregate is itself still running. Its separate terminal is bound by the
    # outer Build receipt after this exclusive publication returns successfully.
    process_receipts=[]
    for name in expected_processes:
        root=q.ordinary(processes/name,True)
        before,_=q.load_json(root/'before.json');terminal,_=q.load_json(root/'terminal.json')
        q.exact_keys(before,['schema','name','tool','argv','cwd','timeout_seconds','child_environment'])
        q.require(before['child_environment']=={'PYTHONDONTWRITEBYTECODE':'1'},'fixed child bytecode policy')
        q.exact_keys(terminal,['schema','name','before','pid','started','exit_observed','exit_code','drained','timed_out',
                             'elapsed_ms','tool_unchanged','error','qualified_process'])
        q.require(before['schema']=='LocalPlayersRootProcessBefore/v1' and terminal['schema']=='LocalPlayersRootProcessTerminal/v1'
                  and before['name']==terminal['name']==name and terminal['before']==q.file_pin(root/'before.json')
                  and terminal['qualified_process'] is True and terminal['exit_observed'] is True and terminal['started'] is True
                  and terminal['drained'] is True and terminal['timed_out'] is False and terminal['tool_unchanged'] is True
                  and type(terminal['exit_code']) is int and terminal['exit_code']==0 and terminal['error'] is None
                  and type(terminal['pid']) is int and terminal['pid']>0
                  and q.file_pin(before['tool']['path'])==before['tool'], 'observed joined Root process')
        process_receipts.append({'before':q.file_pin(root/'before.json'),'terminal':q.file_pin(root/'terminal.json'),
                                 'stdout':q.file_pin(root/'stdout.log'),'stderr':q.file_pin(root/'stderr.log')})
    result={'schema':'LocalPlayersCompiledBuildEvidence/v1','compiled_build_verified':True,
        'native_checks_executed':False,'bridge_checks_executed':False,'source_identity':q.file_pin(build/'local-players-identity/local-players-source-identity.json'),
        'configuration_policy':q.file_pin(policy_path),'compile_database':q.file_pin(build/'compile_commands.json'),
        'compiled_source_count':9,'compiles':compiles,'forced_header':header,'sqlite_compile':compile_witness,
        'root_processes':process_receipts,
        'sqlite_archive':archive_witness,'production_archives':production_archives,'inner_link':link,'actual_link_plan_chain':link_chain,'prelink_admission':q.file_pin(build/'local-players-witness/prelink-admission.json'),
        'postbuild_witnesses':{'sqlite_c_compile_command_sha256':compile_witness['command_sha256'],
         'sqlite_static_archive_sha256':archive_witness['archive']['sha256'],'sqlite_object_roster_sha256':archive_witness['object_roster_sha256'],
         'storage_link_command_sha256':link['link_command_sha256']},
        'scope':'Build source/actual compiler/object/archive/header/inner-link closure only. Not CTest, capability, ClassDB, storage durability, package or issue219 acceptance.'}
    q.write_new(build/'local-players-witness/compiled-build-evidence.json',q.json_bytes(result))

def build_backend_main():
    import sys
    mode,repo_arg,deps_arg,build_arg,config,qualifier_sha,policy_sha,manifest_sha=sys.argv[1:]
    repo,deps,build=map(Path,(repo_arg,deps_arg,build_arg))
    q=reviewed_qualifier(repo,qualifier_sha)
    repo,deps,build=(q.ordinary(p,True) for p in (repo,deps,build))
    q.require(mode in ('operand-facts','compile-plans','link-plan','aggregate'),'closed build-only backend mode')
    functions={'operand-facts':publish_operand_facts,'compile-plans':publish_compile_plans,'link-plan':publish_link_plan,'aggregate':final_build_evidence}
    functions[mode](q,repo,deps,build,config,policy_sha,manifest_sha)
    q.require(q.file_pin(repo/'tools/local-players/qualify.py')['sha256']==qualifier_sha,'reviewed qualifier continuity')

build_backend_main()
'@

# Explicitly authorized actual qualification. Build evidence alone never enters
# these branches; the qualifier reconstructs the separate ON-build closure.
if ($Stage -cin @('NativeChecks','BridgeChecks')) {
    foreach ($value in @($ExecutionAuthorization,$TestBuildManifest,$CtestExecutable)) {
        if (-not $value) { throw 'Explicit NativeChecks/BridgeChecks authorization and ON-build inputs required' }
        Assert-OrdinaryPath $value $false
    }
    foreach ($pair in @(@($PythonExecutable,$PythonSha256),@($CtestExecutable,$CtestSha256),
            @($ExecutionAuthorization,$ExecutionAuthorizationSha256),@($TestBuildManifest,$TestBuildManifestSha256))) {
        if (-not $pair[1] -or (Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'Pinned qualification input changed' }
    }
    $qualifier=Join-Path $RepositoryRoot 'tools/local-players/qualify.py'
    if (-not $QualifierSha256 -or (Get-RootFilePin $qualifier).sha256 -cne $QualifierSha256) { throw 'Reviewed qualifier required' }
    $authorization=Get-Content -LiteralPath $ExecutionAuthorization -Raw | ConvertFrom-Json
    # No caller-selected output root: the closed raw-pinned authorization owns
    # this pre-existing ordinary parent. Qualifier validates it independently.
    Assert-OrdinaryPath $authorization.evidence_parent $true
    $evidence=Join-Path $authorization.evidence_parent ('root-'+$Stage.ToLowerInvariant()+'-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $evidence -ErrorAction Stop | Out-Null
    $runnerPin=Get-RootFilePin $PSCommandPath
    $arguments=@('-I','-B',$qualifier,$Stage.ToLowerInvariant().Replace('nativechecks','native-checks').Replace('bridgechecks','bridge-checks'),
        '--authorization',$ExecutionAuthorization,'--authorization-sha256',$ExecutionAuthorizationSha256,
        '--test-build',$TestBuildManifest,'--test-build-sha256',$TestBuildManifestSha256,
        '--ctest',$CtestExecutable,'--ctest-sha256',$CtestSha256)
    if ($Stage -ceq 'BridgeChecks') {
        foreach ($pair in @(@($GodotExecutable,$GodotSha256),@($NativeChecksReceipt,$NativeChecksReceiptSha256))) {
            if (-not $pair[0] -or -not $pair[1] -or (Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'Explicit focused bridge prerequisites required' }
        }
        $arguments+=@('--native-checks',$NativeChecksReceipt,'--native-checks-sha256',$NativeChecksReceiptSha256,
            '--godot',$GodotExecutable,'--godot-sha256',$GodotSha256)
    }
    $timeout=if ($Stage -ceq 'NativeChecks') {14400} else {600}
    $name=if ($Stage -ceq 'NativeChecks') {'native-checks'} else {'bridge-checks'}
    $null=Invoke-RootObservedProcess $name $PythonExecutable $PythonSha256 $arguments $RepositoryRoot $evidence $timeout
    if ((Get-RootFilePin $PSCommandPath).sha256 -cne $runnerPin.sha256) { throw 'Qualification runner changed' }
    Write-Output ('LOCAL PLAYERS '+$Stage.ToUpperInvariant()+' FOCUSED QUALIFICATION COMPLETED; installed-user journey and full issue219 acceptance remain separate.')
    return
}

$testBuildBackend = @'
# Private source-authoring fragment; embedded in the sole allocated run.ps1.
# No observed compiler/link command string supplies an expected argument.
import hashlib
import importlib.util
import json
import os
import ntpath
from pathlib import Path
import stat

TARGETS = {
    'flight_sqlite': ('C', ('sqlite3.c',)),
    'flight_local_players_core': ('CXX', ('records.cpp', 'codec.cpp', 'store.cpp', 'service.cpp', 'storage_identity.cpp')),
    'flight_local_players_windows': ('CXX', ('windows_filesystem.cpp',)),
    'flight_local_players_bridge': ('CXX', ('local_players.cpp', 'register_types.cpp')),
}

def reviewed_qualifier(repository, expected_sha):
    path = repository / 'tools/local-players/qualify.py'
    for item in (*reversed(path.parents), path):
        observed = item.lstat()
        if stat.S_ISLNK(observed.st_mode) or getattr(observed, 'st_file_attributes', 0) & 0x400:
            raise ValueError('nonordinary reviewed qualifier path')
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_sha:
        raise ValueError('reviewed qualifier changed')
    spec = importlib.util.spec_from_file_location('root_storage_build_witness', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def strings(q, value):
    q.require(type(value) is list and all(type(v) is str and v and not any(c in v for c in '\0\r\n') for v in value),
              'ordered literal token array')
    return value

def unique(values):
    return list(dict.fromkeys(values))

# Source-only future Build helpers. The offline fixtures do not call Win32.
def native_operand(value):
    return value.replace('/', '\\')


def ninja_relative_operand(q, value, build):
    path = Path(os.path.abspath(value))
    q.require(path.is_relative_to(build), 'contained top-build Ninja operand')
    return native_operand(str(path.relative_to(build)))


def native_path_identity(q, value, directory):
    # This is executed only by an explicitly authorized future Windows Build.
    # FILE_ID_INFO binds an 8.3 alias to the same physical ordinary file/dir.
    import ctypes
    from ctypes import wintypes
    q.require(os.name == 'nt', 'native CMake operand facts require Windows')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
        ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    kernel.GetFileInformationByHandleEx.restype = wintypes.BOOL
    kernel.GetFileAttributesW.argtypes = [wintypes.LPCWSTR]
    kernel.GetFileAttributesW.restype = wintypes.DWORD
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    class FileIdInfo(ctypes.Structure):
        _fields_ = [('volume', ctypes.c_ulonglong), ('identifier', ctypes.c_ubyte * 16)]
    class AttributeTagInfo(ctypes.Structure):
        _fields_ = [('attributes', wintypes.DWORD), ('reparse_tag', wintypes.DWORD)]
    q.ordinary(value, directory)
    attributes = kernel.GetFileAttributesW(str(value))
    q.require(attributes != 0xffffffff and not attributes & 0x400
              and bool(attributes & 0x10) == directory, 'ordinary native operand kind')
    handle = kernel.CreateFileW(str(value), 0x80, 7, None, 3, 0x02200000, None)
    q.require(handle not in (None, ctypes.c_void_p(-1).value), 'open physical operand identity')
    try:
        attributes = AttributeTagInfo()
        q.require(kernel.GetFileInformationByHandleEx(handle, 9, ctypes.byref(attributes), ctypes.sizeof(attributes))
                  and not attributes.attributes & 0x400 and bool(attributes.attributes & 0x10) == directory,
                  'actual opened operand is ordinary and has declared kind')
        info = FileIdInfo()
        q.require(kernel.GetFileInformationByHandleEx(handle, 18, ctypes.byref(info), ctypes.sizeof(info)),
                  'actual FILE_ID_INFO for operand')
        return {'volume_serial': str(info.volume), 'file_id_hex': bytes(info.identifier).hex()}
    finally:
        q.require(kernel.CloseHandle(handle), 'close operand identity handle')


def native_short_path(q, value):
    # CMake 3.31.8 kwsys::SystemTools::GetShortPath uses this exact two-call API.
    import ctypes
    from ctypes import wintypes
    q.require(os.name == 'nt', 'short operand query requires Windows')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetShortPathNameW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
    kernel.GetShortPathNameW.restype = wintypes.DWORD
    size = kernel.GetShortPathNameW(value, None, 0)
    if not size:
        return None
    q.require(size <= 32768, 'bounded native short operand')
    buffer = ctypes.create_unicode_buffer(size)
    result = kernel.GetShortPathNameW(value, buffer, size)
    if not result:
        return None
    q.require(result < size and buffer.value, 'stable native short operand length')
    return buffer.value


def existing_operand_fact(q, value, directory):
    # No command parser or observed argv is used. CMake shell escaping surrounds
    # these operands but is absent from the argv received by the Python launcher.
    q.require(type(value) is str and value and not any(c in value for c in '\0\r\n"'), 'literal CMake operand')
    long_path = q.ordinary(value, directory)
    identity = native_path_identity(q, value, directory)
    query = any(c in value for c in ' #')
    short = native_short_path(q, value) if query else None
    selected = short if short is not None else value
    q.require(native_path_identity(q, selected, directory) == identity, 'selected native alias must identify same physical operand')
    pin = None if directory else q.file_pin(long_path)
    selected_pin = None if directory else q.file_pin(selected)
    if not directory:
        q.require((pin['bytes'], pin['sha256']) == (selected_pin['bytes'], selected_pin['sha256']), 'same executable alias bytes')
    return {'path': value, 'directory': directory, 'existed': True,
            'short_path_status': 'not_needed' if not query else ('success' if short is not None else 'fallback'),
            'operand': native_operand(selected), 'physical_identity': identity,
            'long_pin': pin, 'selected_pin': selected_pin, 'ancestor': None}


def operand_roster(q, policy):
    values = [(policy['languages'][language]['compiler'], False) for language in ('C', 'CXX')]
    values += [(policy[name], False) for name in ('linker', 'librarian')]
    values += [(path, True) for target in policy['targets'] for path in strings(q, target['includes'])]
    return unique(values)


def publish_operand_facts(q, repo, deps, build, config, policy_sha, unused_manifest_sha):
    policy, policy_path = load_compile_policy(q, build, config, policy_sha)
    rows = []
    for value, directory in operand_roster(q, policy):
        path = Path(os.path.abspath(value))
        q.require(Path(value).is_absolute(), 'absolute exported operand')
        if directory:
            q.require(any(path.is_relative_to(root) for root in (repo, deps, build)), 'closed include operand roots')
        if path.exists():
            rows.append(existing_operand_fact(q, value, directory))
        else:
            # Preserve generation-time absence before the dependency build.
            # An include created later must not retroactively select an 8.3 name.
            q.require(directory and path.is_relative_to(build/'deps/godot-cpp/gen'), 'only generated include may be absent')
            ancestor = path.parent
            while not ancestor.exists():
                ancestor = ancestor.parent
            q.ordinary(ancestor, True)
            rows.append({'path': value, 'directory': True, 'existed': False,
                'short_path_status': 'absent', 'operand': native_operand(value),
                'physical_identity': None, 'long_pin': None, 'selected_pin': None,
                'ancestor': {'path': str(ancestor), 'physical_identity': native_path_identity(q, ancestor, True)}})
    q.write_new(build/'local-players-witness/cmake-operand-facts.json', q.json_bytes({
        'schema': 'LocalPlayersCMakeOperandFacts/v1', 'policy': q.file_pin(policy_path),
        'source_root': str(repo), 'build_root': str(build), 'dependency_root': str(deps), 'operands': rows}))


def admitted_operand_facts(q, repo, deps, build, policy, policy_path):
    facts, _ = q.load_json(build/'local-players-witness/cmake-operand-facts.json')
    q.exact_keys(facts, ['schema', 'policy', 'source_root', 'build_root', 'dependency_root', 'operands'])
    q.require(facts['schema'] == 'LocalPlayersCMakeOperandFacts/v1' and facts['policy'] == q.file_pin(policy_path)
              and [facts[k] for k in ('source_root', 'dependency_root', 'build_root')] == list(map(str, (repo, deps, build))),
              'frozen configure operand authority')
    q.require(type(facts['operands']) is list and [(r['path'], r['directory']) for r in facts['operands']] == operand_roster(q, policy),
              'closed configured operand roster')
    for row in facts['operands']:
        q.exact_keys(row, ['path', 'directory', 'existed', 'short_path_status', 'operand', 'physical_identity', 'long_pin', 'selected_pin', 'ancestor'])
        q.require(type(row['directory']) is bool and type(row['existed']) is bool, 'typed operand facts')
        if row['existed']:
            q.require(existing_operand_fact(q, row['path'], row['directory']) == row, 'configure alias/physical identity continuity')
        else:
            q.require(row['directory'] is True and Path(row['path']).is_relative_to(build/'deps/godot-cpp/gen')
                      and row['short_path_status'] == 'absent' and row['operand'] == native_operand(row['path'])
                      and row['physical_identity'] is row['long_pin'] is row['selected_pin'] is None, 'closed initially absent generated operand')
            ancestor = row['ancestor']
            q.exact_keys(ancestor, ['path', 'physical_identity'])
            q.require(Path(row['path']).is_relative_to(Path(ancestor['path'])) and Path(ancestor['path']).is_relative_to(build)
                      and native_path_identity(q, ancestor['path'], True) == ancestor['physical_identity'], 'generation ancestor continuity')
            if Path(row['path']).exists():
                q.ordinary(row['path'], True)
    return facts['operands']


def frozen_operand(q, policy, value, directory):
    matches = [row for row in policy['_operands'] if row['path'] == value and row['directory'] is directory]
    q.require(len(matches) == 1, 'exact frozen configured operand')
    return matches[0]['operand']


def same_identity_roots(identity, repo, deps, build):
    return [identity[k] for k in ('source_root', 'dependency_root', 'build_root')] == [p.as_posix() for p in (repo, deps, build)]

def target_archive_witness(q, target, object_paths):
    archive_path = q.ordinary(target['output'])
    archive_pin = q.file_pin(archive_path)
    raw = archive_path.read_bytes()
    q.require(len(raw) == archive_pin['bytes'] and hashlib.sha256(raw).hexdigest() == archive_pin['sha256'], 'stable target archive read')
    members = q.read_msvc_archive(raw)
    q.require(len(members) == len(object_paths) and len(set(object_paths)) == len(object_paths), 'exact target archive COFF roster count')
    matched, objects = [], []
    for object_path in object_paths:
        pin = q.file_pin(object_path)
        object_raw = q.ordinary(object_path).read_bytes()
        q.require(len(object_raw) == pin['bytes'] and hashlib.sha256(object_raw).hexdigest() == pin['sha256'], 'stable measured object read')
        matches = [i for i, member in enumerate(members) if ntpath.basename(member['name']) == Path(object_path).name
                   and member['bytes'] == pin['bytes'] and member['sha256'] == pin['sha256'] and member['data'] == object_raw]
        q.require(len(matches) == 1 and matches[0] not in matched, 'unique exact measured object inside target archive')
        matched.append(matches[0]); objects.append(pin)
        q.require(q.file_pin(object_path) == pin, 'measured object continuity')
    q.require(set(matched) == set(range(len(members))) and q.file_pin(archive_path) == archive_pin, 'no extra or changed target archive member')
    roster = [{key: member[key] for key in ('offset', 'name', 'bytes', 'sha256')} for member in members]
    return {'target': target['target'], 'archive': archive_pin, 'objects': objects,
            'members': roster, 'object_roster_sha256': hashlib.sha256(q.json_bytes(roster)).hexdigest(),
            'scope': 'Exact measured COFF member bytes; no separately observed librarian command or runtime claim.'}


def production_archive_witnesses(q, policy, snapshot):
    result = []
    for name, count in (('flight_local_players_core', 5), ('flight_local_players_windows', 1)):
        targets = [target for target in policy['targets'] if target['target'] == name]
        objects = [row['object'] for row in snapshot['objects'] if row['target'] == name]
        q.require(len(targets) == 1 and len(objects) == count, 'closed measured core/windows target roster')
        result.append(target_archive_witness(q, targets[0], objects))
    return result


def admitted_link_plan_chain(q, before, prelink, repo, build):
    path = build/'local-players-witness/link-plan.json'
    digest_path = build/'local-players-witness/link-plan-digest.json'
    plan_pin, digest_pin = q.file_pin(path), q.file_pin(digest_path)
    q.require(before['plan'] == prelink['plan'] == plan_pin and before['plan_sha256'] == plan_pin['sha256'],
              'actual inner link must use exact object-bound prelink plan')
    q.require(before['plan_digest_file'] == prelink['plan_digest_file'] == digest_pin
              and q.resolve_plan_digest(path, digest_file=digest_path) == (plan_pin['sha256'], digest_pin),
              'actual inner link must use exact frozen raw plan-digest artifact')
    plan, _ = q.load_json(path, plan_pin['sha256'])
    q.exact_keys(plan, ['schema', 'kind', 'source_root', 'build_root', 'cwd', 'argv', 'tools', 'inputs', 'outputs'])
    q.require(plan['schema'] == 'LocalPlayersInvocationPlan/v1' and before['kind'] == plan['kind'] == 'link'
              and [before[k] for k in ('source_root', 'build_root', 'cwd')] == [str(repo), str(build), str(build)]
              and all(plan[k] == before[k] for k in ('kind', 'source_root', 'build_root', 'cwd', 'argv', 'tools', 'inputs'))
              and plan['outputs'] == before['expected_outputs'], 'declared link kind/roots/complete plan correspondence')
    return {'plan': plan_pin, 'plan_digest_file': digest_pin}

def compile_rows(q, database, build):
    rows, _ = q.load_json(database)
    q.require(type(rows) is list and rows, 'original compile database required')
    indexed = {}
    for row in rows:
        q.require(type(row) is dict and all(type(row.get(k)) is str for k in ('file', 'directory', 'output')),
                  'compile metadata needs file/directory/output')
        directory = q.ordinary(row['directory'], True)
        source = Path(os.path.abspath(directory / row['file']))
        # The output is not created yet. Inspect the existing nearest ancestor;
        # the launcher will require its exact ordinary parent before compilation.
        output = Path(os.path.abspath(directory / row['output']))
        q.require(output.is_relative_to(build), 'contained compile object metadata')
        indexed.setdefault(source, []).append((row, directory, output))
    return indexed

def expected_compile_argv(q, policy, target, source, row, directory, object_path):
    language = target['language']
    facts = policy['languages'][language]
    q.require(language in ('C', 'CXX') and target['cxx_modules'] == 'OFF', 'closed native language/modules')
    compiler = frozen_operand(q, policy, facts['compiler'], False)
    q.ordinary(compiler)
    # cmLocalGenerator::JoinDefines uses a sorted set, independently of the
    # order of target property collection. Preserve actual argv spelling.
    defines = strings(q, target['defines'])
    if target['export_define']:
        q.require(target['export_define'] == target['target'] + '_EXPORTS', 'closed production export define')
        defines = defines + [target['export_define']]
    defines = ['-D' + value for value in sorted(set(defines))]
    includes = unique(strings(q, target['includes']))
    system = unique(strings(q, target['system_includes']))
    q.require(all(value in includes for value in system), 'system include must belong to actual target includes')
    normal = [value for value in includes if value not in system]
    includes_argv = ['-I' + frozen_operand(q, policy, value, True) for value in normal]
    system_flag = facts['system_include_option']
    if system:
        q.require(system_flag in ('-external:I', '/external:I'), 'closed pinned MSVC system include option')
        includes_argv += [system_flag + frozen_operand(q, policy, value, True) for value in includes if value in system]
        warning = facts['system_include_warning_option']
        q.require(warning == '-external:W0 ', 'exact pinned CMake 3.31.8 MSVC raw external warning option')
        warning_tokens = q.windows_response_tokens(warning)
        q.require(warning_tokens == ['-external:W0'], 'one pinned MSVC external warning token')
        includes_argv += warning_tokens
    runtime = 'MultiThreadedDebugDLL' if policy['configuration'] == 'Debug' else 'MultiThreadedDLL'
    q.require(target['msvc_runtime'] == runtime, 'actual target dynamic CRT mismatch')
    runtime_flags = strings(q, facts['runtime_options'][runtime])
    q.require(runtime_flags == (['-MDd'] if runtime.endswith('DebugDLL') else ['-MD']), 'pinned dynamic CRT options')
    debug = target['debug_information_format']
    q.require(debug == ('ProgramDatabase' if policy['configuration'] in ('Debug', 'RelWithDebInfo') else ''),
              'closed actual debug-information selection')
    debug_flags = strings(q, facts['debug_options'][debug]) if debug else []
    q.require(not debug or debug_flags == ['-Zi'], 'pinned ProgramDatabase option')
    flags = strings(q, facts['global_flags']) + strings(q, facts['configuration_flags'])
    if language == 'CXX':
        q.require(policy['cxx_standard_option'] in ('-std:c++20', '/std:c++20'), 'exact C++20 option')
        flags.append(policy['cxx_standard_option'])
    flags += runtime_flags + debug_flags + unique(strings(q, target['options'])) + strings(q, source['options'])
    flags += strings(q, facts['depfile_flags'])
    name = Path(source['path']).name
    strict = name in ('records.cpp', 'codec.cpp', 'local_players.cpp')
    q.require(sum(value == '/fp:strict' for value in flags) == int(strict), 'source-specific strict FP policy')
    q.require(not any(value.startswith(('/fp:', '-fp:')) and value != '/fp:strict' for value in flags), 'no conflicting FP mode')
    # Rule spelling comes from pinned Windows-MSVC.cmake. No command parser is
    # used to recover definitions, flags, object or source arguments.
    expected_rule = ('<CMAKE_' + language + '_COMPILER>  /nologo' + (' /TP' if language == 'CXX' else '')
        + ' <DEFINES> <INCLUDES> <FLAGS> /Fo<OBJECT> /Fd<TARGET_COMPILE_PDB> /FS -c <SOURCE>')
    q.require(facts['rule'] == expected_rule, 'unsupported pinned compile rule; review generated rule before build')
    q.require(directory == q.ordinary(policy['_build_root'], True), 'Ninja compile cwd must be declared build root')
    output_arg = row['output'].replace('/', '\\')
    pdb_arg = ninja_relative_operand(q, target['compiler_pdb'], q.ordinary(policy['_build_root'], True))
    source_arg = source['path'].replace('/', '\\')
    argv = [compiler, '/nologo'] + (['/TP'] if language == 'CXX' else []) + defines + includes_argv + flags
    argv += ['/Fo' + output_arg, '/Fd' + pdb_arg, '/FS', '-c', source_arg]
    q.require(len(' '.join(argv)) < 7000 and not any(value.startswith('@') for value in argv),
              'unreviewed compiler response-file route required')
    return argv

def load_compile_policy(q, build, config, policy_sha):
    policy_path = build / ('local-players-compile-policy-' + config + '.json')
    policy, _ = q.load_json(policy_path, policy_sha)
    q.exact_keys(policy, ['schema','rule_policy','configuration','languages','targets','cxx_standard_option',
                          'linker','librarian','archive_rule','shared_rule','godot_cpp_archive','link_policy'])
    q.require(policy['schema'] == 'LocalPlayersCompilePolicy/v1' and policy['configuration'] == config
              and policy['rule_policy'] == 'cmake-3.31.8-msvc-ninja-x64/v1', 'closed generated compile policy')
    q.exact_keys(policy['languages'], ['C','CXX'])
    for language in policy['languages'].values():
        q.exact_keys(language, ['compiler','global_flags','configuration_flags','depfile_flags',
             'system_include_option','system_include_warning_option','runtime_options','debug_options','rule'])
        q.exact_keys(language['runtime_options'], ['MultiThreadedDLL','MultiThreadedDebugDLL'])
        q.exact_keys(language['debug_options'], ['Embedded','ProgramDatabase','EditAndContinue'])
        q.require(language['depfile_flags'] == ['/showIncludes'], 'pinned Ninja MSVC dependency flag')
    q.require(type(policy['targets']) is list and [t.get('target') for t in policy['targets']] == list(TARGETS),
              'closed four production targets')
    return policy, policy_path


def metadata(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy, policy_path = load_compile_policy(q, build, config, policy_sha)
    _, identity = q.identity_header(build/'local-players-identity/local-players-source-identity.json', manifest_sha)
    q.require(same_identity_roots(identity, repo, deps, build) and identity['compiled_build_scalars']['platform'] == 'Windows-x64',
              'independent source identity roots/platform')
    q.require(identity['compiled_build_scalars']['configuration'] == config, 'actual source configuration')
    expected_sources = {
        'flight_sqlite': [deps/'sqlite/sqlite3.c'],
        'flight_local_players_core': [repo/'native/persistence/local_players/src'/n for n in TARGETS['flight_local_players_core'][1]],
        'flight_local_players_windows': [repo/'native/persistence/local_players/src/windows_filesystem.cpp'],
        'flight_local_players_bridge': [repo/'native/persistence/godot_bridge/src'/n for n in TARGETS['flight_local_players_bridge'][1]],
    }
    for target in policy['targets']:
        q.exact_keys(target, ['target','language','defines','includes','system_includes','options','export_define',
                              'msvc_runtime','cxx_modules','debug_information_format','compiler_pdb','output','sources'])
        name = target['target']
        q.require(target['language'] == TARGETS[name][0], 'target language source allocation')
        q.require([q.ordinary(s['path']) for s in target['sources']] == expected_sources[name], 'exact allocated CPP/C source roster')
        for source in target['sources']:
            q.exact_keys(source, ['path','options'])
        includes = strings(q, target['includes'])
        q.require(all(Path(p).is_absolute() for p in includes), 'absolute actual target includes')
        q.require(all(q.ordinary(p,True).is_relative_to(repo) or q.ordinary(p,True).is_relative_to(deps)
                      or q.ordinary(p,True).is_relative_to(build) for p in includes), 'closed source/dependency/generated includes')
        if name == 'flight_sqlite':
            q.require(sorted(target['defines']) == ['SQLITE_OMIT_LOAD_EXTENSION=1','SQLITE_THREADSAFE=1']
                      and includes == [str(deps/'sqlite').replace('\\','/')], 'exact SQLite target settings')
        output = Path(os.path.abspath(target['output']))
        pdb = Path(os.path.abspath(target['compiler_pdb']))
        q.require(output.is_relative_to(build) and pdb.is_relative_to(build/'local-players-compiler-pdb'/name), 'target/PDB containment')
    policy['_operands'] = admitted_operand_facts(q, repo, deps, build, policy, policy_path)
    policy['_build_root'] = str(build)
    return policy, identity, policy_path

def frozen_inputs(q, repo, deps, build, identity, policy_path):
    paths = [repo/r['path'] for r in identity['source_bindings']]
    paths += [deps/name/r['path'] for name,d in identity['dependencies'].items() for r in d['files']]
    paths += [Path(d['archive']['path']) for d in identity['dependencies'].values()]
    paths += [deps/name/'.verified.json' for name in identity['dependencies']]
    paths += [Path(r['path']) for r in identity['configure_provenance'].values()]
    policy,_=q.load_json(policy_path)
    paths += [q.ordinary(policy['linker']),q.ordinary(policy['librarian'])]
    operands = admitted_operand_facts(q, repo, deps, build, policy, policy_path)
    paths += [build/'local-players-witness/cmake-operand-facts.json']
    paths += [Path(pin['path']) for row in operands for pin in (row['long_pin'], row['selected_pin']) if pin is not None]
    generated=q.ordinary(build/'deps/godot-cpp/gen',True)
    for current,dirs,files in os.walk(generated,followlinks=False):
        for name in dirs:q.ordinary(Path(current)/name,True)
        for name in files:paths.append(q.ordinary(Path(current)/name))
    paths += [Path(identity['build_plan']['path']), policy_path, build/'compile_commands.json',
              build/('local-players-configure-controls-'+identity['compiled_build_scalars']['configuration']+'.json'),
              build/'local-players-identity/local-players-source-identity.json',
              build/'local-players-identity/local-players-identity.gd',
              build/'local-players-generated/compiled_identity.hpp', repo/'third_party/dependencies.lock.json',
              build/'local-players-witness/root-inputs.json',build/'local-players-witness/build-backend.py',
              build/'.cmake/api/v1/query/client-flight-local-players/query.json']
    root_inputs,_=q.load_json(build/'local-players-witness/root-inputs.json')
    q.exact_keys(root_inputs,['schema','runner','tools','backend'])
    q.require(root_inputs['schema']=='LocalPlayersRootBuildInputs/v1'
              and root_inputs['backend']==q.file_pin(build/'local-players-witness/build-backend.py'),'generated backend raw binding')
    for pin in [root_inputs['runner'],*root_inputs['tools']]:
        q.require(q.file_pin(pin['path'])==pin,'Root source/tool raw continuity')
        paths.append(Path(pin['path']))
    return [q.file_pin(p) for p in unique(paths)]

def publish_digest(q, path, plan):
    return q.write_new(path, q.json_bytes({'schema':'LocalPlayersInvocationPlanDigest/v1',
                    'plan_path':str(plan), 'plan_sha256':q.file_pin(plan)['sha256']}))

def publish_compile_plans(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy, identity, policy_path = metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    inputs = frozen_inputs(q,repo,deps,build,identity,policy_path)
    indexed = compile_rows(q,build/'compile_commands.json',build)
    parent = q.ordinary(build/'local-players-witness/plans',True)
    plans, objects, targets = [], [], []
    for target in policy['targets']:
        target_objects = []
        for source in target['sources']:
            matches = [r for r in indexed.get(q.ordinary(source['path']),[]) if 'CMakeFiles/'+target['target']+'.dir/' in r[0]['output'].replace('\\','/')]
            q.require(len(matches)==1, 'one actual source/directory/output metadata row')
            row,cwd,obj = matches[0]
            q.require(not obj.exists() and not obj.is_symlink(), 'fresh unique compilation object')
            argv = expected_compile_argv(q,policy,target,source,row,cwd,obj)
            plan = {'schema':'LocalPlayersInvocationPlan/v1','kind':'compile','source_root':str(repo),
                    'build_root':str(build),'cwd':str(cwd),'argv':argv,'tools':[q.file_pin(argv[0])],
                    'inputs':inputs,'outputs':[str(obj)]}
            path = parent/(target['target']+'-'+Path(source['path']).name+'.json')
            plans.append(q.write_new(path,q.json_bytes(plan)))
            objects.append({'target':target['target'],'source':source['path'],'object':str(obj),'cwd':str(cwd),'plan':plans[-1]})
            target_objects.append(str(obj))
        targets.append({'target':target['target'],'objects':target_objects,'compiler_pdb':target['compiler_pdb'],'output':target['output']})
    q.require(len(plans)==9 and len({r['object'] for r in objects})==9,'exact nine unique compiled objects')
    index = build/'local-players-witness/compile-index.json'
    q.write_new(index,q.json_bytes({'schema':'LocalPlayersCompilePlanIndex/v1','source_root':str(repo),'build_root':str(build),'entries':plans}))
    publish_digest(q,build/'local-players-witness/compile-index-digest.json',index)
    snapshot = {'schema':'LocalPlayersBuildInputs/v1','policy':q.file_pin(policy_path),'inputs':inputs,
                'objects':objects,'targets':targets,'compile_index':q.file_pin(index)}
    q.write_new(build/'local-players-witness/build-inputs.json',q.json_bytes(snapshot))
    return snapshot

def verify_compiles(q, build, snapshot):
    root = q.ordinary(build/'local-players-witness/compile-receipts',True)
    children = list(root.iterdir())
    q.require(all(p.is_dir() and not p.is_symlink() for p in children), 'ordinary compile receipt directories')
    runs = [p for p in children if p.name.startswith('invocation-')]
    selections = [p for p in children if p.name.startswith('compile-selection-')]
    q.require(len(runs)==len(selections)==9 and len(children)==18,'exact nine invocation/selection pairs')
    observed={}
    for run in runs:
        before,terminal=q.read_invocation(run)
        q.require(before['kind']=='compile' and len(terminal['outputs'])==1,'one measured unique object')
        name=terminal['outputs'][0]['path'];q.require(name not in observed,'no duplicated object witness')
        observed[name]=(run,before,terminal)
    selection_plans=[]
    for selection in selections:
        before,_=q.load_json(selection/'before.json');terminal,_=q.load_json(selection/'terminal.json')
        q.exact_keys(before,['schema','index','digest_file','selected_plan','argv','cwd','launcher'])
        q.exact_keys(terminal,['schema','before','selected_plan','exit_code','error','qualified_selection'])
        q.require(before['schema']=='LocalPlayersCompilePlanSelection/v1'
                  and terminal['schema']=='LocalPlayersCompilePlanSelectionTerminal/v1'
                  and terminal['before']==q.file_pin(selection/'before.json')
                  and terminal['exit_code']==0 and type(terminal['exit_code']) is int
                  and terminal['qualified_selection'] is True and terminal['error'] is None
                  and terminal['selected_plan']==before['selected_plan'],'actual selection terminal')
        q.require(before['index']==snapshot['compile_index']==q.file_pin(before['index']['path'])
                  and before['digest_file']==q.file_pin(build/'local-players-witness/compile-index-digest.json')
                  and before['launcher']==q.file_pin(q.__file__),'exact frozen selection authority')
        q.require(before['selected_plan']==q.file_pin(before['selected_plan']['path']),'selected plan raw pin')
        selected,_=q.load_json(before['selected_plan']['path'])
        q.require(before['argv']==selected['argv'] and before['cwd']==selected['cwd'], 'selection actual argv/cwd equals its frozen plan')
        q.require(q.resolve_plan_digest(before['index']['path'], digest_file=before['digest_file']['path'])
                  == (before['index']['sha256'],before['digest_file']), 'current closed compile-index digest')
        selection_plans.append(before['selected_plan']['path'])
    q.require(sorted(selection_plans)==sorted(r['plan']['path'] for r in snapshot['objects']), 'closed unique selected plan roster')
    result=[]
    rows,_=q.load_json(build/'compile_commands.json')
    for entry in snapshot['objects']:
        run,before,terminal=observed[entry['object']]
        q.require(before['plan']==entry['plan'] and q.actual_source(before['expanded_argv'],before['cwd'],q.ordinary(entry['source'])), 'actual allocated source compile')
        candidates=[r for r in rows if Path(os.path.abspath(Path(r['directory'])/r['file']))==q.ordinary(entry['source']) and type(r.get('output')) is str and Path(os.path.abspath(Path(r['directory'])/r['output']))==q.ordinary(entry['object'])]
        q.require(len(candidates)==1,'one original compile row')
        row=candidates[0]
        q.require(q.ordinary(row['directory'],True)==q.ordinary(before['cwd'],True)
                  and q.ordinary(Path(row['directory'])/row['output'])==q.ordinary(entry['object']), 'raw compile metadata/current object match')
        # command-only CMake rows are retained as evidence, NEVER parsed.
        if 'arguments' in row:q.require(row['arguments']==before['argv'],'optional actual array equality')
        else:q.require(type(row.get('command')) is str and row['command'],'original unparsed command evidence')
        result.append({'source':q.file_pin(entry['source']),'object':q.file_pin(entry['object']),
                      'invocation_before':q.file_pin(run/'before.json'),'invocation_terminal':q.file_pin(run/'terminal.json'),
                      'command_sha256':before['command_sha256']})
    return result,observed

def file_api_link(q, build, config):
    reply=q.ordinary(build/'.cmake/api/v1/reply',True)
    indexes=list(reply.glob('index-*.json'))
    q.require(len(indexes)==1,'fresh single CMake FileAPI index')
    index,_=q.load_json(indexes[0])
    q.require(index['cmake']['version']['string']=='3.31.8' and index['cmake']['generator']['name']=='Ninja', 'pinned actual FileAPI producer')
    responses=index['reply']['client-flight-local-players']['query.json']['responses']
    matches=[r for r in responses if r.get('kind')=='codemodel' and r.get('version',{}).get('major')==2]
    q.require(len(matches)==1,'one requested codemodel-v2 response')
    def read_reply(name):
        q.require(type(name) is str and Path(name).name==name and name.endswith('.json'),'closed reply filename')
        path=q.ordinary(reply/name);q.require(path.is_relative_to(reply),'reply containment')
        return q.load_json(path)[0],q.file_pin(path)
    model,model_pin=read_reply(matches[0]['jsonFile'])
    q.require(model['kind']=='codemodel' and model['version']['major']==2
              and q.ordinary(model['paths']['build'],True)==build,'actual codemodel root/version')
    configurations=[c for c in model['configurations'] if c['name']==config]
    q.require(len(configurations)==1,'one declared codemodel configuration')
    targets=[t for t in configurations[0]['targets'] if t['name']=='flight_local_players_bridge']
    q.require(len(targets)==1,'one production bridge codemodel target')
    target,target_pin=read_reply(targets[0]['jsonFile'])
    q.require(target['name']=='flight_local_players_bridge' and target['type']=='SHARED_LIBRARY'
              and target['link']['language']=='CXX','production shared CXX link metadata')
    parts=[]
    for item in target['link']['commandFragments']:
        q.require(item.get('role') in ('flags','libraries','libraryPath') and type(item.get('fragment')) is str,'configuration fragments only')
        values=q.windows_response_tokens(item['fragment']) if item['fragment'].strip() else []
        parts.append((item['role'],values))
    return parts,[q.file_pin(indexes[0]),model_pin,target_pin]

def publish_link_plan(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy,identity,policy_path=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    snapshot,_=q.load_json(build/'local-players-witness/build-inputs.json')
    compiles,observed=verify_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'frozen precompile input changed')
    sqlite=next(r for r in snapshot['objects'] if r['target']=='flight_sqlite')
    sqlite_compile=q.match_compile_database(build/'compile_commands.json',observed[sqlite['object']][0],sqlite['source'],sqlite['object'])
    sqlite_archive=next(t['output'] for t in policy['targets'] if t['target']=='flight_sqlite')
    archive_admission=q.sqlite_archive_witness(sqlite_archive,sqlite['object'])
    production_archives=production_archive_witnesses(q,policy,snapshot)
    identity_object=next(r for r in snapshot['objects'] if Path(r['source']).name=='storage_identity.cpp')
    header_admission=q.verify_header_compile(observed[identity_object['object']][0],build/'local-players-identity/local-players-source-identity.json',
                                           manifest_sha,build/'local-players-generated/compiled_identity.hpp')
    link=policy['link_policy']
    q.exact_keys(link,['schema','dll','import_library','link_pdb','map','global_flags','configuration_flags',
                        'target_options','supervisor_policy','manifest_inputs','supervisor_appended_options'])
    q.require(link['schema']=='LocalPlayersLinkPolicy/v1'
              and link['supervisor_policy']=='cmake-3.31.8-vs_link_dll-nonincremental-no-manifest-inputs/v1'
              and link['manifest_inputs']==[] and link['supervisor_appended_options']==['/MANIFEST:EMBED,ID=2'],
              'pinned no-input nonincremental manifest policy')
    bridge=[t for t in policy['targets'] if t['target']=='flight_local_players_bridge'][0]
    q.require(q.ordinary(Path(link['dll']).parent,True)==build/'bin'
              and Path(os.path.abspath(link['dll']))==Path(os.path.abspath(bridge['output'])), 'closed production DLL output')
    parts,reply_pins=file_api_link(q,build,config)
    actual_flags=[];libraries=[]
    for role,tokens in parts:
        if role=='flags':actual_flags+=tokens
        elif role=='libraries':libraries+=tokens
        else:q.require(not tokens,'no additional library search directory')
    expected_flags=strings(q,link['global_flags'])+strings(q,link['configuration_flags'])+strings(q,link['target_options'])
    q.require(actual_flags==expected_flags,'FileAPI resolved flags differ from independently exported target flags')
    # MSVC uses the last INCREMENTAL option, not the final unrelated option.
    # CMake's exact target options also append /DEBUG:FULL in this configuration.
    incremental=[v.upper() for v in expected_flags if v.upper().split(':',1)[0]=='/INCREMENTAL']
    q.require(incremental and incremental[-1]=='/INCREMENTAL:NO'
              and sum(v.upper().startswith('/MAP:') for v in expected_flags)==1,'exact nonincremental/map final link options')
    archives={Path(os.path.abspath(t['output'])) for t in policy['targets'] if t['target']!='flight_local_players_bridge'}
    archives.add(q.ordinary(policy['godot_cpp_archive']))
    selected_archives=[];system=[]
    allowed_system={'kernel32.lib','user32.lib','gdi32.lib','winspool.lib','shell32.lib','ole32.lib',
                    'oleaut32.lib','uuid.lib','comdlg32.lib','advapi32.lib','bcrypt.lib'}
    for value in libraries:
        path=Path(os.path.abspath(build/value))
        if path in archives:selected_archives.append(path)
        else:
            q.require(Path(value).name==value and value.lower() in allowed_system,'unallocated archive/system library')
            system.append(value.lower())
    q.require(set(selected_archives)==archives and set(system)==allowed_system
              and all(selected_archives.count(p)==1 for p in archives if p.name.lower()!='flight_local_players_core.lib')
              and 1<=sum(p.name.lower()=='flight_local_players_core.lib' for p in selected_archives)<=2,
              'closed actual storage/Godot/SQLite archive and Win32 library roster')
    for value in allowed_system:q.require(1<=system.count(value)<=2,'bounded actual Win32 library duplication')
    objects=[r for r in snapshot['objects'] if r['target']=='flight_local_players_bridge']
    q.require(len(objects)==2,'exact production bridge object roster')
    relative=lambda value:str(Path(os.path.abspath(value)).relative_to(build)).replace('/','\\')
    argv=[frozen_operand(q,policy,policy['linker'],False),'/nologo']+[relative(r['object']) for r in objects]
    argv+=['/out:'+relative(link['dll']),'/implib:'+relative(link['import_library']),
           '/pdb:'+relative(link['link_pdb']),'/dll','/version:0.0']+expected_flags+libraries+link['supervisor_appended_options']
    q.require(not any(v.startswith('@') for v in argv),'no expected link response-file route')
    input_paths=[Path(r['object']) for r in snapshot['objects']]+list(archives)
    inputs=snapshot['inputs']+reply_pins+[q.file_pin(p) for p in input_paths]
    # Compilation PDBs are shared within their target. They become evidence only
    # after all target object invocations have joined, never fresh child outputs.
    pdbs=[]
    for target in policy['targets']:
        pdb=Path(target['compiler_pdb'])
        if target['debug_information_format']:
            pdbs.append(q.file_pin(pdb));inputs.append(pdbs[-1])
        else:q.require(not pdb.exists(),'unexpected compiler PDB without debug information')
    outputs=[link[k] for k in ('dll','import_library','map')]
    if config in ('Debug','RelWithDebInfo'):outputs.append(link['link_pdb'])
    outputs=[str(Path(os.path.abspath(p))) for p in outputs]
    for output in outputs:q.require(not Path(output).exists() and Path(output).is_relative_to(build),'fresh final link outputs')
    plan={'schema':'LocalPlayersInvocationPlan/v1','kind':'link','source_root':str(repo),'build_root':str(build),
          'cwd':str(build),'argv':argv,'tools':[q.file_pin(argv[0])],'inputs':inputs,'outputs':outputs}
    path=build/'local-players-witness/link-plan.json';q.write_new(path,q.json_bytes(plan))
    digest_pin=publish_digest(q,build/'local-players-witness/link-plan-digest.json',path)
    q.write_new(build/'local-players-witness/prelink-admission.json',q.json_bytes({'schema':'LocalPlayersPrelinkAdmission/v1',
        'compiles':compiles,'compiler_pdbs':pdbs,'configuration_replies':reply_pins,'plan':q.file_pin(path),'plan_digest_file':digest_pin,
        'production_archives':production_archives,
        'sqlite_compile':sqlite_compile,'sqlite_archive':archive_admission,'forced_header':header_admission,
        'scope':'Measured compiler/archive inputs only; no native/SQLite/Godot execution qualification'}))

def final_build_evidence(q, repo, deps, build, config, policy_sha, manifest_sha):
    policy,identity,policy_path=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    snapshot,_=q.load_json(build/'local-players-witness/build-inputs.json')
    compiles,observed=verify_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'final precompile input continuity')
    sqlite=next(r for r in snapshot['objects'] if r['target']=='flight_sqlite')
    sqlite_run=observed[sqlite['object']][0]
    compile_witness=q.match_compile_database(build/'compile_commands.json',sqlite_run,sqlite['source'],sqlite['object'])
    identity_object=next(r for r in snapshot['objects'] if Path(r['source']).name=='storage_identity.cpp')
    header=q.verify_header_compile(observed[identity_object['object']][0],build/'local-players-identity/local-players-source-identity.json',
                                   manifest_sha,build/'local-players-generated/compiled_identity.hpp')
    archive=next(t['output'] for t in policy['targets'] if t['target']=='flight_sqlite')
    archive_witness=q.sqlite_archive_witness(archive,sqlite['object'])
    link_root=q.ordinary(build/'local-players-witness/link-receipts',True)
    links=list(link_root.iterdir());q.require(len(links)==1 and links[0].is_dir() and links[0].name.startswith('invocation-'),'one actual final inner link')
    link=q.link_inclusion_witness(links[0],archive,sqlite['object'],policy['link_policy']['dll'],policy['link_policy']['map'])
    prelink,_=q.load_json(build/'local-players-witness/prelink-admission.json')
    q.exact_keys(prelink,['schema','compiles','compiler_pdbs','configuration_replies','plan','plan_digest_file',
                          'production_archives','sqlite_compile','sqlite_archive','forced_header','scope'])
    q.require(prelink['schema']=='LocalPlayersPrelinkAdmission/v1','closed prelink admission schema')
    before,terminal=q.read_invocation(links[0])
    link_chain=admitted_link_plan_chain(q,before,prelink,repo,build)
    production_archives=production_archive_witnesses(q,policy,snapshot)
    q.require(production_archives==prelink['production_archives'],'actual core/windows archives unchanged since object-bound prelink')
    q.require(compiles==prelink['compiles'] and archive_witness==prelink['sqlite_archive']
              and compile_witness==prelink['sqlite_compile'] and header==prelink['forced_header'],'complete prelink measured input continuity')
    for pin in prelink['compiler_pdbs']+prelink['configuration_replies']:q.require(q.file_pin(pin['path'])==pin,'post-link PDB/configuration continuity')
    processes=q.ordinary(build/'local-players-witness/processes',True)
    expected_processes=['configure','publish-operand-facts','publish-identity-plan','publish-identity','publish-header','build-godot-cpp',
                        'publish-compile-plans','build-storage-objects','publish-link-plan','build-storage-dll']
    # Aggregate is itself still running. Its separate terminal is bound by the
    # outer Build receipt after this exclusive publication returns successfully.
    process_receipts=[]
    for name in expected_processes:
        root=q.ordinary(processes/name,True)
        before,_=q.load_json(root/'before.json');terminal,_=q.load_json(root/'terminal.json')
        q.exact_keys(before,['schema','name','tool','argv','cwd','timeout_seconds','child_environment'])
        q.require(before['child_environment']=={'PYTHONDONTWRITEBYTECODE':'1'},'fixed child bytecode policy')
        q.exact_keys(terminal,['schema','name','before','pid','started','exit_observed','exit_code','drained','timed_out',
                             'elapsed_ms','tool_unchanged','error','qualified_process'])
        q.require(before['schema']=='LocalPlayersRootProcessBefore/v1' and terminal['schema']=='LocalPlayersRootProcessTerminal/v1'
                  and before['name']==terminal['name']==name and terminal['before']==q.file_pin(root/'before.json')
                  and terminal['qualified_process'] is True and terminal['exit_observed'] is True and terminal['started'] is True
                  and terminal['drained'] is True and terminal['timed_out'] is False and terminal['tool_unchanged'] is True
                  and type(terminal['exit_code']) is int and terminal['exit_code']==0 and terminal['error'] is None
                  and type(terminal['pid']) is int and terminal['pid']>0
                  and q.file_pin(before['tool']['path'])==before['tool'], 'observed joined Root process')
        process_receipts.append({'before':q.file_pin(root/'before.json'),'terminal':q.file_pin(root/'terminal.json'),
                                 'stdout':q.file_pin(root/'stdout.log'),'stderr':q.file_pin(root/'stderr.log')})
    result={'schema':'LocalPlayersCompiledBuildEvidence/v1','compiled_build_verified':True,
        'native_checks_executed':False,'bridge_checks_executed':False,'source_identity':q.file_pin(build/'local-players-identity/local-players-source-identity.json'),
        'configuration_policy':q.file_pin(policy_path),'compile_database':q.file_pin(build/'compile_commands.json'),
        'compiled_source_count':9,'compiles':compiles,'forced_header':header,'sqlite_compile':compile_witness,
        'root_processes':process_receipts,
        'sqlite_archive':archive_witness,'production_archives':production_archives,'inner_link':link,'actual_link_plan_chain':link_chain,'prelink_admission':q.file_pin(build/'local-players-witness/prelink-admission.json'),
        'postbuild_witnesses':{'sqlite_c_compile_command_sha256':compile_witness['command_sha256'],
         'sqlite_static_archive_sha256':archive_witness['archive']['sha256'],'sqlite_object_roster_sha256':archive_witness['object_roster_sha256'],
         'storage_link_command_sha256':link['link_command_sha256']},
        'scope':'Build source/actual compiler/object/archive/header/inner-link closure only. Not CTest, capability, ClassDB, storage durability, package or issue219 acceptance.'}
    q.write_new(build/'local-players-witness/compiled-build-evidence.json',q.json_bytes(result))

def build_backend_main():
    import sys
    mode,repo_arg,deps_arg,build_arg,config,qualifier_sha,policy_sha,manifest_sha=sys.argv[1:]
    repo,deps,build=map(Path,(repo_arg,deps_arg,build_arg))
    q=reviewed_qualifier(repo,qualifier_sha)
    repo,deps,build=(q.ordinary(p,True) for p in (repo,deps,build))
    q.require(mode in ('operand-facts','compile-plans','link-plan','aggregate'),'closed build-only backend mode')
    functions={'operand-facts':publish_operand_facts,'compile-plans':publish_compile_plans,'link-plan':publish_link_plan,'aggregate':final_build_evidence}
    functions[mode](q,repo,deps,build,config,policy_sha,manifest_sha)
    q.require(q.file_pin(repo/'tools/local-players/qualify.py')['sha256']==qualifier_sha,'reviewed qualifier continuity')


def expected_test_compile_argv(q, policy, target, source, row, directory, object_path):
    language = target['language']
    facts = policy['languages'][language]
    q.require(language in ('C', 'CXX') and target['cxx_modules'] == 'OFF', 'closed native language/modules')
    compiler = frozen_operand(q, policy, facts['compiler'], False)
    q.ordinary(compiler)
    # cmLocalGenerator::JoinDefines uses a sorted set, independently of the
    # order of target property collection. Preserve actual argv spelling.
    defines = strings(q, target['defines'])
    if target['export_define']:
        q.require(target['export_define'] == target['target'] + '_EXPORTS', 'closed test export define')
        defines = defines + [target['export_define']]
    defines = ['-D' + value for value in sorted(set(defines))]
    includes = unique(strings(q, target['includes']))
    system = unique(strings(q, target['system_includes']))
    q.require(all(value in includes for value in system), 'system include must belong to actual target includes')
    normal = [value for value in includes if value not in system]
    includes_argv = ['-I' + frozen_operand(q, policy, value, True) for value in normal]
    system_flag = facts['system_include_option']
    if system:
        q.require(system_flag in ('-external:I', '/external:I'), 'closed pinned MSVC system include option')
        includes_argv += [system_flag + frozen_operand(q, policy, value, True) for value in includes if value in system]
        warning = facts['system_include_warning_option']
        q.require(warning == '-external:W0 ', 'exact pinned CMake 3.31.8 MSVC raw external warning option')
        warning_tokens = q.windows_response_tokens(warning)
        q.require(warning_tokens == ['-external:W0'], 'one pinned MSVC external warning token')
        includes_argv += warning_tokens
    runtime = 'MultiThreadedDebugDLL' if policy['configuration'] == 'Debug' else 'MultiThreadedDLL'
    q.require(target['msvc_runtime'] == runtime, 'actual target dynamic CRT mismatch')
    runtime_flags = strings(q, facts['runtime_options'][runtime])
    q.require(runtime_flags == (['-MDd'] if runtime.endswith('DebugDLL') else ['-MD']), 'pinned dynamic CRT options')
    debug = target['debug_information_format']
    q.require(debug == ('ProgramDatabase' if policy['configuration'] in ('Debug', 'RelWithDebInfo') else ''),
              'closed actual debug-information selection')
    debug_flags = strings(q, facts['debug_options'][debug]) if debug else []
    q.require(not debug or debug_flags == ['-Zi'], 'pinned ProgramDatabase option')
    flags = strings(q, facts['global_flags']) + strings(q, facts['configuration_flags'])
    if language == 'CXX':
        q.require(policy['cxx_standard_option'] in ('-std:c++20', '/std:c++20'), 'exact C++20 option')
        flags.append(policy['cxx_standard_option'])
    flags += runtime_flags + debug_flags + unique(strings(q, target['options'])) + strings(q, source['options'])
    flags += strings(q, facts['depfile_flags'])
    name = Path(source['path']).name
    strict = name in ('records.cpp', 'codec.cpp', 'local_players.cpp')
    q.require(sum(value == '/fp:strict' for value in flags) == 1 + sum(v == '/fp:strict' for v in source['options']), 'source-specific strict FP policy')
    q.require(not any(value.startswith(('/fp:', '-fp:')) and value != '/fp:strict' for value in flags), 'no conflicting FP mode')
    # Rule spelling comes from pinned Windows-MSVC.cmake. No command parser is
    # used to recover definitions, flags, object or source arguments.
    expected_rule = ('<CMAKE_' + language + '_COMPILER>  /nologo' + (' /TP' if language == 'CXX' else '')
        + ' <DEFINES> <INCLUDES> <FLAGS> /Fo<OBJECT> /Fd<TARGET_COMPILE_PDB> /FS -c <SOURCE>')
    q.require(facts['rule'] == expected_rule, 'unsupported pinned compile rule; review generated rule before build')
    q.require(directory == q.ordinary(policy['_build_root'], True), 'Ninja compile cwd must be declared build root')
    output_arg = row['output'].replace('/', '\\')
    pdb_arg = ninja_relative_operand(q, target['compiler_pdb'], q.ordinary(policy['_build_root'], True))
    source_arg = source['path'].replace('/', '\\')
    argv = [compiler, '/nologo'] + (['/TP'] if language == 'CXX' else []) + defines + includes_argv + flags
    argv += ['/Fo' + output_arg, '/Fd' + pdb_arg, '/FS', '-c', source_arg]
    q.require(len(' '.join(argv)) < 7000 and not any(value.startswith('@') for value in argv),
              'unreviewed compiler response-file route required')
    return argv

def file_api_test_link(q, build, config, target_name, target_kind):
    q.require(target_kind in ('EXECUTABLE','SHARED_LIBRARY'),'closed test link target kind')
    reply=q.ordinary(build/'.cmake/api/v1/reply',True)
    indexes=list(reply.glob('index-*.json'))
    q.require(len(indexes)==1,'fresh single CMake FileAPI index')
    index,_=q.load_json(indexes[0])
    q.require(index['cmake']['version']['string']=='3.31.8' and index['cmake']['generator']['name']=='Ninja', 'pinned actual FileAPI producer')
    responses=index['reply']['client-flight-local-players']['query.json']['responses']
    matches=[r for r in responses if r.get('kind')=='codemodel' and r.get('version',{}).get('major')==2]
    q.require(len(matches)==1,'one requested codemodel-v2 response')
    def read_reply(name):
        q.require(type(name) is str and Path(name).name==name and name.endswith('.json'),'closed reply filename')
        path=q.ordinary(reply/name);q.require(path.is_relative_to(reply),'reply containment')
        return q.load_json(path)[0],q.file_pin(path)
    model,model_pin=read_reply(matches[0]['jsonFile'])
    q.require(model['kind']=='codemodel' and model['version']['major']==2
              and q.ordinary(model['paths']['build'],True)==build,'actual codemodel root/version')
    configurations=[c for c in model['configurations'] if c['name']==config]
    q.require(len(configurations)==1,'one declared codemodel configuration')
    targets=[t for t in configurations[0]['targets'] if t['name']==target_name]
    q.require(len(targets)==1,'one declared test codemodel target')
    target,target_pin=read_reply(targets[0]['jsonFile'])
    q.require(target['name']==target_name and target['type']==target_kind
              and target['link']['language']=='CXX','declared test CXX link metadata')
    parts=[]
    for item in target['link']['commandFragments']:
        q.require(item.get('role') in ('flags','libraries','libraryPath') and type(item.get('fragment')) is str,'configuration fragments only')
        values=q.windows_response_tokens(item['fragment']) if item['fragment'].strip() else []
        parts.append((item['role'],values))
    return parts,[q.file_pin(indexes[0]),model_pin,target_pin]

# Original MIT. Embedded test-build producer extension; source only.
# All subprocesses are owned by the PowerShell Root observed-process wrapper.
TEST_SOURCE_TARGETS = {
 'local_players_codec_native': ('codec',['codec.cpp']),
 'local_players_store_native': ('store',['native.cpp','test_capability.cpp']),
 'local_players_service_native': ('service',['service.cpp','test_capability.cpp']),
 'local_players_windows_native': ('windows',['windows.cpp','test_capability.cpp']),
 'local_players_crash_native': ('crash',['native.cpp','test_capability.cpp']),
 'local_players_crash_actor': ('crash_actor',['crash_actor.cpp','test_capability.cpp']),
 'local_players_lock_actor': ('lock_actor',['faults/lock_actor.cpp','test_capability.cpp']),
 'flight_local_players_test_bridge': ('test_bridge',['@boundary','test_capability.cpp','test_bridge.cpp'])}


def test_metadata(q,repo,deps,build,config,policy_sha,manifest_sha,before_generation=False):
    if before_generation:
        production,production_path=load_compile_policy(q,build,config,policy_sha)
        _,identity=q.identity_header(build/'local-players-identity/local-players-source-identity.json',manifest_sha)
        q.require(same_identity_roots(identity,repo,deps,build),'same pre-generation source identity roots')
    else:
        production,identity,production_path=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    path=build/('local-players-test-policy-'+config+'.json')
    value,_=q.load_json(path)
    q.exact_keys(value,['schema','configuration','production_policy','executable_rule','shared_rule','targets'])
    q.require(value['schema']=='LocalPlayersTestCompilePolicy/v1' and value['configuration']==config
        and q.ordinary(value['production_policy'])==production_path,'same-configure closed test policy')
    expected_exe_rule=production['shared_rule'].replace('vs_link_dll','vs_link_exe').replace(' /dll','').replace(' <LINK_FLAGS>',' <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS>').rstrip()
    q.require(value['executable_rule']==expected_exe_rule,'pinned Windows-MSVC executable rule, including language flag slot')
    q.require(type(value['targets']) is list and [t['target'] for t in value['targets']]==list(TEST_SOURCE_TARGETS),'closed eight test targets')
    for row in value['targets']:
        q.exact_keys(row,['target','language','defines','includes','system_includes','options','export_define',
            'msvc_runtime','cxx_modules','debug_information_format','compiler_pdb','output','sources','link'])
        role,names=TEST_SOURCE_TARGETS[row['target']]
        expected=[repo/'native/persistence/godot_bridge/src/local_players.cpp' if name=='@boundary'
            else repo/'tests/persistence/local_players'/name for name in names]
        q.require(row['language']=='CXX' and row['cxx_modules']=='OFF'
            and [q.ordinary(s['path']) for s in row['sources']]==expected,'closed actual test CPP roster')
        for source in row['sources']:
            q.exact_keys(source,['path','options'])
            q.require(source['options']==(['/fp:strict'] if Path(source['path']).name=='local_players.cpp' else []),'closed test source strict options')
        core=next(t for t in production['targets'] if t['target']=='flight_local_players_core')
        bridge=next(t for t in production['targets'] if t['target']=='flight_local_players_bridge')
        q.require(core['options']==['/Zc:__cplusplus','/utf-8','/W4','/WX','/permissive-','/utf-8'], 'closed inherited parent/core options')
        godot_options=bridge['options'][len(core['options']):]
        q.require(bridge['options'][:len(core['options'])]==core['options'] and len(godot_options)==2
            and godot_options[0].startswith('/MP') and godot_options[0][3:].isdigit() and godot_options[1]=='/utf-8','pinned Godot transitive options')
        expected_options=core['options'][:2]+['/W4','/WX','/permissive-','/utf-8','/fp:strict']+(godot_options if role=='test_bridge' else [])
        q.require(row['options']==expected_options,'closed inherited and target-local test options')
        expected_defines=bridge['defines'] if role=='test_bridge' else ['WIN32_LEAN_AND_MEAN','NOMINMAX']
        q.require(row['defines']==expected_defines,'closed actual transitive test definitions')
        for include in strings(q,row['includes']):
            candidate=Path(os.path.abspath(include))
            q.require(any(candidate.is_relative_to(root) for root in [repo,deps,build]),'test include containment')
            if candidate.exists():q.ordinary(candidate,True)
            else:q.require(before_generation and candidate.is_relative_to(build/'deps/godot-cpp/gen'),'only declared generated include absent')
        q.require(Path(row['compiler_pdb'])==build/'local-players-compiler-pdb'/row['target']/(row['target']+'.pdb'), 'declared target compiler PDB')
        extension='.dll' if role=='test_bridge' else '.exe'
        q.require(Path(row['output'])==build/'bin'/(row['target']+extension),'closed actual test output path')
        link=row['link']
        q.exact_keys(link,['kind','output','import_library','link_pdb','map','global_flags','configuration_flags',
            'language_flags','console_options','target_options','manifest_inputs','supervisor_appended_options'])
        q.require(link['kind']==('SHARED_LIBRARY' if role=='test_bridge' else 'EXECUTABLE')
            and link['output']==row['output'] and Path(link['import_library'])==build/'lib'/(row['target']+'.lib')
            and Path(link['link_pdb'])==build/'bin'/(row['target']+'.pdb')
            and Path(link['map'])==build/('local-players-test-'+row['target']+'.map'),'closed target link operands')
        q.require(link['manifest_inputs']==[] and link['supervisor_appended_options']==['/MANIFEST:EMBED,ID='+('2' if role=='test_bridge' else '1')], 'DLL2/EXE1 no-input manifest policy')
        q.require(link['console_options']==([] if role=='test_bridge' else ['/subsystem:console'])
            and link['language_flags']==[], 'pinned non-WinCE ordinary console language options')
        inherited_link_options=production['link_policy']['target_options'][2:] if role=='test_bridge' else []
        q.require(inherited_link_options==(['/DEBUG:FULL'] if role=='test_bridge' and config in ['Debug','RelWithDebInfo'] else []), 'closed Godot debug-link inheritance')
        q.require(link['target_options']==['/MAP:'+str(build/('local-players-test-'+row['target']+'.map')).replace('\\','/'),'/INCREMENTAL:NO']+inherited_link_options, 'closed test map/nonincremental options')
        if role=='test_bridge':q.require(value['shared_rule']==production['shared_rule'],'same pinned DLL rule')
    policy={key:production[key] for key in ['schema','rule_policy','configuration','languages','cxx_standard_option',
        'linker','librarian','archive_rule','godot_cpp_archive']}
    policy['targets']=value['targets'];policy['shared_rule']=value['shared_rule'];policy['executable_rule']=value['executable_rule']
    policy['_build_root']=str(build)
    return policy,identity,path,production_path


def publish_test_operand_facts(q,repo,deps,build,config,policy_sha,manifest_sha):
    policy,_,path,_=test_metadata(q,repo,deps,build,config,policy_sha,manifest_sha,True)
    rows=[]
    for value,directory in operand_roster(q,policy):
        candidate=Path(os.path.abspath(value))
        if candidate.exists(): rows.append(existing_operand_fact(q,value,directory))
        else:
            q.require(directory and candidate.is_relative_to(build/'deps/godot-cpp/gen'),'only generated test include may initially be absent')
            ancestor=candidate.parent
            while not ancestor.exists():ancestor=ancestor.parent
            q.ordinary(ancestor,True)
            rows.append({'path':value,'directory':True,'existed':False,'short_path_status':'absent','operand':native_operand(value),
                'physical_identity':None,'long_pin':None,'selected_pin':None,'ancestor':{'path':str(ancestor),'physical_identity':native_path_identity(q,ancestor,True)}})
    q.write_new(build/'local-players-test-witness/cmake-operand-facts.json',q.json_bytes({
        'schema':'LocalPlayersTestCMakeOperandFacts/v1','policy':q.file_pin(path),'source_root':str(repo),'dependency_root':str(deps),'build_root':str(build),'operands':rows}))


def test_operand_facts(q,policy,path,repo,deps,build):
    value,_=q.load_json(build/'local-players-test-witness/cmake-operand-facts.json')
    q.exact_keys(value,['schema','policy','source_root','dependency_root','build_root','operands'])
    q.require(value['schema']=='LocalPlayersTestCMakeOperandFacts/v1' and value['policy']==q.file_pin(path)
        and [value[k] for k in ['source_root','dependency_root','build_root']]==list(map(str,[repo,deps,build])),'test operand authority')
    q.require([(r['path'],r['directory']) for r in value['operands']]==operand_roster(q,policy),'closed configure operand roster')
    for row in value['operands']:
        q.exact_keys(row,['path','directory','existed','short_path_status','operand','physical_identity','long_pin','selected_pin','ancestor'])
        q.require(type(row['directory']) is bool and type(row['existed']) is bool,'typed test operand facts')
        if row['existed']:q.require(existing_operand_fact(q,row['path'],row['directory'])==row,'test operand physical/alias continuity')
        else:
            q.require(row['directory'] and Path(row['path']).is_relative_to(build/'deps/godot-cpp/gen')
                and row['operand']==native_operand(row['path']) and row['short_path_status']=='absent'
                and row['physical_identity'] is row['long_pin'] is row['selected_pin'] is None,'initially absent generated operand')
            q.exact_keys(row['ancestor'],['path','physical_identity'])
            q.require(Path(row['path']).is_relative_to(Path(row['ancestor']['path']))
                and Path(row['ancestor']['path']).is_relative_to(build)
                and native_path_identity(q,row['ancestor']['path'],True)==row['ancestor']['physical_identity'],'fixed generated ancestor')
            if Path(row['path']).exists():q.ordinary(row['path'],True)
    return value['operands']


def test_source_bindings(q,repo):
    names=q.source_test_roster(repo)
    q.require(len(names)==len(set(names)),'closed unique allocated source/reference paths')
    return [{'path':name,'bytes':q.file_pin(repo/name)['bytes'],'sha256':q.file_pin(repo/name)['sha256']} for name in names]


def publish_test_compile_plans(q,repo,deps,build,config,policy_sha,manifest_sha):
    policy,identity,path,prodpath=test_metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    policy['_operands']=test_operand_facts(q,policy,path,repo,deps,build)
    inputs=frozen_inputs(q,repo,deps,build,identity,prodpath)+[q.file_pin(path),q.file_pin(build/'local-players-test-witness/cmake-operand-facts.json'),q.file_pin(build/'local-players-test-witness/test-build-backend.py')]
    bindings=test_source_bindings(q,repo);inputs += [q.file_pin(repo/p['path']) for p in bindings]
    inputs=unique_pins(q,inputs)
    indexed=compile_rows(q,build/'compile_commands.json',build)
    plans=[];objects=[]
    for target in policy['targets']:
        for source in target['sources']:
            rows=[row for row in indexed.get(q.ordinary(source['path']),[]) if 'CMakeFiles/'+target['target']+'.dir/' in row[0]['output'].replace('\\','/')]
            q.require(len(rows)==1,'one original target/source/object compile metadata row')
            row,cwd,obj=rows[0];q.require(not obj.exists() and not obj.is_symlink(),'fresh unique test object')
            argv=expected_test_compile_argv(q,policy,target,source,row,cwd,obj)
            plan={'schema':'LocalPlayersInvocationPlan/v1','kind':'compile','source_root':str(repo),'build_root':str(build),'cwd':str(cwd),
                'argv':argv,'tools':[q.file_pin(argv[0])],'inputs':inputs,'outputs':[str(obj)]}
            pin=q.write_new(build/'local-players-test-witness/plans'/(target['target']+'-'+Path(source['path']).name+'.json'),q.json_bytes(plan))
            plans.append(pin);objects.append({'target':target['target'],'source':source['path'],'object':str(obj),'cwd':str(cwd),'plan':pin})
    q.require(len(plans)==16 and len({r['object'] for r in objects})==16,'exact sixteen unique actual test object plans')
    path=build/'local-players-test-witness/compile-index.json'
    q.write_new(path,q.json_bytes({'schema':'LocalPlayersCompilePlanIndex/v1','source_root':str(repo),'build_root':str(build),'entries':plans}))
    publish_digest(q,build/'local-players-test-witness/compile-index-digest.json',path)
    result={'schema':'LocalPlayersTestBuildInputs/v1','inputs':inputs,'objects':objects,'compile_index':q.file_pin(path),'test_source_bindings':bindings}
    q.write_new(build/'local-players-test-witness/build-inputs.json',q.json_bytes(result));return result


def verify_test_compiles(q,build,snapshot):
    root=q.ordinary(build/'local-players-test-witness/compile-receipts',True)
    runs=[p for p in root.iterdir() if p.name.startswith('invocation-')]
    selections=[p for p in root.iterdir() if p.name.startswith('compile-selection-')]
    q.require(len(runs)==len(selections)==16 and len(list(root.iterdir()))==32,'exact sixteen compiler/selection pairs')
    observed={}
    for run in runs:
        before,terminal=q.read_invocation(run)
        q.require(before['kind']=='compile' and len(terminal['outputs'])==1,'one actual test object')
        key=terminal['outputs'][0]['path'];q.require(key not in observed,'unique actual test object');observed[key]=run
    selected=[]
    for directory in selections:
        before,_=q.load_json(directory/'before.json');terminal,_=q.load_json(directory/'terminal.json')
        q.exact_keys(before,['schema','index','digest_file','selected_plan','argv','cwd','launcher'])
        q.exact_keys(terminal,['schema','before','selected_plan','exit_code','error','qualified_selection'])
        q.require(before['schema']=='LocalPlayersCompilePlanSelection/v1' and terminal['schema']=='LocalPlayersCompilePlanSelectionTerminal/v1'
            and terminal['before']==q.file_pin(directory/'before.json') and terminal['selected_plan']==before['selected_plan']
            and terminal['exit_code']==0 and type(terminal['exit_code']) is int and terminal['qualified_selection'] is True and terminal['error'] is None,'actual compile selection terminal')
        q.require(before['index']==snapshot['compile_index']==q.file_pin(before['index']['path'])
            and before['digest_file']==q.file_pin(build/'local-players-test-witness/compile-index-digest.json')
            and before['launcher']==q.file_pin(q.__file__) and before['selected_plan']==q.file_pin(before['selected_plan']['path']),'test compile selection authority')
        q.require(q.resolve_plan_digest(before['index']['path'],digest_file=before['digest_file']['path'])
            ==(before['index']['sha256'],before['digest_file']),'closed current test compile-index digest')
        plan,_=q.load_json(before['selected_plan']['path']);q.require(before['argv']==plan['argv'] and before['cwd']==plan['cwd'],'actual selection argv/cwd')
        selected.append(before['selected_plan']['path'])
    q.require(sorted(selected)==sorted(o['plan']['path'] for o in snapshot['objects']),'closed selected test plans')
    for row in snapshot['objects']:
        run=observed[row['object']];before,_=q.read_invocation(run)
        q.require(before['plan']==row['plan'],'exact independently written test plan')
        q.verify_cpp_compile(build/'compile_commands.json',run,q.ordinary(row['source']),q.ordinary(row['object']))
    return observed


def publish_test_link_plans(q,repo,deps,build,config,policy_sha,manifest_sha):
    policy,identity,path,prodpath=test_metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    policy['_operands']=test_operand_facts(q,policy,path,repo,deps,build)
    snapshot,_=q.load_json(build/'local-players-test-witness/build-inputs.json');observed=verify_test_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'prelink test input continuity')
    production,_,_=metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    prodsnap,_=q.load_json(build/'local-players-witness/build-inputs.json')
    production_archive_witnesses(q,production,prodsnap)
    sqlite=next(o for o in prodsnap['objects'] if o['target']=='flight_sqlite')
    archives={t['target']:q.ordinary(t['output']) for t in production['targets'] if t['target']!='flight_local_players_bridge'}
    q.sqlite_archive_witness(archives['flight_sqlite'],sqlite['object'])
    plans=[];rows=[]
    base_system={'kernel32.lib','user32.lib','gdi32.lib','winspool.lib','shell32.lib','ole32.lib','oleaut32.lib','uuid.lib','comdlg32.lib','advapi32.lib'}
    relative=lambda value:str(Path(os.path.abspath(value)).relative_to(build)).replace('/','\\')
    for target in policy['targets']:
        role=TEST_SOURCE_TARGETS[target['target']][0];link=target['link']
        objects=[o for o in snapshot['objects'] if o['target']==target['target']]
        parts,replies=file_api_test_link(q,build,config,target['target'],link['kind'])
        flags=[];libraries=[]
        for part,tokens in parts:
            if part=='flags':flags+=tokens
            elif part=='libraries':libraries+=tokens
            else:q.require(not tokens,'no unallocated link search path')
        expected_flags=link['global_flags']+link['configuration_flags']+link['console_options']+link['target_options']
        # CMake 3.31.8 GetTargetFlags emits executable language flags before
        # linker flags in FileAPI. Windows-MSVC's exact admitted link rule has
        # no <FLAGS> placeholder: validate this metadata, never pass it to link.
        fileapi_language_flags=[]
        if link['kind']=='EXECUTABLE':
            facts=policy['languages']['CXX']
            fileapi_language_flags=strings(q,facts['global_flags'])+strings(q,facts['configuration_flags'])
            fileapi_language_flags+=strings(q,facts['runtime_options'][target['msvc_runtime']])
            debug=target['debug_information_format']
            if debug:fileapi_language_flags+=strings(q,facts['debug_options'][debug])
        q.require(flags==fileapi_language_flags+expected_flags,
            'FileAPI resolved test language/link flags equal independent configuration arrays')
        required={archives['flight_local_players_core'],archives['flight_sqlite']}
        expected_system=set(base_system)
        if role!='codec':required.add(archives['flight_local_players_windows']);expected_system.add('bcrypt.lib')
        if role=='test_bridge':required.add(q.ordinary(production['godot_cpp_archive']))
        selected=[];system=[]
        for value in libraries:
            candidate=Path(os.path.abspath(build/value))
            if candidate in required:selected.append(candidate)
            else:
                q.require(Path(value).name==value and value.lower() in expected_system,'closed test archive/system library');system.append(value.lower())
        q.require(set(selected)==required and set(system)==expected_system
            and all(1<=selected.count(a)<=2 for a in required) and all(1<=system.count(a)<=2 for a in expected_system),'exact required test library closure')
        argv=[frozen_operand(q,policy,policy['linker'],False),'/nologo']+[relative(o['object']) for o in objects]
        argv+=['/out:'+relative(link['output']),'/implib:'+relative(link['import_library']),'/pdb:'+relative(link['link_pdb'])]
        if role=='test_bridge':argv+=['/dll']
        argv+=['/version:0.0']+link['language_flags']+expected_flags+libraries+link['supervisor_appended_options']
        q.require(len(' '.join(argv))<7000 and not any(v.startswith('@') for v in argv),'no unreviewed link response file')
        inputs=snapshot['inputs']+replies+[q.file_pin(o['object']) for o in objects]+[q.file_pin(a) for a in sorted(required)]
        for t in policy['targets']:
            if t['debug_information_format']:inputs.append(q.file_pin(t['compiler_pdb']))
        outputs=[link['output'],link['map']]
        if role=='test_bridge':outputs.append(link['import_library'])
        if config in ['Debug','RelWithDebInfo']:outputs.append(link['link_pdb'])
        outputs=[str(Path(os.path.abspath(p))) for p in outputs]
        for output in outputs:q.require(not Path(output).exists() and Path(output).is_relative_to(build),'fresh test link output')
        plan={'schema':'LocalPlayersInvocationPlan/v1','kind':'link','source_root':str(repo),'build_root':str(build),'cwd':str(build),
            'argv':argv,'tools':[q.file_pin(argv[0])],'inputs':unique_pins(q,inputs),'outputs':outputs}
        pin=q.write_new(build/'local-players-test-witness/plans'/(target['target']+'-link.json'),q.json_bytes(plan));plans.append(pin)
        rows.append({'target':target['target'],'plan':pin,'objects':objects,'replies':replies,'output':link['output'],'map':link['map']})
    index=build/'local-players-test-witness/link-index.json'
    q.write_new(index,q.json_bytes({'schema':'LocalPlayersLinkPlanIndex/v1','source_root':str(repo),'build_root':str(build),'entries':plans}))
    publish_digest(q,build/'local-players-test-witness/link-index-digest.json',index)
    q.write_new(build/'local-players-test-witness/prelink-admission.json',q.json_bytes({'schema':'LocalPlayersTestPrelinkAdmission/v1','rows':rows,'index':q.file_pin(index),'snapshot':q.file_pin(build/'local-players-test-witness/build-inputs.json')}))


def final_test_build_evidence(q,repo,deps,build,config,policy_sha,manifest_sha,crt_directory):
    policy,identity,path,prodpath=test_metadata(q,repo,deps,build,config,policy_sha,manifest_sha)
    snapshot,_=q.load_json(build/'local-players-test-witness/build-inputs.json');observed=verify_test_compiles(q,build,snapshot)
    for pin in snapshot['inputs']:q.require(q.file_pin(pin['path'])==pin,'postlink source/test policy continuity')
    prelink,_=q.load_json(build/'local-players-test-witness/prelink-admission.json')
    q.exact_keys(prelink,['schema','rows','index','snapshot'])
    q.require(prelink['schema']=='LocalPlayersTestPrelinkAdmission/v1' and prelink['snapshot']==q.file_pin(build/'local-players-test-witness/build-inputs.json')
        and prelink['index']==q.file_pin(build/'local-players-test-witness/link-index.json'),'test prelink binding')
    q.require([r['target'] for r in prelink['rows']]==list(TEST_SOURCE_TARGETS),'exact ordered prelink target roster')
    root=q.ordinary(build/'local-players-test-witness/link-receipts',True)
    runs=[p for p in root.iterdir() if p.name.startswith('invocation-')];selections=[p for p in root.iterdir() if p.name.startswith('link-selection-')]
    q.require(len(runs)==len(selections)==8 and len(list(root.iterdir()))==16,'eight actual inner-link/selection pairs')
    target_rows=[];used=set()
    for expected in prelink['rows']:
        candidates=[]
        for run in runs:
            before,terminal=q.read_invocation(run)
            if before['plan']==expected['plan']:candidates.append((run,before,terminal))
        q.require(len(candidates)==1,'one actual frozen inner-link per target')
        run,before,terminal=candidates[0];used.add(str(run))
        q.require(before['kind']=='link' and before['plan']==q.file_pin(expected['plan']['path'])
            and q.file_pin(expected['output']) in terminal['outputs'] and q.file_pin(expected['map']) in terminal['outputs'],'actual exact test binary/map output')
        for reply in expected['replies']:q.require(q.file_pin(reply['path'])==reply,'FileAPI input continuity')
        matches=[]
        for directory in selections:
            selected,_=q.load_json(directory/'before.json');ended,_=q.load_json(directory/'terminal.json')
            q.exact_keys(selected,['schema','index','digest_file','selected_plan','argv','cwd','launcher'])
            q.exact_keys(ended,['schema','before','selected_plan','exit_code','error','qualified_selection'])
            if selected['selected_plan']==expected['plan']:matches.append(directory)
            q.require(selected['schema']=='LocalPlayersLinkPlanSelection/v1' and ended['schema']=='LocalPlayersLinkPlanSelectionTerminal/v1'
                and ended['before']==q.file_pin(directory/'before.json') and ended['selected_plan']==selected['selected_plan']
                and type(ended['exit_code']) is int and ended['exit_code']==0 and ended['qualified_selection'] is True and ended['error'] is None,'actual link selection terminal')
            q.require(selected['index']==prelink['index'] and selected['digest_file']==q.file_pin(build/'local-players-test-witness/link-index-digest.json')
                and selected['index']==q.file_pin(selected['index']['path']) and selected['selected_plan']==q.file_pin(selected['selected_plan']['path'])
                and selected['launcher']==q.file_pin(q.__file__),'frozen actual link index authority')
            q.require(q.resolve_plan_digest(selected['index']['path'],digest_file=selected['digest_file']['path'])
                ==(selected['index']['sha256'],selected['digest_file']),'closed current test link-index digest')
            plan,_=q.load_json(selected['selected_plan']['path']);q.require(selected['argv']==plan['argv'] and selected['cwd']==plan['cwd'],'exact planned link selection argv')
        q.require(len(matches)==1,'unique target link selection')
        objects=[{'source':q.file_pin(o['source']),'object':q.file_pin(o['object']),'invocation':str(observed[o['object']])} for o in expected['objects']]
        target_rows.append({'role':TEST_SOURCE_TARGETS[expected['target']][0],'target':expected['target'],'output':q.file_pin(expected['output']),'objects':objects,'link_invocation':str(run)})
    q.require(len(used)==8,'no inner-link reuse')
    crt_directory=q.ordinary(crt_directory,True)
    crt=[q.file_pin(crt_directory/name) for name in ['MSVCP140.dll','MSVCP140_2.dll','MSVCP140_ATOMIC_WAIT.dll','VCRUNTIME140.dll','VCRUNTIME140_1.dll']]
    bindings=test_source_bindings(q,repo);q.require(bindings==snapshot['test_source_bindings'],'all test/reference raw bytes unchanged')
    refs=[row for row in bindings if any('/'+name+'/' in row['path'] for name in ['reference','service_reference','full_record_reference','reservation_reference'])]
    q.require(len(refs)==17,'all original/service/full/reservation reference transport files')
    result={'schema':'LocalPlayersTestCompiledBuildEvidence/v1','source_root':str(repo),'dependency_root':str(deps),'build_root':str(build),
        'source_identity':q.file_pin(build/'local-players-identity/local-players-source-identity.json'),'configuration_cache':q.file_pin(build/'CMakeCache.txt'),
        'production_build':q.file_pin(build/'local-players-witness/compiled-build-evidence.json'),'compile_database':q.file_pin(build/'compile_commands.json'),
        'test_source_bindings':bindings,'reference_bindings':refs,'targets':target_rows,'crt':crt,'ctest_source':q.file_pin(repo/'tests/persistence/local_players/CMakeLists.txt'),
        'scope':'Actual single-configure ON source/strict production9+test16 object/archive/header/inner-link closure only. No native, SQLite storage, CTest, Godot, capability or issue219 acceptance.'}
    output=build/'local-players-test-witness/test-compiled-build-evidence.json'
    q.write_new(output,q.json_bytes(result));q.admit_test_build(output,q.file_pin(output)['sha256']);q.module_crt_closure(result)


def unique_pins(q,pins):
    result=[];seen={}
    for pin in pins:
        q.exact_keys(pin,['path','bytes','sha256'])
        if pin['path'] in seen:q.require(seen[pin['path']]==pin,'same-path raw pin agreement')
        else:seen[pin['path']]=pin;result.append(pin)
    return result


def test_backend_main():
    import sys
    mode,repo,deps,build,config,qualifier_sha,policy_sha,manifest_sha=sys.argv[1:9]
    repo,deps,build=map(lambda p:Path(os.path.abspath(p)),[repo,deps,build])
    q=reviewed_qualifier(repo,qualifier_sha)
    methods={'test-operands':publish_test_operand_facts,'test-compile-plans':publish_test_compile_plans,
        'test-link-plans':publish_test_link_plans,'test-aggregate':final_test_build_evidence}
    q.require(mode in methods,'closed test-build backend mode')
    args=[q,repo,deps,build,config,policy_sha,manifest_sha]
    if mode=='test-aggregate':args.append(sys.argv[9])
    methods[mode](*args)
    q.require(q.file_pin(repo/'tools/local-players/qualify.py')['sha256']==qualifier_sha,'final test qualifier continuity')

import sys
if sys.argv[1].startswith('test-'): test_backend_main()
else: build_backend_main()

'@

if ($Stage -ceq 'BuildTests') {
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'Build requires Windows and PowerShell 7 literal ArgumentList supervision' }
    foreach ($value in @($RepositoryRoot,$DependencyRoot,$BuildRoot,$PythonExecutable,$CmakeExecutable,$NinjaExecutable,$CCompilerExecutable,$CxxCompilerExecutable)) {
        if (-not $value -or -not [IO.Path]::IsPathRooted($value) -or $value -match '[;\r\n"<>]' -or $value.Contains([char]0)) { throw 'Explicit literal absolute Build paths required' }
    }
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $DependencyRoot = [IO.Path]::GetFullPath($DependencyRoot)
    $BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
    Assert-OrdinaryPath $RepositoryRoot $true
    Assert-OrdinaryPath $DependencyRoot $true
    Assert-OrdinaryPath ([IO.Path]::GetDirectoryName($BuildRoot)) $true
    $comparison = [StringComparison]::OrdinalIgnoreCase
    if ([string]::Equals($BuildRoot,$RepositoryRoot,$comparison) -or
        [string]::Equals($BuildRoot,$DependencyRoot,$comparison) -or
        $BuildRoot.StartsWith($DependencyRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison) -or
        $RepositoryRoot.StartsWith($BuildRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison) -or
        $DependencyRoot.StartsWith($BuildRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison)) {
        throw 'Build must be disjoint from dependencies and cannot contain source/dependencies'
    }
    if (Test-Path -LiteralPath $BuildRoot) { throw 'Build root must be absent; retain earlier attempts' }
    if (-not $QualifierSha256 -or -not $CmakeSha256 -or -not $NinjaSha256 -or -not $CCompilerSha256 -or -not $CxxCompilerSha256) {
        throw 'Explicit reviewed Build tool hashes required'
    }
    foreach ($value in @($ProofParent,$ExecutionAuthorization,$CrtDirectory)) {
        if (-not $value -or -not [IO.Path]::IsPathRooted($value) -or $value -match '[;\r\n"<>]' -or $value.Contains([char]0)) {
            throw 'Explicit literal absolute test-build proof, future authorization and CRT paths required'
        }
    }
    $ProofParent=[IO.Path]::GetFullPath($ProofParent)
    $ExecutionAuthorization=[IO.Path]::GetFullPath($ExecutionAuthorization)
    $CrtDirectory=[IO.Path]::GetFullPath($CrtDirectory)
    Assert-OrdinaryPath $ProofParent $true
    Assert-OrdinaryPath ([IO.Path]::GetDirectoryName($ExecutionAuthorization)) $true
    Assert-OrdinaryPath $CrtDirectory $true
    if (Test-Path -LiteralPath $ExecutionAuthorization) { throw 'Future native authorization output must be absent; BuildTests does not authorize or execute native tests' }
    $qualifier = Join-Path $RepositoryRoot 'tools/local-players/qualify.py'
    $runnerPin = Get-RootFilePin $PSCommandPath
    $toolPairs = @(@($PythonExecutable,$PythonSha256),@($CmakeExecutable,$CmakeSha256),@($NinjaExecutable,$NinjaSha256),
                   @($CCompilerExecutable,$CCompilerSha256),@($CxxCompilerExecutable,$CxxCompilerSha256),@($qualifier,$QualifierSha256))
    foreach ($pair in $toolPairs) {
        if ((Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'A declared Build tool differs from reviewed bytes' }
    }
    # Developer environment supplies INCLUDE/LIB/SDK paths. Effective options
    # and CMake generator/toolchain injection are not inherited as overrides.
    foreach ($name in @('CL','_CL_','LINK','_LINK_','CFLAGS','CXXFLAGS','LDFLAGS','CMAKE_TOOLCHAIN_FILE','CMAKE_GENERATOR','CMAKE_GENERATOR_PLATFORM','CMAKE_GENERATOR_TOOLSET')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) { throw ('Unreviewed effective option environment: '+$name) }
    }
    New-Item -ItemType Directory -Path $BuildRoot -ErrorAction Stop | Out-Null
    $witness = Join-Path $BuildRoot 'local-players-witness'
    foreach ($relative in @('local-players-witness','local-players-witness/plans','local-players-witness/compile-receipts',
                            'local-players-witness/link-receipts','local-players-witness/processes','local-players-test-witness','local-players-test-witness/plans','local-players-test-witness/compile-receipts','local-players-test-witness/link-receipts','.cmake/api/v1/query/client-flight-local-players')) {
        New-Item -ItemType Directory -Path (Join-Path $BuildRoot $relative) -ErrorAction Stop | Out-Null
        Assert-OrdinaryPath (Join-Path $BuildRoot $relative) $true
    }
    $processes=Join-Path $witness 'processes'
    Write-RootJsonNew (Join-Path $BuildRoot '.cmake/api/v1/query/client-flight-local-players/query.json') ([ordered]@{requests=@([ordered]@{kind='codemodel';version=2})})
    $backendPath=Join-Path $witness 'build-backend.py'
    Write-RootTextNew $backendPath $testBuildBackend
    $rootInputs=[ordered]@{schema='LocalPlayersRootBuildInputs/v1'; runner=$runnerPin; tools=@($toolPairs | ForEach-Object {Get-RootFilePin $_[0]});backend=Get-RootFilePin $backendPath}
    Write-RootJsonNew (Join-Path $witness 'root-inputs.json') $rootInputs
    $configureArgs=@('-S',$RepositoryRoot,'-B',$BuildRoot,'-G','Ninja',('-DCMAKE_MAKE_PROGRAM='+$NinjaExecutable),
        ('-DCMAKE_C_COMPILER='+$CCompilerExecutable),('-DCMAKE_CXX_COMPILER='+$CxxCompilerExecutable),
        ('-DPython3_EXECUTABLE='+$PythonExecutable),('-DCMAKE_BUILD_TYPE='+$Configuration),
        ('-DFLIGHT_DEPENDENCY_ROOT='+$DependencyRoot),'-DCMAKE_EXPORT_COMPILE_COMMANDS=ON','-DBUILD_TESTING=ON',
        '-DFLIGHT_JSBSIM_VARIANT=upstream','-DFLIGHT_BUILD_LOCAL_PLAYERS=ON','-DFLIGHT_BUILD_GODOT_BINDINGS=ON',
        '-DFLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE=ON','-DFLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE=windows',
        ('-DFLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE='+$PythonExecutable),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_INDEX='+(Join-Path $witness 'compile-index.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_INDEX_DIGEST_FILE='+(Join-Path $witness 'compile-index-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_RECEIPTS='+(Join-Path $witness 'compile-receipts')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_PLAN='+(Join-Path $witness 'link-plan.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_PLAN_DIGEST_FILE='+(Join-Path $witness 'link-plan-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_RECEIPTS='+(Join-Path $witness 'link-receipts')))
    $testWitness=Join-Path $BuildRoot 'local-players-test-witness'
    $testBackendPath=Join-Path $testWitness 'test-build-backend.py'
    Write-RootTextNew $testBackendPath $testBuildBackend
    $configureArgs+=@(
        ('-DFLIGHT_LOCAL_PLAYERS_PROOF_PARENT='+$ProofParent),
        ('-DFLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION='+$ExecutionAuthorization),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY='+(Join-Path $BuildRoot 'local-players-bridge-package')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX='+(Join-Path $testWitness 'compile-index.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX_DIGEST_FILE='+(Join-Path $testWitness 'compile-index-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_COMPILE_RECEIPTS='+(Join-Path $testWitness 'compile-receipts')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX='+(Join-Path $testWitness 'link-index.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX_DIGEST_FILE='+(Join-Path $testWitness 'link-index-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_TEST_LINK_RECEIPTS='+(Join-Path $testWitness 'link-receipts')))
    $null=Invoke-RootObservedProcess configure $CmakeExecutable $CmakeSha256 $configureArgs $RepositoryRoot $processes $BuildTimeoutSeconds
    # Freeze CMake existing-path conversions before dependency generation can
    # create include directories that were absent during configure/generation.
    $policySha=(Get-RootFilePin (Join-Path $BuildRoot ('local-players-compile-policy-'+$Configuration+'.json'))).sha256
    $operandArgs=@('-I','-B',$backendPath,'operand-facts',$RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$QualifierSha256,$policySha,'not-created')
    $null=Invoke-RootObservedProcess publish-operand-facts $PythonExecutable $PythonSha256 $operandArgs $RepositoryRoot $processes 120
    $controls=Join-Path $BuildRoot ('local-players-configure-controls-'+$Configuration+'.json')
    $controlsSha=(Get-RootFilePin $controls).sha256
    $null=Invoke-RootObservedProcess publish-identity-plan $PythonExecutable $PythonSha256 @('-I','-B','-c',$publish,$RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$controlsSha) $RepositoryRoot $processes 120
    $identityTool=Join-Path $RepositoryRoot 'tools/local-players/source-identity.py'
    if ((Get-RootFilePin $identityTool).sha256 -cne '23b4494799d795b77bede1c0b4b4cf43421f5b592b312f1f8f60c3a0dd2965a3') { throw 'Reviewed identity producer changed' }
    $null=Invoke-RootObservedProcess publish-identity $PythonExecutable $PythonSha256 @('-I','-B',$identityTool,'--repo-root',$RepositoryRoot,'--dependency-root',$DependencyRoot,'--build-plan',(Join-Path $BuildRoot 'local-players-precompile-plan.json'),'--output-root',(Join-Path $BuildRoot 'local-players-identity')) $RepositoryRoot $processes 120
    $manifest=Join-Path $BuildRoot 'local-players-identity/local-players-source-identity.json'
    $manifestSha=(Get-RootFilePin $manifest).sha256
    $headerDirectory=Join-Path $BuildRoot 'local-players-generated'
    if (Test-Path -LiteralPath $headerDirectory) { throw 'Generated header parent unexpectedly exists' }
    New-Item -ItemType Directory -Path $headerDirectory -ErrorAction Stop | Out-Null
    $null=Invoke-RootObservedProcess publish-header $PythonExecutable $PythonSha256 @('-I','-B',$qualifier,'emit-header','--identity-manifest',$manifest,'--identity-manifest-sha256',$manifestSha,'--output',(Join-Path $headerDirectory 'compiled_identity.hpp')) $RepositoryRoot $processes 120
    $commonBackend=@($RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$QualifierSha256,$policySha,$manifestSha)
    $null=Invoke-RootObservedProcess publish-test-operand-facts $PythonExecutable $PythonSha256 (@('-I','-B',$testBackendPath,'test-operands')+$commonBackend) $RepositoryRoot $processes 120
    # Generate and compile only the binding dependency; none of the nine storage
    # objects can run before their independently written plans exist.
    $null=Invoke-RootObservedProcess build-godot-cpp $CmakeExecutable $CmakeSha256 @('--build',$BuildRoot,'--target','godot-cpp','--parallel',([string]$Parallel)) $RepositoryRoot $processes $BuildTimeoutSeconds
    $policySha=(Get-RootFilePin (Join-Path $BuildRoot ('local-players-compile-policy-'+$Configuration+'.json'))).sha256
    $commonBackend=@($RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$QualifierSha256,$policySha,$manifestSha)
    $null=Invoke-RootObservedProcess publish-compile-plans $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'compile-plans')+$commonBackend) $RepositoryRoot $processes 120
    $snapshot=Get-Content -LiteralPath (Join-Path $witness 'build-inputs.json') -Raw | ConvertFrom-Json
    $bridgeObjects=@($snapshot.objects | Where-Object {$_.target -ceq 'flight_local_players_bridge'})
    if ($bridgeObjects.Count -ne 2) { throw 'Closed two bridge object targets required' }
    $objectTargets=@($bridgeObjects | ForEach-Object {[IO.Path]::GetRelativePath($BuildRoot,$_.object).Replace('\','/')})
    if (@($objectTargets | Where-Object {$_ -match '^\.\.' -or [IO.Path]::IsPathRooted($_)}).Count -ne 0) { throw 'Object target escaped build' }
    $null=Invoke-RootObservedProcess build-storage-objects $CmakeExecutable $CmakeSha256 (@('--build',$BuildRoot,'--target','flight_sqlite','flight_local_players_core','flight_local_players_windows')+$objectTargets+@('--parallel',([string]$Parallel))) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess publish-link-plan $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'link-plan')+$commonBackend) $RepositoryRoot $processes 120
    $null=Invoke-RootObservedProcess build-storage-dll $CmakeExecutable $CmakeSha256 @('--build',$BuildRoot,'--target','flight_local_players_bridge','--parallel',([string]$Parallel)) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess aggregate-build $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'aggregate')+$commonBackend) $RepositoryRoot $processes 120
    $null=Invoke-RootObservedProcess publish-test-compile-plans $PythonExecutable $PythonSha256 (@('-I','-B',$testBackendPath,'test-compile-plans')+$commonBackend) $RepositoryRoot $processes 120
    $testSnapshot=Get-Content -LiteralPath (Join-Path $testWitness 'build-inputs.json') -Raw | ConvertFrom-Json
    if (@($testSnapshot.objects).Count -ne 16) { throw 'Closed sixteen test object targets required' }
    $testObjectTargets=@($testSnapshot.objects | ForEach-Object {[IO.Path]::GetRelativePath($BuildRoot,$_.object).Replace('\','/')})
    if (@($testObjectTargets | Where-Object {$_ -match '^\.\.' -or [IO.Path]::IsPathRooted($_)}).Count -ne 0 -or @($testObjectTargets | Select-Object -Unique).Count -ne 16) { throw 'Test object target roster escaped or repeated' }
    $null=Invoke-RootObservedProcess build-test-objects $CmakeExecutable $CmakeSha256 (@('--build',$BuildRoot,'--target')+$testObjectTargets+@('--parallel',([string]$Parallel))) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess publish-test-link-plans $PythonExecutable $PythonSha256 (@('-I','-B',$testBackendPath,'test-link-plans')+$commonBackend) $RepositoryRoot $processes 120
    $testTargetNames=@('local_players_codec_native','local_players_store_native','local_players_service_native','local_players_windows_native','local_players_crash_native','local_players_crash_actor','local_players_lock_actor','flight_local_players_test_bridge')
    $null=Invoke-RootObservedProcess build-test-links $CmakeExecutable $CmakeSha256 (@('--build',$BuildRoot,'--target')+$testTargetNames+@('--parallel',([string]$Parallel))) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess aggregate-test-build $PythonExecutable $PythonSha256 (@('-I','-B',$testBackendPath,'test-aggregate')+$commonBackend+@($CrtDirectory)) $RepositoryRoot $processes 120
    foreach ($pair in $toolPairs) { if ((Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'Build tool changed before final receipt' } }
    if ((Get-RootFilePin $PSCommandPath).sha256 -cne $runnerPin.sha256) { throw 'Build runner changed' }
    $processPins=@(Get-ChildItem -LiteralPath $processes -Directory | Sort-Object Name | ForEach-Object {Get-RootFilePin (Join-Path $_.FullName 'terminal.json')})
    $expectedStages=@('configure','publish-operand-facts','publish-identity-plan','publish-identity','publish-header',
        'publish-test-operand-facts','build-godot-cpp','publish-compile-plans','build-storage-objects','publish-link-plan',
        'build-storage-dll','aggregate-build','publish-test-compile-plans','build-test-objects','publish-test-link-plans','build-test-links','aggregate-test-build')
    $actualStages=@(Get-ChildItem -LiteralPath $processes -Directory | ForEach-Object {$_.Name} | Sort-Object)
    if ($actualStages.Count -ne 17 -or [string]::Join('|',$actualStages) -cne [string]::Join('|',@($expectedStages | Sort-Object))) { throw 'Exact seventeen observed test-build stages required' }
    foreach ($processPin in $processPins) {
        $terminal=Get-Content -LiteralPath $processPin.path -Raw | ConvertFrom-Json
        if ($terminal.qualified_process -ne $true -or $terminal.exit_observed -ne $true -or $terminal.drained -ne $true -or $terminal.timed_out -ne $false -or $terminal.exit_code -ne 0 -or $null -ne $terminal.error) { throw 'Every actual test-build stage must have an observed successful terminal' }
    }
    Write-RootJsonNew (Join-Path $testWitness 'build-receipt.json') ([ordered]@{schema='LocalPlayersRootTestBuildReceipt/v1';compiled_not_tested=$true;
        source_identity=Get-RootFilePin $manifest;compiled_evidence=Get-RootFilePin (Join-Path $witness 'compiled-build-evidence.json');
        test_compiled_evidence=Get-RootFilePin (Join-Path $testWitness 'test-compiled-build-evidence.json'); test_backend=Get-RootFilePin $testBackendPath;
        root_inputs=Get-RootFilePin (Join-Path $witness 'root-inputs.json');processes=$processPins;
        native_checks_executed=$false;bridge_checks_executed=$false;build_testing=$true;
        scope='Fresh ON single-configure production and eight test-target compile/link evidence only. No CTest, Godot/actor/DB execution or issue219 acceptance.'})
    Write-Output 'LOCAL PLAYERS TEST_COMPILED_NOT_TESTED: production9 and test16 actual planned compiles/eight test inner links; native and bridge execution remain separate.'
    return
}

if ($Stage -ceq 'Build') {
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'Build requires Windows and PowerShell 7 literal ArgumentList supervision' }
    foreach ($value in @($RepositoryRoot,$DependencyRoot,$BuildRoot,$PythonExecutable,$CmakeExecutable,$NinjaExecutable,$CCompilerExecutable,$CxxCompilerExecutable)) {
        if (-not $value -or -not [IO.Path]::IsPathRooted($value) -or $value -match '[;\r\n"<>]' -or $value.Contains([char]0)) { throw 'Explicit literal absolute Build paths required' }
    }
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $DependencyRoot = [IO.Path]::GetFullPath($DependencyRoot)
    $BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
    Assert-OrdinaryPath $RepositoryRoot $true
    Assert-OrdinaryPath $DependencyRoot $true
    Assert-OrdinaryPath ([IO.Path]::GetDirectoryName($BuildRoot)) $true
    $comparison = [StringComparison]::OrdinalIgnoreCase
    if ([string]::Equals($BuildRoot,$RepositoryRoot,$comparison) -or
        [string]::Equals($BuildRoot,$DependencyRoot,$comparison) -or
        $BuildRoot.StartsWith($DependencyRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison) -or
        $RepositoryRoot.StartsWith($BuildRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison) -or
        $DependencyRoot.StartsWith($BuildRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,$comparison)) {
        throw 'Build must be disjoint from dependencies and cannot contain source/dependencies'
    }
    if (Test-Path -LiteralPath $BuildRoot) { throw 'Build root must be absent; retain earlier attempts' }
    if (-not $QualifierSha256 -or -not $CmakeSha256 -or -not $NinjaSha256 -or -not $CCompilerSha256 -or -not $CxxCompilerSha256) {
        throw 'Explicit reviewed Build tool hashes required'
    }
    $qualifier = Join-Path $RepositoryRoot 'tools/local-players/qualify.py'
    $runnerPin = Get-RootFilePin $PSCommandPath
    $toolPairs = @(@($PythonExecutable,$PythonSha256),@($CmakeExecutable,$CmakeSha256),@($NinjaExecutable,$NinjaSha256),
                   @($CCompilerExecutable,$CCompilerSha256),@($CxxCompilerExecutable,$CxxCompilerSha256),@($qualifier,$QualifierSha256))
    foreach ($pair in $toolPairs) {
        if ((Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'A declared Build tool differs from reviewed bytes' }
    }
    # Developer environment supplies INCLUDE/LIB/SDK paths. Effective options
    # and CMake generator/toolchain injection are not inherited as overrides.
    foreach ($name in @('CL','_CL_','LINK','_LINK_','CFLAGS','CXXFLAGS','LDFLAGS','CMAKE_TOOLCHAIN_FILE','CMAKE_GENERATOR','CMAKE_GENERATOR_PLATFORM','CMAKE_GENERATOR_TOOLSET')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) { throw ('Unreviewed effective option environment: '+$name) }
    }
    New-Item -ItemType Directory -Path $BuildRoot -ErrorAction Stop | Out-Null
    $witness = Join-Path $BuildRoot 'local-players-witness'
    foreach ($relative in @('local-players-witness','local-players-witness/plans','local-players-witness/compile-receipts',
                            'local-players-witness/link-receipts','local-players-witness/processes','.cmake/api/v1/query/client-flight-local-players')) {
        New-Item -ItemType Directory -Path (Join-Path $BuildRoot $relative) -ErrorAction Stop | Out-Null
        Assert-OrdinaryPath (Join-Path $BuildRoot $relative) $true
    }
    $processes=Join-Path $witness 'processes'
    Write-RootJsonNew (Join-Path $BuildRoot '.cmake/api/v1/query/client-flight-local-players/query.json') ([ordered]@{requests=@([ordered]@{kind='codemodel';version=2})})
    $backendPath=Join-Path $witness 'build-backend.py'
    Write-RootTextNew $backendPath $buildBackend
    $rootInputs=[ordered]@{schema='LocalPlayersRootBuildInputs/v1'; runner=$runnerPin; tools=@($toolPairs | ForEach-Object {Get-RootFilePin $_[0]});backend=Get-RootFilePin $backendPath}
    Write-RootJsonNew (Join-Path $witness 'root-inputs.json') $rootInputs
    $configureArgs=@('-S',$RepositoryRoot,'-B',$BuildRoot,'-G','Ninja',('-DCMAKE_MAKE_PROGRAM='+$NinjaExecutable),
        ('-DCMAKE_C_COMPILER='+$CCompilerExecutable),('-DCMAKE_CXX_COMPILER='+$CxxCompilerExecutable),
        ('-DPython3_EXECUTABLE='+$PythonExecutable),('-DCMAKE_BUILD_TYPE='+$Configuration),
        ('-DFLIGHT_DEPENDENCY_ROOT='+$DependencyRoot),'-DCMAKE_EXPORT_COMPILE_COMMANDS=ON','-DBUILD_TESTING=OFF',
        '-DFLIGHT_JSBSIM_VARIANT=upstream','-DFLIGHT_BUILD_LOCAL_PLAYERS=ON','-DFLIGHT_BUILD_GODOT_BINDINGS=ON',
        '-DFLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE=OFF','-DFLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE=off',
        ('-DFLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE='+$PythonExecutable),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_INDEX='+(Join-Path $witness 'compile-index.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_INDEX_DIGEST_FILE='+(Join-Path $witness 'compile-index-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_COMPILE_RECEIPTS='+(Join-Path $witness 'compile-receipts')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_PLAN='+(Join-Path $witness 'link-plan.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_PLAN_DIGEST_FILE='+(Join-Path $witness 'link-plan-digest.json')),
        ('-DFLIGHT_LOCAL_PLAYERS_LINK_RECEIPTS='+(Join-Path $witness 'link-receipts')))
    $null=Invoke-RootObservedProcess configure $CmakeExecutable $CmakeSha256 $configureArgs $RepositoryRoot $processes $BuildTimeoutSeconds
    # Freeze CMake existing-path conversions before dependency generation can
    # create include directories that were absent during configure/generation.
    $policySha=(Get-RootFilePin (Join-Path $BuildRoot ('local-players-compile-policy-'+$Configuration+'.json'))).sha256
    $operandArgs=@('-I','-B',$backendPath,'operand-facts',$RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$QualifierSha256,$policySha,'not-created')
    $null=Invoke-RootObservedProcess publish-operand-facts $PythonExecutable $PythonSha256 $operandArgs $RepositoryRoot $processes 120
    $controls=Join-Path $BuildRoot ('local-players-configure-controls-'+$Configuration+'.json')
    $controlsSha=(Get-RootFilePin $controls).sha256
    $null=Invoke-RootObservedProcess publish-identity-plan $PythonExecutable $PythonSha256 @('-I','-B','-c',$publish,$RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$controlsSha) $RepositoryRoot $processes 120
    $identityTool=Join-Path $RepositoryRoot 'tools/local-players/source-identity.py'
    if ((Get-RootFilePin $identityTool).sha256 -cne '23b4494799d795b77bede1c0b4b4cf43421f5b592b312f1f8f60c3a0dd2965a3') { throw 'Reviewed identity producer changed' }
    $null=Invoke-RootObservedProcess publish-identity $PythonExecutable $PythonSha256 @('-I','-B',$identityTool,'--repo-root',$RepositoryRoot,'--dependency-root',$DependencyRoot,'--build-plan',(Join-Path $BuildRoot 'local-players-precompile-plan.json'),'--output-root',(Join-Path $BuildRoot 'local-players-identity')) $RepositoryRoot $processes 120
    $manifest=Join-Path $BuildRoot 'local-players-identity/local-players-source-identity.json'
    $manifestSha=(Get-RootFilePin $manifest).sha256
    $headerDirectory=Join-Path $BuildRoot 'local-players-generated'
    if (Test-Path -LiteralPath $headerDirectory) { throw 'Generated header parent unexpectedly exists' }
    New-Item -ItemType Directory -Path $headerDirectory -ErrorAction Stop | Out-Null
    $null=Invoke-RootObservedProcess publish-header $PythonExecutable $PythonSha256 @('-I','-B',$qualifier,'emit-header','--identity-manifest',$manifest,'--identity-manifest-sha256',$manifestSha,'--output',(Join-Path $headerDirectory 'compiled_identity.hpp')) $RepositoryRoot $processes 120
    # Generate and compile only the binding dependency; none of the nine storage
    # objects can run before their independently written plans exist.
    $null=Invoke-RootObservedProcess build-godot-cpp $CmakeExecutable $CmakeSha256 @('--build',$BuildRoot,'--target','godot-cpp','--parallel',([string]$Parallel)) $RepositoryRoot $processes $BuildTimeoutSeconds
    $policySha=(Get-RootFilePin (Join-Path $BuildRoot ('local-players-compile-policy-'+$Configuration+'.json'))).sha256
    $commonBackend=@($RepositoryRoot,$DependencyRoot,$BuildRoot,$Configuration,$QualifierSha256,$policySha,$manifestSha)
    $null=Invoke-RootObservedProcess publish-compile-plans $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'compile-plans')+$commonBackend) $RepositoryRoot $processes 120
    $snapshot=Get-Content -LiteralPath (Join-Path $witness 'build-inputs.json') -Raw | ConvertFrom-Json
    $bridgeObjects=@($snapshot.objects | Where-Object {$_.target -ceq 'flight_local_players_bridge'})
    if ($bridgeObjects.Count -ne 2) { throw 'Closed two bridge object targets required' }
    $objectTargets=@($bridgeObjects | ForEach-Object {[IO.Path]::GetRelativePath($BuildRoot,$_.object).Replace('\','/')})
    if (@($objectTargets | Where-Object {$_ -match '^\.\.' -or [IO.Path]::IsPathRooted($_)}).Count -ne 0) { throw 'Object target escaped build' }
    $null=Invoke-RootObservedProcess build-storage-objects $CmakeExecutable $CmakeSha256 (@('--build',$BuildRoot,'--target','flight_sqlite','flight_local_players_core','flight_local_players_windows')+$objectTargets+@('--parallel',([string]$Parallel))) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess publish-link-plan $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'link-plan')+$commonBackend) $RepositoryRoot $processes 120
    $null=Invoke-RootObservedProcess build-storage-dll $CmakeExecutable $CmakeSha256 @('--build',$BuildRoot,'--target','flight_local_players_bridge','--parallel',([string]$Parallel)) $RepositoryRoot $processes $BuildTimeoutSeconds
    $null=Invoke-RootObservedProcess aggregate-build $PythonExecutable $PythonSha256 (@('-I','-B',$backendPath,'aggregate')+$commonBackend) $RepositoryRoot $processes 120
    foreach ($pair in $toolPairs) { if ((Get-RootFilePin $pair[0]).sha256 -cne $pair[1]) { throw 'Build tool changed before final receipt' } }
    if ((Get-RootFilePin $PSCommandPath).sha256 -cne $runnerPin.sha256) { throw 'Build runner changed' }
    $processPins=@(Get-ChildItem -LiteralPath $processes -Directory | Sort-Object Name | ForEach-Object {Get-RootFilePin (Join-Path $_.FullName 'terminal.json')})
    if ($processPins.Count -ne 11) { throw 'Exact eleven observed Root stages required' }
    Write-RootJsonNew (Join-Path $witness 'build-receipt.json') ([ordered]@{schema='LocalPlayersRootBuildReceipt/v1';compiled_not_tested=$true;
        source_identity=Get-RootFilePin $manifest;compiled_evidence=Get-RootFilePin (Join-Path $witness 'compiled-build-evidence.json');
        root_inputs=Get-RootFilePin (Join-Path $witness 'root-inputs.json');processes=$processPins;
        native_checks_executed=$false;bridge_checks_executed=$false;build_testing=$false;
        scope='Windows production component Build only. No CTest, Godot/actor/DB execution or issue219 acceptance.'})
    Write-Output 'LOCAL PLAYERS COMPILED_NOT_TESTED: exact nine compiler/header/archive/inner-link witnesses; native and bridge qualification remain unavailable.'
    return
}

Assert-OrdinaryPath $PythonExecutable $false
if (-not [IO.Path]::IsPathRooted($PythonExecutable)) { throw "Explicit absolute pinned Python required" }
if (-not (Test-Path -LiteralPath $PythonExecutable -PathType Leaf)) { throw "Pinned Python is missing" }
if ((Get-FileHash -LiteralPath $PythonExecutable -Algorithm SHA256).Hash.ToLowerInvariant() -cne $PythonSha256) {
    throw "Pinned Python bytes changed"
}
if ($Stage -ceq "PrepareHeader") {
    if (-not $QualifierSha256 -or -not $IdentityManifestSha256) { throw "Header publication requires explicit reviewed qualifier and identity-manifest hashes" }
    foreach ($declaredDirectory in @($RepositoryRoot, $DependencyRoot, $BuildRoot)) {
        Assert-OrdinaryPath $declaredDirectory $true
    }
    $qualifier = Join-Path $RepositoryRoot "tools/local-players/qualify.py"
    $manifest = Join-Path $BuildRoot "local-players-identity/local-players-source-identity.json"
    Assert-OrdinaryPath $qualifier $false
    Assert-OrdinaryPath $manifest $false
    if ((Get-FileHash -LiteralPath $qualifier -Algorithm SHA256).Hash.ToLowerInvariant() -cne $QualifierSha256) { throw "Reviewed qualifier bytes changed" }
    if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $IdentityManifestSha256) { throw "Admitted source manifest bytes changed" }
    # The qualifier independently rejects duplicate keys, reconstructs all17/15/11
    # recipes, pins current source/dependencies, and binds the exact .gd sibling.
    $declaredManifest = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($declaredManifest.schema -cne "LocalPlayersPrecompileSourceIdentity/v1" -or
        $declaredManifest.compiled_build_scalars.configuration -cne $Configuration) { throw "Manifest schema/configuration mismatch" }
    $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    foreach ($rootPair in @(@($RepositoryRoot, $declaredManifest.source_root), @($DependencyRoot, $declaredManifest.dependency_root), @($BuildRoot, $declaredManifest.build_root))) {
        if (-not [string]::Equals([IO.Path]::GetFullPath($rootPair[0]), [IO.Path]::GetFullPath($rootPair[1]), $pathComparison)) {
            throw "Manifest does not bind the Root-declared source/dependency/build tree"
        }
    }
    $headerDirectory = Join-Path $BuildRoot "local-players-generated"
    if (Test-Path -LiteralPath $headerDirectory) { throw "Generated header directory must be fresh; retain prior attempt" }
    New-Item -ItemType Directory -Path $headerDirectory -ErrorAction Stop | Out-Null
    Assert-OrdinaryPath $headerDirectory $true
    & $PythonExecutable -I -B $qualifier emit-header --identity-manifest $manifest `
        --identity-manifest-sha256 $IdentityManifestSha256 --output (Join-Path $headerDirectory "compiled_identity.hpp")
    if ($LASTEXITCODE -ne 0) { throw "Header reconstruction rejected; retain attempted output directory" }
    if ((Get-FileHash -LiteralPath $qualifier -Algorithm SHA256).Hash.ToLowerInvariant() -cne $QualifierSha256 -or
        (Get-FileHash -LiteralPath $PythonExecutable -Algorithm SHA256).Hash.ToLowerInvariant() -cne $PythonSha256) {
        throw "Pinned publication tools changed"
    }
    Write-Output "Prepared exact precompile identity header. Actual compiler/header usage and native qualification remain unproven."
    return
}
if (-not $ConfigureControlsSha256) { throw "Identity publication requires an explicit admitted configure-controls hash" }
# All paths are passed as literal argv; no command-string or shell reconstruction.
$publish = @'
import importlib.util
import os
from pathlib import Path
import sys

repo_arg, deps_arg, build_arg, config, controls_sha = sys.argv[1:]
for value in (repo_arg, deps_arg, build_arg):
    if not Path(value).is_absolute():
        raise ValueError("absolute Root-declared input required")
repo = Path(repo_arg)
tool = repo / "tools/local-players/source-identity.py"
expected_tool_sha = "23b4494799d795b77bede1c0b4b4cf43421f5b592b312f1f8f60c3a0dd2965a3"
# Inspect every ancestor before importing the explicitly reviewed tool. No
# environment module path, source-root sys.path injection or unpinned helper.
import hashlib
import stat
for part in (*reversed(tool.parents), tool):
    info = part.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
        raise ValueError("reparse/symlink source tool rejected")
raw_tool = tool.read_bytes()
if hashlib.sha256(raw_tool).hexdigest() != expected_tool_sha:
    raise ValueError("reviewed source-identity tool bytes changed")
spec = importlib.util.spec_from_file_location("root_admitted_storage_identity", tool)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)
repo = identity.ordinary(repo, True)
deps = identity.ordinary(deps_arg, True)
build = identity.ordinary(build_arg, True)
identity.require(build != repo and build != deps and not build.is_relative_to(deps),
                 "build cannot be source root or dependency tree")
controls_path = build / ("local-players-configure-controls-" + config + ".json")
controls_record, controls_bytes = identity.file_record(controls_path, controls_sha)
controls = identity.load_json(controls_bytes)
identity.exact_keys(controls, ("schema", "compiled_build_scalars_without_include_digest",
                    "compiler_paths", "sqlite_include_directories"), "configure export")
identity.require(controls["schema"] == "LocalPlayersConfigureControls/v1", "configure export version")
scalars = controls["compiled_build_scalars_without_include_digest"]
identity.exact_keys(scalars, [key for key in identity.SCALARS
                            if key != "sqlite_include_directories_sha256"], "configure scalar facts")
identity.require(scalars["configuration"] == config, "configuration/export mismatch")
identity.exact_keys(controls["compiler_paths"], ("c", "cxx"), "configure compiler paths")
includes = controls["sqlite_include_directories"]
identity.require(type(includes) is list and len(includes) == 1
                 and type(includes[0]) is str and Path(includes[0]).is_absolute(), "one absolute SQLite include")
include = identity.ordinary(includes[0], True)
identity.require(include == identity.ordinary(deps / "sqlite", True), "actual verified SQLite include")
include_record = {"schema": "LocalPlayersSQLiteIncludeProvenance/v1", "directories": [{
    "path": identity.path_token(include, repo, build),
    "sqlite_header_sha256": identity.sha(identity.read(identity.ordinary(include / "sqlite3.h")))}]}
scalars["sqlite_include_directories_sha256"] = identity.sha(identity.canonical(include_record))
scalars = {key: scalars[key] for key in identity.SCALARS}
compilers = {}
for language in ("c", "cxx"):
    compiler = controls["compiler_paths"][language]
    identity.require(type(compiler) is str and Path(compiler).is_absolute(), "absolute actual compiler path")
    pin, raw = identity.file_record(compiler)
    compilers[language] = {"path": pin["path"], "sha256": pin["sha256"]}
cache_record, cache_bytes = identity.file_record(build / "CMakeCache.txt")
provenance = {"cache": {"path": cache_record["path"], "sha256": cache_record["sha256"]}}
for language, key in (("C", "c_compiler_record"), ("CXX", "cxx_compiler_record")):
    candidates = list((build / "CMakeFiles").glob("*/CMake" + language + "Compiler.cmake"))
    identity.require(len(candidates) == 1, "exact one configured compiler record")
    pin, raw = identity.file_record(candidates[0])
    provenance[key] = {"path": pin["path"], "sha256": pin["sha256"]}
plan = {"schema": "LocalPlayersPrecompilePlan/v1", "compiled_build_scalars": scalars,
        "compiler_files": compilers, "configure_provenance": provenance,
        "sqlite_include_directories": includes}
# Actual cache, compiler records/file formats, platform/runtime/binding constraints
# are checked before any output. This does not witness a compiler invocation.
identity.configure(plan, repo, deps)
plan_bytes = identity.canonical(plan)
for pin in (controls_record, cache_record, *provenance.values(), *compilers.values()):
    current, raw = identity.file_record(pin["path"], pin["sha256"])
    identity.require("bytes" not in pin or current["bytes"] == pin["bytes"], "input changed during publication")
identity.require(hashlib.sha256(tool.read_bytes()).hexdigest() == expected_tool_sha, "identity tool changed")
plan_path = build / "local-players-precompile-plan.json"
identity_output = build / "local-players-identity"
identity.require(not plan_path.exists() and not plan_path.is_symlink(), "precompile plan must be fresh")
identity.require(not identity_output.exists() and not identity_output.is_symlink(), "identity output must be fresh")
with plan_path.open("xb") as stream:
    stream.write(plan_bytes)
    stream.flush()
    os.fsync(stream.fileno())
print("LOCAL PLAYERS PRECOMPILE PLAN PUBLISHED; NO COMPILE/RUNTIME QUALIFICATION")
'@
& $PythonExecutable -I -B -c $publish $RepositoryRoot $DependencyRoot $BuildRoot $Configuration $ConfigureControlsSha256
if ($LASTEXITCODE -ne 0) { throw "Actual configure plan publication rejected; retain attempted outputs" }
if ((Get-FileHash -LiteralPath $PythonExecutable -Algorithm SHA256).Hash.ToLowerInvariant() -cne $PythonSha256) {
    throw "Pinned Python changed before source reconstruction"
}
$identityTool = Join-Path $RepositoryRoot "tools/local-players/source-identity.py"
if ((Get-FileHash -LiteralPath $identityTool -Algorithm SHA256).Hash.ToLowerInvariant() -cne "23b4494799d795b77bede1c0b4b4cf43421f5b592b312f1f8f60c3a0dd2965a3") {
    throw "Reviewed identity tool changed before source reconstruction"
}
& $PythonExecutable -I -B $identityTool --repo-root $RepositoryRoot --dependency-root $DependencyRoot `
    --build-plan (Join-Path $BuildRoot "local-players-precompile-plan.json") `
    --output-root (Join-Path $BuildRoot "local-players-identity")
if ($LASTEXITCODE -ne 0) { throw "Source identity reconstruction rejected; retained plan is not a build qualification" }
Write-Output "Prepared precompile source identity. No compiler, storage DB or CTest executed."
