"""Independent private camera oracle. No camera/engine consumer is imported.

Decimal Rodrigues rotations and an exponential integral are evaluated from exact
dyadic inputs. Lifecycle expectations below are manually authored, not produced
by a candidate state machine. --check is read-only.
"""
from pathlib import Path
from decimal import Decimal, localcontext
import argparse
import hashlib
import json
import struct

HERE = Path(__file__).resolve().parent
ADR_SHA = '2cd89a17541d574559be6a1892e7229e544f94ce1eb142f7f415662abc51ad36'
D = Decimal


def binary(value):
    f = float(value)
    return {'binary64_le': struct.pack('<d', f).hex(), 'display': str(value)}


def vector(values):
    return [binary(x) for x in values]


def sin_cos(x):
    # Alternating Taylor series. All declared |x| <= 1: decreasing terms and
    # next-term remainder bound; Decimal working precision exceeds output needs.
    square = x * x
    st, ct = x, D(1)
    s, c = st, ct
    for n in range(1, 160):
        st = -st * square / D((2*n)*(2*n+1))
        ct = -ct * square / D((2*n-1)*(2*n))
        s += st
        c += ct
        if abs(st) < D('1e-105') and abs(ct) < D('1e-105'):
            return s, c
    raise AssertionError('Taylor capacity')


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def dot(a, b):
    return sum((x*y for x, y in zip(a, b)), D(0))


def turn(v, axis, angle):
    # General Rodrigues theorem, not the ADR's component table or producer Basis.
    s, c = sin_cos(angle)
    perpendicular = cross(axis, v)
    projection = dot(axis, v)
    return [v[i]*c + perpendicular[i]*s + axis[i]*projection*(1-c) for i in range(3)]


def normalized(v):
    length = dot(v, v).sqrt()
    return [x / length for x in v]


def matrix_vector(rows, v):
    return [dot(row, v) for row in rows]


