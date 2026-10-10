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
import stat
import subprocess
import sys
import tempfile

SCHEMA = 'PreviewNativeBuildIdentity/v2'
SCOPE = 'Qualified declared source/build/resource identity; actual loaded facade and library identity require runtime evidence'
VARIANTS = ('jsbsim-1.3.1-upstream', 'jsbsim-1.3.1-event-aware-constant-power-v1',
            'jsbsim-1.3.1-event-aware-coupled-midpoint-v1')
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
    'tests/engine/native-limits.hpp', 'tests/engine/native-limits.json')
TEMPLATE = 'native/fdm_jsbsim/interactive/native_identity.gd.in'
CONTROLS = (
    'CMakeLists.txt', 'CMakePresets.json', 'third_party/dependencies.lock.json',
    'tools/bootstrap/source-selection.cmake', 'tools/bootstrap/source-variant.py',
    'tools/bootstrap/coupled-source-variant.py', 'tools/bootstrap/build.ps1',
    'tools/bootstrap/bootstrap.py', 'native/fdm_jsbsim/CMakeLists.txt',
    'native/fdm_jsbsim/ground/CMakeLists.txt',
    'native/fdm_jsbsim/interactive/CMakeLists.txt', 'tests/fdm/CMakeLists.txt', TEMPLATE)
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
                         'event-aware-coupled-midpoint-v1'), 'Unknown source selector')
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
        script, args = ('tools/bootstrap/coupled-source-variant.py', ['--coupled-midpoint']) if variant == VARIANTS[2] else (
            'tools/bootstrap/source-variant.py', ['--event-aware'])
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
    require(read(build, 'interactive-source-fingerprint.txt') == consumer.encode() + b'\n' + body,
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


def reconstruction_paths(repo):
    # Exact current overlays supplement a pinned public base checkout. Include
    # complete new native/test/bootstrap directories, not just the old six files.
    names = set(SOURCES + CONTROLS)
    for folder in ('native', 'tests/engine', 'tests/interactive', 'tools/bootstrap'):
        root = ordinary(repo / folder, True)
        for path in root.rglob('*'):
            ordinary(path, path.is_dir())
            if path.is_file():
                names.add(path.relative_to(repo).as_posix())
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
        '15 interactive inputs, the closed build controls/template, and current native,\n'
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
    args = parser.parse_args()
    expected = qualify(args.repository_root, args.build_root)
    if args.evidence:
        require(unique_json(ordinary(args.evidence).read_bytes()) == expected, 'Saved identity evidence differs from independent qualification')
    for root in args.staged_root:
        check_stage(expected, root)
    if args.reconstruction_root:
        reconstruction(args.repository_root, args.reconstruction_root)
    if args.check_reconstruction_root:
        check_reconstruction(args.repository_root, args.check_reconstruction_root)
    print(json.dumps(expected, sort_keys=True))


if __name__ == '__main__':
    main()
