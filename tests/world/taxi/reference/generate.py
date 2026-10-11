#!/usr/bin/env python3
"""Original MIT. Independent exact source/content references, no consumer imports.

--check compares immutable expected bytes and fixed content; never overwrites.
"""
from pathlib import Path
from fractions import Fraction as F
from decimal import Decimal as D, localcontext
import argparse, hashlib, json, struct

RECTS=[('runway',(0,-800),(20,900)),('parallel',(82,-800),(F(15,2),920)),('apron',(132,25),(65,95))]+[(s+'-link',(49,z),(F(65,2),F(15,2))) for s,z in [('south',30),('middle',-800),('north',-1630)]]
ROUTES=[('locate-parking',[(0,30),(40,30),(82,30),(108,30),(108,18)]),('outbound-36',[(108,18),(108,0),(82,0),(82,30),(40,30)]),('outbound-18',[(108,18),(108,0),(82,0),(82,-1630),(40,-1630)])]+[('return-'+s,[(40,z),(82,z),(82,0),(108,0),(108,18)]) for s,z in [('south',30),('middle',-800),('north',-1630)]]

def interval(p,q,center,half):
    lo,hi=F(0),F(1)
    for a,b,c,h in zip(p,q,center,half):
        a,b,c,h=map(F,(a,b,c,h));delta=b-a
        if not delta:
            if not c-h<=a<=c+h:return None
        else:
            u,v=(c-h-a)/delta,(c+h-a)/delta
            if u>v:u,v=v,u
            lo=max(lo,u);hi=min(hi,v)
    return (lo,hi) if lo<=hi else None

def cover(p,q):
    pieces=sorted(x for _,c,h in RECTS if (x:=interval(p,q,c,h)) is not None)
    end=F(0)
    for lo,hi in pieces:
        if lo>end:return False
        end=max(end,hi)
    return end==1

def atan_small(x):
    if x<0:return -atan_small(-x)
    factor=1
    while x>D('0.1'):
        x=x/(1+(1+x*x).sqrt());factor*=2
    total=term=x;n=1
    while True:
        term=-term*x*x;next_value=total+term/D(2*n+1)
        if next_value==total:return total*factor
        total=next_value;n+=1

def bits(x):return struct.pack('<d',float(x)).hex()
def metric(dx,dz):
    with localcontext() as ctx:
        ctx.prec=110
        dx=D(dx.numerator)/D(dx.denominator);dz=D(dz.numerator)/D(dz.denominator)
        rng=(dx*dx+dz*dz).sqrt()
        if not rng:return bits(0),None
        pi=16*atan_small(D(1)/5)-4*atan_small(D(1)/239)
        if not dz:bearing=D(90) if dx>0 else D(270)
        elif not dx:bearing=D(0) if dz<0 else D(180)
        else:
            theta=atan_small(abs(dx/dz))*180/pi
            bearing=theta if dz<0 and dx>0 else 360-theta if dz<0 else 180-theta if dx>0 else 180+theta
        return bits(rng),bits(bearing)

