#!/usr/bin/env python3
"""Original MIT source-derived nominal disk support; mathematical only, no consumer imports."""
from decimal import Decimal as D, localcontext
from pathlib import Path
import argparse, hashlib, importlib.util, json, struct, sys

POSE_GENERATOR_SHA = "da0e7b91bd3a3ea7df60f80b01b75df209bc4271950f6458fa462da4efba2645"
POSE_EXPECTED_SHA = "fb543ddd1681c3cb040cdfd1c65ff404eb9409e73bb6f613c225a3a501f2e333"
SOURCES = [
    {"path":"native/fdm_jsbsim/models/original-piston-prop/aircraft/original-piston-prop/original-piston-prop.xml", "sha256":"b9a41861fcbca1917978312d73a192cbe2c2ea0e6ef0e13512c76148a6c9d4c5", "bytes":6784, "role":"lines6,12-14: zero CG, structural location[-2,0,0]m, zero orientation, p_factor0"},
    {"path":"native/fdm_jsbsim/models/original-piston-prop/engine/original-fixed-prop.xml", "sha256":"b4f3f376f062d869a338bb2757466c9ba23d6320d895d3fc5921e351748bb0af", "bytes":826, "role":"line5: diameter6FT; original MIT numerical fixture"},
    {"path":"native/fdm_jsbsim/models/original-piston-prop/inventory.json", "sha256":"f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a", "bytes":3307, "role":"immutable original MIT model inventory"},
]
PRIMARY_SOURCE = [
    {"path":"vendor/src/models/FGMassBalance.cpp","bytes":19792,"sha256":"85c766aecd92fd4a416a9a625a967d19ed69fba39db2fb5bdfeb59d765652fbd","lines":"363-391","role":"StructuralToBody: structural aft/right/up -> body forward/right/down, CG-relative"},
    {"path":"vendor/src/models/propulsion/FGThruster.cpp","bytes":7737,"sha256":"d949f8b5b8da196ce6ae865abb62083e30f63cf56a1122cf32d2085f898772c3","lines":"53-113","role":"location and zero orient loaded from aircraft thruster element"},
    {"path":"vendor/src/models/propulsion/FGPropeller.cpp","bytes":54782,"sha256":"e0ff11682070f2fa5a40ed7f14dbfcf56719a186089eb03185af8cdf9227d9f4","lines":"789-790","role":"diameter read in feet; archived coupled-midpoint-v1 source, geometry premise only, not current solver identity"},
]

def sha(b): return hashlib.sha256(b).hexdigest()
def exact_vec(rows): return [D.from_float(struct.unpack('<d',bytes.fromhex(x['binary64_le']))[0]) for x in rows]

