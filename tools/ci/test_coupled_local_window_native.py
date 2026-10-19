"""Offline synthetic provenance tests; dummy bytes are never native binaries.

Subprocess source-selector/CTest discovery is replaced by declared JSON fixtures.
No compilation, reference generator, simulator, or native child is invoked.
"""
import ast
import copy
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('coupled_ci', Path(__file__).with_name('coupled-local-window-native.py'))
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)
ORIGINAL_REFERENCE = ci.reference


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()/'repo'
        self.work = self.repo/'work'
        self.build = self.work/'build'
        self.vendor = self.work/'bundle/vendor'
        self.build.mkdir(parents=True)
        self.vendor.mkdir(parents=True)
        (self.work/'evidence').mkdir()
        self.backend = 'a'*64
        self.packet = 'b'*64
        self.selected = {'source_variant': ci.VARIANT, 'backend_identity_sha256': self.backend}
        self.write('marker.txt', b'synthetic source\n')
        self.write('tools/bootstrap/build-local-window.ps1', b'synthetic bootstrap\n')
        self.write('tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json', b'synthetic manifest\n')
        self.write('tools/bootstrap/source-selection.cmake', b'set(JSBSIM_BUILD_CONTROL_PATHS marker.txt)\n')
        self.write('native/fdm_jsbsim/interactive/CMakeLists.txt', b'set(INTERACTIVE_SOURCE_PATHS marker.txt)\n')
        for name in ci.SUITE:
            self.write('tests/engine/'+name, ('synthetic '+name).encode())
        self.family = 'MSVC' if os.name == 'nt' else 'GNU'
        self.flags = '/fp:strict' if os.name == 'nt' else '-fno-fast-math -ffp-contract=off -frounding-math'
        compiler = self.build/'CMakeFiles/fixture/CMakeCXXCompiler.cmake'
        compiler.parent.mkdir(parents=True)
        compiler.write_text('set(CMAKE_CXX_COMPILER_ID "'+self.family+'")\nset(CMAKE_CXX_COMPILER_VERSION "1.2.3")\n')
        self.values = {'CMAKE_GENERATOR':'Ninja', 'CMAKE_BUILD_TYPE':'Release', 'CMAKE_CXX_FLAGS':'',
                       'CMAKE_CXX_FLAGS_RELEASE':'-O2', 'CMAKE_MSVC_RUNTIME_LIBRARY':'',
                       'FLIGHT_JSBSIM_VARIANT':'event-aware-coupled-midpoint-local-window-v2', 'FLIGHT_BUILD_GODOT_BINDINGS':'OFF'}
        (self.build/'CMakeCache.txt').write_text(''.join(k+':STRING='+v+'\n' for k,v in self.values.items()))
        self.compile = []
        lines = []
        for name in ('FGPiston.cpp','FGPropeller.cpp'):
            path = self.vendor/'src/models/propulsion'/name
            path.parent.mkdir(parents=True,exist_ok=True);path.write_text('synthetic source only')
            cmd = self.flags+(' /c ' if os.name == 'nt' else ' -c ')+str(path).replace('\\','/')
            self.compile.append({'directory':str(self.build),'file':str(path),'command':cmd})
            lines.append(cmd)
        self.dump(self.build/'compile_commands.json', self.compile)
        (self.build/'native-verbose-build.log').write_text('\n'.join(lines))
        self.manifest = {'packet':{'sha256':self.packet}}
        self.pretrial = {'schema':'coupled-ci-pretrial-local-window-v2',
             'scope':'fixed source/reference/budgets before fresh compilation; no native execution',
             'source_inputs':self.pins(self.repo), 'reference_manifest_sha256':ci.sha(self.repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'),
             'packet_sha256':self.packet,'required_ctests':sorted(ci.REQUIRED)}
        self.dump(self.work/'pretrial.json', self.pretrial)
        self.route = {'repository_root':str(self.repo),'build_directory':str(self.build),
            'pretrial_path':str(self.work/'pretrial.json'),'pretrial_sha256':ci.sha(self.work/'pretrial.json'),
            'execution_path':str(self.work/'physical-execution.json'),'probe_execution_path':str(self.work/'unit-execution.json'),
            'headless_native':True,'source_variant':ci.VARIANT,'source_bundle_root':str(self.vendor.parent),
            'backend_identity_sha256':self.backend,'build_entry_sha256':ci.sha(self.repo/'tools/bootstrap/build-local-window.ps1')}
        self.dump(self.build/'event-aware-route.json', self.route)
        self.dump(self.build/'event-aware-build-result.json', {'status':'COMPILED_NOT_TESTED',
            'route_sha256':ci.sha(self.build/'event-aware-route.json'),
            'cmake_cache_sha256':ci.sha(self.build/'CMakeCache.txt'),
            'compile_commands_sha256':ci.sha(self.build/'compile_commands.json'),
            'verbose_build_sha256':ci.sha(self.build/'native-verbose-build.log')})
        self.control = ci.build_control(self.repo,self.build,self.values,self.selected)
        self.resident = {'sha256':'d'*64, 'sources':('marker.txt',), 'paths':('marker.txt',)}
        self.body = 'verified-jsbsim-backend:'+self.backend+'\njsbsim-build-controls:'+self.control+'\nresident-world-component:'+self.resident['sha256']+'\nmarker.txt:'+ci.lf_sha(self.repo/'marker.txt')+'\n'
        self.consumer = hashlib.sha256(self.body.encode()).hexdigest()
        (self.build/'interactive-source-fingerprint.txt').write_text(self.consumer+'\n'+self.body,encoding='utf-8',newline='\n')
        self.config = {'schema':'coupled-probe-config-local-window-v2','repository_root':str(self.repo),'build_root':str(self.build),
            'vendor_root':str(self.vendor),'source_manifest':str(self.build/'source-manifest.json')}
        self.dump(self.build/'source-manifest.json', {'synthetic':'identity fixture only'})
        for label in ('kernel','library','chronology','terminal','dll','native','mechanism'):
            path = self.build/(label+'.dummy');path.write_bytes(('not executable '+label).encode())
            self.config[label] = str(path)
        scalar=self.build/'bin'/('piston_local_window_native.exe' if os.name=='nt' else 'piston_local_window_native')
        scalar.parent.mkdir();scalar.write_bytes(b'synthetic scalar executable, never run')
        self.apron = self.build/'bin'/('interactive_tests.exe' if os.name == 'nt' else 'interactive_tests')
        self.apron.write_bytes(b'synthetic apron executable, never run')
        for name in ('original-interactive', 'original-piston-prop'):
            (self.repo/'native/fdm_jsbsim/models'/name).mkdir(parents=True, exist_ok=True)
        (self.build/'interactive-proof').mkdir()
        self.apron_command = [str(self.apron), str(self.repo/'native/fdm_jsbsim/models/original-interactive'),
                              str(self.build/'interactive-proof/ctest-apron'), 'apron',
                              str(self.repo/'native/fdm_jsbsim/models/original-piston-prop')]
        self.config['local_window']=str(scalar)
        self.dump(self.build/'coupled-probes-config.json',self.config)
        self.unit_auth = {'authorized':True,'schema':'coupled-probe-execution-local-window-v2',
            'scope':'coupled-midpoint-local-window-isolated-public-probes-v2','config_sha256':ci.sha(self.build/'coupled-probes-config.json'),
            'backend_identity_sha256':self.backend,'build_control_sha256':self.control,'consumer_fingerprint':self.consumer,
            'reference_manifest_sha256':self.pretrial['reference_manifest_sha256'],'packet_sha256':self.packet,
            'source_manifest_sha256':ci.sha(self.build/'source-manifest.json'),
            'executables':{k:{'path':self.config[k],'sha256':ci.sha(self.config[k])} for k in ('kernel','library','chronology','terminal')},
            'dll':{'path':self.config['dll'],'sha256':ci.sha(self.config['dll'])},
            'build_inputs':{str((self.build/n).resolve()):ci.sha(self.build/n) for n in
              ('event-aware-route.json','event-aware-build-result.json','CMakeCache.txt','compile_commands.json','native-verbose-build.log')}}
        self.unit_auth['build_inputs'].update({str(self.work/'pretrial.json'):ci.sha(self.work/'pretrial.json'),
                  str(self.repo/'tools/bootstrap/build-local-window.ps1'):ci.sha(self.repo/'tools/bootstrap/build-local-window.ps1')})
        generated=self.build/'tests/engine/local-window-v2/local-window-references/generated'
        generated.mkdir(parents=True)
        for name in ('driver.cpp','immutable_helpers.inc','candidate_helpers.inc','source-binding.json'):
            path=generated/name;path.write_bytes(b'synthetic generated source')
            self.unit_auth['build_inputs'][str(path.resolve())]=ci.sha(path)
        self.unit_auth['local_window_reference']={'path':str(scalar.resolve()),'sha256':ci.sha(scalar)}
        self.dump(self.work/'unit-execution.json',self.unit_auth)
        self.dump(self.repo/'.local/toolchain/environment.json',{'tools':{'cmake':str(self.repo/'cmake.dummy')}})
        args = ['python',str(self.repo/'tests/engine/native-validate.py'),'--angular-method','event_aware_coupled_midpoint_v1',
             '--pretrial-ratification',str(self.work/'pretrial.json'),'--ratification',str(self.work/'physical-execution.json'),
             '--jsbsim-dll',self.config['dll'],'--native',self.config['native'],'--mechanism',self.config['mechanism']]
        self.discovery = {'tests':[{'name':n,'command':args if n=='piston_engine_lifecycle' else [self.config['local_window']] if n=='piston_local_window_native_references' else self.apron_command if n=='interactive_apron_starts' else ['unused']} for n in sorted(ci.REQUIRED)]}
        next(row for row in self.discovery['tests'] if row['name']=='interactive_apron_starts')['properties'] = [
            {'name':'ENVIRONMENT','value':['JSBSIM_DEBUG=0']}, {'name':'TIMEOUT','value':120.0}]
        # Synthetic authorization scheduling fixture only. Actual component
        # admission/witness tamper controls live in both probe portable suites.
        for name,value in (('source_inputs',self.pins),('reference',lambda _:self.manifest),('command',self.fake_command),('resident_inputs',lambda repo,build=None:self.resident)):
            handle = patch.object(ci,name,value);handle.start();self.addCleanup(handle.stop)
        env = patch.dict(os.environ, {'CL':'','_CL_':''});env.start();self.addCleanup(env.stop)

    def write(self,name,data):
        p=self.repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)

    def test_resident_prefix_not_ignored_as_metadata(self):
        path=self.build/'interactive-source-fingerprint.txt'
        row='resident-world-component:'+self.resident['sha256']+'\n'
        for body in (self.body.replace(row,''),self.body.replace(row,row+row),
                     self.body.replace(row,'resident-world-component:'+'e'*64+'\n'),
                     self.body+'unreviewed.cpp:'+'0'*64+'\n'):
            path.write_text(hashlib.sha256(body.encode()).hexdigest()+'\n'+body,encoding='utf-8',newline='\n')
            with self.assertRaisesRegex(ValueError,'consumer provenance'):ci.qualify(self.repo,self.work)

    def dump(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value),encoding='utf-8')

    def pins(self,repo):
        p=repo/'marker.txt';return {'marker.txt':{'sha256':ci.sha(p),'bytes':p.stat().st_size}}

    def fake_command(self,args,repo):
        # Whitelist only source verification and test enumeration; no native calls.
        if '--coupled-local-window' in args:return json.dumps(self.selected)
        if '--show-only=json-v1' in args:return json.dumps(self.discovery)
        raise AssertionError('unexpected subprocess request')

    def test_complete_ctest_log_requires_new17_and_all_old_passes(self):
        names=('native_toolchain_smoke','contract_boundary','ground_contract','ground_contact_proof',
               'fdm_boundary','interactive_loop','interactive_negative_readback','piston_engine_lifecycle',
               'coupled_shaft_math','coupled_shaft_native','replay_reconstruction','wire_numbers_native',
               'piston_local_window_native_references','interactive_apron_starts')
        rows='\n'.join(f'{i}/14 Test #{i}: {n} ........ Passed 0.01 sec' for i,n in enumerate(names,1))
        good=rows+'\n100% tests passed, 0 tests failed out of 14\n';ci.complete_ctests(good)
        old_rows='\n'.join(f'{i}/13 Test #{i}: {n} ........ Passed 0.01 sec' for i,n in enumerate(names[:-1],1))
        with self.assertRaises(ValueError):ci.complete_ctests(old_rows+'\n100% tests passed, 0 tests failed out of 13\n')
        for bad in (good.replace('Passed','Skipped',1),good.replace(names[-1],names[0]),'\n'.join(good.splitlines()[1:]),good+'\n'+good.splitlines()[0],good.replace('out of 14','out of 13')):
            with self.assertRaises(ValueError):ci.complete_ctests(bad)

    def test_scalar_executable_substitution_rejected_after_authorization(self):
        Path(self.config['local_window']).write_bytes(b'substituted synthetic executable')
        with self.assertRaisesRegex(ValueError,'scalar executable changed after authorization'):ci.qualify(self.repo,self.work)

    def test_scalar_ctest_command_and_containment_are_exact(self):
        ci.local_window_target(self.config,self.build,self.discovery['tests'])
        named=next(row for row in self.discovery['tests'] if row['name']=='piston_local_window_native_references')
        for command in ([self.config['local_window'],'--skip'],[self.config['kernel']],[]):
            wrong=copy.deepcopy(self.discovery['tests']);next(row for row in wrong if row['name']==named['name'])['command']=command
            with self.assertRaises(ValueError):ci.local_window_target(self.config,self.build,wrong)
        with self.assertRaises(ValueError):ci.local_window_target(self.config,self.build,self.discovery['tests']+[named])
        with self.assertRaises(ValueError):ci.local_window_target({**self.config,'local_window':self.config['kernel']},self.build,self.discovery['tests'])

    def test_apron_command_measures_real_fixture_bytes_and_all_paths(self):
        measured=ci.apron_target(self.repo,self.build,self.discovery['tests'])
        self.assertEqual(measured,{'path':str(self.apron),'sha256':ci.sha(self.apron)})
        self.assertFalse((self.build/'interactive-proof/ctest-apron').exists(), 'measurement must not create evidence')
        original=next(row for row in self.discovery['tests'] if row['name']=='interactive_apron_starts')
        for index,value in ((0,self.config['kernel']),(0,'bin/interactive_tests'),
                            (1,str(self.repo/'native/fdm_jsbsim/models/original-piston-prop')),
                            (2,str(self.build/'interactive-proof/ctest-ground')),
                            (3,'negatives'),(4,str(self.repo/'native/fdm_jsbsim/models/original-interactive')),
                            (4,'native/fdm_jsbsim/models/original-piston-prop')):
            with self.subTest(index=index,value=value):
                tests=copy.deepcopy(self.discovery['tests'])
                next(row for row in tests if row['name']==original['name'])['command'][index]=value
                with self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,tests)
        for argv in ([],self.apron_command[:-1],self.apron_command+['--skip'],[True,*self.apron_command[1:]]):
            tests=copy.deepcopy(self.discovery['tests'])
            next(row for row in tests if row['name']==original['name'])['command']=argv
            with self.subTest(argv=argv),self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,tests)
        for tests in ([row for row in self.discovery['tests'] if row['name']!=original['name']],
                      self.discovery['tests']+[copy.deepcopy(original)]):
            with self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,tests)

    def test_apron_properties_are_exact_and_cannot_disguise_bool_timeout(self):
        original=next(row for row in self.discovery['tests'] if row['name']=='interactive_apron_starts')
        good=copy.deepcopy(original['properties'])
        for timeout in (120,120.0):
            original['properties']=[good[0],{'name':'TIMEOUT','value':timeout}]
            ci.apron_target(self.repo,self.build,self.discovery['tests'])
        bad_values=([],[good[0]],[good[1]],good+[good[0]],good+[good[1]],
                    [{'name':'ENVIRONMENT','value':'JSBSIM_DEBUG=0'},good[1]],
                    [{'name':'ENVIRONMENT','value':['JSBSIM_DEBUG=0','EXTRA=1']},good[1]],
                    [{'name':'ENVIRONMENT','value':['JSBSIM_DEBUG=1']},good[1]])
        bad_values+=tuple([good[0],{'name':'TIMEOUT','value':value}] for value in (True,False,'120',0,119,121,float('nan')))
        for properties in bad_values:
            original['properties']=properties
            with self.subTest(properties=properties),self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])
        del original['properties']
        with self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])

    def test_apron_missing_executable_and_model_directories_reject(self):
        original=self.apron.read_bytes();self.apron.unlink()
        with self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])
        self.apron.write_bytes(original)
        for name in ('original-interactive','original-piston-prop'):
            model=self.repo/'native/fdm_jsbsim/models'/name
            model.rmdir()
            with self.subTest(model=name),self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])
            model.mkdir()

    def test_apron_topology_guards_reject_mocked_symlink_and_reparse_metadata(self):
        # Portable guard-branch tests only, not actual Win32/symlink evidence.
        is_symlink=Path.is_symlink
        for blocked in (self.apron,self.apron.parent,self.repo/'native/fdm_jsbsim/models'):
            with patch.object(Path,'is_symlink',autospec=True,side_effect=lambda path: path==blocked or is_symlink(path)):
                with self.subTest(symlink=blocked),self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])
        lstat=Path.lstat
        for blocked in (self.apron,self.apron.parent,self.repo/'native/fdm_jsbsim/models'):
            def observed(path,*args,**kwargs):
                value=lstat(path,*args,**kwargs)
                if path==blocked:
                    return SimpleNamespace(st_mode=value.st_mode,st_file_attributes=0x400)
                return value
            with patch.object(Path,'lstat',autospec=True,side_effect=observed):
                with self.subTest(reparse=blocked),self.assertRaises(ValueError):ci.apron_target(self.repo,self.build,self.discovery['tests'])

    def test_apron_executable_hash_drift_rejects_verify_before_result_admission(self):
        ci.authorize(self.repo,self.work,True)
        saved=ci.load(self.work/'evidence/qualification.json')['apron_target']
        self.assertEqual(saved['sha256'],ci.sha(self.apron))
        self.apron.write_bytes(b'changed synthetic apron executable; never executed')
        with self.assertRaisesRegex(ValueError,'apron executable changed after authorization'):ci.verify(self.repo,self.work)
        self.assertFalse((self.work/'evidence/ci-result.json').exists())

    def test_discovery_requires_exact14_not_old13_extra_or_duplicate(self):
        rows=copy.deepcopy(self.discovery['tests'])
        bad=([row for row in rows if row['name']!='interactive_apron_starts'],
             rows+[copy.deepcopy(rows[0])],rows+[{'name':'extra_test','command':['unused']}],
             [{**row,'name':'replacement_test'} if row['name']=='interactive_apron_starts' else row for row in rows])
        for tests in bad:
            self.discovery['tests']=tests
            with self.subTest(names=[row['name'] for row in tests]),self.assertRaisesRegex(ValueError,'fourteen real CTests'):ci.qualify(self.repo,self.work)

    def test_coherent_staged_identity(self):
        measured=ci.qualify(self.repo,self.work)
        self.assertEqual(measured['consumer'],self.consumer)
        self.assertEqual(measured['control'],self.control)
        self.assertEqual(set(ci.physical_record(self.repo,self.work,measured)),ci.AUTH_KEYS)
        self.assertEqual(len(ci.AUTH_KEYS),11)

    def test_build_control_matches_canonical_text(self):
        body='marker.txt:'+ci.lf_sha(self.repo/'marker.txt')+'\n'
        body+=''.join(k+':'+v+'\n' for k,v in (
            ('source_variant',ci.VARIANT),('backend_identity',self.backend),('compiler',self.family+'-1.2.3'),
            ('generator','Ninja'),('build_type','Release'),('cxx_flags',''),('configuration_flags','-O2'),
            ('msvc_runtime',''),('declared_strict_fp_flags',self.flags)))
        self.assertEqual(self.control,hashlib.sha256(body.encode()).hexdigest())

    def test_mutated_source_fails_before_authorization(self):
        (self.repo/'marker.txt').write_text('changed')
        with self.assertRaisesRegex(ValueError,'pretrial input changed'):ci.qualify(self.repo,self.work)
        self.assertFalse((self.work/'physical-execution.json').exists())

    def test_source_escape_and_closed_pretrial(self):
        for name in ('../outside',str(self.temp.name)):
            with self.assertRaises(ValueError):ci.contained(self.repo,name)
        wrong=copy.deepcopy(self.pretrial);wrong['extra']=True
        with self.assertRaisesRegex(ValueError,'closed schema'):ci.check_pretrial(self.repo,wrong)
        wrong=copy.deepcopy(self.pretrial);wrong['required_ctests']=[]
        with self.assertRaises(ValueError):ci.check_pretrial(self.repo,wrong)

    def test_unit_binary_mutation_and_auth_record_mismatch(self):
        Path(self.config['kernel']).write_text('mutated dummy')
        with self.assertRaisesRegex(ValueError,'unit executable changed'):ci.qualify(self.repo,self.work)

    def test_build_evidence_mutation(self):
        (self.build/'native-verbose-build.log').write_text('replacement')
        with self.assertRaisesRegex(ValueError,'compiled evidence changed'):ci.qualify(self.repo,self.work)

    def test_authorization_explicit_and_exclusive(self):
        with self.assertRaisesRegex(ValueError,'explicit'):ci.authorize(self.repo,self.work,False)
        ci.authorize(self.repo,self.work,True)
        with self.assertRaises(FileExistsError):ci.authorize(self.repo,self.work,True)

    def test_real_ctest_required_and_no_source_only_substitute(self):
        self.discovery['tests']=[t for t in self.discovery['tests'] if t['name']!='coupled_shaft_native']
        with self.assertRaisesRegex(ValueError,'fourteen real CTests'):ci.qualify(self.repo,self.work)

    def test_consumer_prefix_cannot_be_replaced_by_plausible_digest(self):
        (self.build/'interactive-source-fingerprint.txt').write_text('c'*64+'\n'+self.body)
        with self.assertRaisesRegex(ValueError,'consumer provenance'):ci.qualify(self.repo,self.work)

    def test_strict_flags_and_conflicts(self):
        ci.strict('/fp:strict /c file.cpp',True)
        ci.strict('-fno-fast-math -ffp-contract=off -frounding-math -c file.cpp',False)
        for cmd,msvc in (('/fp:strict /fp:fast',True),('/fp:strict /fp:precise',True),('/fp:strictly',True),
             ('-fno-fast-math -ffp-contract=off',False),('-fno-fast-math -ffp-contract=off -frounding-math -Ofast',False)):
            with self.subTest(cmd=cmd),self.assertRaises(ValueError):ci.strict(cmd,msvc)

    def test_duplicate_and_nonfinite_json_rejected(self):
        p=self.work/'bad.json'
        for text in ('{"a":1,"a":2}','{"a":NaN}'):
            p.write_text(text)
            with self.assertRaises(ValueError):ci.load(p)

    def test_reference_rejects_self_declared_omitted_source(self):
        directory=self.repo/'tests/engine/shaft-method/coupled-midpoint-v1'
        sources={}
        for name in ci.REFERENCE_FILES:
            path=directory/name;path.write_bytes(('dummy reference source '+name).encode())
            sources[name]={'sha256':ci.sha(path),'bytes':path.stat().st_size}
        models={}
        for name in ci.REFERENCE_MODELS:
            self.write(name,b'dummy model');models[name]=ci.sha(self.repo/name)
        generators={name:sources[name]['sha256'] for name in ci.GENERATOR_FILES}
        packet={'schema':'coupled-midpoint-reference-v1','method':'event_aware_coupled_midpoint_v1',
          'contract_merge':'eb410a634a9f18b4ea9177640aff391def5e7988','named_group_count':41,
          'generator_sources':generators,'roster_sha256':sources['cases.json']['sha256'],
          'native_fixture_schema':'coupled-native-fixtures-v1','native_fixture_scope':{'maximum_requests':192}}
        self.dump(directory/'references.json',packet)
        manifest={'schema':'coupled-midpoint-reference-manifest-v1','method':packet['method'],
          'contract_merge':packet['contract_merge'],'source_files':sources,'generator_sources':generators,
          'model_pins':models,'packet':{'path':'references.json','sha256':ci.sha(directory/'references.json'),
          'bytes':(directory/'references.json').stat().st_size},'roster':{'path':'cases.json','named_groups':41,
          'sha256':sources['cases.json']['sha256'],'native_fixture_schema':'coupled-native-fixtures-v1','maximum_requests':192}}
        self.dump(directory/'reference-manifest.json',manifest)
        ORIGINAL_REFERENCE(self.repo)
        del manifest['source_files']['test_reference.py']
        self.dump(directory/'reference-manifest.json',manifest)
        with self.assertRaisesRegex(ValueError,'closed source roster'):ORIGINAL_REFERENCE(self.repo)


    def test_receipt_requires_actual_module_and_unchanged_logs(self):
        out=self.work/'unit-out';out.mkdir()
        receipt={'identities_passed':True,'failures':[],'authorization_sha256':ci.sha(self.work/'unit-execution.json'),
          'authorized_source_binding_sha256':self.unit_auth['source_manifest_sha256'],'packet_sha256':self.packet,
          'dll_path':self.config['dll'],'dll_sha256_before':self.unit_auth['dll']['sha256'],
          'dll_sha256_after':self.unit_auth['dll']['sha256'],'children':{}}
        for label,pin in self.unit_auth['executables'].items():
            child={'executable_path':pin['path'],'exit_code':0,'executable_sha256_before':pin['sha256'],
              'executable_sha256_after':pin['sha256'],'dll_sha256_before':self.unit_auth['dll']['sha256'],
              'dll_sha256_after':self.unit_auth['dll']['sha256']}
            for stream in ('stdout','stderr'):
                p=out/(label+'.'+stream);p.write_bytes(b'synthetic log');child[stream+'_sha256']=ci.sha(p)
            if label!='kernel':child.update(actual_loaded_library_path=self.config['dll'],actual_module_sha256=self.unit_auth['dll']['sha256'])
            receipt['children'][label]=child
        ci.check_unit_receipt(out,receipt,self.unit_auth,self.work/'unit-execution.json')
        changed=copy.deepcopy(receipt);changed['children']['library']['actual_module_sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'actual loaded module'):ci.check_unit_receipt(out,changed,self.unit_auth,self.work/'unit-execution.json')
        (out/'terminal.stdout').write_bytes(b'tampered log')
        with self.assertRaisesRegex(ValueError,'evidence changed'):ci.check_unit_receipt(out,receipt,self.unit_auth,self.work/'unit-execution.json')


class ReviewedSourcePinTests(unittest.TestCase):
    def test_public_qualifiers_pin_the_same_actual_source(self):
        repo = Path(__file__).resolve().parents[2]
        runner = repo/'tests/engine/shaft-method/probes-local-window-v2/run.py'
        assignments = [node for node in ast.parse(runner.read_text(encoding='utf-8')).body
                       if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'LOCAL_WINDOW_PINS' for t in node.targets)]
        self.assertEqual(len(assignments), 1)
        pins = ast.literal_eval(assignments[0].value)
        self.assertEqual(pins, ci.LOCAL_WINDOW_PINS)
        for name, expected in pins.items():
            with self.subTest(source=name):
                self.assertEqual(ci.sha(repo/name), expected)


    def test_build_entry_checkout_keeps_exact_manifest_bytes(self):
        # Exercise Git's real Windows-style smudge path, not text normalization
        # inside the qualifier. This private repository never touches owner Git.
        repo = Path(__file__).resolve().parents[2]
        name = 'tools/bootstrap/build-local-window.ps1'
        original = (repo/name).read_bytes()
        manifest = json.loads((repo/'tests/engine/shaft-method/probes-local-window-v2/probe-manifest.json').read_text(encoding='utf-8'))
        expected = manifest['shared_sources'][name]
        attrs = (repo/'.gitattributes').read_bytes()
        rule = b'tools/bootstrap/build-local-window.ps1 text eol=lf'
        self.assertEqual(attrs.splitlines().count(rule), 1)
        self.assertNotIn(b'\r', original)
        self.assertEqual({'sha256':hashlib.sha256(original).hexdigest(), 'bytes':len(original)}, expected)
        variants = (('lf', attrs, True), ('missing-rule', b'\n'.join(line for line in attrs.splitlines() if line != rule)+b'\n', False),
                    ('crlf-rule', attrs.replace(rule, b'tools/bootstrap/build-local-window.ps1 text eol=crlf'), False))
        env = {key:value for key,value in os.environ.items() if not key.startswith('GIT_')}
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_ATTR_NOSYSTEM='1')
        for label, attributes, exact in variants:
            with self.subTest(checkout=label), tempfile.TemporaryDirectory() as temp:
                scratch = Path(temp)
                def git(*args):
                    return subprocess.run(['git', '-c', 'core.autocrlf=true', '-c', 'core.eol=crlf', '-c', 'core.safecrlf=false', '-c', 'core.attributesFile='+os.devnull, *args],
                                          cwd=scratch, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                git('init', '--quiet')
                (scratch/'.gitattributes').write_bytes(attributes)
                entry = scratch/name
                entry.parent.mkdir(parents=True)
                entry.write_bytes(original)
                git('add', '--', '.gitattributes', name)
                entry.unlink()  # Only this newly-created temporary test file.
                git('checkout-index', '--force', '--', name)
                actual = entry.read_bytes()
                observed = {'sha256':hashlib.sha256(actual).hexdigest(), 'bytes':len(actual)}
                if exact:
                    self.assertEqual(actual, original)
                    self.assertEqual(observed, expected)
                else:
                    self.assertEqual(actual, original.replace(b'\n', b'\r\n'))
                    self.assertNotEqual(observed, expected, 'raw-byte guard must reject checkout drift')

    def test_public_probe_manifest_matches_actual_source_closure(self):
        repo = Path(__file__).resolve().parents[2]
        directory = repo/'tests/engine/shaft-method/probes-local-window-v2'
        manifest = json.loads((directory/'probe-manifest.json').read_text(encoding='utf-8'))
        for base, rows in ((directory, manifest['files']), (repo, manifest['shared_sources'])):
            for name, expected in rows.items():
                with self.subTest(source=name):
                    source = base/name
                    self.assertEqual({'sha256':ci.sha(source), 'bytes':source.stat().st_size}, expected)


class ScalarPreparationFreshnessTests(unittest.TestCase):
    """CMake may create an empty output parent; prior evidence must survive."""
    def setUp(self):
        spec = importlib.util.spec_from_file_location('local_window_scalar_prepare',
            Path(__file__).resolve().parents[2]/'tests/engine/shaft-method/local-window-v2/prepare.py')
        self.prepare = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.prepare)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_absent_and_cmake_created_empty_output(self):
        output = self.root/'generated'
        self.assertEqual(self.prepare.fresh_output(output), output.absolute())
        self.assertFalse(output.exists(), 'admission alone cannot create outputs')
        output.mkdir()
        self.assertEqual(self.prepare.fresh_output(output), output.absolute())
        self.assertEqual(list(output.iterdir()), [])

    def test_prior_file_or_subdirectory_is_rejected_and_preserved(self):
        for kind in ('file', 'directory'):
            output = self.root/kind
            output.mkdir()
            old = output/'.retained'
            if kind == 'file': old.write_bytes(b'previous qualification')
            else: old.mkdir()
            with self.assertRaisesRegex(AssertionError, 'preserve earlier evidence'):
                self.prepare.fresh_output(output)
            self.assertTrue(old.exists())
            if kind == 'file': self.assertEqual(old.read_bytes(), b'previous qualification')

    def test_file_output_and_file_ancestor_are_rejected(self):
        old = self.root/'retained'
        old.write_bytes(b'previous qualification')
        for output in (old, old/'generated'):
            with self.assertRaisesRegex(AssertionError, 'ordinary directories'):
                self.prepare.fresh_output(output)
        self.assertEqual(old.read_bytes(), b'previous qualification')

    def test_exclusive_writes_cannot_overwrite_prior_evidence(self):
        output = self.root/'driver.cpp'
        self.prepare.write_new(output, b'original driver')
        with self.assertRaises(FileExistsError):
            self.prepare.write_new(output, b'replacement driver')
        self.assertEqual(output.read_bytes(), b'original driver')


if __name__ == '__main__':
    unittest.main()