def generate():
    bounds=[{'id':name,'minimum_xz_m':[str(F(c)-F(h)) for c,h in zip(center,half)],'maximum_xz_m':[str(F(c)+F(h)) for c,h in zip(center,half)]} for name,center,half in RECTS]
    segments=[{'itinerary':name,'segment':i,'from_xz_m':list(p),'to_xz_m':list(q),'inside_six_rectangle_union':cover(p,q)} for name,points in ROUTES for i,(p,q) in enumerate(zip(points,points[1:]))]
    assert len(segments)==24 and all(x['inside_six_rectangle_union'] for x in segments)
    # Entire interval unions, including a tiny uncovered gap, no sampled-point proxy.
    union_examples=[{'id':'connected_link_crossing','p':[0,30],'q':[82,30],'inside':cover((0,30),(82,30))},{'id':'gap_between_main_strips','p':[0,0],'q':[82,0],'inside':cover((0,0),(82,0))},{'id':'outside_apron','p':[108,18],'q':[250,18],'inside':cover((108,18),(250,18))}]
    assert [x['inside'] for x in union_examples]==[True,False,False]
    signs=[]
    for slug,z,n in [('south',30,1),('middle',-800,2),('north',-1630,3)]:
        for normal in [(0,-1),(0,1)]:
            right=(normal[1],-normal[0]);projection=-right[0]
            signs.append({'site':'junction-'+slug,'site_eus_m':[95,'6/5',z+12],'normal_xz':list(normal),'screen_right_xz':list(right),'direction_world_xz':[-1,0],'arrow_screen': 'right' if projection>0 else 'left','panel_labels_left_to_right':['A','A'+str(n)] if projection>0 else ['A'+str(n),'A'],'panel_width_m':'6/5','panel_height_m':'3/5','panel_center_screen_offsets_m':['-3/5','3/5']})
    metric_rows=[]
    for name,dx,dz in [('north',F(0),F(-5)),('east',F(5),F(0)),('south',F(0),F(5)),('west',F(-5),F(0)),('coincident',F(0),F(0)),('ne_345',F(3),F(-4)),('se_345',F(3),F(4)),('sw_345',F(-3),F(4)),('nw_345',F(-3),F(-4)),('near_north',F(7),F(-24)),('tiny_east',F(1,2**1074),F(0))]:
        r,b=metric(dx,dz);metric_rows.append({'id':name,'delta_x_binary64_le':bits(float(dx)),'delta_z_binary64_le':bits(float(dz)),'range_binary64_le':r,'anchor_bearing_deg_binary64_le':b})
    # Structural recipe expectations are declarative, not executed consumer tests.
    shape_cases=[{'id':'revision_int1','value':1,'accepted':True},{'id':'revision_float1','value':1.0,'accepted':True},{'id':'revision_bool','value':True,'accepted':False},{'id':'revision_string','value':'1','accepted':False},{'id':'revision_fractional','value':1.5,'accepted':False}]
    domain=[{'profile':'original-interactive-prototype','recording_version':1,'archive_version':1,'named_start':s,'accepted_domain':True} for s in ['ground-ready','airborne-prepared','apron-ready']]+[{'profile':'original-piston-prop-v1','recording_version':2,'archive_version':2,'named_start':s,'accepted_domain':True} for s in ['piston-cold-ground','piston-cold-apron']]+[{'profile':'original-interactive-prototype','recording_version':1,'archive_version':1,'named_start':'piston-cold-apron','accepted_domain':False},{'profile':'original-piston-prop-v1','recording_version':2,'archive_version':2,'named_start':'apron-ready','accepted_domain':False}]
    return {'schema':'SyntheticTaxiContentReference/v1','status':'proposed original source/math; no consumer or backend outputs','rectangles':bounds,'route_segments':segments,'segment_counterexamples':union_examples,'parking':[{'id':'park-'+str(i+1),'stripe_center_eus_m':[108+19*i,0,34],'stripe_z_bounds_m':[16,52],'cap_z_m':16,'cap_half_width_m':5,'stand_point_eus_m':[108+19*i,0,18]} for i in range(5)],'junction_faces':signs,'holding':{'offsets_x_m':['-13/10','-7/10','7/10','13/10'],'styles':['dashed','dashed','solid','solid'],'relative_on_z_intervals_m':[[z,z+1] for z in range(-7,7,2)],'approach':'east-to-west','holding_side':'east','east_face_label':'36-18'},'metrics':metric_rows,'revision_admission_recipes':shape_cases,'record_archive_domain_recipes':domain,'criteria':{'exact':'IDs, counts, rectangle/segment rationals, arrows, domains, integer admission and transported reference bits','range_abs_m':'1e-7','bearing_abs_deg':'1e-7','coincident_range':'exact +0 and no bearing','tiny_cardinal':'exact min positive binary64 range, exact90deg bearing; not rounded zero','scope':'predeclared bounded presentation comparisons, no physics/solver/RunIC or universal rounding theorem'}}

