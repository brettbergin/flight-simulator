"""MIT. Prospective ADR024 rational certificates; no candidate/native outputs.

No float, simulation, imported numerical implementation or root-output oracle.
Default creates expected.json once. --check regenerates and compares read-only.
"""
from fractions import Fraction as Q
from math import comb
from pathlib import Path
import argparse
import json

def q(value): return {'n':str(value.numerator),'d':str(value.denominator)}
def sign(x): return (x>0)-(x<0)
def trim(p):
    p=list(p)
    while len(p)>1 and p[-1]==0:p.pop()
    return p
def plus(a,b):return trim([(a[i] if i<len(a) else 0)+(b[i] if i<len(b) else 0) for i in range(max(len(a),len(b)))])
def times(a,b):
    out=[Q(0)]*(len(a)+len(b)-1)
    for i,x in enumerate(a):
        for j,y in enumerate(b):out[i+j]+=x*y
    return trim(out)
def scaled(a,s):return trim([x*s for x in a])
def at(p,x):
    out=Q(0)
    for c in reversed(p):out=out*x+c
    return out
def bits(token):
    n=int(token,16);e=(n>>52)&2047;f=n&((1<<52)-1);assert e!=2047
    a=f if e==0 else (1<<52)+f;k=-1074 if e==0 else e-1023-52
    value=Q(a<<k) if k>=0 else Q(a,1<<-k)
    return -value if n>>63 else value

def polynomial(c,w):
    # Expand the public derivative formula, not the C++ coefficient statements.
    m=[w/2,Q(1,2)];m2=times(m,m);m3=times(m2,m)
    p=plus([0,c[0]],plus(scaled(m2,c[1]+c[2]*w),scaled(times(m3,[2*w-m[0],-m[1]]),c[3])))
    factored=0
    while len(p)>1 and p[0]==0:p=p[1:];factored+=1
    return trim(p),factored

def bernstein(p,lo,hi):
    degree=len(p)-1;width=hi-lo
    power=[sum(p[k]*comb(k,j)*lo**(k-j)*width**j for k in range(j,degree+1)) for j in range(degree+1)]
    return [sum(power[j]*Q(comb(i,j),comb(degree,j)) for j in range(i+1)) for i in range(degree+1)]

def horner(p,lo,hi):
    a=b=p[-1]
    for c in reversed(p[:-1]):
        terms=[a*lo,a*hi,b*lo,b*hi];a=min(terms)+c;b=max(terms)+c
    return a,b

def certificate(p,lo,hi,used=0):
    """Exact interval certificate oracle only; no shaft advance/solve."""
    work=[(lo,hi)];trace=[];initial=used
    while work:
        i=max(range(len(work)),key=lambda j:(work[j][1]-work[j][0],-work[j][0]))
        a,b=work[i];work[i]=work[-1];work.pop();lower,upper=horner(p,a,b)
        decision='certified' if upper<=0 and lower<0 else ('uncertifiable' if lower>0 or used==8 else 'split')
        trace.append({'lo':q(a),'hi':q(b),'lower':q(lower),'upper':q(upper),'used_splits':used,'decision':decision})
        if decision=='uncertifiable':return {'certified':False,'used_splits':used,'new_splits':used-initial,'evaluations':len(trace),'trace':trace}
        if decision=='split':
            middle=(a+b)/2
            assert a<middle<b
            work.extend([(a,middle),(middle,b)]);used+=1
    return {'certified':True,'used_splits':used,'new_splits':used-initial,'evaluations':len(trace),'trace':trace}

