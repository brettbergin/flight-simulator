"""Offline plumbing tamper tests. Never opens a library or launches a child."""
from pathlib import Path
from unittest.mock import patch
import hashlib,json,tempfile,unittest
import validate as v
import run as runner

class PortableIdentityTests(unittest.TestCase):
    def build_fixture(self,root):
        repo=root/'repo';probes=repo/'tests/engine/shaft-method/probes';vendor=root/'vendor';build=root/'build';generated=build/'generated'
        for directory in (probes,vendor,generated):directory.mkdir(parents=True)
        def create(path):path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'fixture\n');return path
        def meta(path):return {'sha256':v.sha(path),'bytes':path.stat().st_size}
        for name in v.PROBE_FILES:create(probes/name)
        for name in v.SHARED_FILES:create(repo/name)
        create(repo/'native/fdm_jsbsim/interactive/src/session.cpp')
        vendor_names=['src/models/propulsion/'+n for n in ('FGPropeller.cpp','FGPropeller.h','FGPiston.cpp')]+['src/FGJSBBase.h','src/models/FGPropulsion.cpp']
        for name in vendor_names:create(vendor/name)
        for name in ('jsbsim-source-build-manifest.txt','interactive-source-fingerprint.txt'):create(build/name)
        for name in ('driver.cpp','extraction-binding.json','chronology-source-evidence.json'):create(generated/name)
        public={'schema':'coupled-probe-source-manifest-v1','files':{n:meta(probes/n) for n in v.PROBE_FILES},'shared_sources':{n:meta(repo/n) for n in v.SHARED_FILES}}
        public_path=probes/'probe-manifest.json';public_path.write_text(json.dumps(public),encoding='utf-8')
        paths={'probes/'+n:probes/n for n in v.PROBE_FILES}
        paths.update({'shared/'+n:repo/n for n in v.SHARED_FILES})
        paths.update({'vendor-tree/'+n:vendor/n for n in vendor_names})
        paths.update({'vendor/'+n:vendor/'src/models/propulsion'/n for n in ('FGPropeller.cpp','FGPropeller.h','FGPiston.cpp')})
        paths.update({'public-probe-manifest':public_path,'vendor/FGJSBBase.h':vendor/'src/FGJSBBase.h','vendor/FGPropulsion.cpp':vendor/'src/models/FGPropulsion.cpp','loaded-library.hpp':repo/'tests/engine/loaded-library.hpp','Session.cpp':repo/'native/fdm_jsbsim/interactive/src/session.cpp','source-build-manifest':build/'jsbsim-source-build-manifest.txt','consumer-fingerprint':build/'interactive-source-fingerprint.txt','generated-driver':generated/'driver.cpp','extraction-binding':generated/'extraction-binding.json','static-chronology':generated/'chronology-source-evidence.json'})
        record={'schema':'coupled-probe-build-source-v1','public_manifest_sha256':v.sha(public_path),'backend_identity_sha256':'a'*64,'build_control_sha256':'b'*64,'consumer_fingerprint':'c'*64,'vendor_root':str(vendor),'vendor_roster':sorted(vendor_names),'repository_root':str(repo),'template_root':str(probes),'build_root':str(build),'files':{n:{'path':str(path),**meta(path)} for n,path in paths.items()}}
        binding=generated/'source-manifest.json';binding.write_text(json.dumps(record),encoding='utf-8')
        return probes,public_path,public,binding,record

    def fixture(self,root):
        ref=root/'reference';ref.mkdir();(ref/'references.json').write_bytes(b'{}\n')
        for name in v.REFERENCE_FILES:(ref/name).write_bytes(b'fixture\n')
        meta=lambda p:{'sha256':v.sha(p),'bytes':p.stat().st_size}
        m={'schema':'coupled-midpoint-reference-manifest-v1','method':'event_aware_coupled_midpoint_v1','contract_merge':'eb410a634a9f18b4ea9177640aff391def5e7988',
           'packet':{'path':'references.json',**meta(ref/'references.json')},
           'source_files':{n:meta(ref/n) for n in sorted(v.REFERENCE_FILES)},
           'generator_sources':{n:v.sha(ref/n) for n in ('generate.py','exact.py','native_fixture.py')},
           'roster':{'path':'cases.json','sha256':v.sha(ref/'cases.json'),'named_groups':41,'maximum_requests':192,'native_fixture_schema':'coupled-native-fixtures-v1'},
           'model_pins':{n:'a'*64 for n in v.MODEL_FILES},'evidence':{},'limitations':[]}
        path=ref/'reference-manifest.json';path.write_text(json.dumps(m),encoding='utf-8')
        return ref,path,m

    def test_public_reference_packet_edit_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            ref,_,_=self.fixture(Path(name))
            with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref):
                v.reference_manifest();(ref/'references.json').write_bytes(b'{ }\n')
                with self.assertRaises(ValueError):v.reference_manifest()

    def test_public_reference_source_edit_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            ref,_,_=self.fixture(Path(name));(ref/'exact.py').write_bytes(b'changed\n')
            with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaises(ValueError):v.reference_manifest()

    def test_packet_path_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            ref,path,m=self.fixture(Path(name));m['packet']['path']='../references.json';path.write_text(json.dumps(m),encoding='utf-8')
            with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaises(ValueError):v.reference_manifest()

    def test_reference_omitted_extra_roster_rejected(self):
        for add in (False,True):
            with tempfile.TemporaryDirectory() as name:
                ref,path,m=self.fixture(Path(name))
                if add:m['source_files']['extra.py']=m['source_files']['exact.py']
                else:del m['source_files']['README.md']
                path.write_text(json.dumps(m),encoding='utf-8')
                with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaises(ValueError):v.reference_manifest()

    def test_generator_omitted_extra_keys_rejected(self):
        for add in (False,True):
            with tempfile.TemporaryDirectory() as name:
                ref,path,m=self.fixture(Path(name))
                if add:m['generator_sources']['../extra.py']=m['generator_sources']['exact.py']
                else:del m['generator_sources']['exact.py']
                path.write_text(json.dumps(m),encoding='utf-8')
                with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaises(ValueError):v.reference_manifest()

    def test_roster_contract_changes_rejected(self):
        for key,value in (('named_groups',40),('maximum_requests',193),('native_fixture_schema','invented-v1')):
            with tempfile.TemporaryDirectory() as name:
                ref,path,m=self.fixture(Path(name));m['roster'][key]=value;path.write_text(json.dumps(m),encoding='utf-8')
                with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaises(ValueError):v.reference_manifest()

    def test_reference_model_roster_omission_extra_escape_rejected(self):
        for mutation in ('omit','extra','escape','absolute','bad-hash'):
            with tempfile.TemporaryDirectory() as name:
                ref,path,m=self.fixture(Path(name));key=next(iter(m['model_pins']))
                if mutation=='omit':del m['model_pins'][key]
                elif mutation=='extra':m['model_pins']['extra.xml']='a'*64
                elif mutation=='escape':m['model_pins']['../outside.xml']=m['model_pins'].pop(key)
                elif mutation=='absolute':m['model_pins'][str((ref.parent/'outside.xml').resolve())]=m['model_pins'].pop(key)
                else:m['model_pins'][key]='A'*64
                path.write_text(json.dumps(m),encoding='utf-8')
                with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),self.assertRaisesRegex(ValueError,'closed reference model pin roster/hash'):v.reference_manifest()

    def test_resolved_escape_rejected_without_symlink_privilege(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);inside=root/'inside';inside.mkdir();outside=root/'outside.py';outside.write_bytes(b'fixture')
            # Mock only OS resolution of a valid contained pathname, modelling
            # a symlink/junction without requiring Windows symlink privilege.
            original=Path.resolve
            def resolve(path,*args,**kwargs):
                return outside if path==inside/'escaped.py' else original(path,*args,**kwargs)
            with patch.object(Path,'resolve',resolve),self.assertRaises(ValueError):v.contained(inside,'escaped.py')

    def test_generated_vendor_binding_omitted_extra_rejected(self):
        for add in (False,True):
            with tempfile.TemporaryDirectory() as name:
                probes,_,_,binding,record=self.build_fixture(Path(name))
                with patch.object(v,'HERE',probes),patch.object(v,'SOURCE_MANIFEST',binding):
                    v.source_files()
                    if add:record['files']['vendor-tree/extra']=record['files']['vendor-tree/src/FGJSBBase.h']
                    else:del record['files']['vendor-tree/src/FGJSBBase.h']
                    binding.write_text(json.dumps(record),encoding='utf-8')
                    with self.assertRaisesRegex(ValueError,'closed configured source binding roster'):v.source_files()

    def test_public_probe_shared_omission_rejected(self):
        for field in ('files','shared_sources'):
            with tempfile.TemporaryDirectory() as name:
                probes,path,public,binding,record=self.build_fixture(Path(name))
                del public[field][next(iter(public[field]))];path.write_text(json.dumps(public),encoding='utf-8')
                record['public_manifest_sha256']=v.sha(path);record['files']['public-probe-manifest'].update(sha256=v.sha(path),bytes=path.stat().st_size)
                binding.write_text(json.dumps(record),encoding='utf-8')
                with patch.object(v,'HERE',probes),patch.object(v,'SOURCE_MANIFEST',binding),self.assertRaisesRegex(ValueError,'closed public probe/shared source roster'):v.source_files()

    def test_strict_msvc_flags_reject_override(self):
        runner.strict('cl /fp:strict /c file.cpp',True)
        for s in ('cl /c file.cpp','cl /fp:strict /fp:fast /c file.cpp','cl /fp:precise /c file.cpp'):
            with self.assertRaises(ValueError):runner.strict(s,True)

    def test_strict_gcc_flags_reject_override(self):
        s='g++ -fno-fast-math -ffp-contract=off -frounding-math -c file.cpp';runner.strict(s,False)
        for changed in (s+' -Ofast',s.replace('-frounding-math','-fno-rounding-math'),s+' -ffp-contract=fast'):
            with self.assertRaises(ValueError):runner.strict(changed,False)

    def test_explicit_approval_required_before_authorization(self):
        with patch.object(runner,'qualify',side_effect=AssertionError('must not inspect/authorize')):
            with self.assertRaises(ValueError):runner.authorize({},Path('unused.json'),False)

    def pretrial_fixture(self,root):
        repo=root/'repo';repo.mkdir();ref=repo/'tests/engine/shaft-method/coupled-midpoint-v1';ref.mkdir(parents=True)
        prefix='tests/engine/shaft-method/'
        names={prefix+'probes/'+n for n in v.PROBE_FILES|{'probe-manifest.json'}}|v.SHARED_FILES
        names|={prefix+'coupled-midpoint-v1/'+n for n in v.REFERENCE_FILES|{'reference-manifest.json','references.json'}}
        names.add('native/consumer.cpp')
        inputs={}
        for name in names:
            p=repo/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'fixture\n');inputs[name]={'sha256':v.sha(p),'bytes':p.stat().st_size}
        data={'schema':'coupled-ci-pretrial-v1','scope':'fixed source/reference/budgets before fresh compilation; no native execution','source_inputs':inputs,'reference_manifest_sha256':v.sha(ref/'reference-manifest.json'),'packet_sha256':'1'*64,'required_ctests':['coupled_shaft_math','coupled_shaft_native','piston_engine_lifecycle']}
        path=root/'pretrial.json';path.write_text(json.dumps(data),encoding='utf-8')
        return repo,ref,path,data

    def test_pretrial_declared_source_edit_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            repo,ref,path,_=self.pretrial_fixture(Path(name))
            with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),patch.object(v,'reference_manifest',return_value={'packet':{'sha256':'1'*64}}):
                runner.verify_pretrial(path,repo,['native/consumer.cpp'])
                (repo/'native/consumer.cpp').write_bytes(b'changed\n')
                with self.assertRaisesRegex(ValueError,'source identity changed'):runner.verify_pretrial(path,repo,['native/consumer.cpp'])

    def test_pretrial_critical_omission_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            repo,ref,path,data=self.pretrial_fixture(Path(name))
            del data['source_inputs']['tests/engine/shaft-method/probes/validate.py'];path.write_text(json.dumps(data),encoding='utf-8')
            with patch.object(v,'HERE',ref.parent/'probes'),patch.object(v,'REFERENCE',ref),patch.object(v,'reference_manifest',return_value={'packet':{'sha256':'1'*64}}),self.assertRaisesRegex(ValueError,'omitted critical source closure'):runner.verify_pretrial(path,repo,['native/consumer.cpp'])

if __name__=='__main__':unittest.main()
