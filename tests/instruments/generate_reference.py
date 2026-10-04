"""Original MIT pre-consumer ADR009 arithmetic/reference packet. No consumer import."""
from fractions import Fraction as F
from pathlib import Path
import copy, hashlib, json, math, sys
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
WORLD='04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5'
UNITS={'tas':'m/s','ground_speed':'m/s','pitch':'rad','bank':'rad','heading_true':'rad','ellipsoid_height':'m','vertical_speed':'m/s','body_yaw_rate':'rad/s','fuel_total':'kg'}
# Frozen before any NativeReadings consumer observation. Inputs are modest exact
# rationals; these budgets bound scalar arithmetic/display conversion, not FDM.
BUDGET={'scalar_abs':2e-12,'angle_abs_rad':2e-12,'display_abs':2e-9,'relative':4e-15,'singularity_dimensionless':1e-6}
def vec(values): return dict(zip(('x','y','z'),map(float,values)))
def ecef(height):
    lat,lon=.8,-2.; e2=(1/298.257223563)*(2-1/298.257223563)
    n=6378137/math.sqrt(1-e2*math.sin(lat)**2)
    return [(n+height)*math.cos(lat)*math.cos(lon),(n+height)*math.cos(lat)*math.sin(lon),(n*(1-e2)+height)*math.sin(lat)]
def rotation(q):
    w,x,y,z=q
    return [[1-2*(y*y+z*z),2*(x*y-w*z),2*(x*z+w*y)], [2*(x*y+w*z),1-2*(x*x+z*z),2*(y*z-w*x)], [2*(x*z-w*y),2*(y*z+w*x),1-2*(x*x+y*y)]]
def expected(q,v,wind,turb,fuel=100.):
    r=rotation(q); ned=[sum(a*b for a,b in zip(row,v)) for row in r]
    air=[a-b-c for a,b,c in zip(ned,wind,turb)]
    pitch=math.asin(max(-1.,min(1.,float(2*(q[0]*q[2]-q[3]*q[1])))))
    bank=None if abs(math.cos(pitch))<=1e-6 else math.atan2(float(2*(q[0]*q[1]+q[2]*q[3])),float(1-2*(q[1]**2+q[2]**2)))
    heading=None if math.hypot(float(r[0][0]),float(r[1][0]))<=1e-6 else math.atan2(float(r[1][0]),float(r[0][0]))%(2*math.pi)
    values={'tas':math.sqrt(float(sum(a*a for a in air))),'ground_speed':math.sqrt(float(ned[0]**2+ned[1]**2)),'pitch':pitch,'bank':bank,'heading_true':heading,'ellipsoid_height':1000.,'vertical_speed':-float(ned[2]),'body_yaw_rate':.125,'fuel_total':fuel}
    exact={'rotation':[[str(a) for a in row] for row in r],'ned_velocity':[str(a) for a in ned],'air_velocity':[str(a) for a in air],'tas_squared':str(sum(a*a for a in air)),'ground_speed_squared':str(ned[0]**2+ned[1]**2)} if all(isinstance(a,(F,int)) for a in q+v+wind+turb) else None
    return values,exact
A0=json.loads((ROOT/'tests/contracts/fixtures/AircraftSnapshot.json').read_text())
W0=json.loads((ROOT/'tests/contracts/fixtures/AtmosphereSample.json').read_text())
def readback(q,v,wind=(F(0),)*3,turb=(F(0),)*3,tick='0'):
    aircraft=copy.deepcopy(A0); weather=copy.deepcopy(W0)
    aircraft.update(tick=tick,session_id='synthetic-reading-reference',elapsed_s=float(int(tick))/120,validity='valid')
    aircraft['position']={'latitude_rad':.8,'longitude_rad':-2.,'ellipsoid_height_m':1000.}
    aircraft['ecef_position_m']=vec(ecef(1000))
    aircraft['orientation_body_to_ned']=dict(zip(('w','x','y','z'),map(float,q)))
    aircraft['velocity_body_mps']=vec(v); aircraft['angular_rate_body_radps']=vec([0,0,.125])
    aircraft['systems']=[{'id':'fuel.total','quantity':'kg','value':100.,'validity':'valid'}]
    weather.update(tick=tick,session_id=aircraft['session_id'],position=copy.deepcopy(aircraft['position']),seed='42',model_id='synthetic-still-air')
    weather['wind_toward_ned_mps']=vec(wind);weather['turbulence_ned_mps']=vec(turb)
    r=rotation(tuple(map(float,q)))
    ecef_to_eus=[[-math.sin(-2),math.cos(-2),0],[math.cos(.8)*math.cos(-2),math.cos(.8)*math.sin(-2),math.sin(.8)],[math.sin(.8)*math.cos(-2),math.sin(.8)*math.sin(-2),-math.cos(.8)]]
    delta=[a-b for a,b in zip(ecef(1000),ecef(0))]
    local=[sum(a*b for a,b in zip(row,delta)) for row in ecef_to_eus]
    return {'host_mode':'live','error':'','historical':False,'session_id':aircraft['session_id'],'tick':tick,'aircraft':aircraft,'atmosphere':weather,'held_axes':{'kind':'axes','roll':0.,'pitch':0.,'yaw':0.,'throttle':0.,'mixture':1.,'left_brake':0.,'right_brake':0.,'trim':0.},'native_outcome':'completed','native_live':True,'paused':False,'time_scale':1.,'debt_quanta':0,'native_fault':'','named_start':'airborne-prepared','model_identity':{'id':'original-interactive-prototype','version':'0.1.0-prototype','backend_model':'original-interactive'},'native_source_fingerprint':'f'*64,'prepared_world_sha256':WORLD,'world_anchor':{'latitude_rad':.8,'longitude_rad':-2.,'ellipsoid_height_m':0.},'canonical':{'ecef_position_m':ecef(1000),'anchor_eus_position_m':local,'body_to_anchor_eus':[float(a) for row in [r[1],[-a for a in r[2]],[-a for a in r[0]]] for a in row]}}