def law_case(name,c,w,I,endpoint,h,old,new,source_event=False,expected_time_order=None):
    c=list(map(Q,c));w=Q(w);I=Q(I);endpoint=Q(endpoint);h=Q(h)
    assert I>0 and 0<=endpoint<w and h>0
    # Independent sufficient whole-interval negative-power evidence: two exact
    # Bernstein hulls. No sampled values stand in for a connected-domain proof.
    half=(endpoint+w)/2
    nsigns=[[sign(v) for v in bernstein(c,a,b)] for a,b in [(endpoint,half),(half,w)]]
    # N may vanish at0 when canceled torque has a finite negative limit.
    # Nonpositive hull coefficients with at least one strict negative imply
    # strict interior negativity; explicitly exclude any positive-speed zero.
    assert all(s<=0 for signs in nsigns for s in signs)
    assert all(any(s<0 for s in signs) for signs in nsigns)
    assert at(c,w)<0 and (at(c,endpoint)<0 or endpoint==0)
    p,factored=polynomial(c,w);full=certificate(p,endpoint,w)
    out={'id':name,'kind':'frozen_law_policy','law':[q(v) for v in c],'w0':q(w),'I':q(I),'endpoint':q(endpoint),'remaining':q(h),
         'original_source_event':source_event,'expected_v1':old,'expected_v2':new,'power_bernstein_signs_by_half':nsigns,
         'time_derivative':[q(v) for v in p],'factored_endpoint_x_zeros':factored,'full_certificate':full,'solve_bisection_ceiling':64,'native_angular_output':None}
    if full['certified']:
        assert old=='original_full_path' and new=='identical_original_full_path'
        out.update({'fallback_attempted':False,'combined_evaluations':full['evaluations']})
    else:
        assert old=='reject_uncertified'
        local=certificate(p,half,w,full['used_splits'])
        out.update({'half':q(half),'local_certificate':local,'fallback_attempted':True,'combined_evaluations':full['evaluations']+local['evaluations'],'combined_splits':local['used_splits'],
                    'local_bernstein_signs':[sign(v) for v in bernstein(p,half,w)]})
        if local['certified']:
            midpoint=(half+w)/2;H=I*(half-w)*midpoint/at(c,midpoint)
            order=sign(h-H);out.update({'half_time':q(H),'remaining_vs_half_time':order})
            if expected_time_order is not None:assert order==expected_time_order
            assert (new=='ordinary_local_interior')==(order<0)
            if order<0:
                assert all(v<0 for v in bernstein(p,half,w))
                out.update({'return_source_event':False,'return_stop':False,'subtract_event_time':False})
        else:
            assert new=='reject_local_uncertified'
            out['positive_local_endpoint_witness']=q(at(p,half))
        assert out['combined_splits']<=8 and out['combined_evaluations']<=18
    return out

