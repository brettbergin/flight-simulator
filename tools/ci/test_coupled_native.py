"""Offline synthetic provenance tests; dummy bytes are never native binaries.

Subprocess source-selector/CTest discovery is replaced by declared JSON fixtures.
No compilation, reference generator, simulator, or native child is invoked.
"""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('coupled_ci', Path(__file__).with_name('coupled-native.py'))
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
        self.write('tools/bootstrap/build.ps1', b'synthetic bootstrap\n')
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
                       'FLIGHT_JSBSIM_VARIANT':'event-aware-coupled-midpoint-v1', 'FLIGHT_BUILD_GODOT_BINDINGS':'OFF'}
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
        self.pretrial = {'schema':'coupled-ci-pretrial-v1',
             'scope':'fixed source/reference/budgets before fresh compilation; no native execution',
             'source_inputs':self.pins(self.repo), 'reference_manifest_sha256':ci.sha(self.repo/'tests/engine/shaft-method/coupled-midpoint-v1/reference-manifest.json'),
             'packet_sha256':self.packet,'required_ctests':sorted(ci.REQUIRED)}
        self.dump(self.work/'pretrial.json', self.pretrial)
        self.route = {'repository_root':str(self.repo),'build_directory':str(self.build),
            'pretrial_path':str(self.work/'pretrial.json'),'pretrial_sha256':ci.sha(self.work/'pretrial.json'),
            'execution_path':str(self.work/'physical-execution.json'),'probe_execution_path':str(self.work/'unit-execution.json'),
            'headless_native':True,'source_variant':ci.VARIANT,'source_bundle_root':str(self.vendor.parent),
            'backend_identity_sha256':self.backend,'build_entry_sha256':ci.sha(self.repo/'tools/bootstrap/build.ps1')}
        self.dump(self.build/'event-aware-route.json', self.route)
        self.dump(self.build/'event-aware-build-result.json', {'status':'COMPILED_NOT_TESTED',
            'route_sha256':ci.sha(self.build/'event-aware-route.json'),
            'cmake_cache_sha256':ci.sha(self.build/'CMakeCache.txt'),
            'compile_commands_sha256':ci.sha(self.build/'compile_commands.json'),
            'verbose_build_sha256':ci.sha(self.build/'native-verbose-build.log')})
        self.control = ci.build_control(self.repo,self.build,self.values,self.selected)
        self.body = 'verified-jsbsim-backend:'+self.backend+'\njsbsim-build-controls:'+self.control+'\nmarker.txt:'+ci.lf_sha(self.repo/'marker.txt')+'\n'
        self.consumer = hashlib.sha256(self.body.encode()).hexdigest()
        (self.build/'interactive-source-fingerprint.txt').write_text(self.consumer+'\n'+self.body,encoding='utf-8',newline='\n')
        self.config = {'schema':'coupled-probe-config-v1','repository_root':str(self.repo),'build_root':str(self.build),
            'vendor_root':str(self.vendor),'source_manifest':str(self.build/'source-manifest.json')}
        self.dump(self.build/'source-manifest.json', {'synthetic':'identity fixture only'})
        for label in ('kernel','library','chronology','terminal','dll','native','mechanism'):
            path = self.build/(label+'.dummy');path.write_bytes(('not executable '+label).encode())
            self.config[label] = str(path)
        self.dump(self.build/'coupled-probes-config.json',self.config)
        self.unit_auth = {'authorized':True,'schema':'coupled-probe-execution-v1',
            'scope':'coupled-midpoint-isolated-public-probes-v1','config_sha256':ci.sha(self.build/'coupled-probes-config.json'),
            'backend_identity_sha256':self.backend,'build_control_sha256':self.control,'consumer_fingerprint':self.consumer,
            'reference_manifest_sha256':self.pretrial['reference_manifest_sha256'],'packet_sha256':self.packet,
            'source_manifest_sha256':ci.sha(self.build/'source-manifest.json'),
            'executables':{k:{'path':self.config[k],'sha256':ci.sha(self.config[k])} for k in ('kernel','library','chronology','terminal')},
            'dll':{'path':self.config['dll'],'sha256':ci.sha(self.config['dll'])},
            'build_inputs':{str((self.build/n).resolve()):ci.sha(self.build/n) for n in
              ('event-aware-route.json','event-aware-build-result.json','CMakeCache.txt','compile_commands.json','native-verbose-build.log')}}
        self.unit_auth['build_inputs'].update({str(self.work/'pretrial.json'):ci.sha(self.work/'pretrial.json'),
                  str(self.repo/'tools/bootstrap/build.ps1'):ci.sha(self.repo/'tools/bootstrap/build.ps1')})
        self.dump(self.work/'unit-execution.json',self.unit_auth)
        self.dump(self.repo/'.local/toolchain/environment.json',{'tools':{'cmake':str(self.repo/'cmake.dummy')}})
        args = ['python',str(self.repo/'tests/engine/native-validate.py'),'--angular-method','event_aware_coupled_midpoint_v1',
             '--pretrial-ratification',str(self.work/'pretrial.json'),'--ratification',str(self.work/'physical-execution.json'),
             '--jsbsim-dll',self.config['dll'],'--native',self.config['native'],'--mechanism',self.config['mechanism']]
        self.discovery = {'tests':[{'name':n,'command':args if n=='piston_engine_lifecycle' else ['unused']} for n in sorted(ci.REQUIRED)]}
        for name,value in (('source_inputs',self.pins),('reference',lambda _:self.manifest),('command',self.fake_command)):
            handle = patch.object(ci,name,value);handle.start();self.addCleanup(handle.stop)
        env = patch.dict(os.environ, {'CL':'','_CL_':''});env.start();self.addCleanup(env.stop)

    def write(self,name,data):
        p=self.repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)

    def dump(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value),encoding='utf-8')

    def pins(self,repo):
        p=repo/'marker.txt';return {'marker.txt':{'sha256':ci.sha(p),'bytes':p.stat().st_size}}

    def fake_command(self,args,repo):
        # Whitelist only source verification and test enumeration; no native calls.
        if '--coupled-midpoint' in args:return json.dumps(self.selected)
        if '--show-only=json-v1' in args:return json.dumps(self.discovery)
        raise AssertionError('unexpected subprocess request')

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
        with self.assertRaisesRegex(ValueError,'CTests missing'):ci.qualify(self.repo,self.work)

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


if __name__ == '__main__':
    unittest.main()
