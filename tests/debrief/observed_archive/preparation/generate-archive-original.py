"""Original MIT independent ADR012 preconsumer text/grammar references.
No app implementation imports. Expected grammar/schema outcomes are declared
from ADR012; this generator is not an archive decoder or runtime validator.
"""
import copy, hashlib, json, math, pathlib, struct
from fractions import Fraction

HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[2]
HEAD='2409a543af654af763fc1b84fa47a61cb030d0e5'
ADR_SHA='bde453e84734251f0f687aebc5b18f895ae7b71970a3c67b0274b605e5a79c5d'
MAX=2**64-1
WORLD='04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5'
UNITS={'tas':'m/s','ground_speed':'m/s','pitch':'rad','bank':'rad','heading_true':'rad','ellipsoid_height':'m','vertical_speed':'m/s','body_yaw_rate':'rad/s','fuel_total':'kg'}
def sha(b): return hashlib.sha256(b).hexdigest()
def text(v): return json.dumps(v,ensure_ascii=True,separators=(',',':'),allow_nan=False)
def tagged(v):
    if type(v) is float:
        assert math.isfinite(v)
        return {'$binary64_le':struct.pack('<d',v).hex()}
    if isinstance(v,dict): return {k:tagged(x) for k,x in v.items()}
    if isinstance(v,list): return [tagged(x) for x in v]
    return v
def nodes(v):
    return 1+sum(nodes(x) for x in v.values()) if isinstance(v,dict) else 1+sum(nodes(x) for x in v) if isinstance(v,list) else 1
def depth(v):
    if not isinstance(v,(dict,list)): return 0
    xs=v.values() if isinstance(v,dict) else v
    return 1+max((depth(x) for x in xs),default=0)
def leaves(v,path=''):
    if type(v) is float: return [{'path':path,'type':'float','le_hex':struct.pack('<d',v).hex()}]
    if type(v) is int: return [{'path':path,'type':'int','value':v}]
    if isinstance(v,dict): return [a for k,x in v.items() for a in leaves(x,path+'/'+k)]
    if isinstance(v,list): return [a for i,x in enumerate(v) for a in leaves(x,path+'/'+str(i))]
    return []
def sample(t,target=None,skipped=0,grid=0):
    target=t if target is None else target
    channels={k:{'value':float(i+1),'unit':unit,'valid':True,'error':''} for i,(k,unit) in enumerate(UNITS.items())}
    return {'tick':str(t),'target_tick':str(target),'late_by_ticks':t-target,'skipped_targets_before':skipped,'gap_before':skipped>0,
      'elapsed_s':float(t)/120.0,'anchor_eus_position_m':[float(3*grid),0.0,float(4*grid)],
      'readings':{'session_id':'archive.reference','tick':str(t),'state':'paused','native_truth':True,'readings':channels,'error':''},
      'held_axes':{'kind':'axes','roll':0.0,'pitch':0.0,'yaw':0.0,'throttle':0.0,'mixture':1.0,'left_brake':0.0,'right_brake':0.0,'trim':0.0}}
def record(first=0):
    return {'contract_version':1,'state':'recording','metadata':{'session_id':'archive.reference','model_identity':{'id':'original-interactive-prototype','version':'0.1.0-prototype','backend_model':'original-interactive'},
      'native_source_fingerprint':'f'*64,'prepared_world_sha256':WORLD,'world_anchor':{'latitude_rad':0.8,'longitude_rad':-2.0,'ellipsoid_height_m':0.0},
      'seed':'42','clock':{'purpose':'runtime','tick_rate_hz':120},'named_start':'ground-ready','first_tick':str(first)},
      'last_observed_tick':str(first),'samples':[sample(first)],'seal_reason':None,'error':'','skipped_target_count':0,'late_sample_count':0,'uncaptured_tail_targets':0}
def envelope(payload):
    return {'format':'ObservedFlightReview','archive_version':1,'recording_contract_version':1,'payload_json':payload,'payload_sha256':sha(payload.encode('utf8'))}
def bytes_for(v): return text(envelope(text(tagged(v)))).encode('utf8')
def mutate_inner(fn):
    v=tagged(record()); fn(v); return text(envelope(text(v))).encode('utf8')
