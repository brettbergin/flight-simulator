"""CI source/build qualification and unchanged physical-suite authorization.

This helper never launches a simulation. Bootstrap owns compilation/CTest;
the unit runner owns its separately authorized children and actual-module gate.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

LIMITS = '9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb'
INVENTORY = 'f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a'
VARIANT = 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'
SUITE = ('CMakeLists.txt', 'loaded-library.hpp', 'selected-method.hpp',
         'native.cpp', 'native-mechanism.cpp', 'native-validate.py',
         'native-limits.json', 'native-limits.hpp', 'native-generate.py')
REQUIRED = {
    'native_toolchain_smoke',
    'contract_boundary',
    'ground_contract',
    'ground_contact_proof',
    'fdm_boundary',
    'interactive_loop',
    'interactive_negative_readback',
    'piston_engine_lifecycle',
    'coupled_shaft_math',
    'coupled_shaft_native',
    'replay_reconstruction',
    'wire_numbers_native',
    'piston_local_window_native_references',
    'interactive_apron_starts'
}
APRON_LEGACY_INVENTORY = '98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd'
AUTH_KEYS = {'authorized', 'scope', 'native_sha256', 'mechanism_sha256',
             'jsbsim_dll_sha256', 'limits_sha256', 'source_fingerprint',
             'backend_identity_sha256', 'model_inventory_sha256',
             'suite_source_sha256', 'pretrial_ratification_sha256'}

REFERENCE_FILES = {'COMPARISON-PLAN.md', 'NATIVE-FIXTURES.md', 'README.md', 'cases.json',
                   'exact.py', 'generate.py', 'native_fixture.py', 'test_native_fixture.py', 'test_reference.py'}
GENERATOR_FILES = {'exact.py', 'generate.py', 'native_fixture.py'}
PROBE_FILES = {'chronology-probe.cpp', 'CMakeLists.txt', 'driver.template.cpp', 'legacy_compare.py',
               'library-probe.cpp', 'prepare.py', 'README.md', 'run.py', 'source-chronology.py',
               'terminal-retention.cpp', 'test_portable.py', 'test_validate.py', 'validate.py'}
SHARED_FILES = {'tests/engine/loaded-library.hpp', 'tests/engine/reference/expected-v3.json',
                'tests/engine/CMakeLists.txt', 'tools/bootstrap/build.ps1', 'tools/interactive-preview/native-identity.py',
                'tests/engine/local-window-v2/CMakeLists.txt', 'tools/bootstrap/build-local-window.ps1'}
REFERENCE_MODELS = {'native/fdm_jsbsim/models/original-piston-prop/engine/original-fixed-prop.xml',
                    'native/fdm_jsbsim/models/original-piston-prop/engine/original-piston.xml'}


LOCAL_WINDOW_PINS = {'docs/decisions/015-source-law-coupled-shaft.md': 'a1e71c20faf5a648990c2bf06c538fa6a9d328f6ab02029b694a4b8d7af595de', 'docs/decisions/024-certified-local-decay-window.md': '3404f1198d34b4faa3c1d640988be88dd8b3839fdfaff0f4e70213798d6db55b', 'docs/evidence/P3/piston-local-window-reference/README.md': 'dea84d14bac0969bed480cd9e5c442d260628d1ac3fe1c1d48790ef6341913d5', 'docs/evidence/P3/piston-local-window-reference/expected.json': 'da53acdff9600e2577832d1e3d110d8cfd221c45e8d1576ff088ef59514bdd7b', 'docs/evidence/P3/piston-local-window-reference/generate.py': '01d4b45c3abee53d3cf72804540973aec7b27171a8b23cd7d82d63bf22782699', 'docs/evidence/P3/piston-local-window-reference/manifest.json': '996dbc36c68fc35b8cb33d2b988fd9b10da235bd5f8e137e4b498101798fc016', 'tests/engine/shaft-method/coupled-midpoint-v1/native_fixture.py': '24aff9ed415b03da7f0f4795c6f8cf410413244821c9e8b19cd45ceeedb40c1f', 'tests/engine/shaft-method/coupled-midpoint-v1/references.json': '9496b4d4ed0930f0cb0fb0f994b66806ce45e18beaca439c92bda1b056fc8437', 'tests/engine/shaft-method/local-window-v2/CMakeLists.txt': '27f116822cbeb2e1950b07b50d47aa6950271d5ce3c941a3a1769fe0a7b95198', 'tests/engine/shaft-method/local-window-v2/README.md': 'dc866eba2416c756ccbd6aded18eb0eb7b73c83acc13fb570fe5258ed91b5d63', 'tests/engine/shaft-method/local-window-v2/driver.template.cpp': '0135f4b10ac51fdc608e3db7ac66a3525d2f8f40758c5c3f71d2da97a9d23795', 'tests/engine/shaft-method/local-window-v2/prepare.py': 'bf274e04e987fd0a2ab558e7249dff2eaa0a4a091228ddaeb29091266f7dda41', 'tests/engine/shaft-method/probes/driver.template.cpp': '0cfb84e5b8097d2de19939b51fe7694cc32bf917f1b4071d85d8c09481e64d5b', 'third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/vendor/src/models/propulsion/FGPropeller.cpp': 'bc8414bfd86d482e32c7c3edd5e73352ffa7209b9daec74cf6ac19f1421a6d17', 'third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/vendor/src/models/propulsion/FGPropeller.h': '730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5', 'third_party/patches/jsbsim/event-aware-coupled-midpoint-v1/vendor/src/models/propulsion/FGPropeller.cpp': 'e0ff11682070f2fa5a40ed7f14dbfcf56719a186089eb03185af8cdf9227d9f4', 'third_party/patches/jsbsim/event-aware-coupled-midpoint-v1/vendor/src/models/propulsion/FGPropeller.h': '730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5'}

def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))


def save(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def same(left, right):
    require(Path(left).samefile(right), 'different path: ' + str(left))


def command(args, repo):
    process = subprocess.run([str(x) for x in args], cwd=repo, text=True,
                             encoding='utf-8', capture_output=True, timeout=180)
    require(process.returncode == 0, 'source/discovery command failed: ' + process.stderr)
    return process.stdout


def cache(path):
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([^#/:][^:]*):[^=]+=(.*)', line)
        if match:
            require(match[1] not in out, 'duplicate cache key')
            out[match[1]] = match[2]
    return out


def cmake_paths(repo, file, variable):
    text = (repo/file).read_text(encoding='utf-8')
    matches = re.findall(r'set\(' + re.escape(variable) + r'\s+([^)]*)\)', text)
    require(len(matches) == 1, 'missing/ambiguous declared source roster')
    paths = matches[0].split()
    require(paths and len(paths) == len(set(paths)), 'invalid source roster')
    for path in paths:
        require(not Path(path).is_absolute() and (repo/path).resolve().is_relative_to(repo),
                'source roster escapes repository')
    return paths


def lf_sha(path):
    return hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()


def reference(repo):
    directory = repo/'tests/engine/shaft-method/coupled-midpoint-v1'
    manifest = load(directory/'reference-manifest.json')
    require(manifest['schema'] == 'coupled-midpoint-reference-manifest-v1' and
            manifest['method'] == 'event_aware_coupled_midpoint_v1' and
            manifest['contract_merge'] == 'eb410a634a9f18b4ea9177640aff391def5e7988', 'reference schema/contract')
    require(set(manifest['source_files']) == REFERENCE_FILES and
            set(manifest['generator_sources']) == GENERATOR_FILES and
            set(manifest['model_pins']) == REFERENCE_MODELS, 'reference closed source roster')
    require(manifest['packet']['path'] == 'references.json' and manifest['roster']['path'] == 'cases.json' and
            manifest['roster']['named_groups'] == 41, 'reference fixed packet/roster')
    require(manifest['roster']['sha256'] == manifest['source_files']['cases.json']['sha256'], 'roster source hash')
    for name, want in manifest['generator_sources'].items():
        require(want == manifest['source_files'][name]['sha256'], 'generator source hash')
    for name, pin in manifest['source_files'].items():
        path = directory/name
        require(path.resolve().parent == directory.resolve(), 'invalid reference member')
        require(sha(path) == pin['sha256'] and path.stat().st_size == pin['bytes'],
                'reference source changed: ' + name)
    packet_path = directory/manifest['packet']['path']
    require(packet_path.resolve().parent == directory.resolve(), 'invalid packet member')
    require(sha(packet_path) == manifest['packet']['sha256'] and
            packet_path.stat().st_size == manifest['packet']['bytes'], 'packet identity')
    packet = load(packet_path)
    require(packet['schema'] == 'coupled-midpoint-reference-v1' and packet['method'] == manifest['method'] and
            packet['contract_merge'] == manifest['contract_merge'] and packet['named_group_count'] == 41, 'packet contract')
    require(packet['generator_sources'] == manifest['generator_sources'] and
            packet['roster_sha256'] == manifest['roster']['sha256'], 'reference provenance')
    require(packet['native_fixture_schema'] == manifest['roster']['native_fixture_schema'] and
            packet['native_fixture_scope']['maximum_requests'] == 192 and
            manifest['roster']['maximum_requests'] == 192, 'reference fixture contract')
    for name, want in manifest['model_pins'].items():
        require(sha(repo/name) == want, 'reference model changed')
    return manifest


def contained(repo, name):
    require(isinstance(name, str) and name and not Path(name).is_absolute(), 'invalid repository source path')
    path = (repo/name).resolve()
    require(path.is_relative_to(repo.resolve()), 'source input escaped repository')
    return path


def resident_inputs(repo, build=None):
    helper = 'tools/interactive-preview/native-identity.py'
    spec = importlib.util.spec_from_file_location('coupled_resident_identity', repo/helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    component = module.resident_component(repo)
    module.cmake_roster(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt', 'INTERACTIVE_SOURCE_PATHS', module.SOURCES)
    if build is not None:
        witness = module.lf(module.read(build, 'resident-world-component-fingerprint.txt'))
        require(witness == component['sha256'].encode()+b'\n'+component['recipe'], 'resident component compiled witness mismatch')
    paths = [helper, module.RESIDENT_MANIFEST, *module.SOURCES]
    paths.extend(row['path'] for group in ('source_bindings', 'control_bindings') for row in component[group])
    return dict(sha256=component['sha256'], sources=module.SOURCES, paths=tuple(dict.fromkeys(paths)))


def source_inputs(repo):
    paths = {'tests/engine/'+name for name in SUITE}
    paths.update(resident_inputs(repo)['paths'])
    for name, want in LOCAL_WINDOW_PINS.items():
        require(sha(contained(repo, name)) == want, 'local-window reference/source changed: '+name)
        paths.add(name)
    paths.update(cmake_paths(repo, 'tools/bootstrap/source-selection.cmake', 'JSBSIM_BUILD_CONTROL_PATHS'))
    paths.update(cmake_paths(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt', 'INTERACTIVE_SOURCE_PATHS'))
    paths.update(('tests/interactive/CMakeLists.txt',
                 'tools/ci/coupled-local-window-native.py', 'tools/ci/test_coupled_local_window_native.py',
                 '.github/workflows/coupled-ci.yml',
                 'third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/identity.json'))
    probes = 'tests/engine/shaft-method/probes-local-window-v2/'
    probe_manifest = load(repo/probes/'probe-manifest.json')
    require(set(probe_manifest) == {'schema', 'files', 'shared_sources'} and
            probe_manifest['schema'] == 'coupled-probe-source-manifest-local-window-v2', 'probe source schema')
    require(set(probe_manifest['files']) == PROBE_FILES and
            set(probe_manifest['shared_sources']) == SHARED_FILES, 'probe closed source roster')
    paths.add(probes+'probe-manifest.json')
    declared = {probes+name: pin for name, pin in probe_manifest['files'].items()}
    declared.update(probe_manifest['shared_sources'])
    for name, pin in declared.items():
        path = contained(repo, name)
        require(sha(path) == pin['sha256'] and path.stat().st_size == pin['bytes'], 'probe source changed: '+name)
        paths.add(name)
    refs = 'tests/engine/shaft-method/coupled-midpoint-v1/'
    manifest = reference(repo)
    paths.update(refs+name for name in manifest['source_files'])
    paths.update((refs+'reference-manifest.json', refs+manifest['packet']['path']))
    model = 'native/fdm_jsbsim/models/original-piston-prop/'
    require(sha(repo/model/'inventory.json') == INVENTORY, 'model inventory changed')
    paths.add(model+'inventory.json')
    inventory = load(repo/model/'inventory.json')
    for pin in inventory['files'] + inventory['metadata']:
        path = contained(repo, model+pin['path'])
        require(sha(path) == pin['sha256'] and path.stat().st_size == pin['bytes'], 'model member changed')
        paths.add(model+pin['path'])
    # The apron CTest passes both original model roots; pin the legacy model too.
    legacy = 'native/fdm_jsbsim/models/original-interactive/'
    require(sha(repo/legacy/'inventory.json') == APRON_LEGACY_INVENTORY, 'legacy apron model inventory changed')
    paths.add(legacy+'inventory.json')
    for pin in load(repo/legacy/'inventory.json')['files']:
        path = contained(repo, legacy+pin['path'])
        require(sha(path) == pin['sha256'] and path.stat().st_size == pin['bytes'], 'legacy apron model member changed')
        paths.add(legacy+pin['path'])
    pins = {name: {'sha256': sha(contained(repo, name)), 'bytes': contained(repo, name).stat().st_size}
            for name in sorted(paths)}
    require(pins['tests/engine/native-limits.json']['sha256'] == LIMITS, 'physical budgets changed')
    return pins


def check_pretrial(repo, before):
    require(set(before) == {'schema', 'scope', 'source_inputs', 'reference_manifest_sha256',
                           'packet_sha256', 'required_ctests'}, 'pretrial closed schema')
    require(before['schema'] == 'coupled-ci-pretrial-local-window-v2' and before['scope'] ==
            'fixed source/reference/budgets before fresh compilation; no native execution', 'pretrial contract')
    require(before['required_ctests'] == sorted(REQUIRED), 'pretrial required gates changed')
    for name, pin in before['source_inputs'].items():
        require(set(pin) == {'sha256', 'bytes'}, 'pretrial source pin schema')
        path = contained(repo, name)
        require(sha(path) == pin['sha256'] and path.stat().st_size == pin['bytes'], 'pretrial input changed: '+name)
    require(before['source_inputs'] == source_inputs(repo), 'pretrial source/model closure changed')


def pretrial(repo, work):
    require(not work.exists(), 'CI work root must be fresh; preserve existing evidence')
    manifest = reference(repo)
    pins = source_inputs(repo)
    work.mkdir(parents=True)
    (work/'evidence').mkdir()
    save(work/'pretrial.json', {'schema': 'coupled-ci-pretrial-local-window-v2',
         'scope': 'fixed source/reference/budgets before fresh compilation; no native execution',
         'source_inputs': pins, 'reference_manifest_sha256': sha(repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'),
         'packet_sha256': manifest['packet']['sha256'], 'required_ctests': sorted(REQUIRED)})


def strict(command_text, windows):
    def flag(text):
        return re.search(r'(^|[\s"])' + re.escape(text) + r'($|[\s"])', command_text)
    if windows:
        require(flag('/fp:strict') and not any(flag('/fp:'+x) for x in ('fast', 'precise')),
                'missing/conflicting MSVC strict FP')
    else:
        require(all(flag(x) for x in ('-fno-fast-math', '-ffp-contract=off', '-frounding-math')),
                'missing GNU strict FP')
        require(not any(flag(x) for x in ('-ffast-math', '-Ofast', '-ffp-contract=fast',
                                        '-ffp-contract=on', '-fno-rounding-math')),
                'conflicting GNU FP options')


def build_control(repo, build, values, selected):
    paths = cmake_paths(repo, 'tools/bootstrap/source-selection.cmake', 'JSBSIM_BUILD_CONTROL_PATHS')
    body = ''.join(path+':'+lf_sha(repo/path)+'\n' for path in paths)
    compiler_files = list((build/'CMakeFiles').glob('*/CMakeCXXCompiler.cmake'))
    require(len(compiler_files) == 1, 'one configured CXX compiler required')
    compiler_text = compiler_files[0].read_text(encoding='utf-8')
    def compiler_value(name):
        items = re.findall(r'set\('+name+r' "([^"]+)"\)', compiler_text)
        require(len(items) == 1, 'missing configured compiler value: ' + name)
        return items[0]
    family = compiler_value('CMAKE_CXX_COMPILER_ID')
    version = compiler_value('CMAKE_CXX_COMPILER_VERSION')
    windows = os.name == 'nt'
    require(family == ('MSVC' if windows else 'GNU'), 'unexpected compiler family')
    flags = '/fp:strict' if windows else '-fno-fast-math -ffp-contract=off -frounding-math'
    fields = [('source_variant', selected['source_variant']), ('backend_identity', selected['backend_identity_sha256']),
              ('compiler', family+'-'+version), ('generator', values['CMAKE_GENERATOR']),
              ('build_type', values['CMAKE_BUILD_TYPE']), ('cxx_flags', values['CMAKE_CXX_FLAGS']),
              ('configuration_flags', values['CMAKE_CXX_FLAGS_'+values['CMAKE_BUILD_TYPE'].upper()]),
              ('msvc_runtime', values['CMAKE_MSVC_RUNTIME_LIBRARY']), ('declared_strict_fp_flags', flags)]
    body += ''.join(key+':'+value+'\n' for key, value in fields)
    return hashlib.sha256(body.encode()).hexdigest()


def local_window_target(config,build,tests):
    build=build.resolve()
    configured=Path(config['local_window'])
    expected=build/'bin'/('piston_local_window_native.exe' if os.name=='nt' else 'piston_local_window_native')
    require(configured.is_absolute() and configured.resolve()==expected.resolve() and configured.resolve().is_relative_to(build) and configured.is_file(),'local-window scalar executable must be the actual contained fresh-build target')
    rows=[row for row in tests if row['name']=='piston_local_window_native_references']
    require(len(rows)==1,'one local-window scalar CTest required')
    command=rows[0]['command']
    require(isinstance(command,list) and len(command)==1 and type(command[0]) is str and Path(command[0]).is_absolute() and Path(command[0]).resolve()==configured.resolve(),'local-window scalar CTest must execute exactly the qualified target with no arguments')
    return {'path':str(configured.resolve()),'sha256':sha(configured)}


def apron_target(repo, build, tests):
    """Measure the actual fresh-build CTest command; this never executes it."""
    repo, build = repo.resolve(), build.resolve()
    rows = [row for row in tests if row['name'] == 'interactive_apron_starts']
    require(len(rows) == 1, 'one actual apron CTest required')
    argv = rows[0]['command']
    require(type(argv) is list and len(argv) == 5 and all(type(value) is str for value in argv),
            'apron CTest requires exactly five String arguments')
    require(argv[3] == 'apron', 'actual apron driver mode required')
    expected = (build/'bin'/('interactive_tests.exe' if os.name == 'nt' else 'interactive_tests'),
                repo/'native/fdm_jsbsim/models/original-interactive',
                build/'interactive-proof/ctest-apron', None,
                repo/'native/fdm_jsbsim/models/original-piston-prop')
    for index in (0, 1, 2, 4):
        path = Path(argv[index])
        require(path.is_absolute() and path == expected[index] and path.resolve() == expected[index],
                'apron CTest executable/model/evidence path differs from declared target')
        # Existing ancestors must be ordinary, including Windows junctions.
        for parent in (path, *path.parents):
            require(not parent.is_symlink(), 'apron CTest path has a symbolic-link ancestor')
            if parent.exists():
                require(not (getattr(parent.lstat(), 'st_file_attributes', 0) & 0x400),
                        'apron CTest path has a reparse ancestor')
        if index == 0:
            require(path.is_file(), 'actual fresh-build apron executable missing')
        elif index in (1, 4):
            require(path.is_dir(), 'actual apron model root missing')
    properties = rows[0].get('properties')
    require(type(properties) is list, 'apron CTest properties missing')
    for name, value in (('ENVIRONMENT', ['JSBSIM_DEBUG=0']), ('TIMEOUT', 120)):
        matches = [row for row in properties if type(row) is dict and row.get('name') == name]
        require(len(matches) == 1 and (type(matches[0].get('value')) in (int, float) if name == 'TIMEOUT' else type(matches[0].get('value')) is list) and matches[0]['value'] == value,
                'apron CTest debug environment/120-second timeout differs')
    return {'path': str(expected[0]), 'sha256': sha(expected[0])}


def qualify(repo, work):
    before = load(work/'pretrial.json')
    check_pretrial(repo, before)
    require(before['reference_manifest_sha256'] == sha(repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'), 'reference manifest changed')
    manifest = reference(repo)
    require(before['packet_sha256'] == manifest['packet']['sha256'], 'reference changed')
    if os.name == 'nt':
        require(not os.environ.get('CL') and not os.environ.get('_CL_'), 'implicit MSVC options not admitted')
    build = work/'build'
    route = load(build/'event-aware-route.json')
    result = load(build/'event-aware-build-result.json')
    same(route['repository_root'], repo); same(route['build_directory'], build)
    same(route['pretrial_path'], work/'pretrial.json')
    require(Path(route['execution_path']).resolve() == (work/'physical-execution.json').resolve(), 'physical execution path differs')
    require(Path(route['probe_execution_path']).resolve() == (work/'unit-execution.json').resolve(), 'unit execution path differs')
    require(route['headless_native'] is True and route['source_variant'] == VARIANT, 'wrong headless source route')
    require(result['status'] == 'COMPILED_NOT_TESTED' and result['route_sha256'] == sha(build/'event-aware-route.json'), 'staged compilation missing')
    require(route['pretrial_sha256'] == sha(work/'pretrial.json') and route['build_entry_sha256'] == sha(repo/'tools/bootstrap/build-local-window.ps1'), 'staged entry/pretrial changed')
    for key, name in (('cmake_cache_sha256', 'CMakeCache.txt'), ('compile_commands_sha256', 'compile_commands.json'), ('verbose_build_sha256', 'native-verbose-build.log')):
        require(result[key] == sha(build/name), 'compiled evidence changed: ' + name)
    vendor = Path(route['source_bundle_root'])/'vendor'
    selected = json.loads(command([sys.executable, '-B', repo/'tools/bootstrap/coupled-local-window-source-variant.py', '--coupled-local-window', '--source-root', vendor], repo))
    require(selected['source_variant'] == VARIANT and selected['backend_identity_sha256'] == route['backend_identity_sha256'], 'selected source no longer matches compilation')
    commands = load(build/'compile_commands.json')
    actual = (build/'native-verbose-build.log').read_text(encoding='utf-8').replace('\\', '/')
    for name in ('FGPiston.cpp', 'FGPropeller.cpp'):
        path = (vendor/'src/models/propulsion'/name).resolve()
        entries = [x for x in commands if (Path(x['directory'])/x['file']).resolve() == path]
        require(len(entries) == 1, 'one selected numerical compile command required')
        strict(entries[0].get('command') or ' '.join(entries[0]['arguments']), os.name == 'nt')
        lines = [x for x in actual.splitlines() if str(path).replace('\\', '/') in x and re.search(r'(^|[\s"])(/c|-c)($|[\s"])', x)]
        require(len(lines) == 1, 'one actual numerical compiler invocation required')
        strict(lines[0], os.name == 'nt')
    values = cache(build/'CMakeCache.txt')
    require(values['FLIGHT_JSBSIM_VARIANT'] == 'event-aware-coupled-midpoint-local-window-v2' and values['FLIGHT_BUILD_GODOT_BINDINGS'] == 'OFF', 'wrong configured variant/headless mode')
    control = build_control(repo, build, values, selected)
    resident = resident_inputs(repo, build)
    prefix = 'verified-jsbsim-backend:'+selected['backend_identity_sha256']+'\njsbsim-build-controls:'+control+'\nresident-world-component:'+resident['sha256']+'\n'
    paths = cmake_paths(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt', 'INTERACTIVE_SOURCE_PATHS')
    body = prefix + ''.join(path+':'+lf_sha(repo/path)+'\n' for path in paths)
    consumer = hashlib.sha256(body.encode()).hexdigest()
    require((build/'interactive-source-fingerprint.txt').read_text(encoding='utf-8') == consumer+'\n'+body, 'compiled consumer provenance differs from current source')
    unit_config = load(build/'coupled-probes-config.json')
    unit_auth = load(work/'unit-execution.json')
    require(unit_config['schema'] == 'coupled-probe-config-local-window-v2', 'wrong configured unit schema')
    same(unit_config['repository_root'], repo); same(unit_config['build_root'], build)
    same(unit_config['vendor_root'], vendor)
    require(unit_auth['authorized'] is True and unit_auth['schema'] == 'coupled-probe-execution-local-window-v2' and
            unit_auth['scope'] == 'coupled-midpoint-local-window-isolated-public-probes-v2', 'explicit qualified unit authorization missing')
    require(unit_auth['config_sha256'] == sha(build/'coupled-probes-config.json') and unit_auth['backend_identity_sha256'] == selected['backend_identity_sha256'] and unit_auth['build_control_sha256'] == control and unit_auth['consumer_fingerprint'] == consumer, 'unit authorization provenance mismatch')
    require(unit_auth['reference_manifest_sha256'] == before['reference_manifest_sha256'] and
            unit_auth['packet_sha256'] == manifest['packet']['sha256'] and
            unit_auth['source_manifest_sha256'] == sha(unit_config['source_manifest']), 'unit source/reference identities mismatch')
    for label in ('kernel', 'library', 'chronology', 'terminal'):
        same(unit_auth['executables'][label]['path'], unit_config[label])
        require(unit_auth['executables'][label]['sha256'] == sha(unit_config[label]), 'unit executable changed: ' + label)
    same(unit_auth['dll']['path'], unit_config['dll'])
    expected_inputs = {str((build/name).resolve()): sha(build/name) for name in
                       ('event-aware-route.json', 'event-aware-build-result.json', 'CMakeCache.txt',
                        'compile_commands.json', 'native-verbose-build.log')}
    expected_inputs[str((work/'pretrial.json').resolve())] = sha(work/'pretrial.json')
    expected_inputs[str(repo/'tools/bootstrap/build-local-window.ps1')] = sha(repo/'tools/bootstrap/build-local-window.ps1')
    generated=build/'tests/engine/local-window-v2/local-window-references/generated'
    expected_inputs.update({str((generated/name).resolve()):sha(generated/name) for name in ('driver.cpp','immutable_helpers.inc','candidate_helpers.inc','source-binding.json')})
    require(unit_auth['build_inputs'] == expected_inputs, 'unit authorization measured build inputs mismatch')
    tools = load(repo/'.local/toolchain/environment.json')['tools']
    ctest = Path(tools['cmake']).with_name('ctest.exe' if os.name == 'nt' else 'ctest')
    discovery = json.loads(command([ctest, '--test-dir', build, '--show-only=json-v1'], repo))
    names = [x['name'] for x in discovery['tests']]
    require(len(names) == 14 and len(set(names)) == 14 and set(names) == REQUIRED, 'all fourteen real CTests required')
    apron=apron_target(repo,build,discovery['tests'])
    scalar=local_window_target(unit_config,build,discovery['tests'])
    require(unit_auth.get('local_window_reference')==scalar,'qualified local-window scalar executable changed after authorization')
    test = next(x for x in discovery['tests'] if x['name'] == 'piston_engine_lifecycle')
    args = test['command']
    same(args[1], repo/'tests/engine/native-validate.py')
    def argument(name):
        require(args.count(name) == 1, 'missing/duplicate physical argument: ' + name)
        return args[args.index(name)+1]
    require(argument('--angular-method') == 'event_aware_coupled_midpoint_v1' and '--source-only' not in args, 'wrong physical suite mode')
    same(argument('--pretrial-ratification'), work/'pretrial.json')
    require(Path(argument('--ratification')).resolve() == (work/'physical-execution.json').resolve(), 'physical authorization route mismatch')
    same(argument('--jsbsim-dll'), unit_config['dll'])
    require(sha(unit_config['dll']) == unit_auth['dll']['sha256'], 'qualified DLL changed')
    return {'selected': selected, 'consumer': consumer, 'control': control,
            'native': argument('--native'), 'mechanism': argument('--mechanism'),
            'dll': argument('--jsbsim-dll'), 'ctests': names, 'unit_config': unit_config, 'apron_target': apron}


def physical_record(repo, work, measured):
    """Preserve the physical validator's closed eleven-field admission schema."""
    record = {'authorized': True, 'scope': 'original-piston-coupled-midpoint-v1',
              'native_sha256': sha(measured['native']), 'mechanism_sha256': sha(measured['mechanism']),
              'jsbsim_dll_sha256': sha(measured['dll']), 'limits_sha256': LIMITS,
              'source_fingerprint': measured['consumer'],
              'backend_identity_sha256': measured['selected']['backend_identity_sha256'],
              'model_inventory_sha256': INVENTORY,
              'suite_source_sha256': {name: sha(repo/'tests/engine'/name) for name in SUITE},
              'pretrial_ratification_sha256': sha(work/'pretrial.json')}
    require(set(record) == AUTH_KEYS, 'physical authorization schema changed')
    return record


