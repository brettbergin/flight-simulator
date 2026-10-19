"""Offline synthetic ADR016 qualification tests; no real compiler/native/Godot."""
import copy
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('preview_native_identity', Path(__file__).with_name('native-identity.py'))
n = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(n)
WORKSPACE = Path(__file__).resolve().parents[2] / '.local/native-identity-synthetic'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def put(root, name, raw):
    file = root / name
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(raw.encode() if isinstance(raw, str) else raw)


# Fixed independently from ADR016: original fifteen-source prefix, then
# exactly ten bridge/helper sources. Do not derive expected paths from n.SOURCES.
EXPECTED_SOURCE_PATHS = (
    'native/fdm_jsbsim/interactive/src/session.cpp',
    'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp',
    'native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp',
    'tests/interactive/native.cpp',
    'tests/interactive/negatives.hpp',
    'native/fdm_jsbsim/interactive/src/model-pins.hpp',
    'native/fdm_jsbsim/interactive/src/piston-model-pins.hpp',
    'tests/engine/CMakeLists.txt',
    'tests/engine/loaded-library.hpp',
    'tests/engine/native.cpp',
    'tests/engine/native-mechanism.cpp',
    'tests/engine/native-validate.py',
    'tests/engine/native-generate.py',
    'tests/engine/native-limits.hpp',
    'tests/engine/native-limits.json',
    'native/godot_bridge/src/bridge.cpp',
    'native/godot_bridge/src/codec.hpp',
    'native/godot_bridge/src/codec.cpp',
    'native/godot_bridge/src/worker.hpp',
    'native/godot_bridge/src/worker.cpp',
    'native/godot_bridge/src/interactive_worker.hpp',
    'native/godot_bridge/src/interactive_worker.cpp',
    'native/godot_bridge/src/interactive_bridge.cpp',
    'native/godot_bridge/src/wire_numbers.hpp',
    'native/godot_bridge/src/wire_numbers.cpp',
)


# Independent authored roster, not derived from reconstruction_paths.
EXPECTED_CAMERA_RECONSTRUCTION_PATHS = (
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
)


# Explicit synthetic authoring paths, independent of the reconstruction walker.
EXPECTED_TAXI_RECONSTRUCTION_PATHS = (
    'app/world/taxi/taxi_layout.gd',
    'app/world/taxi/taxi_navigation.gd',
    'app/ui/taxi/taxi_panel.gd',
    'tests/world/taxi/reference/synthetic.json',
    'tests/integration/taxi/scene_checks.gd',
)

# Independently authored four-unit order from the checked runtime contract.
EXPECTED_RESIDENT_UNITS = (
    'native/world_core/grid/src/validation.cpp',
    'native/world_core/grid/src/prepared_grid.cpp',
    'native/world_core/grid/src/grid_payload.cpp',
    'native/fdm_jsbsim/interactive/src/prepared_world.cpp',
)


