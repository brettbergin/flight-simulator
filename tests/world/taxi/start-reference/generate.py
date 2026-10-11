#!/usr/bin/env python3
"""Original MIT, prospective independent pose references; stdlib only, no consumer imports."""
from decimal import Decimal as D, localcontext
from fractions import Fraction
from pathlib import Path
import argparse, hashlib, json, struct

def atan(x):
    if x < 0: return -atan(-x)
    if x > 1: return PI/2-atan(1/x)
    factor=1
    while x>D('0.1'):
        x=x/(1+(1+x*x).sqrt());factor*=2
    term=x; total=x; n=1
    while True:
        term=-term*x*x; nxt=total+term/D(2*n+1)
        if nxt==total:return total*factor
        total=nxt;n+=1

def sincos(x):
    x=x%(2*PI)
    if x>PI:x-=2*PI
    s=x;c=D(1);ts=x;tc=D(1);n=1
    while True:
        ts=-ts*x*x/D((2*n)*(2*n+1));tc=-tc*x*x/D((2*n-1)*(2*n))
        ns=s+ts;nc=c+tc
        if ns==s and nc==c:return s,c
        s,c=ns,nc;n+=1

def dot(a,b):return sum((x*y for x,y in zip(a,b)),D(0))
def plus(a,b):return [x+y for x,y in zip(a,b)]
def scale(a,b):return [x*b for x in a]
def sub(a,b):return plus(a,scale(b,D(-1)))
def basis(p,l):
    s,c=sincos(p);sl,cl=sincos(l)
    return [-s*cl,-s*sl,c],[-sl,cl,D(0)],[c*cl,c*sl,s]
def ecef(p,l,h):
    s,c=sincos(p);sl,cl=sincos(l);n=A/(1-E2*s*s).sqrt()
    return [(n+h)*c*cl,(n+h)*c*sl,(n*(1-E2)+h)*s]
def geodetic(v):
    x,y,z=v;r=(x*x+y*y).sqrt();p=atan(z/r)
    for _ in range(18):
        s,c=sincos(p);q=1-E2*s*s;n=A/q.sqrt();dn=n*E2*s*c/q
        f=r*s-z*c-E2*n*s*c
        df=r*c+z*s-E2*(dn*s*c+n*(c*c-s*s))
        delta=f/df;p-=delta
        if abs(delta)<D('1e-78'):break
    s,c=sincos(p);n=A/(1-E2*s*s).sqrt();h=r*c+z*s-n*(1-E2*s*s)
    # This packet's exact input domain is x<0,y<0 (longitude near -2).
    assert x<0 and y<0
    l=-PI+atan(y/x)
    assert max(abs(a-b) for a,b in zip(ecef(p,l,h),v))<D('1e-65')
    return p,l,h

def metric(v):
    f=float(v)
    return {'decimal':format(v,'.60g'),'nearest_binary64_hex':f.hex(),'binary64_le':struct.pack('<d',f).hex()}
def vec(v):return [metric(x) for x in v]
def project(v):
    d=sub(v,ANCHOR);return [dot(E,d),dot(U,d),-dot(N,d)]
def floor_height(p,l):
    n,e,u=basis(p,l);base=ecef(p,l,D(0))
    return dot(U,sub(ANCHOR,base))/dot(U,u)
def frame(v):
    p,l,h=geodetic(v);n,e,u=basis(p,l)
    # Columns forward/right/down expressed in fixed anchor EUS.
    columns=[[dot(E,w),dot(U,w),-dot(N,w)] for w in [n,e,scale(u,D(-1))]]
    return p,l,h,columns

