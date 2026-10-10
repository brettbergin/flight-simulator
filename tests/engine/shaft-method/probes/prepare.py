"""Verbatim source extraction ONLY; no compiler, numerical code or process run."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
HERE=Path(__file__).resolve().parent

PINS={'FGPropeller.cpp':'e0ff11682070f2fa5a40ed7f14dbfcf56719a186089eb03185af8cdf9227d9f4',
      'FGPropeller.h':'730819eba6e87b94c75c8e02606f55a8006e54822f8f8f669f24d2941b1be6a5',
      'FGPiston.cpp':'509097a76de13c00ff29c6e86e4c475aa6cb14694c3091607be72acc92f730b9'}
def sha(b):return hashlib.sha256(b).hexdigest()
def between(s,a,b):
    assert s.count(a)==1,a
    i=s.index(a);assert s.count(b,i)==1,b
    return s[i:s.index(b,i)]
def main():
    parser=argparse.ArgumentParser()
    for name in ('vendor-root','template-root','output','repo-root','build-root'):
        parser.add_argument('--'+name,required=True,type=Path)
    a=parser.parse_args();vendor=a.vendor_root.resolve();templates=a.template_root.resolve()
    locations={n:vendor/'src/models/propulsion'/n for n in PINS}
    files={n:path.read_bytes() for n,path in locations.items()}
    for n,b in files.items():assert sha(b)==PINS[n],n
    cpp,h,piston=(files[n].decode() for n in ('FGPropeller.cpp','FGPropeller.h','FGPiston.cpp'))
    pi_source=vendor/'src/FGJSBBase.h'
    pi_bytes=pi_source.read_bytes()
    assert sha(pi_bytes)=='f9d2478597ec4cf358900e9d33c0428f531c88f83f58ea0b4803a82deb652d9b'
    pi=pi_bytes.decode();i=pi.index('#ifndef M_PI\n');pi=pi[i:pi.index('#endif',i)+len('#endif')]
    assert '3.14159265358979323846' in pi
    values={
      '@@PINNED_PI@@':pi,
      '@@OWNED_TYPES@@':between(h,'// Original project ADR015 internal values,','/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\nCLASS DOCUMENTATION'),
      '@@EXACT_HELPERS@@':between(cpp,'// Original project modification, 2026-10-09.','} // anonymous namespace\n')+'} // anonymous namespace\n',
      '@@PISTON_CHECK@@':between(piston,'double PistonCoupledValueV1(double v)','}\n}\n\nvoid FGPiston::CalculateCoupled')+'}\n',
      '@@EXACT_MODE_POLICY@@':between(piston,'  if(Running) {\n    if(!spark || !fuel','\n\n  const double twoPi='),
      '@@EXACT_RATIO@@':between(piston,'  const double ratio=PistonCoupledValueV1(equivalence_ratio/14.7);','  const double ME=PistonCoupledValueV1'),
      '@@EXACT_SOURCE_FACTORS@@':between(piston,'  const double twoPi=PistonCoupledValueV1(2.0*M_PI);','  FMEP=0.0;'),
      '@@EXACT_COEFFICIENTS@@':between(piston,'  // Straight-line coefficient construction.','  CoupledShaftFrameV1 frame{'),
      '@@EXACT_WRAPPER@@':between(cpp,'    if(!frame || !std::isfinite(RPM)','  } else {\n    ShaftReject("event-aware shaft: unknown angular method");'),
    }
    # These two statements occur in the preserved pre-stage source; do not carry
    # the unrelated thrust/load block into the isolated angular wrapper fixture.
    encode=['  double RPS = RPM/60.0;\n','  omega = RPS*2.0*M_PI;\n']
    for line in encode:assert cpp.count(line)==1
    values['@@EXACT_ENCODE@@']=''.join(encode)
    template=(templates/'driver.template.cpp').read_bytes();driver=template.decode()
    # The helper block is exact vendor bytes in a uniquely named SYSTEM header.
    # The driver, wrapper, owned types and standard includes stay outside it.
    helper_name='flight_coupled_exact_vendor_helpers_v1.inc'
    helpers=values['@@EXACT_HELPERS@@'].encode()
    assert sha(helpers)=='f207d3d7dde6fe4b36c7112aa78cb235201a1de2172c168a96733c7f6323db6c','Verbatim helper header changed'
    assert driver.count('#include <'+helper_name+'>')==1
    for key,value in values.items():
        if key=='@@EXACT_HELPERS@@':continue
        assert driver.count(key)==1,key
        driver=driver.replace(key,value)
    assert '@@' not in driver
    target=a.output.resolve()
    assert not target.exists() or not any(target.iterdir()),'Preserve old extraction; use a fresh build directory'
    target.mkdir(parents=True,exist_ok=True)
    data=driver.encode()
    assert sha(data)=='962373cc03fc6ce3d44e9f7220ac0d565335682f52a4f6cb7852989be8b7ab38','Verbatim driver changed'
    (target/'driver.cpp').write_bytes(data)
    (target/helper_name).write_bytes(helpers)
    receipt={'status':'SOURCE_ONLY_NO_COMPILER_OR_NUMERICAL_EXECUTION','vendor_source_sha256':PINS,
      'pi_source_sha256':sha(pi_bytes),'template_sha256':sha(template),'prepare_sha256':sha(Path(__file__).read_bytes()),
      'driver_sha256':sha(data),'helper_header':{'path':helper_name,'bytes':len(helpers),'sha256':sha(helpers)},'sections':{k:{'bytes':len(v.encode()),'sha256':sha(v.encode())} for k,v in values.items()}}
    (target/'extraction-binding.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8',newline='\n')
    spec=importlib.util.spec_from_file_location('static_chronology',templates/'source-chronology.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    evidence=module.build_evidence(vendor)
    (target/'chronology-source-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8',newline='\n')
    # Configure declarations are build identity, never actual DLL proof.
    build=a.build_root.resolve();repo=a.repo_root.resolve()
    build_manifest=build/'jsbsim-source-build-manifest.txt'
    text=build_manifest.read_text(encoding='utf-8')
    def field(name):
        rows=[line[len(name)+2:] for line in text.splitlines() if line.startswith(name+': ')]
        assert len(rows)==1,name
        return rows[0]
    assert field('Source variant')=='jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
    assert Path(field('Selected source root')).resolve()==vendor
    consumer=build/'interactive-source-fingerprint.txt'
    fingerprint=consumer.read_text(encoding='utf-8').splitlines()[0]
    assert len(fingerprint)==64 and all(c in '0123456789abcdef' for c in fingerprint)
    public_manifest=templates/'probe-manifest.json'
    manifest=json.loads(public_manifest.read_bytes())
    assert manifest['schema']=='coupled-probe-source-manifest-v1'
    bound={}
    def bind(label,path,want=None):
        data=path.read_bytes();got=sha(data)
        if want is not None:assert got==want,label
        bound[label]={'path':str(path.resolve()),'sha256':got,'bytes':len(data)}
    for name,meta in manifest['files'].items():bind('probes/'+name,templates/name,meta['sha256'])
    bind('public-probe-manifest',public_manifest)
    for name,meta in manifest['shared_sources'].items():bind('shared/'+name,repo/name,meta['sha256'])
    for name,path in locations.items():bind('vendor/'+name,path,PINS[name])
    vendor_roster=sorted(str(path.relative_to(vendor)).replace('\\','/') for path in vendor.rglob('*') if path.is_file())
    for name in vendor_roster:bind('vendor-tree/'+name,vendor/name)
    bind('vendor/FGJSBBase.h',pi_source,receipt['pi_source_sha256'])
    bind('vendor/FGPropulsion.cpp',vendor/'src/models/FGPropulsion.cpp')
    bind('loaded-library.hpp',repo/'tests/engine/loaded-library.hpp')
    bind('Session.cpp',repo/'native/fdm_jsbsim/interactive/src/session.cpp')
    bind('source-build-manifest',build_manifest);bind('consumer-fingerprint',consumer)
    bind('generated-driver',target/'driver.cpp');bind('generated-helpers',target/helper_name)
    bind('extraction-binding',target/'extraction-binding.json')
    bind('static-chronology',target/'chronology-source-evidence.json')
    record={'schema':'coupled-probe-build-source-v1','public_manifest_sha256':sha(public_manifest.read_bytes()),
      'backend_identity_sha256':field('Backend identity SHA256'),
      'build_control_sha256':field('Build controls SHA256'),'consumer_fingerprint':fingerprint,
      'vendor_root':str(vendor),'vendor_roster':vendor_roster,'repository_root':str(repo),
      'template_root':str(templates),'build_root':str(build),'files':bound}
    (target/'source-manifest.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