def authorize(repo, work, approved):
    require(approved, 'physical authorization requires explicit --approve-execution')
    measured = qualify(repo, work)
    record = physical_record(repo, work, measured)
    save(work/'physical-execution.json', record)
    save(work/'evidence/qualification.json', {'passed': True, 'scope': 'measured source/build identities before execution',
         'backend_identity_sha256': record['backend_identity_sha256'], 'build_control_sha256': measured['control'],
         'consumer_fingerprint': measured['consumer'], 'physical_authorization_sha256': sha(work/'physical-execution.json'),
         'unit_authorization_sha256': sha(work/'unit-execution.json'), 'ctests': measured['ctests'],
         'apron_target': measured['apron_target']})


def check_unit_receipt(directory, receipt, auth, auth_path):
    require(receipt['identities_passed'] is True and receipt['failures'] == [] and
            receipt['authorization_sha256'] == sha(auth_path) and
            receipt['authorized_source_binding_sha256'] == auth['source_manifest_sha256'] and
            receipt['packet_sha256'] == auth['packet_sha256'], 'unit execution receipt provenance failed')
    same(receipt['dll_path'], auth['dll']['path'])
    require(receipt['dll_sha256_before'] == receipt['dll_sha256_after'] == auth['dll']['sha256'], 'unit DLL identity failed')
    require(set(receipt['children']) == {'kernel', 'library', 'chronology', 'terminal'}, 'unit child roster')
    for label, child in receipt['children'].items():
        same(child['executable_path'], auth['executables'][label]['path'])
        require(type(child['exit_code']) is int and child['exit_code'] == 0, 'unit child exit failure')
        require(child['executable_sha256_before'] == child['executable_sha256_after'] == auth['executables'][label]['sha256'] and
                child['dll_sha256_before'] == child['dll_sha256_after'] == auth['dll']['sha256'], 'unit child identity failed')
        for stream in ('stdout', 'stderr'):
            require(sha(directory/(label+'.'+stream)) == child[stream+'_sha256'], 'unit child evidence changed')
        if label != 'kernel':
            same(child['actual_loaded_library_path'], auth['dll']['path'])
            require(child['actual_module_sha256'] == auth['dll']['sha256'], 'unit actual loaded module failed')