def generate():
    global PI,A,E2,ANCHOR,N,E,U
    with localcontext() as ctx:
        ctx.prec=90
        # Machin identity avoids platform libm; 90-digit Decimal series.
        PI=D(16)*atan(D(1)/5)-D(4)*atan(D(1)/239)
        A=D(6378137);F=1/D.from_float(298.257223563);E2=F*(2-F)
        lat=D.from_float(.8);lon=D(-2);h=D.from_float(1.05)
        ANCHOR=ecef(lat,lon,D(0));N,E,U=basis(lat,lon)
        ideal=plus(ANCHOR,plus(scale(E,D(108)),plus(scale(N,D(-18)),scale(U,h))))
        # Declared binary64 operand order: basis/anchor individually rounded,
        # every multiply/add rounded, no FMA, no vector/float32 conversion.
        af=[float(x) for x in ANCHOR];nf=[float(x) for x in N];ef=[float(x) for x in E];uf=[float(x) for x in U]
        pf=[af[i]+(108.0*ef[i]+((-18.0*nf[i])+(1.05*uf[i]))) for i in range(3)]
        v=[D.from_float(x) for x in pf];p,l,gh,columns=frame(v);fh=floor_height(p,l)
        gear=[]
        for name,arm in [('gear.nose',[2,0,1]),('gear.left',[-1,D('-1.3'),1]),('gear.right',[-1,D('1.3'),1])]:
            n,e,u=basis(p,l);pt=plus(v,plus(scale(n,D(arm[0])),plus(scale(e,D(arm[1])),scale(u,-D(arm[2])))))
            gp,gl,hh=geodetic(pt);ff=floor_height(gp,gl)
            gear.append({'id':name,'nominal_body_frd_m':[str(x) for x in arm],'ecef_m':vec(pt),'anchor_eus_m':vec(project(pt)),'plane_signed_clearance_m':metric(dot(U,sub(pt,ANCHOR))),'geodetic_ray_agl_m':metric(hh-ff)})
        # Conservative complete authored airframe box (not native gear compression).
        # Box encloses authored primitives at every propeller angle; y lower
        # includes radius hypot(1.05,.075) of the rotating tip-box corners.
        # exact content bounds: x tips4.5375, forward spinner-3.395, aft ball3.6075.
        corners=[]
        for x in [D('-4.54'),D('4.54')]:
            for y in [D('-1.10'),D('1.55')]:
                for z in [D('-3.40'),D('3.61')]:
                    # model right/up/aft -> body(-aft,right,-up).
                    pt=plus(v,plus(scale(basis(p,l)[0],-z),plus(scale(basis(p,l)[1],x),scale(basis(p,l)[2],y))))
                    corners.append(project(pt))
        mins=[min(c[i] for c in corners) for i in range(3)];maxs=[max(c[i] for c in corners) for i in range(3)]
        winds=['calm','from-north','from-west','from-east'];legacy='original-interactive-prototype';piston='original-piston-prop-v1'
        old=[(s,legacy,w) for s in ['ground-ready','airborne-prepared'] for w in winds]+[('piston-cold-ground',piston,'calm')]
        new=[('apron-ready',legacy,'calm'),('piston-cold-apron',piston,'calm')]
        matrix=[{'named_start':s,'profile_id':q,'wind_profile':w,'seed':'42','accepted_old':(s,q,w) in old,'proposed_accepted':(s,q,w) in old+new} for s in ['ground-ready','airborne-prepared','piston-cold-ground','apron-ready','piston-cold-apron'] for q in [legacy,piston] for w in winds]
        negatives=[]
        for label,offset in [('north_sign',[108,h,-18]),('east_sign',[-108,h,18]),('eus_swap',[18,h,108]),('paint_center_as_cg',[108,h,34]),('anchor_ellipsoid_height_only',[0,h,0])]:
            q=plus(ANCHOR,plus(scale(E,D(offset[0])),plus(scale(N,-D(offset[2])),scale(U,D(offset[1])))))
            negatives.append({'id':label,'wrong_anchor_eus_m':[str(x) for x in offset],'distance_from_selected_cg_m':metric(dot(sub(q,v),sub(q,v)).sqrt()),'matches_selected_pose':False})
        # Treating height1.05 as ellipsoid at the displaced lat/lon misses planeCG.
        wrong=ecef(p,l,h)
        negatives.append({'id':'plane_height_as_ellipsoid_height','wrong_ellipsoid_height_m':metric(h),'miss_distance_m':metric(dot(sub(wrong,v),sub(wrong,v)).sqrt()),'matches_selected_pose':False})
        return {'schema':'ProspectiveApronPoseReference/v1','status':'proposed independent preconsumer mathematical references, no native observations','tuple_matrix':matrix,'old_admitted_count':9,'proposed_new_count':2,'anchor':{'latitude_rad':metric(lat),'longitude_rad':metric(lon),'ellipsoid_height_m':'0','ecef_m':vec(ANCHOR),'north_ecef':vec(N),'east_ecef':vec(E),'up_ecef':vec(U)},'selected':{'cg_anchor_eus_m':['108','binary64(1.05)','18'],'height_binary64_minus_21_over_20':str(D.from_float(1.05)-D(21)/20),'rpy_local_ned_rad':['0','0','0'],'body_to_local_ned_quaternion_wxyz':['1','0','0','0'],'body_velocity_mps':['0','0','0'],'seed':'42','brakes_left_right':['1','1'],'wind_ned_mps':['0','0','0'],'unrounded_binary_input_ecef_m':vec(ideal),'rounded_order_ecef_m':vec(v),'reprojected_anchor_eus_m':vec(project(v)),'geodetic_rad_m':vec([p,l,gh]),'surface_ellipsoid_height_m':metric(fh),'geodetic_ray_agl_m':metric(gh-fh),'anchor_plane_normal_clearance_m':metric(dot(U,sub(v,ANCHOR))),'body_to_anchor_eus_columns':list(map(vec,columns))},'nominal_gears':gear,'visual':{'paint_stand_x':'108','paint_center_z':'34','paint_cap_z':'16','paint_cap_half_width_m':'5','conservative_model_right_up_aft_min':['-4.54','-1.10','-3.40'],'conservative_model_right_up_aft_max':['4.54','1.55','3.61'],'anchor_eus_bbox_min_m':vec(mins),'anchor_eus_bbox_max_m':vec(maxs),'apron_paving_xz_min':['67','-70'],'apron_paving_xz_max':['197','120'],'hangar_front_z':'95.5','entire_nominal_visual_box_inside_apron':mins[0]>67 and maxs[0]<197 and mins[2]>-70 and maxs[2]<120,'nominal_box_separated_from_hangar_front':maxs[2]<D('95.5')},'axis_anchor_negatives':negatives,'admission_negatives':[{'id':'new_seed_41','admitted':False},{'id':'new_seed_uint64_max','admitted':False},{'id':'unknown_start','admitted':False},{'id':'nonzero_rpy_or_velocity','admitted':False}], 'comparators':{'pure_geodesy_and_plane_abs_m':'1e-7','local_rotation_abs_component':'1e-12','actual_nominal_gear_source_conversion_abs_m':'1e-4','existing_native_tickzero_ellipsoid_abs_m':'1e-5','presentation_local_float32_abs_m':'1e-4','enum_seed_and_input_binary64_bits':'exact'}}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true',required=True);ap.parse_args()
    expected=Path(__file__).with_name('expected-v1.json');actual=(json.dumps(generate(),indent=2,ensure_ascii=True)+'\n').encode()
    assert expected.read_bytes()==actual,'Frozen expected bytes differ; never overwrite in --check'
    print('PASS independent apron pose: 9 old +2 prospective tuples, 40 closed pairs, WGS84/gear/visual/sign cases; mathematical only')
if __name__=='__main__':main()