def fixture(root, family='MSVC', variant=n.VARIANTS[0]):
    repo, build = root / 'repo', root / 'build'
    repo.mkdir(); build.mkdir()
    for name in set(EXPECTED_SOURCE_PATHS + n.CONTROLS):
        put(repo, name, 'original synthetic source ' + name + '\r\n')
    put(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt',
        'set(INTERACTIVE_SOURCE_PATHS\n' + '\n'.join(EXPECTED_SOURCE_PATHS) + ')\n')
    put(repo, 'tools/bootstrap/source-selection.cmake',
        'set(JSBSIM_BUILD_CONTROL_PATHS\n' + '\n'.join(n.CONTROLS) + ')\n')
    put(repo, n.TEMPLATE, n.TEMPLATE_BYTES)
    # Entirely synthetic component bytes and pin; no real native/artifact proof.
    component_sources = []
    for name in EXPECTED_RESIDENT_UNITS:
        data = ('synthetic resident unit ' + name + '\n').encode()
        put(repo, name, data)
        component_sources.append(dict(path=name, sha256=sha(data)))
    component_control = 'native/world_core/grid/CMakeLists.txt'
    put(repo, component_control, 'synthetic standalone grid control\n')
    component_controls = [dict(path=component_control, sha256=sha(b'synthetic standalone grid control\n'))]
    component = dict(schema='ResidentWorldComponent/v1', sources=component_sources, controls=component_controls)
    component_raw = (json.dumps(component, indent=2) + '\n').encode()
    put(repo, 'native/world_core/resident_world/component-v1.json', component_raw)
    # Local test process only. Production uses its fixed independently reviewed
    # manifest pin and never derives a pin from a supplied candidate manifest.
    n.RESIDENT_MANIFEST_SHA256 = sha(component_raw)
    cmake = repo/'native/fdm_jsbsim/interactive/CMakeLists.txt'
    cmake.write_text(cmake.read_text() + 'set(RESIDENT_WORLD_SOURCE_PATHS\n' + '\n'.join(EXPECTED_RESIDENT_UNITS) +
                    ')\nset(RESIDENT_WORLD_CONTROL_PATHS\n' + component_control + ')\n', encoding='utf-8', newline='\n')
    resident_body = b'resident-world-component-v1\n'
    for group, records in (('source', component_sources), ('control', component_controls)):
        for item in records: resident_body += (group + ':' + item['path'] + ':' + item['sha256'] + '\n').encode('ascii')
    resident_digest = sha(resident_body)
    put(build, 'resident-world-component-fingerprint.txt', resident_digest.encode() + b'\n' + resident_body)
    for name in EXPECTED_CAMERA_RECONSTRUCTION_PATHS:
        put(repo, name, 'synthetic camera authoring ' + name + '\n')
    for name in ('app/persistence/local_players_controller.gd',
                 'app/ui/profiles/player_options.gd',
                 'app/ui/history/practice_panel.gd',
                 'tests/ui/profiles/local_players_controller_checks.gd'):
        put(repo, name, 'Synthetic local-player corresponding-source fixture ' + name + '\n')
    for name in EXPECTED_TAXI_RECONSTRUCTION_PATHS:
        put(repo, name, 'Synthetic taxi corresponding-source fixture ' + name + '\n')
    put(repo, 'app/world/terrain/resident_grid_reader.gd', 'synthetic reader source\n')
    put(repo, 'app/world/world_admission.gd', 'synthetic registry source\n')
    put(repo, 'tools/interactive-preview/world-catalog.mjs', 'synthetic catalog generator\n')
    put(repo, 'content/world/catalog/kawo-runtime-v1.json', '{}\n')
    for name in ('world.json','ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt'):
        put(repo, 'content/world/airports/kawo/runtime-v1/' + name, 'synthetic pack input ' + name + '\n')
    (repo/'deps/jsbsim').mkdir(parents=True)
    (repo/'bundle/vendor').mkdir(parents=True)
    source = repo / ('deps/jsbsim' if variant == n.VARIANTS[0] else 'bundle/vendor')
    selected = dict(source_variant=variant, source_root=str(source), backend_identity_sha256='a'*64)
    compiler = '19.40.33813.0' if family == 'MSVC' else '13.3.0'
    common = '/DWIN32 /D_WINDOWS /EHsc' if family == 'MSVC' else ''
    config = '/O2 /Ob1 /DNDEBUG' if family == 'MSVC' else '-O2 -g -DNDEBUG'
    flags = (('/fp:strict' if family == 'MSVC' else '-fno-fast-math -ffp-contract=off -frounding-math')
             if variant != n.VARIANTS[0] else '')
    values = dict(CMAKE_HOME_DIRECTORY=str(repo), CMAKE_EXPORT_COMPILE_COMMANDS='ON',
        FLIGHT_BUILD_GODOT_BINDINGS='ON', FLIGHT_USE_EVENT_AWARE_JSBSIM='OFF',
        FLIGHT_JSBSIM_VARIANT=variant.removeprefix('jsbsim-1.3.1-'),
        FLIGHT_DEPENDENCY_ROOT=str(repo/'deps'), FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT=str(repo/'bundle'),
        CMAKE_GENERATOR='Ninja', CMAKE_BUILD_TYPE='RelWithDebInfo', CMAKE_CXX_FLAGS=common,
        CMAKE_CXX_FLAGS_RELWITHDEBINFO=config, CMAKE_MSVC_RUNTIME_LIBRARY='MultiThreaded$<$<CONFIG:Debug>:Debug>DLL')
    for key, filename in (('CMAKE_CXX_COMPILER','cl.exe'),('CMAKE_AR','lib.exe'),('CMAKE_LINKER','link.exe')):
        put(build, 'fixture-tools/' + filename, 'synthetic nonexecutable tool token\n')
        values[key] = str(build/'fixture-tools'/filename)
    put(build, 'CMakeCache.txt', ''.join(k+':STRING='+v+'\n' for k,v in values.items()))
    put(build, 'CMakeFiles/3.31.6/CMakeCXXCompiler.cmake',
        'set(CMAKE_CXX_COMPILER_ID "'+family+'")\nset(CMAKE_CXX_COMPILER_VERSION "'+compiler+'")\n')
    # Independent fixture construction mirrors the accepted contract text, not
    # generated CMake output or the qualifier's build_controls/resource helpers.
    body = ''.join(p+':'+sha((repo/p).read_bytes().replace(b'\r\n',b'\n'))+'\n' for p in n.CONTROLS)
    body += ('source_variant:'+variant+'\nbackend_identity:'+'a'*64+'\ncompiler:'+family+'-'+compiler+
        '\ngenerator:Ninja\nbuild_type:RelWithDebInfo\ncxx_flags:'+common+'\nconfiguration_flags:'+config+
        '\nmsvc_runtime:MultiThreaded$<$<CONFIG:Debug>:Debug>DLL\ndeclared_strict_fp_flags:'+flags+'\n')
    control = sha(body.encode())
    body = ('verified-jsbsim-backend:'+'a'*64+'\njsbsim-build-controls:'+control+'\nresident-world-component:'+resident_digest+'\n'+
        ''.join(p+':'+sha((repo/p).read_bytes().replace(b'\r\n',b'\n'))+'\n' for p in EXPECTED_SOURCE_PATHS))
    consumer = sha(body.encode())
    put(build, 'interactive-source-fingerprint.txt', consumer+'\n'+body)
    put(build, 'jsbsim-source-build-manifest.txt', 'Source variant: '+variant+'\nSelected source root: '+source.as_posix()+
        '\nBackend identity SHA256: '+'a'*64+'\nBuild controls SHA256: '+control+'\nCompiler: '+family+' '+compiler+
        '\nGenerator: Ninja\nBuild configuration: RelWithDebInfo\nCommon CXX flags: '+common+
        '\nSelected configuration CXX flags: '+config+'\nMSVC runtime: MultiThreadedDLL\nDeclared modified-source strict FP flags: '+flags+
        '\nActual compiler commands must be inspected before numerical execution.\n')
    put(build, 'toolchain-build-manifest.txt', 'Project: synthetic not executable\nCompiler: '+family+' '+compiler+
        '\nGenerator: Ninja\nBuild type: RelWithDebInfo\nMSVC runtime: MultiThreadedDLL\n')
    command = 'fixture-compiler -D'+n.MACRO+'=\\"'+consumer+'\\" -c '+str(repo/EXPECTED_SOURCE_PATHS[0])
    put(build, 'compile_commands.json', json.dumps([dict(directory=str(build),file=str(repo/EXPECTED_SOURCE_PATHS[0]),command=command)]))
    put(build, 'build.ninja', 'DEFINES = -D'+n.MACRO+'=\\"'+consumer+'\\"\n')
    put(build, n.witness_paths(family)[0], b'not executable synthetic bridge\x00'+consumer.encode()+b'\x00')
    resource = ('extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\n'
        'const SOURCE_VARIANT: String = "'+variant+'"\nconst BACKEND_IDENTITY_SHA256: String = "'+'a'*64+
        '"\nconst BUILD_CONTROL_SHA256: String = "'+control+'"\nconst SOURCE_FINGERPRINT: String = "'+consumer+'"\n')
    put(build, n.BUILD_PATH, resource)
    return repo, build, selected, consumer