def no_duplicates(pairs):
    out={}
    for key,value in pairs:
        if key in out:raise ValueError('Duplicate raw JSON key')
        out[key]=value
    return out

def verify_content(root):
    path=root/'content/world/synthetic/taxi-layout-v1.json';raw=path.read_bytes();content=json.loads(raw,object_pairs_hook=no_duplicates,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))
    binding=json.loads(Path(__file__).with_name('source-binding-v1.json').read_bytes())
    assert hashlib.sha256(raw).hexdigest()==binding['content_sha256'],'Changed fixed content bytes'
    assert hashlib.sha256((root/binding['schema_path']).read_bytes()).hexdigest()==binding['schema_sha256'],'Changed fixed schema bytes'
    assert hashlib.sha256(Path(__file__).read_bytes()).hexdigest()==binding['generator_sha256'],'Changed reference generator bytes'
    assert hashlib.sha256(Path(__file__).with_name('expected-v1.json').read_bytes()).hexdigest()==binding['expected_sha256'],'Changed frozen reference bytes'
    for row in binding['companion_files']:
        companion=(root/row['path']).read_bytes()
        assert len(companion)==row['bytes'] and hashlib.sha256(companion).hexdigest()==row['sha256'],row['path']
    assert set(content)=={'schema','id','revision','license','provenance','world','frame','pavement','links','parking','signs','itineraries','starts'}
    actual=content['pavement']+content['links'];assert len(actual)==6
    for row,(name,c,h) in zip(actual,RECTS):
        assert row['id']==name and [F(str(x)) for x in row['center_xz_m']]==list(map(F,c)) and [F(str(x)) for x in row['half_extent_xz_m']]==list(map(F,h))
    assert len(content['itineraries'])==6 and len(content['parking'])==5 and len(content['signs'])==7
    for row,(name,points) in zip(content['itineraries'],ROUTES):assert row['id']==name and [p['point_eus_m'] for p in row['points']]==[[x,0,z] for x,z in points]
    for i,row in enumerate(content['parking']):assert row['stripe_center_eus_m']==[108+19*i,0,34] and row['stand_point_eus_m']==[108+19*i,0,18] and row['cap_z_m']==16
    for row in content['links']:assert row['bar_styles']==['dashed','dashed','solid','solid'] and row['dash_pattern_m']=={'length':1,'gap':1,'origin_relative_z':-7}
    for row,slug,n,z in zip(content['signs'][::2][:3],['south','middle','north'],[1,2,3],[30,-800,-1630]):
        assert row['id']=='junction-'+slug and row['point_eus_m']==[95,1.2,z+12]
        assert [f['normal_xz'] for f in row['faces']]==[[0,-1],[0,1]]
        assert [[p['label'] for p in f['panels']] for f in row['faces']]==[['A','A'+str(n)],['A'+str(n),'A']]
        for face in row['faces']:
            assert len(face['panels'])==2
            for panel in face['panels']:assert panel['direction_xz']==([-1,0] if panel['role']=='direction' else None)
    assert [(x['named_start'],x['profile_id'],x['wind_profile'],x['requested_cg_eus_m']) for x in content['starts']]==[('apron-ready','original-interactive-prototype','calm',[108,1.05,18]),('piston-cold-apron','original-piston-prop-v1','calm',[108,1.05,18])]
    # Raw duplicate parser negative is actually exercised, unlike consumer recipes.
    try:json.loads('{"revision":1,"revision":1}',object_pairs_hook=no_duplicates)
    except ValueError:pass
    else:raise AssertionError('Duplicate-key source verifier failed')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true',required=True);parser.parse_args()
    here=Path(__file__).resolve().parent;generated=(json.dumps(generate(),indent=2,ensure_ascii=True)+'\n').encode('ascii')
    assert generated==here.joinpath('expected-v1.json').read_bytes(),'Frozen expected bytes differ; --check cannot write'
    verify_content(here.parents[3]);print('PASS source/math content reference: 6 rectangles,24 route segments,6junction faces,5stands,11metrics; no consumer/backend run')

if __name__=='__main__':main()