def complete_ctests(text):
    expected=REQUIRED
    rows=re.findall(r'^\s*(\d+)/14 Test\s+#\d+:\s+([a-z_]+)\s+\.{2,}\s+Passed\b.*$',text,re.M)
    require(len(rows)==14 and {int(row[0]) for row in rows}==set(range(1,15)) and {row[1] for row in rows}==expected,'fourteen unique actual passed CTests required')
    require('100% tests passed, 0 tests failed out of 14' in text,'full CTest success summary required')


def verify(repo, work):
    measured = qualify(repo, work)
    auth = load(work/'physical-execution.json')
    require(auth == physical_record(repo, work, measured), 'physical authorization no longer matches current measured inputs')
    require(load(work/'evidence/qualification.json')['apron_target'] == measured['apron_target'],
            'actual apron executable changed after authorization')
    complete_ctests((work/'build/native-ctest.log').read_text(encoding='utf-8'))
    physical_paths = list((work/'build/piston-engine-proof').glob('run-*/suite-receipt.json'))
    unit_paths = list((work/'build/coupled-unit-proof').glob('run-*/validation-result.json'))
    require(len(physical_paths) == len(unit_paths) == 1, 'one complete fresh physical/unit trial required')
    physical, unit = load(physical_paths[0]), load(unit_paths[0])
    require(physical['passed'] is True and physical['failed_checks'] == 0 and physical['checks'] > 0 and
            physical['skipped_cases'] == [] and physical['skipped_comparisons'] == [] and
            physical['dependent_comparisons_skipped'] is False and len(physical['processes']) == 12,
            'original twelve-process physical gate failed or skipped')
    require(physical['limits_sha256'] == LIMITS and physical['ratification_sha256'] == sha(work/'physical-execution.json') and
            physical['angular_integration_method'] == 'event_aware_coupled_midpoint_v1', 'physical receipt identity mismatch')
    require(unit['passed'] is True and unit['native_rows'] == 137 and unit['legacy_checks'] == 270 and unit['actual_chronology_rows'] == 12,
            'isolated unit/default/chronology gate failed')
    unit_auth = load(work/'unit-execution.json')
    execution = load(unit_paths[0].parent/'execution-receipt.json')
    check_unit_receipt(unit_paths[0].parent, execution, unit_auth, work/'unit-execution.json')
    require(unit['packet_sha256'] == unit_auth['packet_sha256'] and
            unit['source_binding_sha256'] == unit_auth['source_manifest_sha256'], 'unit result source/reference mismatch')
    save(work/'evidence/ci-result.json', {'passed': True, 'scope': 'coupled headless CI, not aircraft or phase acceptance',
         'physical_receipt_sha256': sha(physical_paths[0]), 'unit_result_sha256': sha(unit_paths[0]),
         'physical_checks': physical['checks'], 'physical_processes': 12, 'ctests': 14, 'skipped': False,
         'native_rows': 137, 'legacy_checks': 270, 'actual_chronology_rows': 12})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('pretrial', 'authorize', 'verify'))
    parser.add_argument('--repository-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--work-root', type=Path, required=True)
    parser.add_argument('--approve-execution', action='store_true')
    args = parser.parse_args()
    repo, work = args.repository_root.resolve(), args.work_root.resolve()
    if args.mode == 'pretrial':
        pretrial(repo, work)
    elif args.mode == 'authorize':
        authorize(repo, work, args.approve_execution)
    else:
        verify(repo, work)


if __name__ == '__main__':
    main()