I=(F(1),F(0),F(0),F(0)); MIX=(F(1,3),F(2,3),F(2,3),F(0)); Z=(F(0),)*3; V=(F(3),F(4),F(12)); S=math.sqrt(.5)
CASES=[]
def add(name,q=I,v=V,wind=Z,turb=Z,mutate=None,state='live',invalid=None,missing_fuel=False):
    value=readback(q,v,wind,turb); channels,exact=expected(q,v,wind,turb,None if missing_fuel else 100.)
    if mutate: mutate(value)
    if invalid: channels={name:None for name in UNITS}
    CASES.append({'id':name,'input':value,'expected_state':'invalid' if invalid else state,'expected_values':channels,'expect_null_identity':bool(invalid or state=='empty'),'expected_invalid_reason':invalid,'exact_arithmetic':exact,'display_expected':{'tas_kt':None if channels['tas'] is None else channels['tas']*float(F(900,463)),'height_ft':None if channels['ellipsoid_height'] is None else channels['ellipsoid_height']*float(F(1250,381)),'vsi_fpm':None if channels['vertical_speed'] is None else channels['vertical_speed']*float(F(25000,127))},'finite_only_json':True})
add('identity-zero',v=Z)
add('identity-3-4-12')
add('mixed-rational-no-wind',q=MIX)
add('mixed-rational-toward-wind-turbulence',q=MIX,wind=(F(1),F(-2),F(1,2)),turb=(F(0),F(1,2),F(-1,2)))
add('east-heading',q=(S,0,0,S))
add('south-heading',q=(F(0),F(0),F(0),F(1)))
add('west-heading',q=(S,0,0,-S))
add('quadrant-positive-rational',q=(F(3,5),F(0),F(0),F(4,5)))
add('quadrant-negative-rational',q=(F(3,5),F(0),F(0),F(-4,5)))
add('roll-quarter-turn',q=(S,S,0,0))
add('pitch-positive-singular',q=(S,0,S,0))
add('pitch-negative-singular',q=(S,0,-S,0))
add('fuel-missing',mutate=lambda x:x['aircraft'].update(systems=[]),missing_fuel=True)
add('fuel-unavailable',mutate=lambda x:x['aircraft']['systems'][0].update(validity='unavailable'),missing_fuel=True)
add('fuel-wrong-quantity',mutate=lambda x:x['aircraft']['systems'][0].update(quantity='radps'),missing_fuel=True)
add('paused-current',mutate=lambda x:x.update(host_mode='paused',paused=True,native_outcome='paused'),state='paused')
add('closed-historical',mutate=lambda x:x.update(host_mode='closed',historical=True,native_live=False,paused=False,canonical=None),state='historical')
def empty(x):
    for key in ['session_id','tick','aircraft','atmosphere','held_axes','native_outcome','named_start','model_identity','native_source_fingerprint','prepared_world_sha256','world_anchor','canonical']:x[key]=None
    x.update(host_mode='closed',historical=True,native_live=False,paused=False)
