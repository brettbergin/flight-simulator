"""Source-only original piston profile checks; never imports or runs JSBSim."""
from pathlib import Path, PurePosixPath
from decimal import Decimal, localcontext
import argparse, hashlib, json, re, xml.etree.ElementTree as ET

IDENTITY = {'id':'original-piston-prop-v1','version':'0.1.0-prototype','backend_model':'original-piston-prop'}
STATUS = 'original-engineering-prototype-unvalidated-no-backend-trial'
XMLS = {'aircraft/original-piston-prop/original-piston-prop.xml','engine/original-piston.xml','engine/original-fixed-prop.xml'}
META = {'parameter-ledger.json','NOTICE-MIT.txt','README.md'}
LEGACY = 'native/fdm_jsbsim/models/original-interactive/aircraft/original-interactive/original-interactive.xml'
LEGACY_SHA = '0213ab8c1176e5d20b01f980da9cb94913f3e9ad8866838adc7e77bf3130722a'
ENGINE_UNITS = {'minmp':'INHG','maxmp':'INHG','man-press-lag':None,'displacement':'IN3','maxhp':'HP','static-friction':'HP','sparkfaildrop':None,'cycles':None,'idlerpm':None,'maxrpm':None,'maxthrottle':None,'minthrottle':None,'bsfc':'LBS/HP*HR','volumetric-efficiency':None,'compression-ratio':None,'bore':'IN','stroke':'IN','cylinders':None,'cylinder-head-mass':'KG','air-intake-impedance-factor':None,'ram-air-factor':None,'cooling-factor':None,'starter-rpm':None,'starter-torque':None,'dynamic-fmep':'PA','static-fmep':'PA','peak-piston-speed':None,'numboostspeeds':None,'oil-pressure-relief-valve-psi':'PSI','design-oil-temp-degK':'DEGK','oil-pressure-rpm-max':None,'oil-viscosity-index':None}
PROP_UNITS = {'ixx':'SLUG*FT2','diameter':'FT','numblades':None,'gearratio':None,'minpitch':None,'maxpitch':None,'minrpm':None,'maxrpm':None,'constspeed':None,'reversepitch':None,'ct_factor':None,'cp_factor':None}
class ContentError(ValueError): pass

def require(condition, message):
    if not condition: raise ContentError(message)
def sha(data): return hashlib.sha256(data).hexdigest()
def relative(name):
    return isinstance(name,str) and name and '\\' not in name and not re.search(r'[\x00-\x1f\x7f]',name) and not name.startswith('/') and all(x not in ('','.','..') for x in name.split('/')) and str(PurePosixPath(name))==name

def read(root, name):
    require(relative(name),'unsafe content path')
    candidate=root/name
    require(candidate.resolve().is_relative_to(root.resolve()),'escaping content path')
    require(not any(x.is_symlink() for x in [candidate,*candidate.parents] if x!=root.parent),'symlink content path')
    require(candidate.is_file() and candidate.stat().st_size<=1024*1024,'missing/oversized content file')
    data=candidate.read_bytes();require(b'\r' not in data,'content must use exact LF bytes');return data

def number(value):
    try: n=Decimal(value)
    except Exception as e: raise ContentError('invalid numeric scalar') from e
    require(n.is_finite(),'nonfinite scalar');return n

def parse(data):
    require(b'<!DOCTYPE' not in data.upper() and b'<!ENTITY' not in data.upper(),'external/entity XML prohibited')
    try: return ET.fromstring(data)
    except ET.ParseError as e: raise ContentError('invalid XML') from e

def scalar(root, tag):
    nodes=root.findall(tag);require(len(nodes)==1,'missing/duplicate scalar '+tag);return nodes[0]

