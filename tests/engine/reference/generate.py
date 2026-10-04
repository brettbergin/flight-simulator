"""Original pre-solver equation references. Python stdlib only; no solver import."""
from decimal import Decimal as D, getcontext
from pathlib import Path
import argparse
import hashlib
import json

getcontext().prec = 80
PI = D('3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628')
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PACK = REPO / 'native/fdm_jsbsim/models/original-piston-prop'
XML_HASHES = {
    'aircraft/original-piston-prop/original-piston-prop.xml': 'b9a41861fcbca1917978312d73a192cbe2c2ea0e6ef0e13512c76148a6c9d4c5',
    'engine/original-piston.xml': '0d1b3eb87f1af2131a495c26ae7a3fb2fdd2a38d3d4309c67a77daaff2cf069e',
    'engine/original-fixed-prop.xml': 'b4f3f376f062d869a338bb2757466c9ba23d6320d895d3fc5921e351748bb0af',
}
FT_M = D('.3048')
LBF_N = D('4.4482216152605')
LB_KG = D('.45359237')
FTLBF_J = FT_M * LBF_N
CT = [(D(x), D(y)) for x, y in [('-1','.12'),('0','.12'),('1','0'),('2','-.06')]]
CP = [(D(x), D(y)) for x, y in [('-1','.06'),('0','.06'),('1','.04'),('2','.02')]]
COMB = [(D(x), D(y)) for x, y in [('0','0'),('.5','.8'),('1','.95'),('1.5','.75'),('2','.5')]]
MIX = [(D(x), D(y)) for x, y in [('0','0'),('.04','0'),('.06','.75'),('.08','1'),('.10','1'),('.12','.5'),('.16','0')]]