class IdentityTests(unittest.TestCase):
    def resident_graph(self):
        """Nonexecuting synthetic CMake/Ninja graph; no binary authenticity claim."""
        self.assertEqual(n.RESIDENT_UNITS, EXPECTED_RESIDENT_UNITS)
        rows = json.loads((self.build/'compile_commands.json').read_text())
        tools = n.cache_values(self.build)
        # Actual CMake has no global DEFINES. Session's edge below declares its
        # required macro; grid edges omit DEFINES entirely.
        ninja = ''
        workdir = str(self.build).replace('$','$$').replace(':','$:').replace(' ','$ ') + '/'
        ninja += ('cmake_ninja_workdir = ' + workdir + '\n'
                  'build ignored-one | ${cmake_ninja_workdir}ignored-one: CUSTOM_COMMAND\n'
                  'build ignored-two | ${cmake_ninja_workdir}ignored-two: CUSTOM_COMMAND\n')
        session_object = 'objects/session.cpp.obj'
        session_macro = '-D' + n.MACRO + '="' + self.consumer + '"'
        rows[0] = dict(directory=str(self.build), file=str(self.repo/EXPECTED_SOURCE_PATHS[0]),
                       arguments=[tools['CMAKE_CXX_COMPILER'],'/fp:strict',session_macro,'/Fo' + session_object,'-c',str(self.repo/EXPECTED_SOURCE_PATHS[0])])
        session_path = str(self.repo/EXPECTED_SOURCE_PATHS[0]).replace('$','$$').replace(':','$:').replace(' ','$ ')
        ninja += 'build ' + session_object + ': CXX_COMPILER__session ' + session_path + '\n  DEFINES = -D' + n.MACRO + '=\\"' + self.consumer + '\\"\n'
        put(self.build, session_object, 'synthetic Session object\n')
        objects = []
        for source in EXPECTED_RESIDENT_UNITS:
            output = 'objects/' + Path(source).name + '.obj'
            objects.append(output)
            args = [tools['CMAKE_CXX_COMPILER'],'/fp:strict','/Fo' + output,'-c',str(self.repo/source)]
            rows.append(dict(directory=str(self.build), file=str(self.repo/source), arguments=args))
            source_path = str(self.repo/source).replace('$','$$').replace(':','$:').replace(' ','$ ')
            ninja += 'build ' + output + ' | ${cmake_ninja_workdir}' + output + ': CXX_COMPILER__resident ' + source_path + '\n'
            put(self.build, output, 'synthetic object ' + source + '\n')
        for output, inputs in (('lib/flight_resident_grid.lib', objects[:3]), ('lib/flight_interactive.lib', [session_object] + objects[3:])):
            ninja += ('build ' + output + ': CXX_STATIC_LIBRARY_LINKER__resident ' + ' '.join(inputs) +
                      '\n  TARGET_FILE = ' + output + '\n  PRE_LINK = cd .\n  POST_BUILD = cd .\n')
            # Independent literal ordinary-ar construction, never an archiver.
            def member(name, data):
                header = (name.ljust(16) + '0'.ljust(12) + '0'.ljust(6) + '0'.ljust(6) +
                          '100644'.ljust(8) + str(len(data)).ljust(10) + '`\n').encode('ascii')
                return header + data + (b'\n' if len(data) % 2 else b'')
            names, offsets = b'', []
            for filename in inputs:
                offsets.append(len(names))
                names += Path(filename).name.encode() + b'/\n'
            raw = b'!<arch>\n' + member('//', names)
            for offset, filename in zip(offsets, inputs): raw += member('/' + str(offset), (self.build/filename).read_bytes())
            put(self.build, output, raw)
        ninja += ('build bin/flight_godot_bridge.dll: CXX_SHARED_LIBRARY_LINKER__resident | lib/flight_interactive.lib lib/flight_resident_grid.lib\n'
                  '  TARGET_FILE = bin/flight_godot_bridge.dll\n  PRE_LINK = cd .\n  POST_BUILD = cd .\n'
                  '  LINK_LIBRARIES = lib/flight_interactive.lib lib/flight_resident_grid.lib\n')
        put(self.build, 'build.ninja', ninja)
        put(self.build, 'compile_commands.json', json.dumps(rows))
        put(self.build, 'CMakeFiles/rules.ninja',
            'rule CXX_COMPILER__session\n  command = "' + tools['CMAKE_CXX_COMPILER'] + '" /fp:strict $DEFINES /showIncludes /Fo$out -c $in\n'
            'rule CXX_COMPILER__resident\n  command = "' + tools['CMAKE_CXX_COMPILER'] + '" $DEFINES /fp:strict /showIncludes /Fo$out -c $in\n'
            'rule CXX_STATIC_LIBRARY_LINKER__resident\n  command = cmd.exe /C "$PRE_LINK && "' + tools['CMAKE_AR'] + '" /out:$TARGET_FILE $in && $POST_BUILD"\n'
            'rule CXX_SHARED_LIBRARY_LINKER__resident\n  command = cmd.exe /C "$PRE_LINK && "' + tools['CMAKE_LINKER'] + '" $MANIFESTS $LINK_PATH /out:$TARGET_FILE $in $LINK_LIBRARIES && $POST_BUILD"\n')
        return rows, objects

    def test_resident_component_and_exact_inserted_line(self):
        good = self.qualify()
        self.assertEqual(len(good['source_bindings']), 25)
        self.assertEqual(len(good['build_witnesses']), 7)
        raw = (self.build/'interactive-source-fingerprint.txt').read_bytes()
        lines = raw.splitlines()
        self.assertEqual(lines[3].split(b':')[0], b'resident-world-component')
        for name in EXPECTED_RESIDENT_UNITS:
            target = self.repo/name; original = target.read_bytes()
            target.write_bytes(original + b'changed\n')
            try:
                with self.assertRaises(ValueError): self.qualify()
            finally: target.write_bytes(original)
        manifest = self.repo/'native/world_core/resident_world/component-v1.json'
        before = manifest.read_bytes()
        manifest.write_bytes(before + b'\n')
        try:
            with self.assertRaises(ValueError): self.qualify()
        finally: manifest.write_bytes(before)

    def test_resident_component_generated_witness_platform_newlines(self):
        self.resident_graph()
        identity = self.qualify()
        identity_raw = json.dumps(identity).encode()
        expected = n.resident_closure(self.repo, self.build, identity_raw, identity)
        witness = self.build/'resident-world-component-fingerprint.txt'
        original = witness.read_bytes()
        witness.write_bytes(original.replace(b'\n', b'\r\n'))
        try:
            self.assertEqual(self.qualify(), identity)
            self.assertEqual(n.resident_closure(self.repo, self.build, identity_raw, identity), expected)
            witness.write_bytes(witness.read_bytes().replace(b'resident-world-component-v1', b'resident-world-component-X1', 1))
            with self.assertRaises(ValueError): self.qualify()
            with self.assertRaises(ValueError): n.resident_closure(self.repo, self.build, identity_raw, identity)
        finally: witness.write_bytes(original)

    def test_resident_actual_graph_observation_and_negative_flags_links(self):
        rows, objects = self.resident_graph()
        identity = self.qualify()
        identity_raw = (json.dumps(identity, indent=2) + '\n').encode()
        result = n.resident_closure(self.repo, self.build, identity_raw, identity)
        self.assertEqual(result['schema'], 'ResidentWorldNativeClosure/v1')
        self.assertEqual([row['source'] for row in result['translation_units']], list(EXPECTED_RESIDENT_UNITS))
        self.assertEqual([row['object_path'] for row in result['translation_units']], objects)
        self.assertEqual(result['link']['grid_archive']['path'], 'lib/flight_resident_grid.lib')
        self.assertEqual(result['native_identity']['sha256'], sha(identity_raw))
        self.assertEqual(result['build_witnesses'], identity['build_witnesses'])
        original = (self.build/'CMakeFiles/rules.ninja').read_bytes()
        for changed in (original.replace(b'/fp:strict', b'/fp:fast'),
                        original.replace(b'$LINK_LIBRARIES', b''),
                        original.replace(b' /out:$TARGET_FILE $in && ', b' /out:$TARGET_FILE && '),
                        original.replace(b' /fp:strict', b' $UNDECLARED /fp:strict'),
                        original.replace(b'/showIncludes', b'/showIncludes /showIncludes'),
                        original.replace(b'/out:$TARGET_FILE $in &&', b'/out:bin/flight_godot_bridge.dll $in &&'),
                        original.replace(b'/out:$TARGET_FILE $in $LINK_LIBRARIES', b'/out:lib/flight_interactive.lib $in $LINK_LIBRARIES'),
                        original.replace(b'/out:$TARGET_FILE', b'/out:$TARGET_FILE /out:lib/flight_interactive.lib')):
            (self.build/'CMakeFiles/rules.ninja').write_bytes(changed)
            try:
                with self.assertRaises(ValueError): n.resident_closure(self.repo, self.build, identity_raw, identity)
            finally: (self.build/'CMakeFiles/rules.ninja').write_bytes(original)
        archive = self.build/'lib/flight_resident_grid.lib'; before = archive.read_bytes()
        archive.write_bytes(before.replace(b'synthetic object', b'synthetic OBJECT', 1))
        try:
            with self.assertRaises(ValueError): n.resident_closure(self.repo, self.build, identity_raw, identity)
        finally: archive.write_bytes(before)
        # New unit duplicated under another output must fail exact row ownership.
        duplicate = dict(rows[1], arguments=list(rows[1]['arguments']))
        duplicate['arguments'][2] = '/Foobjects/competing.obj'
        put(self.build, 'compile_commands.json', json.dumps(rows + [duplicate]))
        put(self.build, 'objects/competing.obj', 'synthetic competing object\n')
        changed_identity = self.qualify()
        with self.assertRaises(ValueError):
            n.resident_closure(self.repo, self.build, json.dumps(changed_identity).encode(), changed_identity)

    def test_resident_strict_json_and_command_readers(self):
        for raw in (b'{"a":1,"a":2}', b'\xef\xbb\xbf{}', b'{"x":NaN}', b'{"x":1e999}', b'{"a":1,}', b'[] []'):
            with self.assertRaises((ValueError, UnicodeError)): n.strict_json(raw, 100, 4, 20)
        with self.assertRaises(ValueError): n.strict_json(b'[[[[[]]]]]', 100, 3, 20)
        with self.assertRaises(ValueError): n.strict_json(b'[0,0,0]', 100, 4, 3)
        self.assertEqual(n.windows_arguments('cl.exe "a b" /Fo"objects/a b.obj"'), ['cl.exe','a b','/Foobjects/a b.obj'])
        with self.assertRaises(ValueError): n.windows_arguments('cl.exe "unfinished')

    def test_resident_dependency_flag_not_a_general_argument_waiver(self):
        rows, _ = self.resident_graph()
        # The valid fixture already has one actual Ninja-only /showIncludes.
        # A repeated declared instrumentation flag is refused independently.
        rows[1]['arguments'][1:1] = ['/showIncludes','/showIncludes']
        put(self.build, 'compile_commands.json', json.dumps(rows))
        identity = self.qualify()
        with self.assertRaises(ValueError):
            n.resident_closure(self.repo, self.build, json.dumps(identity).encode(), identity)

    def test_resident_extra_ordinary_source_is_not_a_slash_option(self):
        rows, _ = self.resident_graph()
        rows[1]['arguments'].insert(-2, str(self.repo/EXPECTED_SOURCE_PATHS[0]))
        put(self.build, 'compile_commands.json', json.dumps(rows))
        identity = self.qualify()
        with self.assertRaisesRegex(ValueError, 'source operand'):
            n.resident_closure(self.repo, self.build, json.dumps(identity).encode(), identity)

    def test_resident_implicit_aliases_do_not_admit_double_owners_or_variables(self):
        self.resident_graph()
        ninja = (self.build/'build.ninja').read_text()
        for changed in (ninja + 'build objects/validation.cpp.obj: CUSTOM_COMMAND\n',
                        ninja.replace('build ignored-one | ', 'build ignored-one | extra | ', 1),
                        ninja.replace('${cmake_ninja_workdir}', '${unadmitted_workdir}'),
                        re.sub(r'^cmake_ninja_workdir =.*$', lambda _: 'cmake_ninja_workdir = ' + str(self.repo).replace('$','$$').replace(':','$:').replace(' ','$ ') + '/', ninja, flags=re.M)):
            put(self.build, 'build.ninja', changed)
            try:
                identity = self.qualify()
                with self.assertRaises(ValueError): n.resident_closure(self.repo, self.build, json.dumps(identity).encode(), identity)
            finally: put(self.build, 'build.ninja', ninja)

    def test_resident_rejects_metadata_only_source_and_wrong_ninja_dependency(self):
        rows, objects = self.resident_graph()
        ninja = (self.build/'build.ninja').read_text()
        rules = (self.build/'CMakeFiles/rules.ninja').read_text()
        source = EXPECTED_RESIDENT_UNITS[0]
        wrong = EXPECTED_SOURCE_PATHS[0]
        encode = lambda name: str(self.repo/name).replace('$','$$').replace(':','$:').replace(' ','$ ')
        output_prefix = 'build ' + objects[0] + ' | ${cmake_ninja_workdir}' + objects[0] + ': '
        old_edge = output_prefix + 'CXX_COMPILER__resident ' + encode(source)
        self.assertIn(old_edge, ninja)
        for case in ('crossed_command_and_edge', 'wrong_edge_ignored_by_literal_rule'):
            changed_rows = copy.deepcopy(rows)
            changed_rules = rules
            if case == 'crossed_command_and_edge':
                # file metadata still says validation.cpp; both actual command
                # and graph instead compile Session. Matching arrays is no proof.
                changed_rows[1]['arguments'][-1] = str(self.repo/wrong)
                changed_ninja = ninja.replace(old_edge, output_prefix + 'CXX_COMPILER__resident ' + encode(wrong), 1)
            else:
                changed_ninja = ninja.replace(old_edge, output_prefix + 'CXX_COMPILER__literal ' + encode(wrong), 1)
                compiler = n.cache_values(self.build)['CMAKE_CXX_COMPILER']
                changed_rules += ('rule CXX_COMPILER__literal\n  command = "' + compiler + '" /fp:strict /Fo$out -c "' + str(self.repo/source) + '"\n')
            put(self.build, 'compile_commands.json', json.dumps(changed_rows))
            put(self.build, 'build.ninja', changed_ninja)
            put(self.build, 'CMakeFiles/rules.ninja', changed_rules)
            try:
                identity = self.qualify()
                with self.subTest(case=case), self.assertRaises(ValueError):
                    n.resident_closure(self.repo, self.build, json.dumps(identity).encode(), identity)
            finally:
                put(self.build, 'compile_commands.json', json.dumps(rows))
                put(self.build, 'build.ninja', ninja)
                put(self.build, 'CMakeFiles/rules.ninja', rules)

    def test_local_window_explicit_controls_and_variant_rosters(self):
        self.assertEqual(n.CONTROLS, ('CMakeLists.txt', 'CMakePresets.json', 'third_party/dependencies.lock.json', 'tools/bootstrap/source-selection.cmake', 'tools/bootstrap/source-variant.py', 'tools/bootstrap/coupled-source-variant.py', 'tools/bootstrap/build.ps1', 'tools/bootstrap/bootstrap.py', 'native/fdm_jsbsim/CMakeLists.txt', 'native/fdm_jsbsim/ground/CMakeLists.txt', 'native/fdm_jsbsim/interactive/CMakeLists.txt', 'tests/fdm/CMakeLists.txt', 'native/fdm_jsbsim/interactive/native_identity.gd.in', 'native/godot_bridge/CMakeLists.txt', 'tests/wire_codec/CMakeLists.txt', 'tools/bootstrap/coupled-local-window-source-variant.py', 'tools/bootstrap/build-local-window.ps1', 'tests/engine/local-window-v2/CMakeLists.txt'))
        self.assertEqual(n.VARIANTS, ('jsbsim-1.3.1-upstream', 'jsbsim-1.3.1-event-aware-constant-power-v1', 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1', 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'))
        values=n.cache_values(self.build)
        self.assertEqual(n.route(dict(values,FLIGHT_JSBSIM_VARIANT='event-aware-coupled-midpoint-local-window-v2')), 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2')
        for selected in ('event-aware-coupled-midpoint-local-window-v1','event-aware-coupled-midpoint-v2','event-aware-coupled-midpoint-local-window-v3'):
            with self.assertRaises(ValueError):n.route(dict(values,FLIGHT_JSBSIM_VARIANT=selected))
        with self.assertRaises(ValueError):n.route(dict(values,FLIGHT_JSBSIM_VARIANT='event-aware-coupled-midpoint-local-window-v2',FLIGHT_USE_EVENT_AWARE_JSBSIM='ON'))

    def setUp(self):
        WORKSPACE.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='case-', dir=WORKSPACE)
        self.root = Path(self.temp.name)
        self.repo, self.build, self.selected, self.consumer = fixture(self.root)


    def test_repository_reconstruction_excludes_only_python_caches(self):
        for folder in ('native', 'tests/engine', 'tests/interactive', 'tools/bootstrap'):
            (self.repo/folder).mkdir(parents=True, exist_ok=True)
        put(self.repo, 'tests/engine/keep.py', 'source fixture\n')
        put(self.repo, 'tests/engine/keep.pyc.txt', 'ordinary authored fixture\n')
        put(self.repo, 'tests/engine/__pycache__/cached.pyc', 'cache artifact\n')
        put(self.repo, 'native/cached.pyc', 'cache artifact\n')
        put(self.repo, 'tools/bootstrap/__pycache__/nested/ordinary.txt', 'cache-tree artifact\n')
        names = n.reconstruction_paths(self.repo)
        self.assertIn('tests/engine/keep.py', names)
        self.assertIn('tests/engine/keep.pyc.txt', names)
        self.assertNotIn('tests/engine/__pycache__/cached.pyc', names)
        self.assertNotIn('native/cached.pyc', names)
        self.assertNotIn('tools/bootstrap/__pycache__/nested/ordinary.txt', names)
        self.assertTrue(set(n.SOURCES+n.CONTROLS) <= set(names))

    def tearDown(self):
        self.temp.cleanup()

    def qualify(self):
        return n.qualify(self.repo, self.build, lambda *_: self.selected)

    def test_windows_linux_all_closed_routes(self):
        expected_variants = (
            'jsbsim-1.3.1-upstream',
            'jsbsim-1.3.1-event-aware-constant-power-v1',
            'jsbsim-1.3.1-event-aware-coupled-midpoint-v1',
            'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2',
        )
        self.assertEqual(n.VARIANTS, expected_variants)
        fingerprints = []
        for i, (family, variant) in enumerate((f,v) for f in ('MSVC','GNU') for v in n.VARIANTS):
            root=self.root/str(i);root.mkdir()
            repo, build, selected, expected = fixture(root,family,variant)
            result = n.qualify(repo,build,lambda *_:selected)
            self.assertEqual(result['declared_source_fingerprint'],expected)
            self.assertEqual(n.SOURCES, EXPECTED_SOURCE_PATHS)
            self.assertEqual(tuple(row['path'] for row in result['source_bindings']), EXPECTED_SOURCE_PATHS)
            self.assertEqual(tuple(row['path'] for row in result['build_witnesses']), (
                'bin/flight_godot_bridge.dll' if family == 'MSVC' else 'bin/libflight_godot_bridge.so',
                'build.ninja', 'CMakeCache.txt', 'toolchain-build-manifest.txt',
                'jsbsim-source-build-manifest.txt', 'interactive-source-fingerprint.txt',
                'compile_commands.json'))
            fingerprints.append(expected)
        self.assertEqual(len(set(fingerprints)),8)

    def test_number_helper_missing_and_changed_source(self):
        for name in EXPECTED_SOURCE_PATHS[-2:]:
            path = self.repo/name; old = path.read_bytes()
            with self.subTest(path=name, mutation='missing'):
                path.unlink()
                try:
                    with self.assertRaises((ValueError, FileNotFoundError)): self.qualify()
                finally:
                    path.write_bytes(old)
            with self.subTest(path=name, mutation='changed'):
                path.write_bytes(old+b'changed helper source')
                try:
                    with self.assertRaises(ValueError): self.qualify()
                finally:
                    path.write_bytes(old)

    def test_number_helper_declared_and_evidence_roster(self):
        good = self.qualify()
        path = self.repo/'native/fdm_jsbsim/interactive/CMakeLists.txt'
        old = path.read_bytes()
        for mutation in ('omit-header', 'omit-implementation', 'swap-helpers'):
            paths = list(EXPECTED_SOURCE_PATHS)
            rows = copy.deepcopy(good['source_bindings'])
            if mutation == 'swap-helpers':
                paths[-2], paths[-1] = paths[-1], paths[-2]
                rows[-2], rows[-1] = rows[-1], rows[-2]
            else:
                index = -2 if mutation == 'omit-header' else -1
                paths.pop(index); rows.pop(index)
            with self.subTest(mutation=mutation):
                bad = copy.deepcopy(good); bad['source_bindings'] = rows
                with self.assertRaises(ValueError): n.validate_evidence(bad)
                put(self.repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt',
                    'set(INTERACTIVE_SOURCE_PATHS\n'+'\n'.join(paths)+')\n')
                try:
                    with self.assertRaises(ValueError): self.qualify()
                finally:
                    path.write_bytes(old)

    def test_v2_exact_shapes_types_and_order(self):
        good=self.qualify();n.validate_evidence(good)
        bads=[]
        for key in good:
            bad=copy.deepcopy(good);del bad[key];bads.append(bad)
        for key,value in [('schema','historical'),('source_variant','unknown'),('backend_identity_sha256','A'*64),('root','relative')]:
            bad=copy.deepcopy(good);bad[key]=value;bads.append(bad)
        bad=copy.deepcopy(good);bad['extra']=True;bads.append(bad)
        for group in ('source_bindings','build_witnesses'):
            for change in ('omit','extra','order','bool','negative','field'):
                bad=copy.deepcopy(good)
                if change=='omit':bad[group].pop()
                elif change=='extra':bad[group].append(copy.deepcopy(bad[group][0]))
                elif change=='order':bad[group][0],bad[group][1]=bad[group][1],bad[group][0]
                elif change=='bool':bad[group][0]['bytes']=True
                elif change=='negative':bad[group][0]['bytes']=-1
                else:bad[group][0]['extra']=True
                bads.append(bad)
        for key,value in [('build_path','../native-identity.gd'),('staged_path','simulation/native_identity.gd'),('bytes',True),('bytes',0),('sha256','b'*64)]:
            bad=copy.deepcopy(good);bad['resource'][key]=value;bads.append(bad)
        for bad in bads:
            with self.subTest(bad=repr(bad)[:80]),self.assertRaises((ValueError,TypeError)):
                n.validate_evidence(bad)

    def test_resource_grammar_and_stale_bytes(self):
        path=self.build/n.BUILD_PATH;old=path.read_bytes()
        for raw in (b'\xef\xbb\xbf'+old,old.replace(b'\n',b'\r\n'),old[:-1],old+b'\n',old+b'func injected(): pass\n',old.replace(self.consumer.encode(),b'b'*64)):
            path.write_bytes(raw)
            with self.assertRaises(ValueError):self.qualify()
        path.write_bytes(old)

    def test_crlf_fingerprint_manifest_preserves_identity_but_resource_is_raw(self):
        for family in ('MSVC','GNU'):
            root=self.root/('crlf-'+family);root.mkdir()
            repo,build,selected,expected=fixture(root,family)
            original=n.qualify(repo,build,lambda *_:selected)
            manifest=build/'interactive-source-fingerprint.txt';raw=manifest.read_bytes()
            manifest.write_bytes(raw.replace(b'\n',b'\r\n'))
            actual=n.qualify(repo,build,lambda *_:selected)
            self.assertEqual(actual['declared_source_fingerprint'],expected)
            self.assertEqual(actual['resource'],original['resource'])
            # Evidence still records the actual CRLF witness bytes; only the
            # semantic metadata comparison normalizes platform line endings.
            witness=next(row for row in actual['build_witnesses'] if row['path']=='interactive-source-fingerprint.txt')
            self.assertEqual(witness['sha256'],sha(manifest.read_bytes()))
            self.assertNotEqual(witness['sha256'],sha(raw))
            manifest.write_bytes(manifest.read_bytes().replace(expected.encode(),b'b'*64,1))
            with self.assertRaises(ValueError):n.qualify(repo,build,lambda *_:selected)
            manifest.write_bytes(raw.replace(b'\n',b'\r\n'))
            resource=build/n.BUILD_PATH;resource.write_bytes(resource.read_bytes().replace(b'\n',b'\r\n'))
            with self.assertRaises(ValueError):n.qualify(repo,build,lambda *_:selected)

    def test_changed_source_controls_template_and_backend(self):
        for name in (n.SOURCES[0],n.CONTROLS[0],n.TEMPLATE):
            path=self.repo/name;old=path.read_bytes();path.write_bytes(old+b'changed')
            with self.assertRaises(ValueError):self.qualify()
            path.write_bytes(old)
        self.selected['backend_identity_sha256']='b'*64
        with self.assertRaises(ValueError):self.qualify()

    def test_closed_cmake_rosters(self):
        for name,word in [('native/fdm_jsbsim/interactive/CMakeLists.txt',n.SOURCES[-1]),('tools/bootstrap/source-selection.cmake',n.CONTROLS[-1])]:
            path=self.repo/name;old=path.read_text();put(self.repo,name,old.replace(word,'unknown/path'))
            with self.assertRaises(ValueError):self.qualify()
            put(self.repo,name,old+old)
            with self.assertRaises(ValueError):self.qualify()
            put(self.repo,name,old)

    def test_cache_compiler_manifest_drift_and_duplicate(self):
        for name in ('CMakeCache.txt','CMakeFiles/3.31.6/CMakeCXXCompiler.cmake','toolchain-build-manifest.txt','jsbsim-source-build-manifest.txt','interactive-source-fingerprint.txt'):
            path=self.build/name;old=path.read_bytes()
            path.write_bytes(old.replace(b'RelWithDebInfo',b'Release') if b'RelWithDebInfo' in old else old.replace(b'19.40.33813.0',b'19.40.99999.0') if b'19.40.33813.0' in old else b'changed\n'+old)
            with self.assertRaises((ValueError,KeyError)):self.qualify()
            path.write_bytes(old)
        path=self.build/'CMakeCache.txt';old=path.read_bytes();path.write_bytes(old+b'CMAKE_GENERATOR:STRING=Ninja\n')
        with self.assertRaises(ValueError):self.qualify()
        path.write_bytes(old)
        for name in ('CL','_CL_'):
            with patch.dict(os.environ,{name:'/DUNDECLARED'}):
                with self.assertRaises(ValueError):self.qualify()

    def test_missing_witness_and_changed_bridge(self):
        for name in n.witness_paths('MSVC'):
            path=self.build/name;old=path.read_bytes();path.unlink()
            with self.assertRaises((ValueError,FileNotFoundError)):self.qualify()
            path.write_bytes(old)
        put(self.build,n.witness_paths('MSVC')[0],b'bridge without identity')
        with self.assertRaises(ValueError):self.qualify()

    def test_per_command_definition_uniqueness_and_conflicts(self):
        path=self.build/'compile_commands.json';old=json.loads(path.read_text());command=old[0]['command']
        for text in (command+' -D'+n.MACRO+'='+self.consumer,
                     command+' -D'+n.MACRO+'='+'b'*64,
                     command.replace(self.consumer,'b'*64),command.replace(n.MACRO,'OTHER'),
                     command.replace(self.consumer,'A'*64),command.replace(self.consumer,'a'*63)):
            row=copy.deepcopy(old);row[0]['command']=text;path.write_text(json.dumps(row))
            with self.assertRaises(ValueError):self.qualify()
        path.write_text(json.dumps(old+old))
        with self.assertRaises(ValueError):self.qualify()
        row=copy.deepcopy(old);row[0]['arguments']=['fixture', '-D'+n.MACRO+'='+self.consumer];path.write_text(json.dumps(row))
        with self.assertRaises(ValueError):self.qualify()
        del row[0]['command'];path.write_text(json.dumps(row));self.qualify()

    def test_ninja_duplicate_and_conflicting_definitions(self):
        path=self.build/'build.ninja';old=path.read_text()
        for value in (old.strip()+' -D'+n.MACRO+'='+self.consumer+'\n',old+old.replace(self.consumer,'b'*64),old.replace(self.consumer,'b'*64)):
            path.write_text(value)
            with self.assertRaises(ValueError):self.qualify()

    def test_definition_complete_value_and_argument_boundaries(self):
        macro='-D'+n.MACRO+'='
        for value in (self.consumer,'"'+self.consumer+'"','\\"'+self.consumer+'\\"'):
            self.assertEqual(n.definitions('fixture '+macro+value+' -c file'),[self.consumer])
            self.assertEqual(n.definitions(['fixture',macro+value,'-c','file']),[self.consumer])
        # A quoted/escaped closing delimiter must be consumed in full. Neither
        # adjacent string literals nor suffixes may masquerade as the digest.
        malformed=(self.consumer+'suffix',self.consumer+'"suffix',
            '"'+self.consumer+'"suffix','"'+self.consumer+'""other"',
            '\\"'+self.consumer+'\\"suffix','\\"'+self.consumer+'\\"\\"other\\"',
            '"'+self.consumer,'\\"'+self.consumer,self.consumer+'"',
            self.consumer+'\\"','\\\\"'+self.consumer+'\\\\"')
        for value in malformed:
            for text in ('fixture '+macro+value+' -c file',['fixture',macro+value,'-c','file']):
                with self.subTest(value=value,text=type(text).__name__),self.assertRaises(ValueError):n.definitions(text)
        # Joining arguments would hide a suffix after whitespace in one value.
        with self.assertRaises(ValueError):n.definitions(['fixture',macro+self.consumer+' suffix'])
        for text in ('fixture '+macro+self.consumer+' '+macro+self.consumer,
                     ['fixture',macro+self.consumer,macro+self.consumer]):
            with self.assertRaises(ValueError):n.definitions(text)

    def test_malformed_compiler_identity_rejected_in_both_witnesses(self):
        path=self.build/'compile_commands.json';old=json.loads(path.read_text())
        row=copy.deepcopy(old);row[0]['command']=old[0]['command'].replace(self.consumer+'\\"',self.consumer+'\\"suffix')
        path.write_text(json.dumps(row))
        with self.assertRaises(ValueError):self.qualify()
        path.write_text(json.dumps(old))
        ninja=self.build/'build.ninja';ninja.write_text(ninja.read_text().replace(self.consumer+'\\"',self.consumer+'\\"\\"adjacent\\"'))
        with self.assertRaises(ValueError):self.qualify()

    def test_selector_route_consistency(self):
        values=n.cache_values(self.build)
        for change in ({'FLIGHT_JSBSIM_VARIANT':'unknown'},{'FLIGHT_JSBSIM_VARIANT':'event-aware-coupled-midpoint-v1','FLIGHT_USE_EVENT_AWARE_JSBSIM':'ON'},{'FLIGHT_USE_EVENT_AWARE_JSBSIM':'maybe'}):
            with self.assertRaises(ValueError):n.route(dict(values,**change))
        self.selected['source_variant']=n.VARIANTS[2]
        with self.assertRaises(ValueError):self.qualify()

    def test_selector_subprocess_uses_closed_route_workspace_scratch(self):
        for i,variant in enumerate(n.VARIANTS):
            root=self.root/('selector'+str(i));root.mkdir();repo,build,selected,_=fixture(root,variant=variant)
            def process(argv,**kwargs):
                self.assertEqual(argv[1],'-B');self.assertNotIn('--prepare',argv)
                self.assertEqual(kwargs['env']['TEMP'],kwargs['env']['TMP'])
                self.assertTrue(Path(kwargs['env']['TEMP']).is_relative_to(repo/'.local'))
                self.assertEqual('--coupled-midpoint' in argv,variant==n.VARIANTS[2])
                self.assertEqual('--event-aware' in argv,variant==n.VARIANTS[1])
                self.assertEqual('--coupled-local-window' in argv,variant==n.VARIANTS[3])
                if variant==n.VARIANTS[3]:self.assertIn(str(repo/'tools/bootstrap/coupled-local-window-source-variant.py'),argv)
                return type('Result',(),{'returncode':0,'stdout':json.dumps(selected).encode()})()
            with patch.object(n.subprocess,'run',side_effect=process):
                self.assertEqual(n.selected_source(repo,build,n.cache_values(build)),selected)

    def test_path_containment_and_symlink_rejection(self):
        for name in ('../outside','/outside','a/../outside','C:/outside','native\\file','a//b','./file'):
            with self.assertRaises(ValueError):n.contained(self.repo,name)
        link=self.repo/'link'
        try:link.symlink_to(self.build,target_is_directory=True)
        except OSError:
            # Windows may deny link creation. Exercise its actual reparse-bit
            # rejection deterministically; do not claim a real junction trial.
            with patch.object(Path,'lstat',return_value=SimpleNamespace(st_mode=0,st_file_attributes=0x400)):
                with self.assertRaises(ValueError):n.ordinary(self.repo/n.SOURCES[0])
            return
        with self.assertRaises(ValueError):n.contained(self.repo,'link/native-identity.gd')

    def test_staged_resource_bytes(self):
        good=self.qualify();stage=self.root/'stage';stage.mkdir()
        put(stage,n.STAGED_PATH,(self.build/n.BUILD_PATH).read_bytes());n.check_stage(good,stage)
        put(stage,n.STAGED_PATH,b'changed')
        with self.assertRaises(ValueError):n.check_stage(good,stage)

    def test_duplicate_json_fields_rejected(self):
        with self.assertRaises(ValueError):n.unique_json(b'{"schema":1,"schema":2}')

    def test_camera_reconstruction_closed_producer_and_drift(self):
        destination = self.root/'camera-source'
        destination.mkdir()
        qualified_before = self.qualify()
        with patch.object(n.subprocess, 'check_output', return_value='1'*40+'\n'):
            n.reconstruction(self.repo, destination)
            n.check_reconstruction(self.repo, destination)
            rows = json.loads((destination/'native-reconstruction.json').read_bytes())['files']
            camera_rows = [row for row in rows if row['path'].startswith(
                ('app/camera/', 'app/ui/camera/', 'tests/camera/'))]
            self.assertEqual([row['path'] for row in camera_rows],
                             sorted(EXPECTED_CAMERA_RECONSTRUCTION_PATHS))
            for row in camera_rows:
                raw = (self.repo/row['path']).read_bytes()
                self.assertEqual(row['bytes'], len(raw))
                self.assertEqual(row['sha256'], sha(raw))
                self.assertEqual((destination/'repository'/row['path']).read_bytes(), raw)
            with self.assertRaisesRegex(ValueError, 'output must be fresh'):
                n.reconstruction(self.repo, destination)
            policy = destination/'repository/app/camera/view_policy.gd'
            raw = policy.read_bytes()
            policy.unlink()
            with self.assertRaises(ValueError):
                n.check_reconstruction(self.repo, destination)
            policy.write_bytes(raw+b'# changed')
            with self.assertRaises(ValueError):
                n.check_reconstruction(self.repo, destination)
            policy.write_bytes(raw)
            for extra in ('view_policy.gd.uid', 'extra.gd'):
                file = policy.with_name(extra)
                file.write_bytes(b'uid://abc123\n')
                with self.assertRaisesRegex(ValueError, 'omitted/extra source files'):
                    n.check_reconstruction(self.repo, destination)
                file.unlink()
            n.check_reconstruction(self.repo, destination)
        self.assertEqual(self.qualify(), qualified_before,
                         'Camera reconstruction must not change compiled identity')

    def test_missing_authored_camera_file_cannot_be_reconstructed(self):
        (self.repo/'tests/camera/expected-v1.json').unlink()
        destination = self.root/'missing-camera-source'
        destination.mkdir()
        with patch.object(n.subprocess, 'check_output', return_value='1'*40+'\n'):
            with self.assertRaises((ValueError, FileNotFoundError)):
                n.reconstruction(self.repo, destination)

    def test_taxi_reconstruction_closed_source_and_each_copy_drift(self):
        destination=self.root/'taxi-source';destination.mkdir()
        qualified_before=self.qualify()
        with patch.object(n.subprocess,'check_output',return_value='1'*40+'\n'):
            n.reconstruction(self.repo,destination)
            n.check_reconstruction(self.repo,destination)
            rows=json.loads((destination/'native-reconstruction.json').read_bytes())['files']
            taxi_rows=[r for r in rows if r['path'].startswith(('app/world/taxi/','app/ui/taxi/','tests/world/taxi/','tests/integration/taxi/'))]
            self.assertEqual([r['path'] for r in taxi_rows],sorted(EXPECTED_TAXI_RECONSTRUCTION_PATHS))
            for row in taxi_rows:
                original=self.repo/row['path'];copy_path=destination/'repository'/row['path'];source_bytes=original.read_bytes()
                self.assertEqual(row['sha256'],sha(source_bytes));self.assertEqual(copy_path.read_bytes(),source_bytes)
                for target in (original,copy_path):
                    target.write_bytes(source_bytes+b'drift')
                    with self.assertRaises(ValueError):n.check_reconstruction(self.repo,destination)
                    target.write_bytes(source_bytes)
                    target.unlink()
                    with self.assertRaises((ValueError,FileNotFoundError)):n.check_reconstruction(self.repo,destination)
                    target.write_bytes(source_bytes)
            put(destination/'repository','app/world/taxi/extra.gd',b'unbound synthetic extra')
            with self.assertRaises(ValueError):n.check_reconstruction(self.repo,destination)
            (destination/'repository/app/world/taxi/extra.gd').unlink()
            n.check_reconstruction(self.repo,destination)
        self.assertEqual(self.qualify(),qualified_before,'Taxi reconstruction cannot alter compiled native identity')

    def test_reconstruction_complete_current_overlay_and_tampering(self):
        destination=self.root/'source';destination.mkdir()
        git=patch.object(n.subprocess,'check_output',return_value='1'*40+'\n')
        git.start();self.addCleanup(git.stop)
        n.reconstruction(self.repo,destination)
        n.check_reconstruction(self.repo,destination)
        binding=destination/'native-reconstruction.json';original=binding.read_bytes()
        bad=json.loads(original);bad['files'].pop();binding.write_text(json.dumps(bad))
        with self.assertRaises(ValueError):n.check_reconstruction(self.repo,destination)
        binding.write_bytes(original)
        put(destination/'repository','undeclared',b'extra')
        with self.assertRaises(ValueError):n.check_reconstruction(self.repo,destination)
        (destination/'repository/undeclared').unlink()
        put(destination/'repository',n.TEMPLATE,b'changed')
        with self.assertRaises(ValueError):n.check_reconstruction(self.repo,destination)

    def test_reconstruction_base_and_matching_instruction_tampering(self):
        destination=self.root/'base-source';destination.mkdir()
        with patch.object(n.subprocess,'check_output',return_value='1'*40+'\n') as git:
            n.reconstruction(self.repo,destination)
            n.check_reconstruction(self.repo,destination)
            git.assert_called_with(['git','-C',str(self.repo),'rev-parse','--verify','HEAD^{commit}'],text=True)
            binding=destination/'native-reconstruction.json';bad=json.loads(binding.read_text())
            bad['base_git_commit']='2'*40;binding.write_text(json.dumps(bad))
            instructions=destination/'NATIVE-RECONSTRUCTION.txt'
            instructions.write_text(instructions.read_text().replace('1'*40,'2'*40))
            with self.assertRaisesRegex(ValueError,'immutable base differs'):n.check_reconstruction(self.repo,destination)
        with patch.object(n.subprocess,'check_output',return_value='not-a-commit\n'):
            with self.assertRaises(ValueError):n.immutable_head(self.repo)


if __name__ == '__main__':
    unittest.main()