def check(model_root, repo_root, reference_packet=None):
    root=Path(model_root);repo=Path(repo_root)
    inv=json.loads(read(root,'inventory.json'));ledger=json.loads(read(root,'parameter-ledger.json'))
    require({k:inv.get(k) for k in IDENTITY}==IDENTITY and ledger.get('identity')==IDENTITY,'wrong model identity')
    require(inv.get('status')==STATUS and ledger.get('status')==STATUS,'wrong unvalidated source status')
    require(inv.get('license')=='MIT' and ledger.get('license')=='MIT','wrong source license')
    require(inv.get('accepted_start')=='piston-cold-ground' and inv.get('controls_capability_revision')=='piston-controls-v1','wrong profile/start capability')
    require(inv.get('runtime_consumer')=='not-implemented','source package cannot claim a runtime consumer')
    require(isinstance(inv.get('files'),list) and isinstance(inv.get('metadata'),list),'missing file groups')
    require({x.get('path') for x in inv['files']}==XMLS and len(inv['files'])==len(XMLS),'wrong XML inventory')
    require({x.get('path') for x in inv['metadata']}==META and len(inv['metadata'])==len(META),'wrong metadata inventory')
    require(ledger.get('xml_files')==inv['files'],'ledger/XML inventory disagreement')
    for item in inv['files']+inv['metadata']:
        data=read(root,item['path']);require(type(item.get('bytes')) is int and len(data)==item['bytes'] and sha(data)==item.get('sha256'),'source hash/size mismatch '+item['path'])
    actual=set()
    for item in root.rglob('*'):
        require(not item.is_symlink(),'symlink in package')
        if item.is_file():actual.add(item.relative_to(root).as_posix())
    require(actual==XMLS|META|{'inventory.json'},'unlisted/missing package content')
    require(read(root,'NOTICE-MIT.txt')==(repo/'LICENSE').read_bytes().replace(b'\r\n',b'\n'),'MIT notice differs from project source')
    aircraft=parse(read(root,'aircraft/original-piston-prop/original-piston-prop.xml'))
    engine=parse(read(root,'engine/original-piston.xml'));prop=parse(read(root,'engine/original-fixed-prop.xml'))
    require(aircraft.tag=='fdm_config' and aircraft.get('version')=='2.0','wrong aircraft format')
    require(engine.tag=='piston_engine' and prop.tag=='propeller' and prop.get('version')=='1.1','wrong engine/prop type/convention')
    legacy_data=(repo/LEGACY).read_bytes().replace(b'\r\n',b'\n');require(sha(legacy_data)==LEGACY_SHA,'legacy ancestor source drift')
    legacy=parse(legacy_data)
    for tag in ['metrics','mass_balance','ground_reactions','flight_control','aerodynamics']:
        require(len(aircraft.findall(tag))==1 and ET.tostring(aircraft.find(tag))==ET.tostring(legacy.find(tag)),'inherited subtree drift '+tag)
    propulsion=scalar(aircraft,'propulsion');installed=scalar(propulsion,'engine');tank=scalar(propulsion,'tank');thruster=scalar(installed,'thruster')
    require(installed.get('file')=='original-piston' and thruster.get('file')=='original-fixed-prop' and installed.findtext('feed')=='0' and len(installed.findall('feed'))==1,'wrong engine/prop/feed topology')
    require(tank.get('type')=='FUEL' and tank.get('number')=='0','wrong single feed tank')
    for group,xml,units in [('engine',engine,ENGINE_UNITS),('propeller',prop,PROP_UNITS)]:
        values=[x for x in ledger['parameters'] if x['id'].startswith(group+'.')]
        require({x['id'].split('.',1)[1] for x in values}==set(units) and len(values)==len(units),'wrong scalar ledger')
        require({x.tag for x in xml if x.tag!='table'}==set(units) and len([x for x in xml if x.tag!='table'])==len(units),'unknown/missing/duplicate XML scalar')
        for value in values:
            name=value['id'].split('.',1)[1];node=scalar(xml,name);number(node.text)
            require(node.text==value['xml_value'] and node.get('unit')==value['xml_unit']==units[name],'scalar value/unit mismatch '+value['id'])
    require(prop.findtext('gearratio')=='1' and prop.findtext('constspeed')=='0' and prop.findtext('minpitch')==prop.findtext('maxpitch'),'direct fixed-pitch contract violated')
    require(number(prop.findtext('ixx'))>0 and number(prop.findtext('diameter'))>0,'nonpositive shaft geometry')
    require(engine.findtext('cycles')=='4' and engine.findtext('numboostspeeds')=='0','unsupported cycle/boost model')
    require(number(engine.findtext('compression-ratio'))>1 and number(engine.findtext('bsfc'))>0 and number(engine.findtext('idlerpm'))>0,'invalid engine scalar domain')
    all_tables={}
    for xml,names in [(engine,{'COMBUSTION','MIXTURE'}),(prop,{'C_THRUST','C_POWER'})]:
        nodes=xml.findall('table');require({x.get('name') for x in nodes}==names and len(nodes)==len(names),'wrong internal tables')
        for table in nodes:
            require(table.get('type')=='internal' and [x.tag for x in table]==['tableData'],'table must use internal 1D lookup')
            rows=[line.split() for line in table.findtext('tableData').strip().splitlines()];require(len(rows)>=2 and all(len(x)==2 for x in rows),'invalid table rows')
            for row in rows:number(row[0]);number(row[1])
            require(all(number(rows[i][0])<number(rows[i+1][0]) for i in range(len(rows)-1)),'unordered/duplicate lookup keys')
            name=table.get('name');require(rows==ledger['tables'][name]['rows'],'XML/table ledger disagreement');all_tables[name]=rows
    require(set(ledger['tables'])==set(all_tables),'unlisted ledger tables')
    require(all(number(x[1])>0 for x in all_tables['C_POWER']),'dissipative CP claim violated')
    install=ledger['installation']
    for tag,units,keys,expected in [('location','M',['x','y','z'],install['thruster_structural_location_m']),('orient','RAD',['roll','pitch','yaw'],install['thruster_orientation_rad'])]:
        node=scalar(thruster,tag);require(node.get('unit')==units and [node.findtext(x) for x in keys]==expected,'shaft installation frame/ledger mismatch')
    require(thruster.findtext('sense')==install['sense']=='1' and thruster.findtext('p_factor')==install['p_factor']=='0','unsupported sense/P-factor')
    for tag,unit in [('capacity','LBS'),('contents','LBS'),('unusable-volume','GAL'),('standpipe','LBS'),('radius','IN'),('density','LBS/GAL')]:
        require(scalar(tank,tag).get('unit')==unit,'wrong tank unit '+tag)
    require(tank.findtext('capacity')==tank.findtext('contents')==install['tank_capacity_contents_lbs'],'tank amount ledger mismatch')
    require(abs(number(tank.findtext('contents'))*Decimal('0.45359237')-Decimal(100))<Decimal('1e-24'),'cold recipe fuel is not100kg')
    require(tank.findtext('unusable-volume')==tank.findtext('standpipe')==tank.findtext('radius')=='0' and tank.findtext('priority')=='1','nonusable or unselected point tank')
    require(tank.findtext('density')==install['tank_density_lbs_gal'] and tank.findtext('temperature')==install['tank_temperature_sentinel'],'tank substrate ledger mismatch')
    with localcontext() as ctx:
        ctx.prec=60;geometry=ledger['geometry_derivation'];calc=number(engine.findtext('cylinders'))*number(geometry['pi_decimal'])*number(engine.findtext('bore'))**2*number(engine.findtext('stroke'))/4
        require(abs(calc-number(engine.findtext('displacement')))<Decimal('1e-50'),'cylinder displacement geometry mismatch')
    reference_sha = None
    if reference_packet is not None:
        reference_path=Path(reference_packet)
        packet_data=read(reference_path.parent,reference_path.name)
        packet=json.loads(packet_data)
        require(packet.get('format')=='original-piston-pre-solver-reference-v1','wrong reference packet format')
        bindings=packet.get('model_binding')
        expected=XMLS|{'parameter-ledger.json','inventory.json'}
        require(isinstance(bindings,list) and len(bindings)==len(expected) and {x.get('path') for x in bindings}==expected,'wrong reference model binding')
        for item in bindings:
            data=read(root,item['path']);require(len(data)==item.get('bytes') and sha(data)==item.get('sha256'),'reference binding mismatch '+item['path'])
        reference_sha=sha(packet_data)
    return {'reference_binding_checked':reference_sha is not None,'reference_packet_sha256':reference_sha,'reference_numeric_approval_asserted':False,'passed':True,'scope':'source-only; no JSBSim loader/solver/runtime acceptance','inventory_sha256':sha(read(root,'inventory.json')),'xml_files':inv['files'],'metadata':inv['metadata']}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--model-root',required=True);parser.add_argument('--repo-root',default='.');parser.add_argument('--reference-packet');args=parser.parse_args()
    print(json.dumps(check(args.model_root,args.repo_root,args.reference_packet),indent=2))
