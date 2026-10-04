import hashlib,json,shutil,unittest,uuid,os
from pathlib import Path
import xml.etree.ElementTree as ET
from check_model import check,ContentError
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
MODEL=Path(os.environ.get("FLIGHT_ENGINE_MODEL_PACK",str(ROOT/"publish-candidate" if (ROOT/"publish-candidate").exists() else REPO/"native/fdm_jsbsim/models/original-piston-prop")))
class ContentChecks(unittest.TestCase):
    def setUp(self):
        self.fixtures=ROOT/'check-fixtures';self.fixtures.mkdir(exist_ok=True)
        self.path=self.fixtures/uuid.uuid4().hex;shutil.copytree(MODEL,self.path)
    def tearDown(self):
        target=self.path.resolve();assert target.is_relative_to(self.fixtures.resolve()) and target!=self.fixtures.resolve()
        shutil.rmtree(target)
    def rebind(self):
        inv=json.loads((self.path/'inventory.json').read_text());ledger=json.loads((self.path/'parameter-ledger.json').read_text())
        for f in inv['files']:
            b=(self.path/f['path']).read_bytes();f.update(bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
        ledger['xml_files']=inv['files'];(self.path/'parameter-ledger.json').write_text(json.dumps(ledger,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
        for f in inv['metadata']:
            b=(self.path/f['path']).read_bytes();f.update(bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
        (self.path/'inventory.json').write_text(json.dumps(inv,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    def reject(self,message):
        with self.assertRaisesRegex(ContentError,message):check(self.path,REPO)
    def edit(self,name,mutate):
        file=self.path/name;tree=ET.parse(file);mutate(tree.getroot());file.write_bytes(ET.tostring(tree.getroot(),encoding='utf-8',xml_declaration=True))
    def test_exact_original_source_passes(self):self.assertTrue(check(self.path,REPO)['passed'])
    def test_hash_drift_rejects(self):
        with (self.path/'engine/original-piston.xml').open('ab') as f:f.write(b'\n')
        self.reject('source hash')
    def test_rehashed_wrong_shaft_unit_rejects(self):
        self.edit('engine/original-fixed-prop.xml',lambda root:root.find('ixx').set('unit','KG*M2'))
        ledger=json.loads((self.path/'parameter-ledger.json').read_text());next(x for x in ledger['parameters'] if x['id']=='propeller.ixx')['xml_unit']='KG*M2';(self.path/'parameter-ledger.json').write_text(json.dumps(ledger)+'\n',encoding='utf-8',newline='\n')
        self.rebind();self.reject('unit mismatch')
    def test_rehashed_wrong_drive_ratio_rejects(self):
        self.edit('engine/original-fixed-prop.xml',lambda root:setattr(root.find('gearratio'),'text','2'))
        ledger=json.loads((self.path/'parameter-ledger.json').read_text());next(x for x in ledger['parameters'] if x['id']=='propeller.gearratio')['xml_value']='2';(self.path/'parameter-ledger.json').write_text(json.dumps(ledger)+'\n',encoding='utf-8',newline='\n')
        self.rebind();self.reject('direct fixed-pitch')
    def test_rehashed_table_duplicate_key_rejects(self):
        def duplicate(root):
            node=root.find("table[@name='C_POWER']/tableData");node.text='\n-1 .06\n0 .06\n0 .04\n2 .02\n'
        self.edit('engine/original-fixed-prop.xml',duplicate)
        ledger=json.loads((self.path/'parameter-ledger.json').read_text());ledger['tables']['C_POWER']['rows']=[['-1','.06'],['0','.06'],['0','.04'],['2','.02']];(self.path/'parameter-ledger.json').write_text(json.dumps(ledger)+'\n',encoding='utf-8',newline='\n')
        self.rebind();self.reject('unordered/duplicate')
    def test_rehashed_legacy_gear_drift_rejects(self):
        self.edit('aircraft/original-piston-prop/original-piston-prop.xml',lambda root:setattr(root.find('ground_reactions/contact/static_friction'),'text','0.9'))
        self.rebind();self.reject('inherited subtree drift')
    def test_rehashed_external_engine_alias_rejects(self):
        self.edit('aircraft/original-piston-prop/original-piston-prop.xml',lambda root:root.find('propulsion/engine').set('file','../../other'))
        self.rebind();self.reject('topology')
    def test_extra_content_rejects(self):
        (self.path/'unreviewed-model.xml').write_text('<fdm_config/>');self.reject('unlisted/missing')
    def test_false_runtime_status_rejects(self):
        inv=json.loads((self.path/'inventory.json').read_text());inv['runtime_consumer']='validated';(self.path/'inventory.json').write_text(json.dumps(inv)+'\n',encoding='utf-8',newline='\n');self.reject('cannot claim')
    def test_mismatched_reference_metadata_cannot_bind_source(self):
        inv=json.loads((self.path/'inventory.json').read_text())
        bindings=list(inv['files'])
        for name in ['parameter-ledger.json','inventory.json']:
            data=(self.path/name).read_bytes();bindings.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        next(x for x in bindings if x['path']=='parameter-ledger.json')['sha256']='0'*64
        packet=self.fixtures/(uuid.uuid4().hex+'.json')
        try:
            packet.write_bytes((json.dumps({'format':'original-piston-pre-solver-reference-v1','model_binding':bindings})+'\n').encode('utf-8'))
            with self.assertRaisesRegex(ContentError,'reference binding mismatch'):check(self.path,REPO,packet)
        finally:packet.unlink()
    def test_wrong_profile_metadata_rejects(self):
        inv=json.loads((self.path/'inventory.json').read_text());inv['id']='c172';(self.path/'inventory.json').write_text(json.dumps(inv)+'\n',encoding='utf-8',newline='\n');self.reject('identity')
if __name__=='__main__':unittest.main()