add('empty-closed',mutate=empty,state='empty',invalid='empty is not a malformed record')
CASES[-1]['expected_state']='empty';CASES[-1]['expected_invalid_reason']=None
add('full-uint64-max',mutate=lambda x:[x.update(tick='18446744073709551615'),x['aircraft'].update(tick='18446744073709551615',elapsed_s=float(18446744073709551615)/120),x['atmosphere'].update(tick='18446744073709551615')])
add('unknown-readback-key',mutate=lambda x:x.update(extra=True),invalid='closed Readback shape')
add('weather-tick-mismatch',mutate=lambda x:x['atmosphere'].update(tick='1'),invalid='pair identity')
add('weather-position-mismatch',mutate=lambda x:x['atmosphere']['position'].update(ellipsoid_height_m=1000.01),invalid='pair position')
add('ecef-position-mismatch',mutate=lambda x:x['aircraft']['ecef_position_m'].update(x=x['aircraft']['ecef_position_m']['x']+.01),invalid='v1 coordinate semantics')
add('duplicate-fuel-source',mutate=lambda x:x['aircraft']['systems'].append(copy.deepcopy(x['aircraft']['systems'][0])),invalid='duplicate v1 IDs')
add('wrong-prepared-identity',mutate=lambda x:x.update(prepared_world_sha256='a'*64),invalid='prepared identity')
add('wrong-model-identity',mutate=lambda x:x['model_identity'].update(id='different-model'),invalid='model identity')
add('unavailable-held-pair',mutate=lambda x:x.update(held_axes=None),invalid='Readback null relationships')
add('unknown-canonical-key',mutate=lambda x:x['canonical'].update(origin='float-view'),invalid='closed canonical metadata')
# v2 additions requested in pre-consumer review. No consumer source/output observed.
overflow_input=readback(I,(1e308,0.,0.))
CASES.append({'id':'finite-wire-squared-norm-overflow','input':overflow_input,'expected_state':'invalid','expected_values':{name:None for name in UNITS},'expect_null_identity':True,'expected_invalid_reason':'finite wire components overflow binary64 squared norm','exact_arithmetic':{'velocity_magnitude_mathematical':'1e308','squared_norm_mathematical':'1e616','binary64_squared_norm_finite':False},'display_expected':{'tas_kt':None,'height_ft':None,'vsi_fpm':None},'finite_only_json':True})
add('contradictory-live-paused',mutate=lambda x:x.update(paused=True),invalid='live and paused flags contradict')
packet={'schema_version':1,'scope':'Original pre-consumer ADR009 references; not native flight, source-specific aircraft or sensor calibration','contract_sha256':'892c7a767d1d459cb7704cb8de5534375da4b291f07279a7a08d6514a0d0d28e','reference_method':'Fraction rational rotation/squared norms; Python libm only sqrt/atan2/asin and WGS84 placement. No NativeReadings import, source observation or golden output.','budgets':BUDGET,'units':UNITS,'cases':CASES,'non_json_cases':[{'id':'nan-required-vector','mutation':'aircraft.velocity_body_mps.x=NAN','expected_state':'invalid'},{'id':'infinite-system-value','mutation':'aircraft.systems[0].value=INF','expected_state':'invalid'},{'id':'wrong-readback-object','mutation':'input=Node3D.new()','expected_state':'invalid'}]}
packet['non_json_cases'].extend([
    {'id':'malformed-fingerprint','mutation':"input.native_source_fingerprint='g'*64",'expected_state':'invalid'},
    {'id':'float-debt-counter','mutation':'input.debt_quanta=0.0 (TYPE_FLOAT)','expected_state':'invalid'}])
packet['provenance']={'version':'v2','parent_reference_sha256':'440e7949c209c7a52d1d5498c9fe9b9bd6e9e49df47e45581d062a36cda44c35','parent_manifest_sha256':'42336c6efd3f5f4086f17e7dd2b89c219f882fb1f044d5a1f85abb052629e6bc','reason':'Pre-consumer review requested finite arithmetic overflow and direct metadata invalidity references','consumer_source_observed':False,'consumer_output_observed':False,'tolerances_changed':False,'json_counter_driver_rule':'Restore only the known input.debt_quanta integer fixture path after Godot JSON parsing; direct float-debt-counter recipe must explicitly reintroduce TYPE_FLOAT. Never convert decimal tick/session identity.','research_fingerprint':'f repeated 64 times is structural research metadata, not native binary authority.'}
encoded=(json.dumps(packet,indent=2,ensure_ascii=True,allow_nan=False)+'\n').encode()
expected='413eb124254432f8b39d7079b773d14e276415aa54749de3a1d85e527bf70aae'
if hashlib.sha256(encoded).hexdigest()!=expected: raise SystemExit('Independent frozen reference drift; do not regenerate goldens')
if (OUT/'reference.json').read_bytes()!=encoded: raise SystemExit('Reference bytes differ from frozen independent calculation')
if sys.argv[1:] not in ([],['--check']): raise SystemExit('Only read-only --check is supported')
print(json.dumps({'json_cases':len(CASES),'non_json_cases':len(packet['non_json_cases']),'reference_sha256':hashlib.sha256(encoded).hexdigest(),'generator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'contract_sha256':packet['contract_sha256'],'budgets':BUDGET}))
