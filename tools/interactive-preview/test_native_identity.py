"""Offline synthetic ADR016 qualification tests; no real compiler/native/Godot."""
import copy
import hashlib
import importlib.util
import json
import os
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


def fixture(root, family='MSVC', variant=n.VARIANTS[0]):
    repo, build = root / 'repo', root / 'build'
    repo.mkdir(); build.mkdir()
    for name in set(n.SOURCES + n.CONTROLS):
        put(repo, name, 'original synthetic source ' + name + '\r\n')
    put(repo, 'native/fdm_jsbsim/interactive/CMakeLists.txt',
        'set(INTERACTIVE_SOURCE_PATHS\n' + '\n'.join(n.SOURCES) + ')\n')
    put(repo, 'tools/bootstrap/source-selection.cmake',
        'set(JSBSIM_BUILD_CONTROL_PATHS\n' + '\n'.join(n.CONTROLS) + ')\n')
    put(repo, n.TEMPLATE, n.TEMPLATE_BYTES)
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
    body = ('verified-jsbsim-backend:'+'a'*64+'\njsbsim-build-controls:'+control+'\n'+
        ''.join(p+':'+sha((repo/p).read_bytes().replace(b'\r\n',b'\n'))+'\n' for p in n.SOURCES))
    consumer = sha(body.encode())
    put(build, 'interactive-source-fingerprint.txt', consumer+'\n'+body)
    put(build, 'jsbsim-source-build-manifest.txt', 'Source variant: '+variant+'\nSelected source root: '+source.as_posix()+
        '\nBackend identity SHA256: '+'a'*64+'\nBuild controls SHA256: '+control+'\nCompiler: '+family+' '+compiler+
        '\nGenerator: Ninja\nBuild configuration: RelWithDebInfo\nCommon CXX flags: '+common+
        '\nSelected configuration CXX flags: '+config+'\nMSVC runtime: MultiThreadedDLL\nDeclared modified-source strict FP flags: '+flags+
        '\nActual compiler commands must be inspected before numerical execution.\n')
    put(build, 'toolchain-build-manifest.txt', 'Project: synthetic not executable\nCompiler: '+family+' '+compiler+
        '\nGenerator: Ninja\nBuild type: RelWithDebInfo\nMSVC runtime: MultiThreadedDLL\n')
    command = 'fixture-compiler -D'+n.MACRO+'=\\"'+consumer+'\\" -c '+str(repo/n.SOURCES[0])
    put(build, 'compile_commands.json', json.dumps([dict(directory=str(build),file=str(repo/n.SOURCES[0]),command=command)]))
    put(build, 'build.ninja', 'DEFINES = -D'+n.MACRO+'=\\"'+consumer+'\\"\n')
    put(build, n.witness_paths(family)[0], b'not executable synthetic bridge\x00'+consumer.encode()+b'\x00')
    resource = ('extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\n'
        'const SOURCE_VARIANT: String = "'+variant+'"\nconst BACKEND_IDENTITY_SHA256: String = "'+'a'*64+
        '"\nconst BUILD_CONTROL_SHA256: String = "'+control+'"\nconst SOURCE_FINGERPRINT: String = "'+consumer+'"\n')
    put(build, n.BUILD_PATH, resource)
    return repo, build, selected, consumer


class IdentityTests(unittest.TestCase):
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
        fingerprints = []
        for i, (family, variant) in enumerate((f,v) for f in ('MSVC','GNU') for v in n.VARIANTS):
            root=self.root/str(i);root.mkdir()
            repo, build, selected, expected = fixture(root,family,variant)
            result = n.qualify(repo,build,lambda *_:selected)
            self.assertEqual(result['declared_source_fingerprint'],expected)
            self.assertEqual(len(result['source_bindings']),15)
            self.assertEqual(len(result['build_witnesses']),7)
            fingerprints.append(expected)
        self.assertEqual(len(set(fingerprints)),6)

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