def output(precision):
    with localcontext() as ctx:
        ctx.prec = precision
        up = [D(0), D(1), D(0)]
        right = [D(1), D(0), D(0)]
        eye = [D('-.27'), D('.67'), D('-.92')]
        focus = [D('-.08'), D('.255'), D('-1.535')]
        cockpit = normalized([D(0), D('-.268'), D(-1)])
        panel = normalized([focus[i]-eye[i] for i in range(3)])
        bases = {'cockpit': cockpit, 'forward_horizon': [D(0), D(0), D(-1)], 'left_window': [D(-1), D(0), D(0)], 'right_window': [D(1), D(0), D(0)], 'panel': panel}
        mappings = [
            {'preset': 'cockpit', 'mode': 0, 'default_fov': binary(72), 'base_direction': vector(cockpit)},
            {'preset': 'forward_horizon', 'mode': 0, 'default_fov': binary(72), 'base_direction': vector(bases['forward_horizon'])},
            {'preset': 'left_window', 'mode': 0, 'default_fov': binary(72), 'base_direction': vector(bases['left_window'])},
            {'preset': 'right_window', 'mode': 0, 'default_fov': binary(72), 'base_direction': vector(bases['right_window'])},
            {'preset': 'panel', 'mode': 3, 'default_fov': binary(58), 'base_direction': None, 'host_direction_reference': vector(panel)},
            {'preset': 'chase', 'mode': 1, 'default_fov': binary(72), 'base_direction': None},
            {'preset': 'orbit', 'mode': 2, 'default_fov': binary(72), 'base_direction': None},
        ]
        rotations = {
            'identity': [[D(1), D(0), D(0)], [D(0), D(1), D(0)], [D(0), D(0), D(1)]],
            'permute_x_to_minus_z': [[D(0), D(0), D(1)], [D(0), D(1), D(0)], [D(-1), D(0), D(0)]],
            'inverted_up': [[D(1), D(0), D(0)], [D(0), D(-1), D(0)], [D(0), D(0), D(-1)]],
        }
        direction_specs = []
        for preset in ('forward_horizon', 'left_window', 'right_window'):
            for yaw, pitch in [('0','0'), ('0','.25'), ('0','-.25'), ('.5','0'), ('-.5','0'), ('.5','.25'), ('-.5','-.25')]:
                direction_specs.append((preset, yaw, pitch, 'identity'))
            direction_specs.append((preset, '.5', '.25', 'permute_x_to_minus_z'))
            direction_specs.append((preset, '.5', '.25', 'inverted_up'))
        # Traditional references are ideal-math supplements only. Exact legacy
        # evaluation order/normalization must also be compared in the same engine.
        direction_specs += [('cockpit', '0', '0', 'identity'), ('cockpit', '.5', '.25', 'identity'), ('panel', '0', '0', 'identity'), ('panel', '-.5', '-.25', 'identity')]
        directions = []
        for i, (preset, ya, pi, rotation) in enumerate(direction_specs, 1):
            yaw, pitch = D(ya), D(pi)
            # All chosen decimals are dyadic and exactly representable in binary64.
            assert D.from_float(float(yaw)) == yaw and D.from_float(float(pitch)) == pitch
            base = bases[preset]
            pitch_axis = cross(base, up) if preset in ('left_window', 'right_window') else right
            local = turn(turn(base, pitch_axis, pitch), up, -yaw)
            scene = matrix_vector(rotations[rotation], local)
            directions.append({'id': f'D{i:02}', 'preset': preset, 'yaw': binary(yaw), 'pitch': binary(pitch), 'basis': rotation, 'pitch_axis': vector(pitch_axis), 'expected_local': vector(local), 'expected_scene': vector(scene), 'expected_scene_up': vector(matrix_vector(rotations[rotation], up)), 'oracle': 'Decimal Rodrigues; exact dyadic angle inputs'})

        # Exact copied settings field types remain explicit; Python/JSON's numeric
        # representation does not determine the tested Godot Variant type.
        def setting(p='left_window', f='61.5', response='immediate'):
            return {'preset': p, 'fov_deg': binary(D(f)), 'external_response': response}
        valid_settings = [
            {'id': 'S01', 'input': setting('cockpit','72','smooth'), 'expected_ok': True},
            {'id': 'S02', 'input': setting('left_window','35','immediate'), 'expected_ok': True},
            {'id': 'S03', 'input': setting('right_window','90','smooth'), 'expected_ok': True},
            {'id': 'S04', 'input': setting('panel','61.5','immediate'), 'expected_ok': True},
        ]
        rejected_specs = [
            ('missing fov key', {'remove': 'fov_deg'}),
            ('extra key', {'add': {'unknown': True}}),
            ('integer FOV', {'field': 'fov_deg', 'variant': 'INT', 'value': 72}),
            ('boolean FOV', {'field': 'fov_deg', 'variant': 'BOOL', 'value': True}),
            ('string FOV', {'field': 'fov_deg', 'variant': 'STRING', 'value': '72'}),
            ('NaN FOV', {'field': 'fov_deg', 'variant': 'FLOAT', 'binary64_le': '000000000000f87f'}),
            ('positive infinity FOV', {'field': 'fov_deg', 'variant': 'FLOAT', 'binary64_le': '000000000000f07f'}),
            ('below35 adjacent binary64', {'field': 'fov_deg', 'variant': 'FLOAT', 'binary64_le': 'ffffffffff7f4140'}),
            ('above90 adjacent binary64', {'field': 'fov_deg', 'variant': 'FLOAT', 'binary64_le': '0100000000805640'}),
            ('StringName preset', {'field': 'preset', 'variant': 'STRING_NAME', 'value': 'left_window'}),
            ('StringName response', {'field': 'external_response', 'variant': 'STRING_NAME', 'value': 'smooth'}),
            ('StringName key', {'key_type': 'STRING_NAME', 'key': 'preset'}),
            ('unknown preset', {'field': 'preset', 'variant': 'STRING', 'value': 'Left window'}),
            ('unknown response', {'field': 'external_response', 'variant': 'STRING', 'value': 'Smooth'}),
            ('null settings', {'replace_root_variant': 'NIL'}),
            ('Array settings', {'replace_root_variant': 'ARRAY'}),
            ('Object settings', {'replace_root_variant': 'OBJECT'}),
        ]
        rejected_settings = [{'id': f'S{i:02}', 'description': why, 'base_input': setting(), 'edit': edit, 'expected_ok': False, 'expected_value': None, 'error': 'nonempty exact String; wording not prescribed', 'host_and_input': 'unchanged'} for i, (why, edit) in enumerate(rejected_specs, 5)]
        copies = [
            {'id': 'C01', 'operation': 'Mutate defaults() result, call defaults() again', 'expected': setting('cockpit','72','smooth')},
            {'id': 'C02', 'operation': 'After validate success, mutate caller input', 'expected': 'Previously returned value unchanged and not aliased'},
            {'id': 'C03', 'operation': 'Mutate successful returned value', 'expected': 'Original input, subsequent defaults and validation unchanged'},
            {'id': 'C04', 'operation': 'Mutate describe() base-direction array', 'expected': 'Subsequent describe() and all other preset directions unchanged'},
        ]

        initial = {'settings': setting(), 'look_angles': [binary(D('.25')),binary(D('-.125'))], 'distance_m': binary(17), 'follow_offset_m': vector([D(1),D(2),D(3)]), 'follow_ready': True, 'manual_aid_visibility': 'captured unchanged per same-mode current owner', 'session_id': 'camera-reference-session-A'}
        defaults = {'settings': setting('cockpit','72','smooth'), 'look_angles': [binary(0), binary(0)], 'distance_m': binary(13)}
        valid_entry = {'adopted_session_id': 'camera-reference-session-A', 'identity_qualified': True, 'paused': True, 'host_mode': 'paused', 'valid_current_visual_pose': True, 'menu_open': True, 'initializing': False, 'closing': False, 'other_modal_owner': None, 'visible_pointer': True, 'active_pointer_capture': False, 'queued_pointer_capture': False}
        page_cases = [
            {'id':'L01','action':'open then edit draft to right_window/58/smooth','expected':{'host_camera':'EXACT_INITIAL','draft':'changed owned copy','page':'open','default_focus':'Cancel'}},
            {'id':'L02','action':'open, edit draft, Cancel','expected':{'host_camera':'EXACT_INITIAL','page':'closed','host_mode':'paused'}},
            {'id':'L03','action':'open, edit draft, Escape','expected':{'host_camera':'EXACT_INITIAL','page':'closed','host_mode':'paused'}},
            {'id':'L04','action':'open, edit draft, Back','expected':{'host_camera':'EXACT_INITIAL','page':'closed','host_mode':'paused'}},
            {'id':'L05','action':'open, select right_window, edit FOV58, Apply','expected':{'settings':setting('right_window','58','immediate'),'look_angles':[binary(0),binary(0)],'distance_m':binary(17),'follow_offset_policy':'reseed from desired at next coherent draw; no stale blend; internal readiness flag not prescribed','page':'closed','host_mode':'paused','same_mode_aids':'EXACT_INITIAL'}},
            {'id':'L06','action':'open, Restore defaults, Cancel','expected':{'host_camera':'EXACT_INITIAL','page':'closed'}},
            {'id':'L07','action':'open, Restore defaults, Apply','expected':{'settings':setting('cockpit','72','smooth'),'look_angles':[binary(0),binary(0)],'distance_m':binary(17),'follow_offset_policy':'reseed at next coherent draw','same_mode_aids':'EXACT_INITIAL','host_mode':'paused'}},
            {'id':'L08','action':'open, select panel, then set draft FOV61.5, Apply','expected':{'settings':setting('panel','61.5','immediate'),'mode':3,'distance_m':binary(17),'inherited_visibility':'traditional mode3 rules apply; not same-mode aid invariance'}},
            {'id':'L09','action':'open, corrupt draft FOV Variant to INT72, Apply','expected':{'host_camera':'EXACT_INITIAL','ok':False,'no_partial_adoption':True}},
            {'id':'L10','action':'Apply identical settings twice from separate valid paused openings','expected':{'after_second':'EXACT_FIRST_APPLIED_PRESENTATION','extra_generation_or_tick_change':False}},
            {'id':'L11','action':'open under sessionA, change adopted session to B externally, deliver stale Apply callback','expected':{'ok':False,'current_sessionB_camera':'unchanged','page_callback':'retired'}},
            {'id':'L12','action':'open, externally fail/close/quit, deliver retired callback','expected':{'ok':False,'camera_after_external_lifecycle':'unchanged by callback','page_callback':'retired'}},
            {'id':'L13','action':'cancel requested discard/restart','expected':{'host_camera':'EXACT_INITIAL'}},
            {'id':'L14','action':'external restart attempt fails before fully successful adoption','expected':{'settings':'EXACT_INITIAL','geometry':'may be honestly suppressed by existing failed restart; not claimed current'}},
            {'id':'L15','action':'external fresh session fully adopted successfully, invoke camera session reset','expected':{'camera_defaults':defaults,'old_callback':'retired','no_camera_initiated_native_calls':True}},
            {'id':'L16','action':'open/Apply while physical look button still guarded held from prior pause; Resume after real admission','expected':{'guard':'unchanged until actual up edge','capture':'unavailable while guarded','native_release_fabricated':False}},
        ]
        reject_entries = []
        for i, (field, value) in enumerate([
            ('identity_qualified',False),('paused',False),('host_mode','live'),('valid_current_visual_pose',False),('menu_open',False),('initializing',True),('closing',True),('visible_pointer',False),('active_pointer_capture',True),('queued_pointer_capture',True),
        ], 1):
            reject_entries.append({'id': f'G{i:02}', 'valid_base': 'valid_entry', 'override': {field:value}, 'expected_open':False,'camera':'EXACT_INITIAL','native_pause_requested':False,'capture_or_guard_clear':False})
        for i, owner in enumerate(['archive','discard','review','Controls','Wind','Audio','Scan','Route','First-flight'],11):
            reject_entries.append({'id':f'G{i:02}','valid_base':'valid_entry','override':{'other_modal_owner':owner},'expected_open':False,'camera':'EXACT_INITIAL','native_pause_requested':False,'capture_or_guard_clear':False})
        actions = []
        modes = {x['preset']:x['mode'] for x in mappings}
        next_preset = {0:'chase',1:'orbit',2:'panel',3:'cockpit'}
        for i, preset in enumerate(modes, 1):
            nxt = next_preset[modes[preset]]
            actions.append({'id':f'A{i:02}','initial_preset':preset,'operation':'accepted view_cycle','expected_preset':nxt,'expected_mode':modes[nxt],'expected_fov':binary(58 if nxt=='panel' else 72),'look_angles':[binary(0),binary(0)],'distance_m':binary(17),'external_response':'preserve immediate','aid_effect':'only inherited traditional-mode transition'})
        for i, preset in enumerate(['cockpit','chase','orbit','panel'],8):
            actions.append({'id':f'A{i:02}','initial_preset':'left_window','operation':'accepted view_'+preset,'expected_preset':preset,'expected_fov':binary(58 if preset=='panel' else 72),'look_angles':[binary(0),binary(0)],'distance_m':binary(17),'external_response':'preserve immediate','aid_effect':'existing explicit traditional-action behavior; no new gaze policy'})
        actions += [
            {'id':'A12','initial_preset':'left_window','operation':'accepted recenter','expected_preset':'left_window','expected_fov':binary(D('61.5')),'look_angles':[binary(0),binary(0)],'distance_m':binary(17),'external_response':'immediate','aid_effect':'EXACT_INITIAL'},
            {'id':'A13','initial_preset':'left_window','operation':'interior zoom from FOV35 by -3','expected_fov':binary(35),'distance_m':binary(17)},
            {'id':'A14','initial_preset':'right_window','operation':'interior zoom from FOV90 by +3','expected_fov':binary(90),'distance_m':binary(17)},
            {'id':'A15','initial_preset':'orbit','operation':'external distance from6 by-1','expected_distance_m':binary(6),'fov_policy':'unchanged'},
            {'id':'A16','initial_preset':'chase','operation':'external distance from40 by+1','expected_distance_m':binary(40),'fov_policy':'unchanged'},
            {'id':'A17','initial_preset':'cockpit','operation':'zoom actual FOV to69, open Views','expected_draft_fov':binary(69),'not_stale_previous_draft':True},
            {'id':'A18','initial_preset':'left_window','operation':'actual look_hold up edge after ordinary live input boundary','expected':'pointer visible; same preset/angles/held native intent; no forced recenter'},
        ]
        # Scalar exponential reference independent of Vector3.lerp. All dt inputs
        # are exact dyadics; values <=0 are limited to existing clamp reference,
        # not a new host admission of negative wall time.
        filters = []
        for i, dt in enumerate([D(0),D('.015625'),D('.125'),D('.25'),D('.5')],1):
            clipped=min(max(dt,D(0)),D('.25'))
            weight=1-(-9*clipped).exp()
            filters.append({'id':f'F{i:02}','seconds':binary(dt),'expected_clamped_seconds':binary(clipped),'expected_alpha':binary(weight),'reference':'Integral response of d(offset)/dt=9*(desired-offset), fixed desired for interval'})
        sequence = []
        old = [D(0), D('3.5'), D(13)]
        desireds = [[D(13),D('3.5'),D(0)],[D(0),D('3.5'),D(-13)],[D(0),D('3.5'),D(-13)]]
        for i, (desired, dt) in enumerate(zip(desireds,[D('.125'),D('.25'),D(0)]),1):
            decay=(-9*min(dt,D('.25'))).exp()
            following=[desired[j]+(old[j]-desired[j])*decay for j in range(3)]
            ownship=[D(2*i),D(0),D(0)]
            sequence.append({'id':f'M{i:02}','presented_ownship_m':vector(ownship),'latest_raw_endpoint_m':vector([D(100+i),D(0),D(0)]),'previous_smooth_offset_m':vector(old),'desired_offset_m':vector(desired),'seconds':binary(dt),'expected_smooth_offset_m':vector(following),'expected_smooth_camera_m':vector([ownship[j]+following[j] for j in range(3)]),'expected_immediate_offset_m':vector(desired),'expected_immediate_camera_m':vector([ownship[j]+desired[j] for j in range(3)]),'raw_endpoint_ignored':True})
            old=following
        branches=[
            {'id':'B01','context':'first draw/not ready','response':'smooth','expected_offset':'EXACT_DESIRED','no_stale_mode_blend':True},
            {'id':'B02','context':'paused','response':'smooth','expected_offset':'EXACT_DESIRED'},
            {'id':'B03','context':'interior mode0 or3','response':'smooth','expected_offset':'EXACT_EYE_IN_PRESENTED_BASIS'},
            {'id':'B04','context':'live external ready, seconds0, same desired pose','response':'smooth','expected_offset':'EXACT_PREVIOUS','filter_advance':False},
            {'id':'B05','context':'live external ready, seconds0, same desired pose','response':'immediate','expected_offset':'EXACT_DESIRED','repeat_idempotent':True},
            {'id':'B06','context':'mode/response adopted while paused','response':'either','expected_offset_next_draw':'EXACT_DESIRED','no_stale_mode_blend':True},
            {'id':'B07','context':'Orbit desired y below existing plane-floor+0.35','response':'either','expected':'existing desired and final camera floor clamps retained; no aircraft or plane movement'},
            {'id':'B08','context':'coherent origin rebase by exact common translation(16,0,-8)','response':'either','expected':'camera and ownship receive same common translation; relative offset and view direction unchanged'},
        ]
        # Manual hand-check anchors catch shared accidental oracle errors.
        for case in directions[:27]:
            p=case['preset'];a=struct.unpack('<d',bytes.fromhex(case['yaw']['binary64_le']))[0];b=struct.unpack('<d',bytes.fromhex(case['pitch']['binary64_le']))[0]
            v=[struct.unpack('<d',bytes.fromhex(x['binary64_le']))[0] for x in case['expected_local']]
            if a==0 and b>0: assert v[1]>0
            if a==0 and b<0: assert v[1]<0
            if b==0 and a>0 and p=='left_window': assert v[2]<0
            if b==0 and a>0 and p=='right_window': assert v[2]>0
        assert struct.unpack('<d', bytes.fromhex('ffffffffff7f4140'))[0] == float.fromhex('0x1.17fffffffffffp+5')
        assert struct.unpack('<d', bytes.fromhex('0100000000805640'))[0] > 90
        return {
            'schema':'PrivateCameraPreconsumerReferences/v1','status':'FROZEN_EXPECTATIONS_PROPOSED_FOR_INDEPENDENT_RATIFICATION_NOT_RUNTIME_EVIDENCE',
            'adr_git_lf_sha256':ADR_SHA,
            'format':'binary64_le fields are test descriptors, not production/public JSON schemas; decode bytes to FLOAT without a decimal parser. JSON ints/booleans are declarative metadata only. Explicit Variant edits construct actual types in future driver.',
            'precision':'Decimal110 and140 independently regenerate identical serialized binary64 expected values; working precision is not a runtime/libm claim.',
            'numeric_criteria_proposed_before_outputs':{
                'closed_values_types_ownership_lifecycle_authority':'exact; float bits checked for preserved state; no epsilon/native held snapping',
                'new_direction_or_ideal_normalization_absolute_component':'3e-6 for these bounded unit-direction cases; presentation-only engineering criterion, not universal libm theorem',
                'bounded_local_camera_or_follow_offset_absolute_m':'1e-4 for this <=32m arithmetic sequence; no physics/convergence change',
                'sixty_meter_look_ray_endpoint_absolute_m':'3e-4 if exercising actual Camera target; no calibrated sight-picture claim',
                'scalar_alpha_if_exposed_binary64_absolute':'2e-14; separate from Vector3 component rounding',
                'traditional_expression_regression':'same pinned engine before/after exact expression/order results, not relaxed to ideal-math tolerance',
                'ratification':'Root and independent reviewer must ratify criteria before consumer output; these targets do not establish actual execution/performance/readability.'
            },
            'defaults':{'settings':setting('cockpit','72','smooth'),'distance_m':binary(13),'look_angles':[binary(0),binary(0)]},
            'required_settings_variant_types':{'keys':'exact String','preset':'exact String','fov_deg':'FLOAT','external_response':'exact String'},
            'mappings':mappings,'basis_rows':{k:[vector(row) for row in rows] for k,rows in rotations.items()},'direction_cases':directions,
            'settings_positive_cases':valid_settings,'settings_negative_cases':rejected_settings,'copy_cases':copies,
            'lifecycle_initial_camera':initial,'valid_entry':valid_entry,'page_cases':page_cases,'entry_rejection_cases':reject_entries,'mapped_action_cases':actions,
            'filter_scalar_cases':filters,'filter_moving_sequence':sequence,'filter_branch_cases':branches,
            'authority_oracle':{
                'page_only_boundary':'Capture after existing ordinary pause/capture-retirement succeeds. No native wall advancement is introduced merely to test the page. Native readback copies are allowed for host admission; compare actual complete typed state, not arbitrary sentinel subset.',
                'exact_unchanged':['full native Readback incl session/tick/debt/held controls/aircraft/weather/engine/event/command history','native submit/step/lifecycle/open/close call counters','mapper preset/calibration/capture/generation/edge/rearm state','observed recording/status/samples','same-mode aid geometry/requested manual visibility'],
                'allowed_presentation_mutations':'Only validated settings/look-angle reset/follow-offset reseed and page draft/focus/lifecycle described per case.',
                'external_lifecycle_exclusion':'L11/L12/L14/L15 include external lifecycle changes; compare the callback/reset against immediately post-lifecycle authority. Never require successful restart or real pause/resume to equal a no-lifecycle native history.',
                'mapped_action_scope':'A cases begin after an existing action is admitted; physical Raw polling is not asserted nonexistent. Compare accepted-action effect to unchanged input/native authority with identical wall/lifecycle schedule.',
                'mode_change_exception':'Existing explicit traditional-mode visibility/layout effects permitted; same-mode new lookout/FOV/comfort do not add side effects. If an existing geometry condition requires pointer retirement, preserve ADR017 ordering; page baseline has no active capture.'
            },
            'legacy_source_constraints':['Keep Cockpit/Panel original gaze matrix multiplication and normalized base evaluation order unchanged.','Preserve original eye(-.27,.67,-.92),focus(-.08,.255,-1.535),near.1,Orbit floor and four-mode proof API.','No consumer, native/source/model/schema/Mapper/action or flight-aid policy implementation exists in this packet.'],
        }


def render():
    first=output(110)
    second=output(140)
    # Human display is the resulting binary64 repr; only immutable binary64
    # outputs are normative arithmetic references.
    def simplify(value):
        if isinstance(value,dict):
            if 'binary64_le' in value:
                return {'binary64_le':value['binary64_le'],'display_binary64':repr(struct.unpack('<d',bytes.fromhex(value['binary64_le']))[0])}
            return {key:simplify(item) for key,item in value.items()}
        if isinstance(value,list):return [simplify(item) for item in value]
        return value
    a,b=simplify(first),simplify(second)
    assert a==b,'Reference precision disagreement'
    return (json.dumps(a,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode('utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    raw=render();target=HERE/'expected-v1.json'
    if args.check:
        assert target.read_bytes()==raw,'Frozen reference regeneration mismatch'
    else:
        with target.open('xb') as stream:stream.write(raw)
    data=json.loads(raw)
    counts={key:len(value) for key,value in data.items() if key.endswith('_cases') or key in ['mappings','filter_moving_sequence']}
    print(json.dumps({'readonly':args.check,'expected_sha256':hashlib.sha256(raw).hexdigest(),'counts':counts,'consumer_execution':False}))