def lerp_table(table, key):
    """Independent piecewise-linear/clamped equation, not a runtime table call."""
    if key <= table[0][0]:
        return table[0][1]
    if key >= table[-1][0]:
        return table[-1][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x0 <= key <= x1:
            return y0 + (y1-y0)*(key-x0)/(x1-x0)
    raise ValueError('uncovered interval')


def strings(value):
    if isinstance(value, D):
        return str(value)
    if isinstance(value, dict):
        return {k: strings(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [strings(v) for v in value]
    return value


def prop_case(name, n, velocity, power, hz=120, q='0', r='0'):
    n, velocity, power, q, r = map(D, [n, velocity, power, q, r])
    diameter, inertia, rho = D(6), D(2), D(1)/400
    dt, omega = D(1)/hz, 2*PI*n
    # Two different thresholds: RPS>.01 for J, omega>.01 for excess torque.
    j = velocity/(n*diameter) if n > D('.01') else velocity/diameter
    ct, cp = lerp_table(CT, j), lerp_table(CP, j)
    thrust = ct*rho*n*n*diameter**4
    load = cp*rho*max(n, D('.01'))**3*diameter**5
    excess = (power-load)/(omega if omega>D('.01') else D(1))
    unclamped = omega + excess/inertia*dt
    after = max(D(0), unclamped)
    # version1.1 => Sense_multiplier=-1; Sense=+1; shaft/body axes aligned.
    hx = -inertia*omega
    return {'id': name, 'kind': 'prop-discrete',
            'input': {'rps': n, 'axial_velocity_fps': velocity,
                      'engine_power_ftlbf_per_s': power, 'density_slug_per_ft3': rho,
                      'hz': hz, 'pitch_rate_radps': q, 'yaw_rate_radps': r},
            'expected': {'advance_ratio': j, 'ct': ct, 'cp': cp,
                         'thrust_lbf': thrust, 'thrust_n': thrust*LBF_N,
                         'load_power_ftlbf_per_s': load, 'load_power_w': load*FTLBF_J,
                         'pre_omega_radps': omega, 'excess_torque_ftlbf': excess,
                         'post_omega_radps': after, 'post_rpm': after*60/(2*PI),
                         'body_torque_x_ftlbf': -power/max(D('.01'), omega),
                         'gyro_moment_y_ftlbf': r*hx, 'gyro_moment_z_ftlbf': -q*hx,
                         'unclamped_angular_impulse_residual': inertia*(unclamped-omega)-excess*dt,
                         'discrete_kinetic_energy_delta_ftlbf': inertia*(after*after-omega*omega)/2,
                         'rpm_clamp_active': unclamped<0,
                         'near_zero_advance_branch': n<=D('.01')}}


def piston_case(name, rpm, throttle, mixture, previous_map, ambient='101325', temperature='288', mags=3, starved=False):
    rpm, throttle, mixture, previous_map, ambient, temperature = map(D, [rpm, throttle, mixture, previous_map, ambient, temperature])
    displacement = D('91.125')*PI*(D('.0254')**3)
    mean_speed = rpm*D('4.5')/360
    z_throttle = D(100)/D('7.5')*(D('101320.73')/(D(8)*D('3386.38'))-1)-D('.2')
    ze = D(100)/mean_speed if mean_speed>0 else D(999999)
    target = ambient*ze/(ze+D('.2')+(1-throttle)**2*z_throttle)
    map_after = previous_map+(target-previous_map)/(120*D('.5'))
    mratio = min(D(8), ambient/map_after if map_after>=1 else D(8))
    ve_factor = D('.3')/D('1.3')+(D(8)-mratio)/(D('1.3')*7)
    airflow = displacement*(rpm/60)/2*D('.8')*ve_factor*map_after/(D('287.3')*temperature)
    phi = D('1.3')*mixture*D(101325)/ambient
    fuel_kgps = airflow*phi/D('14.7') if not starved else D(0)
    phi = phi if not starved else D(0)
    fuel_lbps = fuel_kgps*D('2.2046')
    ratio = fuel_kgps/airflow if airflow!=0 else None
    efficiency = lerp_table(MIX, ratio) if ratio is not None else None
    pmep = (map_after-ambient)*D('.8')
    fmep = -(D(18000)*mean_speed*FT_M+D(45000))
    indicated = fuel_lbps*3600/D('.4')*efficiency*(D(1) if mags==3 else D('.9'))-1 if efficiency is not None else None
    horsepower = indicated+(pmep+fmep)*displacement*rpm/(4*D(22371)) if indicated is not None else None
    return {'id': name, 'kind': 'piston-equations-running-branch',
            'input': {'rpm': rpm, 'throttle': throttle, 'mixture': mixture,
                      'previous_map_pa': previous_map, 'ambient_pa': ambient,
                      'temperature_k': temperature, 'magnetos': mags, 'starved': starved},
            'expected': {'map_target_pa': target, 'map_post_pa': map_after,
                         'mean_piston_speed_fps': mean_speed, 'airflow_kgps': airflow,
                         'equivalence_ratio': phi, 'fuel_flow_backend_lbps': fuel_lbps,
                         'fuel_flow_public_kgps': fuel_lbps*LB_KG,
                         'mixture_efficiency': efficiency, 'pmep_pa': pmep,
                         'friction_mean_effective_pressure_pa': fmep, 'indicated_hp': indicated,
                         'shaft_power_hp': horsepower,
                         'shaft_power_w': horsepower*550*FTLBF_J if horsepower is not None else None,
                         'indicated_cutoff_running_false': indicated<D('.125') if indicated is not None else None}}


def packet(model_pack=PACK):
    cases = []
    for key in ['-2','-1','-.5','0','.5','1','1.5','2','3']:
        x=D(key);cases.append({'id':'ctcp_'+key,'kind':'table','input':{'key':x},'expected':{'ct':lerp_table(CT,x),'cp':lerp_table(CP,x)}})
    for key in ['-.1','0','.25','.75','1.25','1.75','3']:
        x=D(key);cases.append({'id':'comb_'+key,'kind':'combustion-table','input':{'phi':x},'expected':{'efficiency':lerp_table(COMB,x)}})
    for key in ['-.01','0','.05','.07','.1','.14','.2']:
        x=D(key);cases.append({'id':'mix_'+key,'kind':'mixture-table','input':{'fuel_air_mass_ratio':x},'expected':{'efficiency':lerp_table(MIX,x)}})
    for args in [('static40','40','0','82500'),('j_half','40','120','82500'),('j_one','40','240','0'),('reverse_flow','40','-240','82500'),('j_end_clamp','40','960','0'),('stopped','0','0','0'),('low_omega_floor','.001','6','1'),('low_rps_floor','.005','6','1'),('rps_boundary','.01','6','1'),('rps_above','.0101','6','1')]:
        cases.append(prop_case(*args))
    for hz in [60,120,240]:
        cases.append(prop_case('gyro_step_'+str(hz),'40','120','82500',hz,q='.1',r='.2'))
    cases.extend([piston_case('running_both','1200','.5','.8','70000'),piston_case('running_left','1200','.5','.8','70000',mags=1),piston_case('mixture_cutoff','1200','.5','0','70000'),piston_case('starved_flow','1200','.5','1','70000',starved=True)])
    for rpm in ['0','600','1200','1500']:
        n=D(rpm);torque=D(60)*max(D(0),1-n/1200);hp=torque*max(n,D(1))/D(5252)
        cases.append({'id':'starter_'+rpm,'kind':'starter-cranking-only','input':{'rpm':n},'expected':{'starter_torque_ftlbf':torque,'indicated_hp':hp,'engine_power_ftlbf_per_s':hp*550}})
    for running, rpm, spark, previous_flow in [(False,479,True,True),(False,480,True,True),(False,481,True,True),(True,480,True,True),(True,479,True,True),(True,1200,False,True),(True,1200,True,False)]:
        after=(spark and previous_flow and rpm>=480) if running else (spark and previous_flow and rpm>480)
        cases.append({'id':'startup_'+str(len(cases)),'kind':'startup-before-current-flow',
                      'input':{'was_running':running,'rpm':rpm,'spark':spark,'previous_fuel_flow_positive':previous_flow},'expected':{'after_startup_running':after}})
    for old,requested in [('10','.001'),('.0001','.001'),('0','.001')]:
        old,requested=map(D,[old,requested]);actual=min(old,requested)
        cases.append({'id':'tank_'+str(len(cases)),'kind':'single-tank-zero-unusable-drain','input':{'contents_lbs':old,'requested_lbs':requested},'expected':{'post_contents_lbs':old-actual,'actual_drained_lbs':actual,'actual_drained_kg':actual*LB_KG,'requested_minus_supplied_lbs':requested-actual,'same_tick_massbalance_fuel_lbs':old}})
    cases.append({'id':'explicit_units_geometry','kind':'units-and-geometry','expected':{
        'bore4_5_stroke4_5_four_cylinder_displacement_in3':D('91.125')*PI,
        'displacement_m3':D('91.125')*PI*D('.0254')**3,
        'diameter_m':D(6)*FT_M,'physical_ixx_kgm2':D(2)*FTLBF_J,
        'xml_loader_ixx_kgm2_if_converted':D(2)*D('1.35594'),
        'engine150_hp_w':D(150)*550*FTLBF_J,'loader_kg_to_lbs_100':D(100)/LB_KG,
        'piston_flow_kg_lbs_boundary_product':D('2.2046')*LB_KG,
        'engine_psf_to_pa_coefficient':D('47.88'),'publication_psf_to_pa_coefficient':D('47.8802589803358'),
        'single_mag_spark_factor':D('.9'),'table_cp_no_negative_airdriven_branch':True}})
    bindings=[]
    for rel in ['aircraft/original-piston-prop/original-piston-prop.xml','engine/original-piston.xml','engine/original-fixed-prop.xml','parameter-ledger.json','inventory.json']:
        b=(model_pack/rel).read_bytes();sha=hashlib.sha256(b).hexdigest()
        if rel in XML_HASHES and sha!=XML_HASHES[rel]:
            raise ValueError('Frozen authored XML changed; new reviewed equation/reference version required: '+rel)
        bindings.append({'path':rel,'bytes':len(b),'sha256':sha})
    return strings({'format':'original-piston-pre-solver-reference-v1','status':'candidate; root independent review required before solver consumption',
        'method':'80-digit Decimal analytic equations and clamped piecewise-linear rational tables; no model output, solver import or numerical fitting',
        'model_binding':bindings,'decimal_precision':80,'pi':PI,'case_count':len(cases),'cases':cases,
        'budgets_before_observation':{'coefficient':{'abs':'2e-12','rel':'2e-12'},'scalar':{'abs':'1e-9','rel':'1e-10'},'force_n':{'abs':'1e-7','rel':'1e-10'},'power_w':{'abs':'1e-6','rel':'1e-10'},'angular_radps':{'abs':'1e-9','rel':'1e-10'},'bool_identity_order':'exact'},
        'scope':'Generic authored branch equations, units and discrete stage checks. Not C172 calibration, model dynamics, cold-start success, continuum energy conservation or phase acceptance.'})


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--model-pack',type=Path,default=PACK);parser.add_argument('--output',type=Path,default=HERE/'expected-v2.json');args=parser.parse_args()
    result=packet(args.model_pack)
    b=(json.dumps(result,indent=2)+'\n').encode('utf-8');output=args.output
    if args.check:
        if output.read_bytes()!=b:raise SystemExit('independent reference/model binding drift')
    else:
        if output.exists():raise SystemExit('preserve frozen output; use --check or a new version')
        output.write_bytes(b)
    print(json.dumps({'path':str(output),'sha256':hashlib.sha256(b).hexdigest(),'cases':result['case_count'],'model_or_solver_executed':False}))
