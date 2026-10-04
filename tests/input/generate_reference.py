"""Pre-consumer ADR008 analytic reference cases promoted for actual consumer tests. No Godot/native/application imports."""
from fractions import Fraction as F
from pathlib import Path
import hashlib, json

HERE = Path(__file__).resolve().parent
CONTRACT = HERE.parents[1] / 'docs/decisions/008-input-presets.md'
CASES = []
def exact(value):
    q = value if isinstance(value, F) else F(str(value))
    return {'rational': str(q), 'decimal_approximation': float(q)}
def case(name, kind, inputs, expected, rationale):
    CASES.append({'id': name, 'kind': kind, 'input': inputs, 'expected': expected, 'basis': rationale})
def axis(name, inputs, value, rationale):
    case(name, 'analytic_mapping', inputs, {'mapped': exact(value)}, rationale)

# Closed-form calibrated side ratios, selected away from floating-point boundaries.
cal = {'minimum':'-0.8','center':'0.1','maximum':'0.9','deadzone':'0','saturation':'1','gain':'1','slew_per_s':'0'}
axis('centered_asymmetric_left', dict(cal, raw='-0.35'), -F(45,90), '(-.35-.1)/(.1-(-.8)) = -1/2')
axis('centered_asymmetric_right', dict(cal, raw='0.5'), F(40,80), '(.5-.1)/(.9-.1) = 1/2')
axis('centered_inverted_right', dict(cal, raw='0.5', invert=True), -F(1,2), 'Inversion reverses the calibrated signed half-throw.')
axis('centered_noise_deadzone', {'normalized':'0.05','deadzone':'0.1','saturation':'0.8'}, 0, 'Magnitude below deadzone contributes zero.')
axis('centered_deadzone_half', {'normalized':'0.45','deadzone':'0.1','saturation':'0.8'}, F(35,70), '(.45-.1)/(.8-.1) = 1/2')
axis('centered_saturated_gain', {'normalized':'0.9','deadzone':'0.1','saturation':'0.8','gain':'0.35'}, F(35,100), 'Saturated unit throw multiplied by explicit gain .35.')
axis('unsigned_asymmetric_quarter', {'minimum':'-0.7','maximum':'0.9','raw':'-0.3'}, F(4,16), '(-.3-(-.7))/(.9-(-.7)) = 1/4')
axis('unsigned_inverted_quarter', {'minimum':'-0.7','maximum':'0.9','raw':'-0.3','invert':True}, F(3,4), 'Unsigned inversion is 1 - calibrated fraction.')
case('separate_unsigned_pedals', 'analytic_mapping', {'left_raw':'-0.3','right_raw':'0.5','minimum':'-0.7','maximum':'0.9','latch':False}, {'left_brake':exact(F(1,4)), 'right_brake':exact(F(3,4))}, 'Each pedal has its own ratio; neither pedal substitutes for the other.')
axis('analog_wall_slew_bound', {'target':'1','held':'0','slew_per_s':'0.8','elapsed_us':250000}, F(1,5), 'The bounded displacement is .8 * 1/4 = 1/5.')
axis('centered_negative_endpoint', dict(cal, raw='-0.8'), -1, 'Calibrated minimum reaches exactly -1 despite asymmetric spans.')

case('throttle_aliases_count_once', 'digital_slew', {'positive_pressed':['W','PageUp'],'rate':'0.25','held':'0.4','elapsed_us':200000}, {'throttle':exact(F(9,20))}, 'ANY alias gives one sign: .4 + .25 * .2 = .45.')
case('opposite_aliases_cancel', 'digital_slew', {'positive_pressed':['W','PageUp'],'negative_pressed':['S'],'held':'0.4','elapsed_us':200000}, {'throttle':exact(F(2,5))}, 'Both sides pressed yield digital sign zero.')
case('legacy_roll_start_bias', 'digital_slew', {'start_roll':'0.1','held_roll':'0.1','digital_sign':1,'gain':'0.35','rate':'0.9','elapsed_us':250000}, {'target':exact(F(9,20)),'roll':exact(F(13,40))}, 'Target .45; maximum quarter-second movement .225 gives .325.')
case('legacy_yaw_return_start', 'digital_slew', {'start_yaw':'-0.1','held_yaw':'0.15','digital_sign':0,'gain':'0.25','rate':'0.9','elapsed_us':250000,'return_to_start':True}, {'yaw':exact(-F(3,40))}, 'Move .225 toward -.1 from .15, yielding -.075, without overshoot.')
case('legacy_pitch_target_clamp', 'digital_slew', {'start_pitch':'0.95','held_pitch':'0.95','digital_sign':1,'gain':'0.15','rate':'0.9','elapsed_us':250000}, {'target':exact(1),'pitch':exact(1)}, 'Target 1.10 clamps to 1; movement stops at target, not at 1.175.')
case('throttle_negative_rate', 'digital_slew', {'held':'0.4','digital_sign':-1,'rate':'0.25','elapsed_us':120000}, {'throttle':exact(F(37,100))}, '.4 - .25 * .12 = .37.')
case('trim_positive_rate', 'digital_slew', {'held':'-0.02','digital_sign':1,'rate':'0.08','elapsed_us':250000}, {'trim':exact(0)}, '-.02 + .08 * .25 = 0.')
case('unsigned_release_holds', 'digital_slew', {'held_throttle':'0.37','held_trim':'-0.12','digital_sign':0,'elapsed_us':250000}, {'throttle':exact(F(37,100)),'trim':exact(-F(3,25))}, 'Unsigned throttle and signed trim position hold when the rate keys are released.')

