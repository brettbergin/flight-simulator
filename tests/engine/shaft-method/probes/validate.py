"""Offline request preparation / saved-output comparison. NEVER launches a process.

Independent generator owns native_cases expectations. Root owns execution,
ratification, actual-module identity and pre/post executable/DLL observations.
"""
from pathlib import Path
from fractions import Fraction as Q
import argparse,hashlib,importlib.util,json,math,re,struct
HERE=Path(__file__).resolve().parent
SOURCE_MANIFEST=None
REFERENCE=HERE.parent/'coupled-midpoint-v1'
REFERENCE_FILES={'generate.py','exact.py','native_fixture.py','cases.json','test_reference.py','test_native_fixture.py','README.md','COMPARISON-PLAN.md','NATIVE-FIXTURES.md'}
PROBE_FILES={'CMakeLists.txt','prepare.py','driver.template.cpp','library-probe.cpp','chronology-probe.cpp','terminal-retention.cpp','validate.py','test_validate.py','legacy_compare.py','source-chronology.py','run.py','test_portable.py','README.md'}
SHARED_FILES={'tests/engine/loaded-library.hpp','tests/engine/reference/expected-v3.json','tests/engine/CMakeLists.txt','tools/bootstrap/build.ps1'}
MODEL_FILES={'native/fdm_jsbsim/models/original-piston-prop/engine/original-fixed-prop.xml','native/fdm_jsbsim/models/original-piston-prop/engine/original-piston.xml'}
GROUPS={f'{p}{i:02}' for p,n in [('C',7),('K',16),('E',7),('R',5),('M',6)] for i in range(1,n+1)}
CHRONO_IDS=['M01-mixture-cutoff','M01-spark-cutoff','M02-feed-first','M02-feed-second']+[f'M03-rpm-{p}-{s}' for p in range(2) for s in range(3)]+['M04-crossing-first','M04-crossing-next']
HEX=re.compile(r'[0-9a-f]{16}\Z');ID=re.compile(r'[A-Za-z0-9_.-]+\Z')
def demand(b,why):
    if not b:raise ValueError(why)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def unique(pairs):
    result={}
    for k,v in pairs:demand(k not in result,f'duplicate JSON key {k}');result[k]=v
    return result
def load(p):
    return json.loads(Path(p).read_text(encoding='utf-8'),object_pairs_hook=unique,
        parse_constant=lambda x:(_ for _ in ()).throw(ValueError('nonfinite JSON '+x)))
def lines(p):
    text=Path(p).read_text(encoding='utf-8');demand(text.endswith('\n'),'truncated output')
    return [json.loads(s,object_pairs_hook=unique,parse_constant=lambda x:(_ for _ in ()).throw(ValueError(x))) for s in text.splitlines()]
def qbits(s):
    demand(isinstance(s,str) and HEX.fullmatch(s),'invalid result bits')
    x=struct.unpack('>d',bytes.fromhex(s))[0];demand(math.isfinite(x),'nonfinite result bits');return Q.from_float(x)
def bound(x):
    demand(isinstance(x,str) and re.fullmatch(r'-?\d+(?:/[1-9]\d*)?',x),'invalid exact rational bound');return Q(x)
def interval(spec):
    demand(isinstance(spec,dict) and set(spec)=={'lo','hi'},'invalid interval keys')
    lo,hi=bound(spec['lo']),bound(spec['hi']);demand(lo<=hi,'inverted interval');return lo,hi
def dyadic(a):
    demand(set(a)=={'sign','exponent','limbs_le'},'invalid dyadic fields')
    sign,exp,limbs=a['sign'],a['exponent'],a['limbs_le']
    demand(type(sign)is int and sign in (-1,0,1) and type(exp)is int and -100000<exp<100000,'invalid dyadic sign/exponent')
    demand(isinstance(limbs,list) and len(limbs)<=128 and all(type(x)is int and 0<=x<2**32 for x in limbs),'invalid limbs')
    n=sum(x<<(32*i) for i,x in enumerate(limbs));demand((sign==0)==(n==0),'inconsistent zero')
    return sign*Q(n)*(Q(2)**exp)
def ratio(a):
    demand(set(a)=={'n','d'},'invalid ratio fields');n,d=dyadic(a['n']),dyadic(a['d']);demand(d>0,'nonpositive ratio denominator');return n/d