def mutate_outer(fn):
    v=envelope(text(tagged(record()))); fn(v); return text(v).encode('utf8')

def generate():
    assert sha((ROOT/'docs/decisions/012-observed-review-interchange.md').read_bytes().replace(b'\r\n',b'\n'))==ADR_SHA
    positives=[]
    def positive(name,r):
        encoded=tagged(r); inner=text(encoded); outer=envelope(inner); data=text(outer).encode('utf8')
        metrics={'samples':len(r['samples']),'payload_bytes':len(inner.encode('utf8')),'file_bytes':len(data),'payload_values':nodes(encoded),'outer_values':nodes(outer),'payload_depth':depth(encoded),'outer_depth':depth(outer)}
        assert metrics['payload_bytes']<=8388608 and metrics['file_bytes']<=8388608 and metrics['payload_values']<=250000 and metrics['payload_depth']<=16
        namefile=name+'.fsreview.json'; (HERE/namefile).write_bytes(data)
        positives.append({'id':name,'file':namefile,'sha256':sha(data),'payload_sha256':outer['payload_sha256'],'expected':'accept','metrics':metrics,
          'numeric_types_and_bits':leaves(r) if name!='dense-2401' else {'shared_template':'minimal','elapsed_s':'float(actual absolute tick)/120 legacy field consistency only','position':'float3i,0,float4i; ticks exact60i','clock_type':'int','axes_type':'float','channel_types':'float'}})
    positive('minimal',record())
    r=record(); r['state']='sealed';r['seal_reason']='limit';r['last_observed_tick']='144000';r['samples']=[sample(60*i,grid=i) for i in range(2401)]; positive('dense-2401',r)
    r=record();r['metadata']['clock']['tick_rate_hz']=120.0
    for k in r['samples'][0]['held_axes']:
        if k!='kind':r['samples'][0]['held_axes'][k]=1 if k=='mixture' else 0
    positive('clock-float-axes-integer',r)
    r=record();r['samples'][0]['readings']['readings']['fuel_total']={'value':None,'unit':'kg','valid':False,'error':'Synthetic unavailable reference'};positive('unavailable',r)
    r=record();r['samples'][0]['anchor_eus_position_m']=[-0.0,struct.unpack('<d',bytes.fromhex('0100000000000000'))[0],0.0];r['samples'][0]['held_axes']['roll']=-0.0;positive('signed-zero-subnormal',r)
    r=record(2**53+1);r['samples'].append(sample(2**53+61,grid=1));r['last_observed_tick']=str(2**53+61);r['state']='sealed';r['seal_reason']='manual';positive('full-uint64-over-2pow53',r)
    r=record(MAX);r['state']='sealed';r['seal_reason']='tick_exhausted';positive('max-uint64',r)
    r=record();r['samples']=[sample(0),sample(61,60,grid=1),sample(181,180,1,3)];r['last_observed_tick']='240';r['state']='sealed';r['seal_reason']='manual';r['late_sample_count']=2;r['skipped_target_count']=2;r['uncaptured_tail_targets']=1;positive('late-gap-tail',r)
    base=bytes_for(record()); neg=[]
    def negative(name,data,reason):
        filename=name+'.bin';(HERE/filename).write_bytes(data)
        neg.append({'id':name,'file':filename,'sha256':sha(data),'bytes':len(data),'expected':'reject','reason':reason})
    for name,prefix in [('utf8-bom',b'\xef\xbb\xbf'),('utf8-overlong',b'\xc0\xaf'),('utf8-stray',b'\x80'),('utf8-surrogate',b'\xed\xa0\x80'),('utf8-above-max',b'\xf4\x90\x80\x80'),('nul',b'\0')]: negative(name,prefix+base,'Strict raw UTF8/BOM/NUL refusal before parse')
    negative('utf8-incomplete',base[:-1]+b'\xe2\x82','Truncated UTF8 sequence')
    negative('truncated',base[:-1],'Unclosed root object')
    negative('outer-duplicate',base.replace(b'{',b'{"format":"ObservedFlightReview",',1),'Duplicate outer key')
    negative('outer-escaped-key',base.replace(b'"format"',b'"\\u0066ormat"',1),'All escaped keys forbidden')
    for name,token in [('negative-zero',b'-0'),('fraction',b'1.0'),('exponent',b'1e0'),('leading-zero',b'01'),('plus',b'+1')]:negative(name,base.replace(b'"archive_version":1',b'"archive_version":'+token,1),'Canonical integer grammar only')
    negative('trailing-comma',base[:-1]+b',}','Trailing commas forbidden')
    negative('comment',b'/*x*/'+base,'Comments forbidden')
    negative('trailing-token',base+b'false','Trailing non-whitespace forbidden')
    negative('non-json-space',b'\xc2\xa0'+base,'Only RFC8259 whitespace')
    for name,escape in [('lone-high-surrogate','\\ud800'),('lone-low-surrogate','\\udc00'),('reversed-surrogates','\\udc00\\ud800')]:negative(name,base.replace(b'ObservedFlightReview',escape.encode('ascii'),1),'Unicode scalar value escape qualification')
    negative('checksum-corrupt',mutate_outer(lambda v:v.__setitem__('payload_sha256','0'*64)),'Payload digest mismatch')
    negative('future-version',mutate_outer(lambda v:v.__setitem__('archive_version',2)),'Unsupported archive version')
    negative('outer-extra',mutate_outer(lambda v:v.__setitem__('extra',True)),'Closed envelope keys')
    negative('tag-uppercase',mutate_inner(lambda v:v['metadata']['world_anchor']['latitude_rad'].__setitem__('$binary64_le','9A9999999999e93f')),'Only16 lowercase hex tag')
    negative('tag-nan',mutate_inner(lambda v:v['samples'][0]['anchor_eus_position_m'][0].__setitem__('$binary64_le','000000000000f87f')),'Nonfinite tagged scalar rejected even with valid digest')
    negative('tag-extra',mutate_inner(lambda v:v['metadata']['world_anchor']['latitude_rad'].__setitem__('extra',0)),'Exactly one tag key')
    negative('tag-wrong-position',mutate_inner(lambda v:v['metadata'].__setitem__('seed',{'$binary64_le':'0000000000004540'})),'Seed remains canonical String')
    negative('inner-malformed-count',mutate_inner(lambda v:v.__setitem__('late_sample_count',1)),'Recomputed digest cannot bypass recording count consistency')
    inner=text(tagged(record()))
    negative('inner-duplicate',text(envelope(inner.replace('{','{"contract_version":1,',1))).encode('utf8'),'Duplicate inner key even with correct digest')
    negative('inner-escaped-key',text(envelope(inner.replace('"state"','"\\u0073tate"',1))).encode('utf8'),'Escaped inner key even with correct digest')
    assert len(positives)==8 and len(neg)==32
    manifest={'status':'independent-preconsumer-fixtures-awaiting-root-review','license':'MIT','contract_head':HEAD,'contract_git_lf_sha256':ADR_SHA,
      'scope':'Representation/schema/grammar references only; no codec import/output, native flight, actual IO or acceptance claim.',
      'bit_budget':'Exact64bits/type; no tolerance','tick_budget':'Exactdecimal String identity; never scheduling viafloat',
      'fingerprint_scope':'f*64 is structurally valid synthetic reference metadata, not an executed native binary identity.',
      'positions_scope':'Synthetic fixed-anchor EUS; recorded channel scalars arbitrary finite mock observations, not flight dynamics.',
      'serialization':'Deterministic compact ASCII JSON key insertion order is a reference choice; decoder must accept other permitted order/whitespace.',
      'positives':positives,'negatives':neg,'generator_sha256':sha(pathlib.Path(__file__).read_bytes())}
    (HERE/'expected-text-v1.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=True)+'\n',encoding='utf8',newline='\n')
    print(json.dumps({'expected_sha256':sha((HERE/'expected-text-v1.json').read_bytes()),'positives':len(positives),'negatives':len(neg),'dense':positives[1]['metrics']}))
if __name__=='__main__': generate()