def generate(repo_root, pose_generator):
    # Only the independently authored mathematical reference is imported, after
    # exact byte admission. No Godot/native/runtime implementation is imported.
    assert sha(pose_generator.read_bytes()) == POSE_GENERATOR_SHA
    assert sha(pose_generator.with_name('expected-v1.json').read_bytes()) == POSE_EXPECTED_SHA
    for row in SOURCES:
        b=(repo_root/row['path']).read_bytes()
        assert len(b)==row['bytes'] and sha(b)==row['sha256'], row['path']
    spec=importlib.util.spec_from_file_location('independent_apron_pose_reference',pose_generator)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    with localcontext() as ctx:
        ctx.prec=90
        pose=m.generate()
        # Exact binary64 ECEF operand-order result selected by the reviewed pose
        # packet. Geodetic inverse/basis then recomputed using its Decimal math.
        p=exact_vec(pose['selected']['rounded_order_ecef_m'])
        lat,lon,height=m.geodetic(p);n,e,u=m.basis(lat,lon);down=m.scale(u,D(-1))
        radius=D(6)*D('0.3048')/2
        center=m.plus(p,m.scale(n,D(2)))
        axes=[m.E,m.U,m.scale(m.N,D(-1))]
        center_eus=m.project(center)
        spans=[radius*(m.dot(a,e)**2+m.dot(a,down)**2).sqrt() for a in axes]
        low=[c-r for c,r in zip(center_eus,spans)]
        high=[c+r for c,r in zip(center_eus,spans)]
        normal_clearance=low[1]
        assert normal_clearance>D(0)
        assert low[0]>67 and high[0]<197 and low[2]>-70 and high[2]<120
        axis_vectors=[m.project(m.plus(m.ANCHOR,x)) for x in [n,e,down]]
        return {
            'schema':'ProspectiveApronPhysicalPropDiskReference/v1',
            'status':'proposed independent source-derived mathematics; no native, contact, collision, blade-motion or fidelity observation',
            'license':'Original reference code and fixtures MIT; pinned JSBSim source cited for frame/unit semantics, no vendor source redistributed here',
            'pose_expected_sha256':POSE_EXPECTED_SHA,'pose_generator_sha256':POSE_GENERATOR_SHA,
            'sources':SOURCES,'primary_source_semantics':PRIMARY_SOURCE,
            'domain':{'profile_id':'original-piston-prop-v1','named_start':'piston-cold-apron','seed':'42','cg_anchor_eus_m':['108','binary64(1.05)','18'],'body_to_query_local_ned_rpy_rad':['0','0','0'],'structural_location_m':['-2','0','0'],'cg_structural_m':['0','0','0'],'body_frd_center_m':['2','0','0'],'diameter_ft':'6','metres_per_foot_exact':'0.3048','radius_m_exact':'0.9144'},
            'definition':{'point':'P+2*N_query+r*(cos(theta)*E_query+sin(theta)*D_query), all theta', 'support':'for each unit anchor axis a, halfspan=r*sqrt((a dot E_query)^2+(a dot D_query)^2)', 'frame':'fixed anchor EUS=[E_anchor,U_anchor,-N_anchor]; D_query=-U_query', 'arithmetic':'90-digit Decimal analytical support; P is exact decoded binary64 declared pose result; no native unit-conversion rounding implied'},
            'query_local_ned_axes_in_anchor_eus':list(map(m.vec,axis_vectors)),
            'center_ecef_m':m.vec(center),'center_anchor_eus_m':m.vec(center_eus),
            'axis_support_halfspan_m':m.vec(spans),'support_min_anchor_eus_m':m.vec(low),'support_max_anchor_eus_m':m.vec(high),
            'anchor_plane_normal_min_clearance_m':m.metric(normal_clearance),
            'apron_paving_xz_bounds_m':{'min':['67','-70'],'max':['197','120']},
            'apron_margin_m':{'west':m.metric(low[0]-67),'east':m.metric(D(197)-high[0]),'north':m.metric(low[2]+70),'south':m.metric(D(120)-high[2])},
            'entire_ideal_disk_within_apron_xz':True,
            'distinctions':['Physical authored fixed-pitch disk differs from visual propeller plane at model aft -3.18m and visual radial tips; neither is substituted for the other.', 'Plane clearance is support along fixed anchor normal, not ellipsoid height or geodetic-ray AGL.', 'CG/mass distribution is nominal authored CG0; runtime CG, attitude, compression and blade geometry require actual qualification.', 'The paint cap at z16 is paint, not a collision or containment boundary; center z need not equal16 after query-local basis conversion.'],
            'negative_interpretations':[{'id':'structural_x_used_as_body_forward','wrong_body_center_m':['-2','0','0'],'center_displacement_m':'4'}, {'id':'diameter_used_as_radius','wrong_radius_m':'1.8288','matches_source':False}, {'id':'anchor_N_instead_of_query_N','matches_query_local_basis':False}, {'id':'visual_rotor_center_substituted','wrong_body_forward_m':'3.18','matches_native_thruster':False}],
            'comparators':{'analytical_support_abs_m':'1e-7','actual_native_geometry_source_conversion_abs_m':'1e-4','basis_component_abs':'1e-12','source_and_pose_bits':'exact','scope':'Existing source-derived geometry/geodesy budgets; no new solver or physics budget; actual geometry only if future qualified observer exposes it.'}
        }

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true',required=True)
    ap.add_argument('--repo-root',type=Path,default=Path(__file__).resolve().parents[4])
    ap.add_argument('--pose-generator',type=Path,default=Path(__file__).with_name('generate.py'))
    args=ap.parse_args()
    actual=(json.dumps(generate(args.repo_root,args.pose_generator),indent=2,ensure_ascii=True)+'\n').encode('utf-8')
    assert Path(__file__).with_name('prop-disk-v1.json').read_bytes()==actual,'Frozen disk references differ; --check never writes'
    print('PASS source-derived nominal piston disk: exact6ft/FRD+2m, query-local basis, anchor support and apron margins; mathematical only')
if __name__=='__main__': main()