def expectation_policy(case):
    kind,e=case['kind'],case['expected']
    demand(isinstance(e,dict) and set(e)<={'status','fields','intervals','remaining','reason'},'invalid expected shape')
    if e['status']=='reject':
        demand(set(e)=={'status','reason'},'rejection must carry only exact reason');return
    fields=e.get('fields',{});intervals=e.get('intervals',{})
    demand(isinstance(fields,dict) and isinstance(intervals,dict),'invalid comparison maps')
    exact={'K':{'w_bits','hold','stop','source_event'},'E':{'w_bits','hold','stop','cp_crossings','starter_crossings'},'W':{'rpm_bits'},'P':{'running'}}
    coeff={'C':{'c0_bits','c1_bits','c2_bits','t0_bits','ws_bits'},'L':{'c0_bits','c1_bits','c2_bits','c3_bits'}}
    if kind in exact:
        demand(set(fields)==exact[kind] and not intervals,'exact-field comparison required')
    elif kind in coeff:
        demand(e['status']=='coefficients' and not fields and set(intervals)==coeff[kind],'complete absolute coefficient intervals required')
    else:demand(kind=='G' and set(e)=={'status'} and e['status']=='accept','unexpected guard expectation')
    if 'remaining' in e:
        demand(kind=='K' and e['status'] in ('stop','event'),'unexpected remainder expectation')
        lo,hi=interval(e['remaining']);demand(lo==hi,'exact point remainder required')
    if kind=='K':demand(('remaining' in e)==(e['status'] in ('stop','event')),'missing exact event/stop remainder')

def request_bytes(cases):
    return ''.join(c['request_id']+' '+c['kind']+' '+' '.join(c['request_tokens'])+'\n' for c in cases).encode('ascii')

def shape(case):
    demand(isinstance(case,dict),'invalid native case')
    demand(case['group_id'] in GROUPS and ID.fullmatch(case['request_id']),'unknown group/bad request id')
    kind,t=case['kind'],case['request_tokens'];demand(isinstance(t,list) and all(isinstance(x,str) for x in t),'tokens must be strings')
    # Exact positional grammar: no free-form commands, implicit float parsing or
    # missing fields can masquerade as an expected production rejection.
    if kind=='K':
        demand(len(t)==9 and t[7] in ('0','1'),'invalid K shape');indices=list(range(7))+[8]
        h=qbits(t[6]);demand(h==0 or -60<=math.frexp(abs(float(h)))[1]-1<=60,'unsupported initial K h domain')
    elif kind in ('E','W'):
        invalid_mode=case['group_id']=='R02' and case['expected'].get('reason')=='coupled shaft: unknown operating mode'
        demand(len(t)==13 and t[0] in (('0','1','2','3') if invalid_mode else ('0','1','2')),'invalid E/W shape');indices=list(range(1,13))
        if kind=='W':demand(t[8]=='0000000000000000','W unused w must be zero')
    elif kind=='C':demand(len(t)==23 and all(x in ('0','1') for x in t[:2]),'invalid C shape');indices=list(range(2,23))
    elif kind=='L':demand(len(t)==13 and t[0] in ('0','1','2') and t[-1] in ('-1','1'),'invalid L shape');indices=list(range(1,12))
    elif kind=='P':demand(len(t)==6 and all(x in ('0','1') for x in t[:3]),'invalid P shape');indices=[3,4,5]
    elif kind=='G':
        demand(bool(t),'missing guard');name=t[0]
        if name=='operand':demand(len(t)==2,'operand guard shape');indices=[1]
        else:
            demand(len(t)==1 and name in {'product','bisect64','split8','capacity128','ftz','daz','rounding'},'unknown guard');indices=[]
    else:raise ValueError('unknown request kind')
    for i in indices:demand(HEX.fullmatch(t[i]) is not None,'invalid scalar token bits')
    expected=case['expected'];demand(expected['status'] in {'advance','hold','stop','event','reject','accept','policy','coefficients'},'unknown expected category')
    demand(set(expected)<={'status','fields','intervals','remaining','reason'},'unknown expected field')
    if expected['status']=='reject':demand(isinstance(expected.get('reason'),str) and expected['reason'].startswith(('coupled shaft:','coupled piston:','event-aware shaft:')),'missing exact production rejection')
    else:demand('reason' not in expected,'reason on accepted case')
    for s in expected.get('intervals',{}).values():interval(s)
    if 'remaining'in expected:interval(expected['remaining'])
    expectation_policy(case)