def make():
    actual_hex=['c081300000000000','4038bc9a3eb24f9e','bfc714c17e42c5e0','bf724f7cf01413f2']
    actual=list(map(bits,actual_hex));w=bits('404f8ca57ddc4412');h=Q(4803839602528529,576460752303423488)
    assert h==bits('3f81111111111111')
    simple=[Q(-1),Q(1,2),Q(-1,8),Q(0)]
    cases=[
        law_case('L01_actual_captured',actual,w,2,0,h,'reject_uncertified','ordinary_local_interior'),
        law_case('L02_authored_local',simple,2,1,0,Q(1,8),'reject_uncertified','ordinary_local_interior'),
        law_case('L03_half_time_equal',simple,2,1,0,Q(48,17),'reject_uncertified','reject_local_time',expected_time_order=0),
        law_case('L04_half_time_excess',simple,2,1,0,Q(48,17)+Q(1,16),'reject_uncertified','reject_local_time',expected_time_order=1),
        law_case('L05_local_positive',[Q(-1),Q(31,32),Q(-1,4),0],2,1,0,Q(1,8),'reject_uncertified','reject_local_uncertified'),
        law_case('L06_constant_power_full',[-1,0,0,0],2,1,0,Q(1,4),'original_full_path','identical_original_full_path'),
        law_case('L07_constant_torque_full',[0,-1,0,0],2,1,0,Q(1,4),'original_full_path','identical_original_full_path'),
        law_case('L08_full_source_endpoint',simple,2,1,1,Q(1,8),'original_full_path','identical_original_full_path',True),
        law_case('L09_local_before_source',simple,2,1,Q(1,16),Q(1,8),'reject_uncertified','ordinary_local_interior',True),
    ]
    assert cases[0]['full_certificate']['used_splits']==8
    assert cases[0]['full_certificate']['evaluations']==16
    assert cases[0]['local_certificate']['new_splits']==0 and cases[0]['combined_evaluations']==17
    # Certificate primitives are not production trajectories. The negative
    # quadratic is -(x-1/2)^2-1/8, strictly negative on the entire real line.
    for name,p,used,expect in [('B01_zero_split_at8',[-1],8,True),('B02_undecided_at8',[0],8,False),
                              ('B03_shared_last3',[-Q(3,8),1,-1],5,True),('B04_shared_insufficient',[-Q(3,8),1,-1],6,False)]:
        result=certificate(list(map(Q,p)),Q(0),Q(1),used);assert result['certified']==expect
        cases.append({'id':name,'kind':'certificate_primitive','polynomial':[q(Q(v)) for v in p],'lo':q(Q(0)),'hi':q(Q(1)),
                      'initial_used_splits':used,'expected_certified':expect,'result':result,'trajectory_claim':False})
    # Immutable v1 R05_split8 is a direct certificate call with identicallyzero
    # b. CAdvance would hold at its exact zero drift before ever certifying.
    r05p,_=polynomial([Q(0),Q(2),Q(-1),Q(0)],Q(2));assert r05p==[0]
    r05=certificate(r05p,Q(1),Q(2));assert not r05['certified'] and r05['used_splits']==8
    cases.append({'id':'R05_split8_unchanged','kind':'existing_direct_guard','source_request_id':'R05_split8','law':[q(Q(v)) for v in [0,2,-1,0]],'w0':q(Q(2)),'endpoint':q(Q(1)),
                  'time_derivative':[q(v) for v in r05p],'certificate':r05,'expected_v1':'reject','expected_v2':'reject','reason':'coupled shaft: decay continuation uncertified',
                  'v2_adapter':'map direct certificate uncertifiable to original guard rejection; do not invoke local continuation',
                  'CAdvance_classification':'exact zero drift hold before certificate; no invented R05 progressing trajectory'})
    cases.append({'id':'R05_bisect64_unchanged','kind':'existing_direct_guard','source_request_id':'R05_bisect64','expected_v1':'reject','expected_v2':'reject',
                  'reason':'coupled shaft: 64 root bisections exhausted','polynomial':[q(-Q(1,1<<60)),q(Q(1))],
                  'initial_bracket':[q(Q(0)),q(Q(1<<60))],'after64_bracket':[q(Q(0)),q(Q(1,16))],
                  'proof':'root2^-60 remains strictly interior and endpoints nonadjacent after64 halvings; no full/local decay status or fallback'})
    cases.append({'id':'R05_capacity128_unchanged','kind':'existing_direct_guard','source_request_id':'R05_capacity128','expected_v1':'reject','expected_v2':'reject',
                  'reason':'coupled shaft: exact dyadic capacity','required_aligned_magnitude_bits':4097,'available_bits':4096,
                  'proof':'CAdd(CScale(1,4096),1) aligns2^4096+1; arithmetic capacity failure is fatal, never local fallback'})
    # Halfway rounding of adjacent binary64 endpoints, exact ties-to-even.
    endpoint=Q(1);start=Q(1)+Q(1,1<<52);unrounded=(endpoint+start)/2
    assert unrounded-endpoint==start-unrounded==Q(1,1<<53)
    cases.append({'id':'G01_stagnant_half','kind':'midpoint_admission_primitive','endpoint':q(endpoint),'w0':q(start),'exact_half':q(unrounded),'rounded_half':q(endpoint),
                  'rounding_proof':'adjacent positive binary64 endpoints, lower even significand; midpoint rounds to endpoint',
                  'expected_v2':'reject_invalid_half','trajectory_claim':False})
    return {'format':'PistonLocalWindowRationalReference/v1','issue':207,'candidate_outputs_consumed':False,
            'scope':'Prospective exact certificate/admission references; no native angular-output goldens, tolerance or coupled accuracy claim',
            'captured_frame_sha256':'01a8cbc256bbc30a5a53265362d5af89a7297cc5d6f5f065cd1b53d9d3458e8b','captured_law_binary64_hex':actual_hex,
            'finite_work':{'max_attempts':2,'shared_total_splits':8,'max_evaluations':18,'proof':'at most2 initial cells plus2 children for each of8 total splits','solve_bisection_ceiling':64},'cases':cases}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    generated=(json.dumps(make(),indent=2)+'\n').encode('utf-8');target=Path(__file__).with_name('expected.json')
    if args.check:assert target.read_bytes()==generated,'Frozen reference differs; never rewrite from candidate output'
    else:
        assert not target.exists(),'Refuse frozen fixture overwrite; use --check'
        target.write_bytes(generated)
    print('reference cases:',len(make()['cases']),'check' if args.check else 'generated')