case('first_ground_hold_seed', 'latch_transition', {'first_successful_configure':True,'start_brakes':['0.8','0.8'],'held_brakes':['0.8','0.8']}, {'brake_hold':True}, 'Both accepted start brakes exceed .5; only first successful configure seeds latch.')
case('first_airborne_hold_false', 'latch_transition', {'first_successful_configure':True,'start_brakes':['0','0'],'held_brakes':['0','0']}, {'brake_hold':False}, 'Fresh airborne session does not inherit the prior session latch.')
case('later_apply_preserves_false', 'latch_transition', {'first_successful_configure':False,'brake_hold_before':False,'start_brakes':['0.8','0.8'],'held_brakes':['1','1'],'momentary_both_brakes':True}, {'brake_hold':False}, 'Apply cannot infer a latch from held momentary Space/pedals or reseed from start.')
case('B_edge_one_toggle', 'latch_transition', {'brake_hold_before':True,'B_samples':[False,True,True,False,True]}, {'brake_hold_after_each':[True,False,False,False,True]}, 'Each rising edge toggles once; held key or OS repeat does not toggle again.')
case('held_overrides_return_primary', 'latch_transition', {'brake_hold':False,'primary_brakes':['0.25','0.75'],'left_full_samples':[True,False]}, {'brakes_after_each':[['1','0.75'],['0.25','0.75']]}, 'Declared left-full override affects only left; release returns to the pedal values.')
case('suspend_preserves_hold', 'latch_transition', {'brake_hold_before':True,'suspend_held_brakes':['0.2','0.4'],'resume_buttons_released':True}, {'brake_hold':True,'first_live_brakes':['1','1']}, 'Suspend/resume preserves latch even if copied held values differ; live override stays visible.')