def native_cases(packet):
    demand(packet['schema']=='coupled-midpoint-reference-v1' and packet['method']=='event_aware_coupled_midpoint_v1' and packet['contract_merge']=='eb410a634a9f18b4ea9177640aff391def5e7988','wrong packet contract/method')
    demand(packet['named_group_count']==41 and packet['backend_pi_bits']=='400921fb54442d18','wrong finite group/pi contract')
    manifest=reference_manifest()
    demand(packet['generator_sources']==manifest['generator_sources'],'packet generator source mismatch')
    demand(packet['roster_sha256']==manifest['roster']['sha256'],'packet roster source mismatch')
    demand(packet['native_fixture_schema']=='coupled-native-fixtures-v1','wrong native fixture schema')
    scope=packet['native_fixture_scope'];demand(type(scope['maximum_requests'])is int and scope['maximum_requests']==192,'wrong fixed request ceiling')
    cases=packet['native_cases'];demand(isinstance(cases,list) and 0<len(cases)<=scope['maximum_requests'],'native_cases absent/over ceiling')
    for c in cases:shape(c)
    ids=[c['request_id'] for c in cases];demand(len(ids)==len(set(ids)),'duplicate request id')
    covered={c['group_id'] for c in cases}|{'M01','M02','M04','M05','M06','R03'}
    demand(covered==GROUPS,f'incomplete/extra41-group coverage: {sorted(GROUPS-covered)}')
    return cases
def contained(root,name):
    demand(isinstance(name,str) and bool(name) and not Path(name).is_absolute() and '..' not in Path(name).parts,'invalid contained source path')
    path=(root/name).resolve(strict=True)
    demand(path.is_relative_to(root.resolve(strict=True)),'source path escaped its root')
    return path

def file_identity(path,meta):
    demand(isinstance(meta,dict) and set(meta)=={'sha256','bytes'} and type(meta['bytes'])is int and meta['bytes']>=0 and isinstance(meta['sha256'],str) and re.fullmatch(r'[0-9a-f]{64}',meta['sha256']),'invalid source identity')
    demand(path.is_file() and path.stat().st_size==meta['bytes'] and sha(path)==meta['sha256'],'source identity changed: '+str(path))

def reference_manifest():
    demand(REFERENCE.resolve(strict=True).is_relative_to(HERE.parent.resolve(strict=True)),'public reference root escaped suite')
    manifest=load(contained(REFERENCE,'reference-manifest.json'))
    demand(set(manifest)=={'schema','method','contract_merge','packet','generator_sources','roster','source_files','model_pins','evidence','limitations'},'wrong public reference manifest fields')
    demand(manifest['schema']=='coupled-midpoint-reference-manifest-v1','wrong public reference manifest')
    demand(manifest['method']=='event_aware_coupled_midpoint_v1' and manifest['contract_merge']=='eb410a634a9f18b4ea9177640aff391def5e7988','wrong reference manifest contract')
    demand(isinstance(manifest['model_pins'],dict) and set(manifest['model_pins'])==MODEL_FILES and all(isinstance(want,str) and re.fullmatch(r'[0-9a-f]{64}',want) for want in manifest['model_pins'].values()),'wrong closed reference model pin roster/hash')
    demand(set(manifest['source_files'])==REFERENCE_FILES,'wrong closed reference source roster')
    for name,meta in manifest['source_files'].items():
        file_identity(contained(REFERENCE,name),meta)
    packet=manifest['packet'];demand(set(packet)=={'path','bytes','sha256'} and packet['path']=='references.json','wrong packet basename/fields')
    file_identity(contained(REFERENCE,packet['path']),{k:packet[k] for k in ('bytes','sha256')})
    demand(set(manifest['generator_sources'])=={'generate.py','exact.py','native_fixture.py'},'wrong generator source roster')
    for name,want in manifest['generator_sources'].items():demand(want==manifest['source_files'][name]['sha256'] and sha(contained(REFERENCE,name))==want,'generator identity changed')
    roster=manifest['roster']
    demand(set(roster)=={'path','sha256','named_groups','maximum_requests','native_fixture_schema'} and roster['path']=='cases.json','wrong reference roster fields/path')
    demand(type(roster['named_groups'])is int and roster['named_groups']==41 and type(roster['maximum_requests'])is int and roster['maximum_requests']==192 and roster['native_fixture_schema']=='coupled-native-fixtures-v1','wrong reference fixture roster contract')
    demand(roster['sha256']==manifest['source_files']['cases.json']['sha256'] and sha(contained(REFERENCE,'cases.json'))==roster['sha256'],'roster identity changed')
    return manifest

