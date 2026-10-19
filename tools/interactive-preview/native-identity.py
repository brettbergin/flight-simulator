"""ADR016 build-side qualification. Never runs the compiler, bridge or Godot.

The existing source selectors may reconstruct provenance in disposable scratch;
their selected source trees remain unchanged. Expected identity never comes from
a runtime reply. Synthetic tests inject a selector into qualify(), not the CLI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import subprocess
import sys
import tempfile

SCHEMA = 'PreviewNativeBuildIdentity/v2'
SCOPE = 'Qualified declared source/build/resource identity; actual loaded facade and library identity require runtime evidence'
VARIANTS = ('jsbsim-1.3.1-upstream', 'jsbsim-1.3.1-event-aware-constant-power-v1',
            'jsbsim-1.3.1-event-aware-coupled-midpoint-v1',
            'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2')
SOURCES = (
    'native/fdm_jsbsim/interactive/src/session.cpp',
    'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp',
    'native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp',
    'tests/interactive/native.cpp', 'tests/interactive/negatives.hpp',
    'native/fdm_jsbsim/interactive/src/model-pins.hpp',
    'native/fdm_jsbsim/interactive/src/piston-model-pins.hpp',
    'tests/engine/CMakeLists.txt', 'tests/engine/loaded-library.hpp',
    'tests/engine/native.cpp', 'tests/engine/native-mechanism.cpp',
    'tests/engine/native-validate.py', 'tests/engine/native-generate.py',
    'tests/engine/native-limits.hpp', 'tests/engine/native-limits.json',
    'native/godot_bridge/src/bridge.cpp',
    'native/godot_bridge/src/codec.hpp',
    'native/godot_bridge/src/codec.cpp',
    'native/godot_bridge/src/worker.hpp',
    'native/godot_bridge/src/worker.cpp',
    'native/godot_bridge/src/interactive_worker.hpp',
    'native/godot_bridge/src/interactive_worker.cpp',
    'native/godot_bridge/src/interactive_bridge.cpp',
    'native/godot_bridge/src/wire_numbers.hpp',
    'native/godot_bridge/src/wire_numbers.cpp')
TEMPLATE = 'native/fdm_jsbsim/interactive/native_identity.gd.in'
CONTROLS = (
    'CMakeLists.txt', 'CMakePresets.json', 'third_party/dependencies.lock.json',
    'tools/bootstrap/source-selection.cmake', 'tools/bootstrap/source-variant.py',
    'tools/bootstrap/coupled-source-variant.py', 'tools/bootstrap/build.ps1',
    'tools/bootstrap/bootstrap.py', 'native/fdm_jsbsim/CMakeLists.txt',
    'native/fdm_jsbsim/ground/CMakeLists.txt',
    'native/fdm_jsbsim/interactive/CMakeLists.txt', 'tests/fdm/CMakeLists.txt', TEMPLATE,
    'native/godot_bridge/CMakeLists.txt', 'tests/wire_codec/CMakeLists.txt',
    'tools/bootstrap/coupled-local-window-source-variant.py', 'tools/bootstrap/build-local-window.ps1',
    'tests/engine/local-window-v2/CMakeLists.txt')
BUILD_PATH = 'native-identity.gd'
STAGED_PATH = 'build/native_identity.gd'
TOP = ('schema', 'root', 'source_variant', 'backend_identity_sha256',
       'build_control_sha256', 'declared_source_fingerprint', 'source_bindings',
       'build_witnesses', 'resource', 'scope')
HASH = re.compile(r'[0-9a-f]{64}')
MACRO = 'FLIGHT_INTERACTIVE_SOURCE_SHA256'
TEMPLATE_BYTES = (b'extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\n'
    b'const SOURCE_VARIANT: String = "@FLIGHT_JSBSIM_SOURCE_VARIANT@"\n'
    b'const BACKEND_IDENTITY_SHA256: String = "@FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256@"\n'
    b'const BUILD_CONTROL_SHA256: String = "@FLIGHT_JSBSIM_BUILD_CONTROL_SHA256@"\n'
    b'const SOURCE_FINGERPRINT: String = "@INTERACTIVE_SOURCE_FINGERPRINT@"\n')

RESIDENT_MANIFEST = 'native/world_core/resident_world/component-v1.json'
# External reviewed pin: intentionally outside its own component/25/18 inputs.
RESIDENT_MANIFEST_SHA256 = 'ad219321c2f867e11cbd49b1a18f513625a4e19b78b2c1cda56155c423f6d6b5'
RESIDENT_UNITS = (
    'native/world_core/grid/src/validation.cpp',
    'native/world_core/grid/src/prepared_grid.cpp',
    'native/world_core/grid/src/grid_payload.cpp',
    'native/fdm_jsbsim/interactive/src/prepared_world.cpp')


def require(value, message):
    if not value:
        raise ValueError(message)


def closed(value, keys, message):
    require(type(value) is dict and set(value) == set(keys), message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def ordinary(path, directory=False):
    """Check every ancestor before resolution; resolving first hides junctions."""
    path = Path(os.path.abspath(path))
    for item in (path, *path.parents):
        info = item.lstat()
        require(not stat.S_ISLNK(info.st_mode) and
                not (getattr(info, 'st_file_attributes', 0) & 0x400),
                'Symlink/reparse path is not admitted')
    require(path.is_dir() if directory else path.is_file(), 'Ordinary file/directory required')
    return path.resolve(strict=True)


# Only configured Linux/GNU system-tool leaves may be aliases. This is not a
# caller-selected root and does not change ordinary project/input admission.
_GNU_TOOL_DIRECTORY = Path('/usr/bin')


def _configured_tool(path, key, family):
    require(type(path) is str and Path(path).is_absolute(), 'Absolute configured tool required')
    lexical = Path(os.path.abspath(path))
    if family != 'GNU' or sys.platform != 'linux' or key not in ('CMAKE_CXX_COMPILER', 'CMAKE_AR', 'CMAKE_RANLIB') or not lexical.is_symlink():
        return ordinary(lexical)
    directory = ordinary(_GNU_TOOL_DIRECTORY, True)
    require(lexical.parent == directory, 'GNU tool alias must be a system-directory leaf')
    current, seen = lexical, set()
    for _ in range(9):
        require(current.parent == directory and current not in seen, 'Escaped/cyclic GNU tool alias')
        info = current.lstat()
        if not stat.S_ISLNK(info.st_mode):
            target = ordinary(current)
            require(os.access(target, os.X_OK), 'GNU tool alias target must be executable')
            return target
        require(len(seen) < 8, 'GNU tool alias chain bound')
        seen.add(current)
        current = Path(os.path.abspath(current.parent / os.readlink(current)))
    raise ValueError('GNU tool alias chain bound')


def _known_tool(args, cache, key, family, bindings):
    require(key in cache and type(cache[key]) is str and Path(cache[key]).is_absolute(), 'Configured resident tool missing: ' + key)
    lexical = Path(os.path.abspath(cache[key]))
    expected = _configured_tool(cache[key], key, family)
    candidates = [arg for arg in args if Path(arg).name.lower() == lexical.name.lower()]
    require(len(candidates) == 1 and Path(candidates[0]).is_absolute(), 'Resident command uses an unconfigured/conflicting tool: ' + key)
    if family == 'GNU':
        require(candidates[0] == str(lexical), 'GNU command tool spelling differs from configured tool: ' + key)
    require(_configured_tool(candidates[0], key, family) == expected, 'Resident command tool target differs: ' + key)
    binding = (str(lexical), str(expected))
    require(key not in bindings or bindings[key] == binding, 'Configured tool target changed during observation: ' + key)
    bindings[key] = binding
    return expected


def contained(root, name):
    require(type(name) is str and '\\' not in name and ':' not in name and
            str(PurePosixPath(name)) == name and not name.startswith('/') and
            all(x not in ('', '.', '..') for x in name.split('/')), 'Unsafe relative path')
    root = ordinary(root, True)
    result = ordinary(root / name)
    require(result.is_relative_to(root), 'Path escapes its declared root')
    return result


def read(root, name):
    return contained(root, name).read_bytes()


def lf(raw):
    raw.decode('utf-8', errors='strict')
    return raw.replace(b'\r\n', b'\n')


def strict_json(raw, limit, depth, count):
    require(type(raw) is bytes and len(raw) <= limit and not raw.startswith(b'\xef\xbb\xbf'), 'Bounded UTF-8 JSON required')
    def pairs(rows):
        result = {}
        for key, value in rows:
            require(key not in result, 'Duplicate JSON field')
            result[key] = value
        return result
    def constant(_):
        raise ValueError('Nonfinite JSON constant')
    value = json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=pairs, parse_constant=constant)
    remaining = count
    def visit(item, level):
        nonlocal remaining
        remaining -= 1
        require(level <= depth and remaining >= 0, 'JSON structural budget exceeded')
        if type(item) is dict:
            for key, child in item.items():
                key.encode('utf-8', errors='strict')
                visit(child, level + 1)
        elif type(item) is list:
            for child in item: visit(child, level + 1)
        elif type(item) is str: item.encode('utf-8', errors='strict')
        elif type(item) is float:
            require(item == item and abs(item) != float('inf'), 'Nonfinite JSON number')
    visit(value, 0)
    return value


def safe_relative(name):
    require(type(name) is str and 0 < len(name) <= 1024 and '\\' not in name and ':' not in name and
            not name.startswith('/') and str(PurePosixPath(name)) == name and
            all(part not in ('', '.', '..') for part in name.split('/')), 'Unsafe resident relative path')
    return name


def resident_component(repo, pin=None):
    pin = RESIDENT_MANIFEST_SHA256 if pin is None else pin
    raw = read(repo, RESIDENT_MANIFEST)
    require(type(pin) is str and HASH.fullmatch(pin) and digest(raw) == pin, 'Unreviewed resident component manifest')
    value = strict_json(raw, 65536, 4, 2048)
    closed(value, ('schema', 'sources', 'controls'), 'Resident component shape differs')
    require(value['schema'] == 'ResidentWorldComponent/v1' and type(value['sources']) is list and
            type(value['controls']) is list and 1 <= len(value['sources']) + len(value['controls']) <= 256,
            'Resident component roster differs')
    seen, total, bindings, body = set(), 0, [], b'resident-world-component-v1\n'
    forbidden = set(SOURCES + CONTROLS + (RESIDENT_MANIFEST, 'tools/interactive-preview/native-identity.py'))
    for category, rows in (('source', value['sources']), ('control', value['controls'])):
        group = []
        for row in rows:
            closed(row, ('path', 'sha256'), 'Resident component row differs')
            name = safe_relative(row['path'])
            require(name not in seen and name not in forbidden and type(row['sha256']) is str and HASH.fullmatch(row['sha256']),
                    'Duplicate/overlapping/circular resident component input')
            seen.add(name)
            data = read(repo, name)
            require(0 < len(data) <= 4 * 1024 * 1024, 'Resident component input byte limit')
            total += len(data)
            require(total <= 16 * 1024 * 1024, 'Resident component aggregate limit')
            normalized = digest(lf(data))
            require(normalized == row['sha256'], 'Changed resident component input: ' + name)
            group.append(dict(path=name, bytes=len(data), raw_sha256=digest(data), lf_sha256=normalized))
            body += (category + ':' + name + ':' + normalized + '\n').encode('ascii')
        bindings.append(group)
    for variable, rows in (('RESIDENT_WORLD_SOURCE_PATHS', value['sources']), ('RESIDENT_WORLD_CONTROL_PATHS', value['controls'])):
        cmake_roster(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt', variable, tuple(row['path'] for row in rows))
    return dict(manifest=dict(path=RESIDENT_MANIFEST, bytes=len(raw), sha256=digest(raw)), recipe=body,
                sha256=digest(body), source_bindings=bindings[0], control_bindings=bindings[1])


def unique_json(raw):
    def pairs(rows):
        result = {}
        for key, value in rows:
            require(key not in result, 'Duplicate JSON field')
            result[key] = value
        return result
    return json.loads(raw.decode('utf-8-sig'), object_pairs_hook=pairs)


def cmake_roster(repo, name, variable, expected):
    text = read(repo, name).decode('utf-8')
    rows = re.findall(r'set\(' + variable + r'\s+(.*?)\)', text, re.S)
    require(len(rows) == 1 and tuple(rows[0].split()) == expected,
            'Changed or duplicate declared source roster: ' + variable)


def cache_values(build):
    values = {}
    for line in read(build, 'CMakeCache.txt').decode('utf-8').splitlines():
        match = re.fullmatch(r'([^#/:][^:]*):[^=]+=(.*)', line)
        if match:
            key, value = match.groups()
            require(key not in values, 'Duplicate CMake cache declaration')
            values[key] = value
    return values


def route(values):
    selected = values.get('FLIGHT_JSBSIM_VARIANT', '')
    legacy = values.get('FLIGHT_USE_EVENT_AWARE_JSBSIM')
    require(legacy in ('ON', 'OFF'), 'Missing/unknown legacy source selector')
    require(selected in ('', 'upstream', 'event-aware-constant-power-v1',
                         'event-aware-coupled-midpoint-v1', 'event-aware-coupled-midpoint-local-window-v2'), 'Unknown source selector')
    if selected:
        require(legacy == 'OFF' or selected == 'event-aware-constant-power-v1',
                'Conflicting source selectors')
    else:
        selected = 'event-aware-constant-power-v1' if legacy == 'ON' else 'upstream'
    return 'jsbsim-1.3.1-' + selected


def selected_source(repo, build, values):
    variant = route(values)
    if variant == VARIANTS[0]:
        source = ordinary(Path(values['FLIGHT_DEPENDENCY_ROOT']) / 'jsbsim', True)
        script, args = 'tools/bootstrap/source-variant.py', []
    else:
        source = ordinary(Path(values['FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT']) / 'vendor', True)
        if variant == VARIANTS[3]:
            script, args = 'tools/bootstrap/coupled-local-window-source-variant.py', ['--coupled-local-window']
        elif variant == VARIANTS[2]:
            script, args = 'tools/bootstrap/coupled-source-variant.py', ['--coupled-midpoint']
        else:
            script, args = 'tools/bootstrap/source-variant.py', ['--event-aware']
    # Isolated workspace scratch, including nested verifier subprocesses. No
    # global environment changes and no reuse of an owner's existing proof.
    scratch_parent = repo / '.local/native-identity-scratch'
    parent = scratch_parent
    while not parent.exists():
        parent = parent.parent
    ordinary(parent, True)
    scratch_parent.mkdir(parents=True, exist_ok=True)
    ordinary(scratch_parent, True)
    with tempfile.TemporaryDirectory(prefix='verify-', dir=scratch_parent) as scratch:
        environment = dict(os.environ, TEMP=scratch, TMP=scratch, TMPDIR=scratch,
                           PYTHONDONTWRITEBYTECODE='1')
        process = subprocess.run([sys.executable, '-B', str(contained(repo, script)),
            '--repository-root', str(repo), '--source-root', str(source), *args],
            cwd=repo, env=environment, capture_output=True, timeout=120, check=False)
        require(process.returncode == 0, 'Complete selected source verification failed')
        selected = unique_json(process.stdout)
    require(selected['source_variant'] == variant and
            ordinary(selected['source_root'], True) == source and
            type(selected['backend_identity_sha256']) is str and
            HASH.fullmatch(selected['backend_identity_sha256']), 'Selected source route differs')
    return selected


def compiler_identity(build):
    files = list((ordinary(build, True) / 'CMakeFiles').glob('*/CMakeCXXCompiler.cmake'))
    require(len(files) == 1, 'Exactly one configured CXX compiler required')
    text = ordinary(files[0]).read_text(encoding='utf-8')
    def value(name):
        rows = re.findall(r'set\(' + name + r' "([^"]+)"\)', text)
        require(len(rows) == 1, 'Missing/duplicate compiler declaration: ' + name)
        return rows[0]
    family, version = value('CMAKE_CXX_COMPILER_ID'), value('CMAKE_CXX_COMPILER_VERSION')
    require(family in ('MSVC', 'GNU') and re.fullmatch(r'[0-9]+(?:\.[0-9]+)+', version),
            'Unreviewed compiler family/version')
    return family, version


def build_controls(repo, build, values, selected):
    cmake_roster(repo, 'tools/bootstrap/source-selection.cmake', 'JSBSIM_BUILD_CONTROL_PATHS', CONTROLS)
    require(read(repo, TEMPLATE) == TEMPLATE_BYTES, 'Reviewed identity template differs')
    family, version = compiler_identity(build)
    if family == 'MSVC':
        require(not os.environ.get('CL') and not os.environ.get('_CL_'), 'Implicit MSVC options are not admitted')
    modified = selected['source_variant'] != VARIANTS[0]
    flags = ('/fp:strict' if family == 'MSVC' else '-fno-fast-math -ffp-contract=off -frounding-math') if modified else ''
    fields = [('source_variant', selected['source_variant']),
        ('backend_identity', selected['backend_identity_sha256']), ('compiler', family + '-' + version),
        ('generator', values['CMAKE_GENERATOR']), ('build_type', values['CMAKE_BUILD_TYPE']),
        ('cxx_flags', values['CMAKE_CXX_FLAGS']),
        ('configuration_flags', values['CMAKE_CXX_FLAGS_' + values['CMAKE_BUILD_TYPE'].upper()]),
        ('msvc_runtime', values['CMAKE_MSVC_RUNTIME_LIBRARY']), ('declared_strict_fp_flags', flags)]
    require(values['CMAKE_GENERATOR'] == 'Ninja', 'Unreviewed build generator')
    body = b''.join(p.encode() + b':' + digest(lf(read(repo, p))).encode() + b'\n' for p in CONTROLS)
    body += ''.join(k + ':' + v + '\n' for k, v in fields).encode('utf-8')
    return digest(body), family, version, flags


def resource_bytes(variant, backend, controls, consumer):
    require(variant in VARIANTS and all(type(x) is str and HASH.fullmatch(x) for x in (backend, controls, consumer)),
            'Invalid resource identity')
    return ('extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\n'
        'const SOURCE_VARIANT: String = "' + variant + '"\n'
        'const BACKEND_IDENTITY_SHA256: String = "' + backend + '"\n'
        'const BUILD_CONTROL_SHA256: String = "' + controls + '"\n'
        'const SOURCE_FINGERPRINT: String = "' + consumer + '"\n').encode('utf-8')


def definitions(text):
    # CMake command/Ninja definitions have no internal whitespace. Match the
    # complete supported value spelling, including both quotes, never a digest
    # prefix. Arguments arrays already provide boundaries; do not flatten them.
    value = r'(?:([0-9a-f]{64})|"([0-9a-f]{64})"|\\"([0-9a-f]{64})\\")'
    if type(text) is list:
        values = []
        for argument in text:
            if MACRO not in argument:
                continue
            match = re.fullmatch(r'[-/]D' + MACRO + '=' + value, argument)
            require(match is not None, 'Malformed compiled identity argument')
            values.append(next(group for group in match.groups() if group is not None))
        require(len(values) <= 1, 'Duplicate/conflicting per-command identity definitions')
        return values
    rows = list(re.finditer(r'(?<!\S)[-/]D[ \t]*' + MACRO + r'(?![A-Za-z0-9_])', text))
    require(len(rows) == text.count(MACRO), 'Identity must occur only as an explicit compiler definition')
    values = []
    for row in rows:
        tail = text[row.end():]
        match = re.match('=' + value + r'(?=$|[ \t\r\n])', tail)
        require(match is not None, 'Malformed compiled identity definition')
        values.append(next(group for group in match.groups() if group is not None))
    require(len(values) <= 1, 'Duplicate/conflicting per-command identity definitions')
    return values


def check_compilation(repo, build, expected):
    rows = unique_json(read(build, 'compile_commands.json'))
    require(type(rows) is list and rows, 'Compile commands required')
    session = contained(repo, SOURCES[0])
    session_rows = 0
    for row in rows:
        require(type(row) is dict and type(row.get('directory')) is str and type(row.get('file')) is str,
                'Malformed compile command')
        directory = ordinary(row['directory'], True)
        file = ordinary(directory / row['file'])
        require(('command' in row) != ('arguments' in row), 'One compiler command representation required')
        if 'command' in row:
            require(type(row['command']) is str, 'Compiler command must be a string')
            text = row['command']
        else:
            require(type(row['arguments']) is list and all(type(x) is str for x in row['arguments']), 'Compiler arguments must be strings')
            text = row['arguments']
        values = definitions(text)
        require(not values or values == [expected], 'Conflicting compiled source identity')
        if file == session:
            session_rows += 1
            require(values == [expected], 'Selected Session lacks expected compiled identity')
    require(session_rows == 1, 'Exactly one selected Session compilation required')
    lines = [line for line in read(build, 'build.ninja').decode('utf-8').splitlines() if MACRO in line]
    require(lines and all(definitions(line) == [expected] for line in lines), 'Ninja identity declaration differs')


def verify_manifests(build, values, selected, control, family, version, flags, body, consumer):
    source = str(ordinary(selected['source_root'], True)).replace('\\', '/')
    runtime = values['CMAKE_MSVC_RUNTIME_LIBRARY'].replace('$<$<CONFIG:Debug>:Debug>', 'Debug' if values['CMAKE_BUILD_TYPE'] == 'Debug' else '')
    expected = ('Source variant: ' + selected['source_variant'] + '\nSelected source root: ' + source +
        '\nBackend identity SHA256: ' + selected['backend_identity_sha256'] + '\nBuild controls SHA256: ' + control +
        '\nCompiler: ' + family + ' ' + version + '\nGenerator: ' + values['CMAKE_GENERATOR'] +
        '\nBuild configuration: ' + values['CMAKE_BUILD_TYPE'] + '\nCommon CXX flags: ' + values['CMAKE_CXX_FLAGS'] +
        '\nSelected configuration CXX flags: ' + values['CMAKE_CXX_FLAGS_' + values['CMAKE_BUILD_TYPE'].upper()] +
        '\nMSVC runtime: ' + runtime + '\nDeclared modified-source strict FP flags: ' + flags +
        '\nActual compiler commands must be inspected before numerical execution.\n').encode()
    require(lf(read(build, 'jsbsim-source-build-manifest.txt')) == expected, 'Selected source/build manifest differs')
    require(lf(read(build, 'interactive-source-fingerprint.txt')) == consumer.encode() + b'\n' + body,
            'Interactive fingerprint manifest differs')
    toolchain = lf(read(build, 'toolchain-build-manifest.txt')).decode('utf-8')
    for key, value in [('Compiler', family + ' ' + version), ('Generator', values['CMAKE_GENERATOR']),
                       ('Build type', values['CMAKE_BUILD_TYPE']), ('MSVC runtime', runtime)]:
        rows = re.findall(r'^' + re.escape(key) + r': (.*)$', toolchain, re.M)
        require(rows == [value], 'Missing/conflicting toolchain manifest declaration: ' + key)


def witness_paths(family):
    return ('bin/flight_godot_bridge.dll' if family == 'MSVC' else 'bin/libflight_godot_bridge.so',
            'build.ninja', 'CMakeCache.txt', 'toolchain-build-manifest.txt',
            'jsbsim-source-build-manifest.txt', 'interactive-source-fingerprint.txt', 'compile_commands.json')


def qualify(repo, build, selector=selected_source):
    repo, build = ordinary(repo, True), ordinary(build, True)
    values = cache_values(build)
    require(ordinary(values['CMAKE_HOME_DIRECTORY'], True) == repo and
            values.get('FLIGHT_BUILD_GODOT_BINDINGS') == 'ON' and
            values.get('CMAKE_EXPORT_COMPILE_COMMANDS') == 'ON', 'Wrong source/binding/compile-command route')
    selected = selector(repo, build, values)
    require(type(selected) is dict and selected.get('source_variant') == route(values) and
            type(selected.get('backend_identity_sha256')) is str and HASH.fullmatch(selected['backend_identity_sha256']),
            'Source selector returned a conflicting identity')
    cmake_roster(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt', 'INTERACTIVE_SOURCE_PATHS', SOURCES)
    control, family, version, flags = build_controls(repo, build, values, selected)
    bindings, body = [], ('verified-jsbsim-backend:' + selected['backend_identity_sha256'] +
                            '\njsbsim-build-controls:' + control + '\n').encode()
    component = resident_component(repo)
    body += ('resident-world-component:' + component['sha256'] + '\n').encode('ascii')
    require(lf(read(build, 'resident-world-component-fingerprint.txt')) == component['sha256'].encode('ascii') + b'\n' + component['recipe'],
            'Resident component fingerprint witness differs')
    for name in SOURCES:
        raw = read(repo, name)
        normalized_hash = digest(lf(raw))
        bindings.append(dict(path=name, bytes=len(raw), raw_sha256=digest(raw), lf_sha256=normalized_hash))
        body += name.encode() + b':' + normalized_hash.encode() + b'\n'
    consumer = digest(body)
    verify_manifests(build, values, selected, control, family, version, flags, body, consumer)
    check_compilation(repo, build, consumer)
    bridge = read(build, witness_paths(family)[0])
    require(consumer.encode('ascii') in bridge, 'Selected bridge lacks compiled source identity')
    resource = resource_bytes(selected['source_variant'], selected['backend_identity_sha256'], control, consumer)
    require(read(build, BUILD_PATH) == resource, 'Generated resource is stale or noncanonical')
    witnesses = [dict(path=p, bytes=len(read(build, p)), sha256=digest(read(build, p))) for p in witness_paths(family)]
    result = dict(schema=SCHEMA, root=str(build), source_variant=selected['source_variant'],
        backend_identity_sha256=selected['backend_identity_sha256'], build_control_sha256=control,
        declared_source_fingerprint=consumer, source_bindings=bindings, build_witnesses=witnesses,
        resource=dict(build_path=BUILD_PATH, staged_path=STAGED_PATH, bytes=len(resource), sha256=digest(resource)), scope=SCOPE)
    validate_evidence(result)
    return result


def validate_evidence(value):
    closed(value, TOP, 'Identity evidence exact shape rejected')
    require(value['schema'] == SCHEMA and value['scope'] == SCOPE and
            type(value['root']) is str and Path(value['root']).is_absolute() and
            value['source_variant'] in VARIANTS, 'Identity schema/root/variant rejected')
    for key in ('backend_identity_sha256', 'build_control_sha256', 'declared_source_fingerprint'):
        require(type(value[key]) is str and HASH.fullmatch(value[key]), 'Malformed identity digest')
    bindings = value['source_bindings']
    require(type(bindings) is list and len(bindings) == len(SOURCES), 'Identity source roster rejected')
    for name, row in zip(SOURCES, bindings):
        closed(row, ('path', 'bytes', 'raw_sha256', 'lf_sha256'), 'Source record exact shape rejected')
        require(row['path'] == name and type(row['bytes']) is int and row['bytes'] >= 0 and
                all(type(row[k]) is str and HASH.fullmatch(row[k]) for k in ('raw_sha256', 'lf_sha256')), 'Source record rejected')
    rows = value['build_witnesses']
    require(type(rows) is list and len(rows) == 7, 'Build witness roster rejected')
    require(type(rows[0]) is dict and rows[0].get('path') in (witness_paths('MSVC')[0], witness_paths('GNU')[0]), 'Unknown bridge witness')
    for name, row in zip(witness_paths('MSVC' if rows[0]['path'].endswith('.dll') else 'GNU'), rows):
        closed(row, ('path', 'bytes', 'sha256'), 'Build witness exact shape rejected')
        require(row['path'] == name and type(row['bytes']) is int and row['bytes'] >= 0 and
                type(row['sha256']) is str and HASH.fullmatch(row['sha256']), 'Build witness rejected')
    resource = value['resource']
    closed(resource, ('build_path', 'staged_path', 'bytes', 'sha256'), 'Resource exact shape rejected')
    require(resource['build_path'] == BUILD_PATH and resource['staged_path'] == STAGED_PATH and
            type(resource['bytes']) is int and resource['bytes'] >= 0 and
            type(resource['sha256']) is str and HASH.fullmatch(resource['sha256']), 'Resource record rejected')
    raw = resource_bytes(value['source_variant'], value['backend_identity_sha256'],
                         value['build_control_sha256'], value['declared_source_fingerprint'])
    require(len(raw) == resource['bytes'] and digest(raw) == resource['sha256'], 'Resource evidence differs from canonical identity')
    return raw


def check_stage(value, root):
    expected = validate_evidence(value)
    require(read(root, STAGED_PATH) == expected, 'Staged generated identity differs')


def windows_arguments(text):
    """The documented backslash/quote command-line rules; no shell evaluation."""
    require(type(text) is str and '\x00' not in text, 'Invalid Windows command text')
    result, index = [], 0
    while index < len(text):
        while index < len(text) and text[index] in ' \t\r\n': index += 1
        if index == len(text): break
        argument, quoted = '', False
        while index < len(text):
            if text[index] in ' \t\r\n' and not quoted: break
            slash = 0
            while index < len(text) and text[index] == '\\':
                slash += 1
                index += 1
            if index < len(text) and text[index] == '"':
                argument += '\\' * (slash // 2)
                if slash % 2: argument += '"'
                else: quoted = not quoted
                index += 1
            else:
                argument += '\\' * slash
                if index < len(text):
                    argument += text[index]
                    index += 1
        require(not quoted, 'Unclosed Windows command quote')
        result.append(argument)
    return result


def command_arguments(row, family):
    require(('command' in row) != ('arguments' in row), 'One command representation required')
    if 'arguments' in row:
        require(type(row['arguments']) is list and row['arguments'] and all(type(x) is str for x in row['arguments']), 'Invalid compiler arguments')
        return list(row['arguments'])
    require(type(row['command']) is str and row['command'], 'Compiler command missing')
    return windows_arguments(row['command']) if family == 'MSVC' else shlex.split(row['command'], posix=True)


def resident_closure(repo, build, identity_raw, identity):
    """Observe existing commands/artifacts only. Never compile, link or run Ninja."""
    repo, build = ordinary(repo, True), ordinary(build, True)
    require(type(identity_raw) is bytes and len(identity_raw) <= 4 * 1024 * 1024 and
            strict_json(identity_raw, 4 * 1024 * 1024, 12, 20000) == identity, 'Raw native identity observation differs')
    validate_evidence(identity)
    component = resident_component(repo)
    family, _ = compiler_identity(build)
    observations = {}
    def observed(root, name):
        key = (root, name)
        raw = read(root, name)
        require(key not in observations or observations[key] == raw, 'Input changed during resident observation')
        observations[key] = raw
        return raw
    def artifact(name):
        name = safe_relative(name)
        raw = observed(build, name)
        require(len(raw) > 0, 'Empty resident build artifact')
        return dict(path=name, bytes=len(raw), sha256=digest(raw))
    require(digest(observed(repo, RESIDENT_MANIFEST)) == component['manifest']['sha256'], 'Component manifest changed before observation')
    for row in component['source_bindings'] + component['control_bindings']:
        require(digest(observed(repo, row['path'])) == row['raw_sha256'], 'Resident input changed')
    for row in identity['build_witnesses']:
        require(artifact(row['path']) == row, 'Native witness changed before resident observation')
    require(lf(observed(build, 'resident-world-component-fingerprint.txt')) == component['sha256'].encode('ascii') + b'\n' + component['recipe'], 'Component witness changed')
    cache = cache_values(build)
    tool_bindings = {}

    def build_relative(path):
        resolved = ordinary(path)
        require(resolved.is_relative_to(build), 'Resident build input/output escapes actual build')
        return safe_relative(resolved.relative_to(build).as_posix())
    def response_args(args, records, active=None):
        active = set() if active is None else active
        result = []
        for arg in args:
            if not arg.startswith('@'):
                result.append(arg)
                continue
            require(len(arg) > 1, 'Empty response-file argument')
            name = build_relative(build / arg[1:])
            require(name not in active, 'Response-file cycle')
            raw = observed(build, name)
            require(0 < len(raw) <= 4 * 1024 * 1024, 'Response-file size bound')
            if not any(row['path'] == name for row in records):
                records.append(dict(path=name, bytes=len(raw), sha256=digest(raw)))
                require(len(records) <= 16 and sum(row['bytes'] for row in records) <= 4 * 1024 * 1024, 'Response-file aggregate bound')
            text = raw.decode('utf-16') if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else raw.decode('utf-8', errors='strict')
            child = windows_arguments(text) if family == 'MSVC' else shlex.split(text, posix=True)
            result.extend(response_args(child, records, active | {name}))
        return result
    def output_arg(args):
        outputs = []
        for index, arg in enumerate(args):
            if family == 'MSVC' and arg.lower().startswith('/fo'):
                outputs.append(arg[3:] if len(arg) > 3 else args[index + 1])
            elif family == 'GNU' and arg == '-o': outputs.append(args[index + 1])
        require(len(outputs) == 1 and outputs[0], 'Exactly one actual compiler output required')
        return build_relative(build / outputs[0])
    def strict_flags(args):
        if family == 'MSVC':
            policies = [arg.lower() for arg in args if arg.lower().startswith('/fp:') or arg.lower().startswith('-fp:')]
            require(policies and all(item in ('/fp:strict', '-fp:strict') for item in policies), 'Resident MSVC strict FP missing/conflicting')
            require(not any(arg.lower().startswith(('/fpcontract', '-fpcontract')) for arg in args), 'Unreviewed FP contraction option')
        else:
            require('-fno-fast-math' in args and '-ffp-contract=off' in args, 'Resident GNU strict FP missing')
            forbidden = ('-ffast-math', '-Ofast', '-funsafe-math-optimizations', '-fassociative-math',
                         '-freciprocal-math', '-ffinite-math-only', '-fno-signed-zeros', '-fno-trapping-math')
            require(not any(arg in forbidden or (arg.startswith('-ffp-contract=') and arg != '-ffp-contract=off') for arg in args), 'Unsafe/conflicting resident GNU flags')
    def known_tool(args, key):
        return _known_tool(args, cache, key, family, tool_bindings)
    def actual_source(args, edge, source):
        required = contained(repo, source)
        compile_positions = [index for index, arg in enumerate(args) if arg in ('-c', '/c')]
        require(len(compile_positions) == 1 and compile_positions[0] == len(args) - 2,
                'Exactly one final explicit compile-source operand required')
        candidates = []
        for arg in args[1:]:
            if arg.startswith('-') or Path(arg).suffix.lower() not in ('.cpp', '.cc', '.cxx', '.c++', '.c'): continue
            # A POSIX absolute source is still an ordinary source when a
            # synthetic MSVC command is inspected on Linux. Do not classify
            # every leading slash as an option. Known attached MSVC options
            # can contain a source-like suffix without being bare operands.
            path = build / arg
            known_option = family == 'MSVC' and arg.startswith('/') and arg.lower().startswith(('/d','/i','/fi','/fo','/fd','/fp','/yu','/yc'))
            if arg != args[-1] and known_option and not path.is_file(): continue
            if path.is_file(): ordinary(path)
            candidates.append(arg)
        require(len(candidates) == 1 and candidates[0] == args[-1] and ordinary(build / args[-1]) == required,
                'Actual compiler source operand differs from required source')
        require(len(edge['explicit']) == 1 and ordinary(build / edge['explicit'][0]) == required,
                'Actual Ninja compile dependency differs from required source')
    def corresponding_compile(declared, actual, edge):
        # CMake compile_commands intentionally omits its dependency scanner's
        # instrumentation. Admit only these bound, exact generated additions.
        compared = list(actual)
        if family == 'MSVC':
            def positions(args):
                found = [index for index, arg in enumerate(args) if arg.lower() in ('/showincludes','-showincludes')]
                require(len(found) <= 1 and all(args[index] == '/showIncludes' for index in found), 'Duplicate/unreviewed MSVC dependency flag')
                return found
            before, after = positions(declared), positions(actual)
            if not before and after: compared.pop(after[0])
        else:
            markers = ('-MD','-MT','-MF')
            present = [arg for arg in actual if arg in markers]
            if present:
                require(all(actual.count(flag) == 1 for flag in markers), 'Duplicate/incomplete GNU dependency instrumentation')
                index = actual.index('-MD')
                require(index + 4 < len(actual) and actual[index + 1] == '-MT' and actual[index + 3] == '-MF', 'Unreviewed GNU dependency grouping')
                output = output_arg(actual)
                depfile = safe_relative(edge['bindings'].get('DEP_FILE','').replace('\\','/'))
                rule = rules[edge['rule']]
                require(rule.get('depfile') == '$DEP_FILE' and rule.get('deps') == 'gcc' and
                        actual[index + 2].replace('\\','/') == output and actual[index + 4].replace('\\','/') == depfile,
                        'GNU dependency target/file differs from selected Ninja edge')
                if not any(arg in markers for arg in declared): del compared[index:index + 5]
        require(declared == compared, 'Actual Ninja compiler command differs from compile_commands beyond bound dependency instrumentation')

    # CMake's generated Ninja dialect only. This reads fixed files, never asks
    # Ninja to interpret commands and never executes an observed command string.
    def logical_lines(raw):
        require(len(raw) <= 32 * 1024 * 1024, 'Ninja file byte bound')
        return re.sub(r'\$\r?\n[ \t]*', '', raw.decode('utf-8', errors='strict')).splitlines()
    def ninja_words(text):
        words, current, index = [], '', 0
        while index < len(text):
            char = text[index]
            if char == '$':
                index += 1
                require(index < len(text) and text[index] in '$ :', 'Unsupported Ninja path variable')
                current += text[index]
            elif char.isspace():
                if current: words.append(current); current = ''
            else: current += char
            index += 1
        if current: words.append(current)
        return words
    edges, rules, globals_ = {}, {}, {}
    def workdir_paths(text):
        pattern = re.compile(r'\$(?:\{cmake_ninja_workdir\}|cmake_ninja_workdir(?![A-Za-z_0-9]))')
        def replace(_):
            require('cmake_ninja_workdir' in globals_, 'Ninja output workdir is not declared')
            declared = ninja_words(globals_['cmake_ninja_workdir'])
            require(len(declared) == 1 and ordinary(declared[0], True) == build, 'Ninja output workdir differs from actual build')
            return globals_['cmake_ninja_workdir']
        return pattern.sub(replace, text)
    def ninja_key(name):
        # CMake can declare a relative output and its absolute alias on the
        # same edge. Canonicalize lexically; unrelated phony outputs need not
        # exist. Required artifacts still pass ordinary contained reads later.
        absolute = Path(os.path.abspath(build / name.replace('\\','/')))
        return absolute.relative_to(build).as_posix() if absolute.is_relative_to(build) else absolute.as_posix()
    current = None
    for line in logical_lines(observed(build, 'CMakeFiles/rules.ninja')):
        if line.startswith('rule '):
            name = line[5:]
            require(name not in rules, 'Duplicate Ninja rule')
            current = rules[name] = {}
        elif line.startswith('  ') and current is not None and ' = ' in line:
            key, value = line.strip().split(' = ', 1)
            require(key not in current, 'Duplicate Ninja rule binding')
            current[key] = value
        elif line and not line.startswith('#'): current = None
    current = None
    for line in logical_lines(observed(build, 'build.ninja')):
        if line.startswith('build '):
            match = re.search(r'(?<!\$):[ \t]+', line)
            require(match is not None, 'Unrecognized Ninja edge')
            output_words = ninja_words(workdir_paths(line[6:match.start()]))
            require(output_words.count('|') <= 1 and '||' not in output_words and
                    output_words and output_words[0] != '|' and output_words[-1] != '|', 'Malformed implicit Ninja outputs')
            outputs = [word for word in output_words if word != '|']
            words = ninja_words(workdir_paths(line[match.end():]))
            require(outputs and words, 'Empty Ninja edge')
            rule, deps, order = words[0], [], []
            target = deps
            for word in words[1:]:
                if word == '||': target = order
                elif word != '|': target.append(word)
            explicit_words = words[1:]
            explicit_words = explicit_words[:next((i for i, part in enumerate(explicit_words) if part in ('|', '||')), len(explicit_words))]
            current = dict(outputs=outputs, rule=rule, deps=deps, explicit=explicit_words, order=order, bindings={})
            for output in outputs:
                key = ninja_key(output)
                require(key not in edges or edges[key] is current, 'Duplicate Ninja build output owner')
                edges[key] = current
        elif line.startswith('  ') and current is not None and ' = ' in line:
            key, value = line.strip().split(' = ', 1)
            require(key not in current['bindings'], 'Duplicate Ninja edge binding')
            current['bindings'][key] = value
        elif line and not line.startswith('#'):
            current = None
            if ' = ' in line and not line.startswith(('include ', 'subninja ')):
                key, value = line.split(' = ', 1)
                require(key not in globals_, 'Duplicate Ninja global binding')
                globals_[key] = value
    def expand(text, bindings, depth=0):
        require(depth <= 16, 'Ninja variable cycle/depth')
        pattern = re.compile(r'\$(?:\{([A-Za-z_][A-Za-z_0-9]*)\}|([A-Za-z_][A-Za-z_0-9]*)|([$ :]))')
        def replace(match):
            if match[3] is not None: return match[3]
            name = match[1] or match[2]
            # Exact optional bindings observed in the retained CMake rules:
            # no defines for grid, no bridge manifests/search-path additions.
            # Flags/includes/tools/outputs and all unknown names stay required.
            if name in ('LAUNCHER', 'CODE_CHECK', 'DEFINES', 'MANIFESTS', 'LINK_PATH') and name not in bindings: return ''
            require(name in bindings, 'Unbound Ninja command variable: ' + name)
            return expand(bindings[name], bindings, depth + 1)
        return pattern.sub(replace, text)
    def edge_command(name):
        require(name in edges, 'Actual artifact absent from Ninja graph: ' + name)
        edge = edges[name]
        require(edge['rule'] in rules, 'Actual Ninja rule missing')
        rule = rules[edge['rule']]
        bindings = dict(globals_, **edge['bindings'])
        # Only explicit dependencies appear as $in; implicit archive deps remain
        # graph dependencies and LINK_LIBRARIES supplies their command arguments.
        quote = lambda path: '"' + path + '"' if any(c.isspace() for c in path) else path
        bindings['in'] = ' '.join(quote(path) for path in edge['explicit'])
        bindings['out'] = quote(edge['outputs'][0])
        require(bindings.get('PRE_LINK', '') in ('', ':', 'cd .') and bindings.get('POST_BUILD', '') in ('', ':', 'cd .'), 'Unreviewed pre/post-link command')
        command = expand(rule.get('command', ''), bindings)
        require(command and '$' not in command and '\x00' not in command, 'Unresolved Ninja command')
        return edge, command
    def link_arguments(command):
        # CMake's Windows wrapper quotes a shell expression as one /C argument;
        # remove only that fixed wrapper before inspecting its real link stage.
        if family == 'MSVC':
            match = re.fullmatch(r'(?i)(?:"[^"]*cmd\.exe"|[^\s"]*cmd\.exe) /C "(.*)"', command)
            require(match is not None, 'Unreviewed Windows archive/link wrapper')
            stages = match[1].split(' && ')
            require(len(stages) == 3 and stages[0] in ('cd .', ':') and stages[2] in ('cd .', ':'), 'Unreviewed archive/link shell stages')
            require(not any(char in stages[1] for char in '&|<>\r\n'), 'Archive/link shell redirection/operator')
            return windows_arguments(stages[1])
        stages = command.split(' && ')
        require(1 <= len(stages) <= 5 and not any(char in command for char in '|<>;\r\n'), 'Unreviewed GNU archive/link shell stages')
        args = []
        for stage in stages:
            if stage.strip() != ':': args.extend(shlex.split(stage))
        return args
    def primary_output(args, name, archive=False, explicit=None):
        if family == 'MSVC':
            choices = [arg for arg in args if arg.lower().startswith(('/out:', '-out:'))]
            require(len(choices) == 1 and choices[0].lower().startswith('/out:') and
                    not any(arg.lower() in ('/out','-out','-o','--output') for arg in args), 'Unique actual MSVC primary output required')
            output = choices[0][5:]
        elif archive:
            known_tool(args, 'CMAKE_AR')
            ar = Path(cache['CMAKE_AR'])
            indexes = [index for index, arg in enumerate(args) if Path(arg).name == ar.name]
            require(len(indexes) == 1 and indexes[0] + 2 < len(args), 'GNU archive output missing')
            index = indexes[0]
            require(args[index + 1] in ('qc','qcD'), 'Unreviewed GNU archive mode')
            output = args[index + 2]
            # The actual generated archive body is ar + optional ranlib, with
            # an optional fixed cmake -E rm -f of that same primary artifact.
            expected_objects = list(explicit or [])
            cursor = index + 3 + len(expected_objects)
            require(args[index + 3:cursor] == expected_objects, 'GNU archive object operands differ')
            prefix, suffix = args[:index], args[cursor:]
            if prefix:
                known_tool(prefix[:1], 'CMAKE_COMMAND')
                require(len(prefix) == 5 and prefix[1:4] == ['-E','rm','-f'] and build_relative(build / prefix[4]) == name, 'Unreviewed GNU archive cleanup stage')
            if suffix:
                known_tool(suffix[:1], 'CMAKE_RANLIB')
                require(len(suffix) == 2 and build_relative(build / suffix[1]) == name, 'Unreviewed GNU ranlib stage')
        else:
            choices = [index for index, arg in enumerate(args) if arg == '-o']
            require(len(choices) == 1 and choices[0] + 1 < len(args) and
                    not any(arg.startswith(('--output','-Wl,-o,','-Wl,--output')) or (arg.startswith('-o') and arg != '-o') for arg in args),
                    'Unique actual GNU primary output required')
            output = args[choices[0] + 1]
        require(output and build_relative(build / output) == name, 'Actual archive/link primary output differs from selected Ninja artifact')

    rows = strict_json(observed(build, 'compile_commands.json'), 32 * 1024 * 1024, 8, 2000000)
    require(type(rows) is list, 'Compile commands array required')
    session_rows = [row for row in rows if type(row) is dict and type(row.get('directory')) is str and type(row.get('file')) is str and
                    ordinary(Path(row['directory']) / row['file']) == contained(repo, SOURCES[0])]
    require(len(session_rows) == 1 and ordinary(session_rows[0]['directory'], True) == build, 'Actual Session compile route differs')
    session_responses = []
    session_args = response_args(command_arguments(session_rows[0], family), session_responses)
    require(not session_responses, 'Session response inputs need a separately reviewed observation before admission')
    strict_flags(session_args)
    known_tool(session_args[:1], 'CMAKE_CXX_COMPILER')
    session_edge, session_command = edge_command(output_arg(session_args))
    actual_source(session_args, session_edge, SOURCES[0])
    observed_session_args = windows_arguments(session_command) if family == 'MSVC' else shlex.split(session_command)
    corresponding_compile(session_args, observed_session_args, session_edge)
    units, objects = [], []
    for source in RESIDENT_UNITS:
        matched = []
        for index, row in enumerate(rows):
            require(type(row) is dict and type(row.get('directory')) is str and type(row.get('file')) is str, 'Malformed compile record')
            directory = ordinary(row['directory'], True)
            if ordinary(directory / row['file']) == contained(repo, source): matched.append((index, row, directory))
        require(len(matched) == 1, 'Resident unit must have exactly one actual compilation: ' + source)
        index, row, directory = matched[0]
        require(directory == build, 'Unreviewed resident compile working directory')
        response_files = []
        args = response_args(command_arguments(row, family), response_files)
        known_tool(args[:1], 'CMAKE_CXX_COMPILER')
        strict_flags(args)
        output = output_arg(args)
        require(output not in objects, 'Resident units share an output object')
        edge, ninja_command = edge_command(output)
        actual_source(args, edge, source)
        require('CXX_COMPILER' in edge['rule'], 'Resident output is not a CXX compile edge')
        ninja_responses = []
        ninja_args = response_args(windows_arguments(ninja_command) if family == 'MSVC' else shlex.split(ninja_command), ninja_responses)
        corresponding_compile(args, ninja_args, edge)
        require(response_files == ninja_responses, 'Actual Ninja response inputs differ from compile_commands')
        strict_flags(ninja_args)
        objects.append(output)
        units.append(dict(source=source, compile_commands_index=index, object_path=output,
                          fp_policy='msvc-strict' if family == 'MSVC' else 'gnu-no-fast-no-contract', response_files=response_files))
    grid_owners = {name for name, edge in edges.items() if 'STATIC_LIBRARY_LINKER' in edge['rule'] and
                   all(obj in [ninja_key(p) for p in edge['deps']] for obj in objects[:3])}
    prepared_owners = {name for name, edge in edges.items() if 'STATIC_LIBRARY_LINKER' in edge['rule'] and
                       objects[3] in [ninja_key(p) for p in edge['deps']]}
    require(len(grid_owners) == len(prepared_owners) == 1, 'Resident objects lack unique actual archive owners')
    grid_archive, interactive_archive = next(iter(grid_owners)), next(iter(prepared_owners))
    require(grid_archive != interactive_archive, 'Resident archives unexpectedly collapsed')
    def archive_members(name):
        raw = observed(build, name)
        require(len(raw) <= 512 * 1024 * 1024 and raw.startswith(b'!<arch>\n'), 'Bounded ordinary static archive required')
        members, names, position = [], b'', 8
        while position < len(raw):
            require(position + 60 <= len(raw), 'Truncated static archive header')
            header = raw[position:position + 60]
            require(header[58:] == b'`\n', 'Invalid static archive header')
            length_text = header[48:58].strip()
            require(length_text and length_text.isdigit(), 'Invalid static archive member length')
            length = int(length_text)
            begin, end = position + 60, position + 60 + length
            require(end <= len(raw), 'Truncated static archive member')
            token = header[:16].decode('ascii').rstrip()
            data = raw[begin:end]
            if token == '//':
                require(not names, 'Duplicate static archive long-name table')
                names = data
            elif token not in ('/', '/SYM64/'):
                if token.startswith('/'):
                    require(token[1:].isdigit() and int(token[1:]) < len(names), 'Invalid static archive long-name offset')
                    offset = int(token[1:])
                    stops = [i for i in (names.find(b'\x00', offset), names.find(b'/\n', offset)) if i >= 0]
                    require(stops, 'Unterminated static archive long name')
                    token = names[offset:min(stops)].decode('utf-8', errors='strict')
                else:
                    require(not token.startswith('#1/'), 'Unreviewed BSD archive naming')
                    token = token.removesuffix('/')
                require(token and '\x00' not in token, 'Empty static archive member name')
                members.append((token.replace('\\','/'), data))
            position = end + length % 2
            require(position <= len(raw) and (length % 2 == 0 or raw[end:position] == b'\n'), 'Invalid static archive padding')
        require(position == len(raw) and members, 'Static archive size/member mismatch')
        return members
    link_responses = []
    for archive, required in ((grid_archive, objects[:3]), (interactive_archive, [objects[3]])):
        edge, command = edge_command(archive)
        expanded = response_args(link_arguments(command), link_responses)
        known_tool(expanded, 'CMAKE_AR')
        primary_output(expanded, archive, True, edge['explicit'])
        normalized = [arg.replace('\\','/') for arg in expanded]
        require(all(normalized.count(obj) == 1 for obj in required), 'Archive command does not consume the exact resident objects once')
        actual = archive_members(archive)
        expected_members = [build_relative(build / path) for path in edge['explicit']]
        require(len(actual) == len(expected_members), 'Archive contains omitted/extra/stale object members')
        for object_name in expected_members:
            object_bytes = observed(build, object_name)
            matches = [index for index, (member_name, member_bytes) in enumerate(actual)
                       if PurePosixPath(member_name).name == PurePosixPath(object_name).name and member_bytes == object_bytes]
            require(len(matches) == 1, 'Archive member bytes differ from actual Ninja output object')
            actual.pop(matches[0])
    bridge_path = identity['build_witnesses'][0]['path']
    edge, command = edge_command(bridge_path)
    require('SHARED_LIBRARY_LINKER' in edge['rule'], 'Bridge lacks actual shared-library link edge')
    deps = [ninja_key(item) for item in edge['deps']]
    require(deps.count(grid_archive) == deps.count(interactive_archive) == 1, 'Bridge graph does not consume both resident archives once')
    expanded = response_args(link_arguments(command), link_responses)
    known_tool(expanded, 'CMAKE_LINKER' if family == 'MSVC' else 'CMAKE_CXX_COMPILER')
    primary_output(expanded, bridge_path)
    normalized = [arg.replace('\\','/') for arg in expanded]
    require(normalized.count(grid_archive) == normalized.count(interactive_archive) == 1, 'Bridge link command lacks exact resident archives')
    result = dict(schema='ResidentWorldNativeClosure/v1', passed=True,
        scope='reviewed-linked-resident-world-component-only', component_manifest=component['manifest'],
        component_sha256=component['sha256'], source_bindings=component['source_bindings'], control_bindings=component['control_bindings'],
        native_identity=dict(bytes=len(identity_raw), sha256=digest(identity_raw),
            **{key:identity[key] for key in ('source_variant','backend_identity_sha256','build_control_sha256','declared_source_fingerprint')},
            bridge=identity['build_witnesses'][0], resource=identity['resource']), translation_units=units,
        link=dict(bridge=artifact(bridge_path), interactive_archive=artifact(interactive_archive), grid_archive=artifact(grid_archive),
                  grid_objects=[artifact(name) for name in objects[:3]], prepared_world_object=artifact(objects[3]), response_files=link_responses),
        build_witnesses=identity['build_witnesses'])
    for (root, name), raw in observations.items():
        require(read(root, name) == raw, 'Resident input/artifact changed during independent observation: ' + name)
    for key, (lexical, canonical) in tool_bindings.items():
        require(str(_configured_tool(lexical, key, family)) == canonical, 'Configured tool changed before closure completed: ' + key)
    return result


def reconstruction_paths(repo):
    # Exact current overlays supplement a pinned public base checkout. Include
    # complete new native/test/bootstrap directories, not just the old six files.
    names = set(SOURCES + CONTROLS)
    # Exact authored camera copies supplement the compiled reconstruction.
    # These are not native SOURCES/CONTROLS; generated UIDs are never authored.
    names.update((
        'app/camera/view_policy.gd',
        'app/ui/camera/views_panel.gd',
        'tests/camera/.gitattributes',
        'tests/camera/README.md',
        'tests/camera/expected-v1.json',
        'tests/camera/generate.py',
        'tests/camera/root-ratification-v1.json',
        'tests/camera/source-binding-v1.json',
        'tests/camera/policy_checks.gd',
        'tests/camera/panel_checks.gd',
        'tests/camera/scene_checks.gd',
    ))
    for folder in ('native', 'tests/engine', 'tests/interactive', 'tools/bootstrap',
                   'app/world/taxi', 'app/ui/taxi', 'tests/world/taxi',
                   'tests/integration/taxi', 'app/persistence', 'app/ui/profiles',
                   'app/ui/history', 'tests/ui/profiles', 'app/world/terrain'):
        root = ordinary(repo / folder, True)
        for path in root.rglob('*'):
            ordinary(path, path.is_dir())
            if path.is_file():
                relative = path.relative_to(repo)
                # Exclude Python cache artifacts only from repository overlays.
                # ordinary() above still rejects links/unsupported paths.
                if '__pycache__' in relative.parts or relative.suffix == '.pyc':
                    continue
                names.add(relative.as_posix())
    names.update(('app/world/world_admission.gd', 'tools/interactive-preview/world-catalog.mjs',
                  'content/world/catalog/kawo-runtime-v1.json'))
    names.update('content/world/airports/kawo/runtime-v1/' + name for name in
                 ('world.json','ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt'))
    return sorted(names)


def immutable_head(repo):
    head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--verify', 'HEAD^{commit}'], text=True).strip()
    require(re.fullmatch(r'[0-9a-f]{40}', head), 'Verified immutable source base commit required')
    return head


def reconstruction(repo, destination):
    repo = ordinary(repo, True)
    destination = ordinary(destination, True)
    require(not (destination / 'repository').exists() and
            not (destination / 'native-reconstruction.json').exists(), 'Reconstruction output must be fresh')
    head = immutable_head(repo)
    rows = []
    for name in reconstruction_paths(repo):
        raw = read(repo, name)
        target = destination / 'repository' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        rows.append(dict(path=name, bytes=len(raw), sha256=digest(raw)))
    binding = dict(schema='PreviewNativeReconstruction/v1', base_git_commit=head,
        files=rows, scope='Exact current native/build-control overlays on the immutable public base commit; external dependency acquisition and actual DLL replacement proofs remain separate')
    (destination / 'native-reconstruction.json').write_text(json.dumps(binding, indent=2) + '\n', encoding='utf-8', newline='\n')
    instructions = ('Native source reconstruction\n\n'
        'Clone https://github.com/brettbergin/flight-simulator.git into a fresh directory.\n'
        'Check out exact commit ' + head + ' (git checkout --detach ' + head + ').\n'
        'Verify every repository/ overlay against native-reconstruction.json, then copy\n'
        'those repository-relative files over that checkout. These overlays bind all\n'
        '25 interactive inputs, the closed build controls/template, and current native,\n'
        'engine-test, interactive-test and bootstrap source additions. Keep build/\n'
        'native_identity.gd as historical package evidence; do not copy it into a new\n'
        'build. Follow tools/bootstrap/README.md to acquire pinned dependencies and\n'
        'rebuild with your chosen qualified toolchain; CMake generates a new identity.\n'
        'The separately supplied JSBSim source/BUILD.md and source archive preserve\n'
        'library modification, debugging and replacement rights. A compatible rebuilt\n'
        'JSBSim DLL may replace that library without an application DLL-byte allowlist.\n'
        'A modified replacement retains its own provenance; the bridge fingerprint\n'
        'does not relabel it as an unchanged reviewed backend.\n')
    (destination / 'NATIVE-RECONSTRUCTION.txt').write_text(instructions, encoding='utf-8', newline='\n')


def check_reconstruction(repo, destination):
    repo, destination = ordinary(repo, True), ordinary(destination, True)
    binding = unique_json(read(destination, 'native-reconstruction.json'))
    closed(binding, ('schema', 'base_git_commit', 'files', 'scope'), 'Reconstruction manifest exact shape rejected')
    require(binding['schema'] == 'PreviewNativeReconstruction/v1' and
            type(binding['base_git_commit']) is str and re.fullmatch(r'[0-9a-f]{40}', binding['base_git_commit']) and
            type(binding['scope']) is str and binding['scope'], 'Reconstruction manifest rejected')
    require(binding['base_git_commit'] == immutable_head(repo), 'Reconstruction immutable base differs from current verified Git commit')
    expected = reconstruction_paths(repo)
    rows = binding['files']
    require(type(rows) is list and len(rows) == len(expected), 'Reconstruction source closure rejected')
    actual = ordinary(destination / 'repository', True)
    actual_paths = []
    for file in actual.rglob('*'):
        ordinary(file, file.is_dir())
        if file.is_file():
            actual_paths.append(file.relative_to(actual).as_posix())
    require(sorted(actual_paths) == expected, 'Reconstruction contains omitted/extra source files')
    for name, row in zip(expected, rows):
        closed(row, ('path', 'bytes', 'sha256'), 'Reconstruction source record rejected')
        raw = read(repo, name)
        require(row['path'] == name and type(row['bytes']) is int and row['bytes'] == len(raw) and
                row['sha256'] == digest(raw) and read(actual, name) == raw, 'Reconstruction source differs')
    instructions = read(destination, 'NATIVE-RECONSTRUCTION.txt').decode('utf-8')
    require('git checkout --detach ' + binding['base_git_commit'] in instructions, 'Pinned reconstruction instructions missing')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository-root', type=Path, required=True)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--staged-root', type=Path, action='append', default=[])
    parser.add_argument('--reconstruction-root', type=Path)
    parser.add_argument('--check-reconstruction-root', type=Path)
    parser.add_argument('--resident-closure-output', type=Path)
    parser.add_argument('--resident-closure-evidence', type=Path)
    args = parser.parse_args()
    expected = qualify(args.repository_root, args.build_root)
    if args.evidence:
        require(unique_json(ordinary(args.evidence).read_bytes()) == expected, 'Saved identity evidence differs from independent qualification')
    if args.resident_closure_output or args.resident_closure_evidence:
        require(args.evidence is not None, 'Resident closure requires the actual raw identity evidence file')
        identity_raw = ordinary(args.evidence).read_bytes()
        closure = resident_closure(args.repository_root, args.build_root, identity_raw, expected)
        if args.resident_closure_evidence:
            raw = ordinary(args.resident_closure_evidence).read_bytes()
            require(strict_json(raw, 4 * 1024 * 1024, 12, 20000) == closure, 'Resident closure differs from independent actual observation')
        if args.resident_closure_output:
            output = Path(os.path.abspath(args.resident_closure_output))
            ordinary(output.parent, True)
            with output.open('xb') as stream:
                stream.write((json.dumps(closure, indent=2) + '\n').encode('utf-8'))
    for root in args.staged_root:
        check_stage(expected, root)
    if args.reconstruction_root:
        reconstruction(args.repository_root, args.reconstruction_root)
    if args.check_reconstruction_root:
        check_reconstruction(args.repository_root, args.check_reconstruction_root)
    print(json.dumps(expected, sort_keys=True))


if __name__ == '__main__':
    main()