case('suspended_diagnostics_only', 'mode_transition', {'suspended':True,'elapsed_us':0,'held_axes_marker':'H','pressed':['W','B','view_cycle'],'wheel_pulse':True}, {'ok':True,'axes_marker':'H','actions':[],'takeover':[],'filter_unchanged':True,'latch_unchanged':True}, 'Suspended sample diagnostics do not integrate, toggle, or dispatch; copied held axes only.')
case('suspended_elapsed_rejects', 'mode_transition', {'suspended':True,'elapsed_us':1}, {'ok':False,'axes':None,'actions':[],'takeover':[],'mode':'suspended','filter_unchanged':True,'latch_unchanged':True}, 'Nonzero suspended elapsed is not clamped or integrated.')
case('resume_unmatched_absolute_allowed', 'mode_transition', {'generation_matches':True,'observed_indices_present':True,'centered_neutral':'0','persistent_released':True,'held_throttle':'0.6','mapped_throttle':'0.1'}, {'resume_ok':True,'native_resume_is_separate':True,'next_throttle':exact(F(3,5)),'takeover':['throttle']}, 'Absolute mismatch does not forbid explicit resume, but must retain held axis until takeover.')
case('resume_pressed_flight_key_blocks', 'mode_transition', {'generation_matches':True,'centered_neutral':'0','persistent_pressed':['W'],'initiating_resume_key_pressed':True}, {'resume_ok':False,'mode':'suspended'}, 'An initiating UI key is exempt, but a persistent throttle contributor W is not.')
case('resume_centered_not_neutral', 'mode_transition', {'generation_matches':True,'calibrated_centered':'0.06','persistent_released':True}, {'resume_ok':False,'mode':'suspended'}, 'Centered magnitude .06 exceeds the .05 neutral requirement, before any aircraft motion.')
case('active_source_removed', 'mode_transition', {'selected_slot':'pedals','pinned_generation':9,'observed_devices':[]}, {'ok':False,'axes':None,'actions':[],'takeover':[],'controller_pause_before_next_tick':True,'no_neutral_guess':True}, 'Missing active source invalidates admission; controller pause/solver sequencing needs an actual facade fixture later.')
case('slot_reused_generation_changed', 'mode_transition', {'selected_slot':'pedals','pinned_generation':9,'raw_generation':10,'axis_value':'0'}, {'ok':False,'axes':None,'actions':[],'takeover':[],'explicit_reselection_required':True}, 'Numeric slot/control reuse with a new generation cannot silently regain authority.')
case('bound_axis_unobserved', 'mode_transition', {'bound_axis_index':2,'raw_observed_axis_indices':[0,1],'generation_matches':True}, {'configure_or_resume_ok':False,'no_fabricated_zero':True}, 'Absent sparse entry is unavailable even if the physical axis might exist.')
case('idle_rearms_takeover', 'mode_transition', {'held_throttle':'0.6','mapped_absolute_throttle':'0.6','idle_rising_edge':True,'later_unmoved_lever':'0.6'}, {'idle_throttle':exact(0),'later_throttle':exact(0),'later_takeover':['throttle']}, 'Idle sets zero and rearms takeover; an unmoved absolute lever cannot restore power.')
case('takeover_matches_then_follows', 'mode_transition', {'held_throttle':'0.6','mapped_throttle_samples':['0.1','0.58','0.7'],'slew_per_s':'0'}, {'throttle_after_each':['0.6','0.58','0.7'],'takeover_after_each':[['throttle'],[],[]]}, '.58 is within .03 of .6; direct mapping becomes active only at the match.')
case('resume_primes_ui_edges_no_wheel_leak', 'mode_transition', {'suspended':True,'paused_wheel_presses':[4,4],'resume_key_held':True,'persistent_flight_buttons_released':True}, {'resume_ok':True,'next_actions':[],'wheel_pulses_coalesced_then_consumed':True,'held_UI_edge_primed':True}, 'Paused wheel pulses cannot leak into flight; held initiating UI input cannot fire a second edge.')
case('invalid_calibration_atomic', 'configuration_rejection', {'centered_minimum':'0','center':'0.04','maximum':'1','previous_active_marker':'A'}, {'ok':False,'previous_active_marker':'A','filter_unchanged':True}, 'Centered left span .04 is smaller than the minimum .05; invalid configure must remain atomic.')
case('runtime_mixture_rejected', 'configuration_rejection', {'mixture_kind':'joy_axis','previous_active_marker':'A'}, {'ok':False,'previous_active_marker':'A','runtime_mixture':'fixed1'}, 'Runtime mixture is fixed1; unsigned analytic kernels never qualify independent mixture hardware.')

assert 20 <= len(CASES) <= 40
payload = {
 'schema_version':1,
 'classification':'PRIVATE_PRE_CONSUMER_ANALYTIC_REFERENCE_NOT_EXECUTED_DEVICE_EVIDENCE',
 'contract_commit':'ff1909c651e5f8f4d3bb8a52cf75bda48a135fbb',
 'contract_path':'docs/decisions/008-input-presets.md',
 'contract_normalized_lf_sha256':hashlib.sha256(CONTRACT.read_bytes().replace(b'\r\n',b'\n')).hexdigest(),
 'sample_result_exact_keys':['ok','error','axes','actions','takeover','brake_hold'],
 'notes':['Key names are symbolic reference aliases; consumers bind actual pinned backend enums.','Expected numbers are exact decimal-rational algebra, not copied mapper code. Decimal approximations are explanatory only.','Mode/latch cases are declarative contract transitions, not mock execution or native pause evidence.','Takeover matches .58 to .6 away from the .03 boundary; neutral rejection .06 is away from .05.','Frame-rate polling equivalence is not promised: compare explicit elapsed samples and actual admitted commands.'],
 'case_count':len(CASES), 'cases':CASES
}
HERE.mkdir(parents=True,exist_ok=True)
(HERE/'reference.json').write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'case_count':len(CASES),'reference_sha256':hashlib.sha256((HERE/'reference.json').read_bytes()).hexdigest(),'contract_lf_sha256':payload['contract_normalized_lf_sha256']}))