def source_files():
    demand(SOURCE_MANIFEST is not None,'explicit configured source manifest required')
    binding=load(SOURCE_MANIFEST);demand(binding['schema']=='coupled-probe-build-source-v1','wrong source manifest schema')
    demand(set(binding)=={'schema','public_manifest_sha256','backend_identity_sha256','build_control_sha256','consumer_fingerprint','vendor_root','vendor_roster','repository_root','template_root','build_root','files'},'wrong build source manifest fields')
    vendor=Path(binding['vendor_root'])
    repo=HERE.parents[3].resolve();build=Path(binding['build_root']).resolve()
    demand(vendor.is_absolute() and Path(binding['repository_root']).samefile(repo) and Path(binding['template_root']).samefile(HERE),'wrong source roots')
    demand(Path(SOURCE_MANIFEST).resolve().is_relative_to(build),'generated manifest escaped build root')
    demand(binding['vendor_roster']==sorted(str(path.relative_to(vendor)).replace('\\','/') for path in vendor.rglob('*') if path.is_file()),'selected vendor roster changed')
    paths={}
    paths.update({'probes/'+n:contained(HERE,n) for n in PROBE_FILES})
    paths.update({'shared/'+n:contained(repo,n) for n in SHARED_FILES})
    paths.update({'vendor-tree/'+n:contained(vendor,n) for n in binding['vendor_roster']})
    paths.update({'vendor/'+n:contained(vendor,'src/models/propulsion/'+n) for n in ('FGPropeller.cpp','FGPropeller.h','FGPiston.cpp')})
    paths.update({'public-probe-manifest':contained(HERE,'probe-manifest.json'),
      'vendor/FGJSBBase.h':contained(vendor,'src/FGJSBBase.h'),
      'vendor/FGPropulsion.cpp':contained(vendor,'src/models/FGPropulsion.cpp'),
      'loaded-library.hpp':contained(repo,'tests/engine/loaded-library.hpp'),
      'Session.cpp':contained(repo,'native/fdm_jsbsim/interactive/src/session.cpp'),
      'source-build-manifest':contained(build,'jsbsim-source-build-manifest.txt'),
      'consumer-fingerprint':contained(build,'interactive-source-fingerprint.txt'),
      'generated-driver':contained(Path(SOURCE_MANIFEST).parent,'driver.cpp'),
      'extraction-binding':contained(Path(SOURCE_MANIFEST).parent,'extraction-binding.json'),
      'static-chronology':contained(Path(SOURCE_MANIFEST).parent,'chronology-source-evidence.json')})
    demand(set(binding['files'])==set(paths),'wrong closed configured source binding roster')
    for name,path in paths.items():
        meta=binding['files'][name]
        demand(set(meta)=={'path','sha256','bytes'} and Path(meta['path']).is_absolute() and Path(meta['path']).samefile(path),'configured path differs: '+name)
        file_identity(path,{k:meta[k] for k in ('sha256','bytes')})
    public=load(contained(HERE,'probe-manifest.json'))
    demand(set(public)=={'schema','files','shared_sources'},'wrong public probe manifest fields')
    demand(public['schema']=='coupled-probe-source-manifest-v1','wrong probe source manifest')
    demand(set(public['files'])==PROBE_FILES and set(public['shared_sources'])==SHARED_FILES,'wrong closed public probe/shared source roster')
    for name,meta in public['files'].items():
        path=contained(HERE,name);file_identity(path,meta)
        demand(binding['files']['probes/'+name]['sha256']==meta['sha256'] and Path(binding['files']['probes/'+name]['path']).samefile(path),'configured source differs: '+name)
    for name,meta in public['shared_sources'].items():
        path=contained(HERE.parents[3],name);file_identity(path,meta)
        got=binding['files']['shared/'+name];demand(got['sha256']==meta['sha256'] and got['bytes']==meta['bytes'] and Path(got['path']).samefile(path),'configured shared source differs: '+name)
    demand(binding['public_manifest_sha256']==sha(HERE/'probe-manifest.json'),'public source manifest changed')
    return {'binding_sha256':sha(SOURCE_MANIFEST),'files':binding['files']}

def legacy_comparator():
    path=HERE/'legacy_compare.py'
    spec=importlib.util.spec_from_file_location('preserved_legacy_comparator',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def prepare(a):
    demand(sha(a.packet)==a.packet_sha256==reference_manifest()['packet']['sha256'],'packet identity mismatch');packet=load(a.packet);cases=native_cases(packet)
    source=source_files();out=Path(a.output);out.mkdir(exist_ok=False)
    (out/'requests.txt').write_bytes(request_bytes(cases))
    legacy=legacy_comparator();_,legacy_cases=legacy.load_reference();(out/'legacy-requests.txt').write_bytes(legacy.requests(legacy_cases))
    plan={'status':'PREPARED_SOURCE_REQUESTS_ONLY_NO_EXECUTION','packet_path':str(Path(a.packet).resolve()),'packet_sha256':a.packet_sha256,'source':source,'requests_sha256':sha(out/'requests.txt'),'legacy_requests_sha256':sha(out/'legacy-requests.txt'),'native_request_ids':[c['request_id'] for c in cases],'chronology_ids':CHRONO_IDS,'named_groups':sorted(GROUPS)}
    (out/'plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8',newline='\n')
def compare_native(cases,rows):
    demand(len(rows)==len(cases),'native row count mismatch');result={}
    for case,row in zip(cases,rows):
        demand(row['id']==case['request_id'] and row['kind']==case['kind'],'row ID/kind/order mismatch')
        demand(row['id'] not in result,'duplicate output id');result[row['id']]=row
        expectation_policy(case)
        expected=case['expected'];rejected=expected['status']=='reject'
        demand(type(row['rejected']) is bool and row['rejected']==rejected,'unexpected admission/rejection '+row['id'])
        if rejected:
            demand(set(row)=={'id','kind','rejected','reason'} and row['reason']==expected['reason'],'wrong production rejection '+row['id']);continue
        allowed={'K':{'w_bits','hold','stop','source_event','remaining'},'E':{'w_bits','hold','stop','cp_crossings','starter_crossings'},'W':{'rpm_bits'},'C':{'c0_bits','c1_bits','c2_bits','t0_bits','ws_bits'},'L':{'c0_bits','c1_bits','c2_bits','c3_bits'},'P':{'running'},'G':set()}[case['kind']]
        demand(set(row)=={'id','kind','rejected'}|allowed,'unexpected result shape '+row['id'])
        # Every emitted meaningful scalar must have an independent expectation.
        checked=set(expected.get('fields',{}))|set(expected.get('intervals',{}))
        ignored={'remaining'} if case['kind']=='K' and 'remaining'not in expected else set()
        demand(checked|({'remaining'} if 'remaining'in expected else set())|ignored==allowed,'incomplete expected result coverage '+row['id'])
        for key,wanted in expected.get('fields',{}).items():demand(type(row[key])is type(wanted) and row[key]==wanted,'exact field mismatch '+row['id']+'/'+key)
        for key,spec in expected.get('intervals',{}).items():
            lo,hi=interval(spec);demand(lo<=qbits(row[key])<=hi,'outside independent interval '+row['id']+'/'+key)
        if 'remaining'in expected:
            lo,hi=interval(expected['remaining']);demand(lo<=ratio(row['remaining'])<=hi,'wrong exact remainder '+row['id'])
    return result

# Independent elementary IEEE error intervals for M01's diagnostic-only power.
# No numerical threshold learned from solver output and no generic gamma count.
U=Q(1,2**53)
def rn(v):
    lo,hi=v;demand(lo<=hi,'bad interval');e=max(abs(lo),abs(hi))*U/(1-U);return lo-e,hi+e
def c(s):return rn((Q(s),Q(s)))
def add(a,b):return rn((a[0]+b[0],a[1]+b[1]))
def neg(a):return -a[1],-a[0]
def mul(a,b):
    v=[x*y for x in a for y in b];return rn((min(v),max(v)))
def div(a,b):
    demand(not b[0]<=0<=b[1],'interval denominator contains zero');v=[x/y for x in a for y in b];return rn((min(v),max(v)))
def obs(x):demand(type(x)in (int,float) and math.isfinite(x),'nonfinite observation');q=Q(x);return q,q
def cutoff_power(row):
    # Exact reviewed source constant DAG; loader/source uncertainty is included.
    ft=c('0.3048');inch=div(c('1'),c('12'));m3=div(c('1'),mul(mul(ft,ft),ft))
    in3=div(mul(mul(inch,inch),inch),m3)
    disp=mul(c('286.277630558369908854908378301344700322467061518056517936342'),in3)
    ambient=mul(obs(row['pressure_psf']),c('47.88'))
    pmep=mul(add(obs(row['map_pa']),neg(ambient)),c('0.8'))
    pump=div(mul(mul(pmep,disp),obs(row['pre_engine_rpm'])),mul(c('4'),c('22371')))
    return mul(add(c('-1'),pump),c('550'))
def compare_chronology(rows,module):
    demand(len(rows)==13 and rows[0]['kind']=='chronology-identity','wrong chronology identity/count')
    demand(Path(rows[0]['loaded_library_path']).samefile(module),'wrong chronology actual DLL')
    observations=rows[1:];demand([r['id'] for r in observations]==CHRONO_IDS,'wrong chronology roster/order')
    for r in observations:
        demand(r['kind']=='chronology' and r['unit_rpm_seed_only'] is True,'wrong chronology unit scope')
        for key in ['running','cranking','starved','tank_selected']:demand(type(r[key])is bool,'nonboolean chronology field')
        for key in ['pre_engine_rpm','post_prop_rpm','fuel_lb_per_s','fuel_pph','power_ftlb_per_s','map_pa','pressure_psf','h_s','reaction_torque_ftlb','fuel_used_lb','tank_lb']:obs(r[key])
    table={r['id']:r for r in observations}
    for id in CHRONO_IDS[:2]:
        r=table[id];demand(not r['running'],'current cutoff remained running');lo,hi=cutoff_power(r)
        demand(lo<=Q(r['power_ftlb_per_s'])<=hi,'cutoff retained running friction/combustion power')
    demand(table['M01-mixture-cutoff']['fuel_lb_per_s']==0,'current mixture cutoff fuel not zero')
    a,b=table['M02-feed-first'],table['M02-feed-second']
    demand(a['running'] and a['starved'] and a['fuel_lb_per_s']>0,'feed lag first boundary incorrect')
    demand(not b['running'] and b['starved'] and b['fuel_lb_per_s']==0,'feed lag next boundary incorrect')
    demand(a['tank_lb']==b['tank_lb'] and a['fuel_used_lb']==b['fuel_used_lb']==0 and not a['tank_selected'] and not b['tank_selected'],'unavailable feed consumed fuel')
    for prior in range(2):
        for side in range(3):
            r=table[f'M03-rpm-{prior}-{side}'];rpm=480+Q(side-1,4096)
            demand(Q(r['pre_engine_rpm'])==rpm and Q(r['post_prop_rpm'])==rpm and r['h_s']==0,'actual h0 RPM changed')
            # The original table is flat ME1 for q/14.7 here; verify enough
            # indicated power instead of claiming exactHP-equality injection.
            key=div(div(mul(c('1.3'),c('101325')),mul(obs(r['pressure_psf']),c('47.88'))),c('14.7'))
            demand(Q('0.08')<key[0]<=key[1]<Q('0.10'),'M03 key not on independently known ME1 plateau')
            sufficient=add(div(obs(r['fuel_pph']),c('0.4')),c('-1'))
            demand(sufficient[0]>Q(1,8),'M03 fixture lacked sufficient power')
            demand(r['running']==(bool(prior) if side==1 else side==2),'actual RPM boundary policy incorrect')
    a,b=table['M04-crossing-first'],table['M04-crossing-next']
    demand(a['pre_engine_rpm']<480<a['post_prop_rpm'] and a['cranking'] and not a['running'],'mode changed during crossing step')
    demand(b['pre_engine_rpm']==a['post_prop_rpm'] and b['running'],'next boundary did not observe crossing')
def check(a):
    plan=load(a.plan);demand(sha(plan['packet_path'])==plan['packet_sha256'],'packet changed');cases=native_cases(load(plan['packet_path']))
    demand(plan['source']==source_files(),'probe source changed since preparation')
    demand(sha(Path(a.plan).parent/'requests.txt')==plan['requests_sha256'],'requests changed')
    demand(sha(Path(a.plan).parent/'legacy-requests.txt')==plan['legacy_requests_sha256'],'legacy requests changed')
    demand((Path(a.plan).parent/'requests.txt').read_bytes()==request_bytes(cases),'requests do not match immutable packet')
    legacy=legacy_comparator();_,old_cases=legacy.load_reference()
    demand((Path(a.plan).parent/'legacy-requests.txt').read_bytes()==legacy.requests(old_cases),'requests do not match immutable legacy reference')
    compare_native(cases,lines(a.kernel_output))
    library=lines(a.library_output);guard=library[0]
    demand(guard['kind']=='guard' and Path(guard['loaded_library_path']).samefile(a.dll),'wrong library actual DLL')
    for name in ['passed','fresh_legacy','unknown_rejected_unchanged','reset_retains_event','legacy_return','case_object_fresh_unset','loaded_original_pair_supported','reset_retains_coupled','unknown_coupled_rejected_unchanged','scalar_coupled_rejected_unchanged','unsupported_public_prop_settings_rejected']:demand(guard[name]is True,'actual selector/default guard failed '+name)
    # Execute only the saved-output comparison from the unchanged reviewed
    # module. Its subprocess/main function is never called.
    legacy=legacy_comparator();old_packet,old_cases=legacy.load_reference();legacy_checks,failures=legacy.compare(old_packet,old_cases,library)
    demand(not failures,'immutable legacy18-field comparison failed: '+repr(failures))
    compare_chronology(lines(a.chronology_output),a.dll)
    evidence=load(Path(SOURCE_MANIFEST).parent/'chronology-source-evidence.json');demand(evidence['source_only']is True and evidence['checks_passed']is True,'source chronology evidence missing')
    # Root's separately reviewed execution wrapper must bind the actual loaded
    # module and every child/executable's pre/post bytes. This offline checker
    # does not launch/approve children or infer identity from vendor metadata.
    execution=load(a.execution_receipt)
    demand(execution['authorized_source_binding_sha256']==sha(SOURCE_MANIFEST),'execution was for different source')
    demand(execution['packet_sha256']==plan['packet_sha256'] and execution['requests_sha256']==plan['requests_sha256'] and execution['legacy_requests_sha256']==plan['legacy_requests_sha256'],'execution packet/requests mismatch')
    demand(Path(execution['dll_path']).samefile(a.dll),'execution DLL path mismatch')
    demand(execution['dll_sha256_before']==execution['dll_sha256_after']==sha(a.dll),'actual DLL bytes changed')
    for label,path in [('kernel',a.kernel_output),('library',a.library_output),('chronology',a.chronology_output)]:
        child=execution['children'][label];demand(child['exit_code']==0 and child['stdout_sha256']==sha(path),'wrong/failed child output')
        demand(child['executable_sha256_before']==child['executable_sha256_after']==sha(child['executable_path']),'child executable bytes changed')
    result={'passed':True,'named_groups':sorted(GROUPS),'native_rows':len(cases),'legacy_checks':legacy_checks,'actual_chronology_rows':12,'scope':'independent numerical packet + actual DLL unit chronology/default + source callback chronology; no aircraft/phase claim','remaining_runtime_gate':'unchanged original complete12-process native physical/publication suite; not replaced by unit fixtures','packet_sha256':plan['packet_sha256'],'source_binding_sha256':sha(SOURCE_MANIFEST)}
    with Path(a.output).open('x',encoding='utf-8')as f:f.write(json.dumps(result,indent=2)+'\n')
def main():
    global SOURCE_MANIFEST
    p=argparse.ArgumentParser();p.add_argument('--source-manifest',required=True);sub=p.add_subparsers(dest='mode',required=True)
    prep=sub.add_parser('prepare');prep.add_argument('--packet',required=True);prep.add_argument('--packet-sha256',required=True);prep.add_argument('--output',required=True)
    verify=sub.add_parser('check')
    for name in ['plan','kernel-output','library-output','chronology-output','dll','execution-receipt','output']:verify.add_argument('--'+name,required=True)
    a=p.parse_args();SOURCE_MANIFEST=Path(a.source_manifest);prepare(a) if a.mode=='prepare' else check(a)
if __name__=='__main__':main()
