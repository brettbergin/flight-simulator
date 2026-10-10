extends RefCounted
# Original MIT. ADR017 real-mapper fixtures over synthetic complete Raw only.
# No facade, native engine, physical hardware, GUI or preset mutation authority.
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok: failures.append(label)
static func axes()->Dictionary:
 return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":0.0,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
static func systems()->Dictionary:
 return {"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true}
static func raw(keys:Array=[],buttons:Array=[],devices:Array=[])->Dictionary:
 return {"keys":keys.duplicate(true),"mouse_buttons":buttons.duplicate(),"devices":devices.duplicate(true)}
func state(m:RefCounted)->Dictionary:
 return {"preset":m._preset.duplicate(true),"values":m._values.duplicate(true),"start":m._start.duplicate(true),"pins":m._pins.duplicate(true),"edges":m._edges.duplicate(true),"takeover":m._takeover.duplicate(true),"configured":m._configured,"live":m._live,"brake":m._brake_hold,"v2":m._v2,"held":m._held_systems.duplicate(true),"systems":m._system_intents.duplicate(true),"system_edges":m._system_edges.duplicate(true),"view":m.pointer_view(),"begin":m._pointer_begin.duplicate(true),"terminal":m._pointer_terminal.duplicate(true),"pending":m._pointer_pending.duplicate(true),"disabled":m._pointer_disabled}
func fresh(preset:Dictionary={},initial:Dictionary={},held:Dictionary={})->RefCounted:
 var m=Mapper.new()
 if preset.is_empty():preset=Mapper.default_preset_v2()
 if initial.is_empty():initial=raw()
 if held.is_empty():held=axes()
 check(m.configure_v2(preset,held,held,initial,Preset.PISTON_PROFILE,systems()).ok,"fixture_configured")
 check(m.bind_pointer_session("pointer-fixture-1").ok,"fixture_bound_suspended")
 check(m.resume_confirmed(initial).ok,"fixture_released_resume")
 return m
static func gesture(m:RefCounted,control:String="throttle",phase:String="begin",value:Variant=0.5)->Dictionary:
 var v:Dictionary=m.pointer_view()
 return {"session_id":v.session_id,"generation":v.generation,"token":v.last_token+1 if phase=="begin" else v.last_token,"control":control,"phase":phase,"button":1,"value":value}
func reject_sample(m:RefCounted,input:Dictionary,label:String)->void:
 var before:Dictionary=state(m)
 var result:Dictionary=m.sample(input,100000)
 check(not result.ok and result.axes==null and result.systems==null and result.actions.is_empty() and result.takeover.is_empty() and result.size()==7,label+"_failure_shape")
 check(state(m)==before,label+"_complete_atomic_state")
func reject_queue(m:RefCounted,g:Dictionary,label:String)->void:
 var before:Dictionary=state(m)
 check(not m.queue_pointer(g).ok,label+"_rejected")
 check(state(m)==before,label+"_complete_atomic_state")
func run()->Dictionary:
 var empty=Mapper.new()
 var view:Dictionary=empty.pointer_view()
 check(view.size()==8 and view.session_id==null and view.capture==null and view.requested_axes==null and view.requested_systems==null and view.rearm_buttons.is_empty(),"empty_closed_view")
 var m:RefCounted=fresh()
 check(m.pointer_view().error.is_empty(),"ordinary_bind_resume_pointer_ready")
 var preset_bytes:PackedByteArray=Preset.encode_v2(m._preset).value
 var begin:Dictionary=gesture(m)
 check(m.queue_pointer(begin).ok,"lever_begin")
 check(m.pointer_view().capture=={"token":begin.token,"control":"throttle","button":1} and m.pointer_view().last_token==begin.token,"queued_capture_token_reservation")
 check(m.pointer_view().requested_axes.throttle==0.0,"queue_not_sampled_intent")
 var before:Dictionary=state(m)
 check(m.queue_pointer(begin.duplicate(true)).ok and state(m)==before,"exact_duplicate_begin_inert")
 begin.value=0.9
 check(m._pointer_begin.value==0.5,"queue_owned_copy")
 var moved:Dictionary=gesture(m,"throttle","move",0.6)
 for i in 40:check(m.queue_pointer(moved).ok,"move_coalesces_"+str(i))
 check(m._pointer_pending.size()==2,"move_queue_bounded")
 var sample:Dictionary=m.sample(raw([], [1]),100000)
 check(sample.ok and sample.axes.throttle==0.6 and sample.systems==systems(),"lever_sampled_exact_float")
 view=m.pointer_view();view.requested_axes.throttle=0.1;view.capture.control="mixture";view.rearm_buttons.clear()
 check(m._values.throttle==0.6 and m.pointer_view().capture.control=="throttle" and m.pointer_view().rearm_buttons==[1],"view_owned_copies")
 reject_sample(m,raw([KEY_W,KEY_S],[1]),"opposing_aliases_not_net_zero")
 reject_sample(m,raw([KEY_X,KEY_B],[1]),"idle_before_any_brake_latch_or_edge")
 reject_sample(m,raw([], [1,2]),"mouse_look_conflict")
 var bad_raw:Dictionary=raw([KEY_B],[1]);bad_raw.devices=[{}]
 reject_sample(m,bad_raw,"malformed_full_raw")
 var ended:Dictionary=gesture(m,"throttle","end",0.7)
 check(m.queue_pointer(ended).ok,"lever_final_queued")
 before=state(m);check(m.queue_pointer(ended).ok and state(m)==before,"exact_duplicate_terminal_inert_pending")
 sample=m.sample(raw(),100000)
 check(sample.axes.throttle==0.7 and m.pointer_view().capture==null and m.pointer_view().rearm_buttons.is_empty(),"release_final_before_ownership_return")
 before=state(m);check(m.queue_pointer(ended).ok and state(m)==before,"exact_duplicate_terminal_inert_consumed")
 sample=m.sample(raw([KEY_W]),100000)
 check(absf(sample.axes.throttle-0.725)<1e-12,"future_only_digital_elapsed")
 check(Preset.encode_v2(m._preset).value==preset_bytes,"preset_exact_bytes_unchanged")
 # Same-interval opposite switch requests reject the entire ordinary sample.
 m=fresh();check(m.queue_pointer(gesture(m,"engine.ignition_left","begin",false)).ok,"switch_false_staged")
 reject_sample(m,raw([KEY_F8,KEY_PERIOD,KEY_B],[1]),"opposite_desired_bool")
 m=fresh();check(m.queue_pointer(gesture(m,"engine.ignition_left","begin",true)).ok,"switch_true_staged")
 sample=m.sample(raw([KEY_F8,KEY_F9,KEY_PERIOD],[1]),100000)
 check(sample.ok and sample.systems["engine.ignition_left"] and sample.systems["engine.ignition_right"] and absf(sample.axes.mixture-0.025)<1e-12,"agreeing_switch_coalesces_independent_controls")
 sample=m.sample(raw([KEY_F8],[1]),100000)
 check(sample.systems["engine.ignition_left"],"held_toggle_not_second_toggle")
 check(m.queue_pointer(gesture(m,"engine.ignition_left","end",null)).ok,"switch_end_null")
 check(m.sample(raw(),0).systems["engine.ignition_left"],"switch_end_retains_desired")
 # Cancel drops only unsampled changes, retaining already committed intent.
 m=fresh();m.queue_pointer(gesture(m,"mixture","begin",0.8));m.queue_pointer(gesture(m,"mixture","cancel",null))
 check(m.sample(raw(),100000).axes.mixture==0.0,"cancel_unsampled_lever")
 m.queue_pointer(gesture(m,"mixture","begin",0.4));m.sample(raw([], [1]),0)
 m.queue_pointer(gesture(m,"mixture","move",0.9));m.queue_pointer(gesture(m,"mixture","cancel",null))
 check(m.sample(raw(),0).axes.mixture==0.4,"cancel_retains_sampled_lever")
 m=fresh();m.queue_pointer(gesture(m,"fuel.feed","begin",false));m.queue_pointer(gesture(m,"fuel.feed","cancel",null))
 check(m.sample(raw(),0).systems["fuel.feed"],"cancel_unsampled_switch")
 # Starter never toggles; down/up before boundary is legitimately no true pulse.
 m=fresh();m.queue_pointer(gesture(m,"engine.starter","begin",true));m.queue_pointer(gesture(m,"engine.starter","end",false))
 check(not m.sample(raw(),100000).systems["engine.starter"],"starter_down_up_no_hidden_pulse")
 m.queue_pointer(gesture(m,"engine.starter","begin",true))
 check(m.sample(raw([], [1]),0).systems["engine.starter"],"starter_held_true")
 reject_sample(m,raw([KEY_F12],[1]),"physical_starter_overlap")
 var old_end:Dictionary=gesture(m,"engine.starter","end",false)
 var actual:Dictionary=systems();actual["engine.starter"]=true
 check(m.suspend_v2("pause",axes(),actual).ok,"pause_invalidates_capture")
 check(m.sample(raw([], [1]),0).systems["engine.starter"] and not m.pointer_view().requested_systems["engine.starter"],"paused_actual_true_requested_false")
 before=state(m);check(not m.resume_confirmed(raw([], [1])).ok,"held_pointer_resume_denied")
 check(m.sample(raw(),0).ok and m.pointer_view().rearm_buttons.is_empty(),"complete_suspended_raw_observes_release")
 check(m.resume_confirmed(raw()).ok and not m.sample(raw(),0).systems["engine.starter"],"released_resume_starter_false")
 m.queue_pointer(gesture(m,"engine.starter","begin",true));before=state(m)
 check(m.queue_pointer(old_end).ok and state(m)==before,"old_generation_end_cannot_retire_new_starter")
 var other:Dictionary=old_end.duplicate(true);other.session_id="other-valid-1";other.generation=2147483647;other.token=2147483647
 before=state(m);check(m.queue_pointer(other).ok and state(m)==before,"other_session_terminal_obsolete_before_counters")
 var future:Dictionary=gesture(m,"engine.starter","end",false);future.generation+=1;future.token=1
 reject_queue(m,future,"future_generation_not_old_token_noop")
 # Every lifecycle invalidation latches release; repeated suspended diagnostics do not consume generations.
 for reason in ["focus","modal","widget retirement","reset","profile","fault"]:
  m=fresh();m.queue_pointer(gesture(m,"engine.starter","begin",true));m.sample(raw([], [1]),0)
  m.invalidate_pointer(reason);var generation:int=m.pointer_view().generation
  check(m.pointer_view().error.is_empty(),reason+"_normal_invalidation_not_fault")
  check(m.pointer_view().capture==null and m.pointer_view().rearm_buttons==[1],reason+"_capture_retired_latched")
  reject_queue(m,gesture(m,"engine.starter","begin",true),reason+"_held_cannot_reenter")
  m.suspend_v2(reason,axes(),actual);generation=m.pointer_view().generation
  m.sample(raw([], [1]),0);m.sample(raw([], [1]),0);m.suspend_v2(reason,axes(),actual)
  check(m.pointer_view().generation==generation,reason+"_idle_no_generation_churn")
  check(m.sample(raw(),0).ok and m.resume_confirmed(raw()).ok,reason+"_observed_release_fresh_resume")
 # Invalid closed shapes cannot exploit obsolete-terminal handling.
 m=fresh();var mutations:Array=[];var g:Dictionary=gesture(m)
 var bad:Dictionary=g.duplicate(true);bad.extra=0;mutations.append(bad)
 for key in ["generation","token","button"]:
  bad=g.duplicate(true);bad[key]=true;mutations.append(bad)
 for value in [0, true, NAN, INF, -INF, -0.01, 1.01]:
  bad=g.duplicate(true);bad.value=value;mutations.append(bad)
 for key in ["session_id","control","phase"]:
  bad=g.duplicate(true);bad[key]=StringName(g[key]);mutations.append(bad)
 for value in ["", "BAD", "a--b", "a/"]:
  bad=g.duplicate(true);bad.session_id=value;mutations.append(bad)
 bad=g.duplicate(true);bad.button=4;mutations.append(bad)
 bad=g.duplicate(true);bad.phase="move";mutations.append(bad)
 bad=g.duplicate(true);bad.token=2;mutations.append(bad)
 bad=g.duplicate(true);bad.generation+=1;mutations.append(bad)
 bad=g.duplicate(true);bad.session_id="other-valid";mutations.append(bad)
 bad=g.duplicate(true);bad.phase="cancel";bad.value=false;bad.session_id="old-valid";mutations.append(bad)
 for i in mutations.size():reject_queue(m,mutations[i],"closed_mutant_"+str(i))
 for control in ["engine.ignition_left","engine.ignition_right","fuel.feed","engine.starter"]:
  bad=gesture(m,control,"move",true);reject_queue(m,bad,"switch_starter_move_"+control)
 # Full preset button authority, including controls not currently being moved.
 for id in ["look_hold","both_brakes","idle","view_cycle"]:
  var p:Dictionary=Mapper.default_preset_v2()
  for action in p.actions:
   if action.id==id:action.sources=[{"kind":"mouse_button","button":1}]
  var bound:RefCounted=fresh(p)
  reject_queue(bound,gesture(bound),"bound_button_"+id)
 var fixed:Dictionary=Mapper.default_preset_v2()
 for i in fixed.axes.size():
  if fixed.axes[i].target=="mixture":fixed.axes[i]={"target":"mixture","kind":"fixed","value":0.2}
 m=fresh(fixed);reject_queue(m,gesture(m,"mixture"),"fixed_disabled")
 # Reversed joy takeover uses mapped values and only the released target is rearmed.
 var p:Dictionary=Mapper.default_preset_v2()
 p.devices=[{"slot":"lever","label":"Synthetic lever","match":{"guid":"fixture","name":"fixture","vendor_id":"","product_id":""}}]
 for i in p.axes.size():
  if p.axes[i].target in ["throttle","mixture"]:
   p.axes[i]={"target":p.axes[i].target,"kind":"joy_axis","slot":"lever","index":0 if p.axes[i].target=="throttle" else 1,"range":"unsigned","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":true,"deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
 var device:Dictionary={"slot":"lever","generation":7,"axes":[{"index":0,"value":1.0},{"index":1,"value":1.0}],"buttons":[]}
 for distance in [0.029,0.03,0.031]:
  m=fresh(p,raw([],[],[device]));m.sample(raw([],[],[device]),0)
  check(not m._takeover.throttle and not m._takeover.mixture,"joy_initial_owned")
  m.queue_pointer(gesture(m,"throttle","begin",0.0));device.axes[0].value=-1.0
  check(m.sample(raw([], [1],[device]),100000).axes.throttle==0.0,"joy_influence_suspended")
  var absent:Dictionary=device.duplicate(true);absent.axes.pop_back()
  reject_sample(m,raw([KEY_B],[1],[absent]),"unowned_axis_unobserved_drag")
  var changed:Dictionary=device.duplicate(true);changed.generation=8
  reject_sample(m,raw([], [1],[changed]),"device_generation_drag")
  reject_sample(m,raw([], [1]),"device_disconnect_drag")
  m.queue_pointer(gesture(m,"throttle","end",0.0));m.sample(raw([],[],[device]),100000)
  check(m._takeover.throttle and not m._takeover.mixture,"only_released_target_rearmed")
  # This construction is the mapper's actual reversed mapped value; the .03 comparator is unchanged.
  device.axes[0].value=1.0-2.0*distance
  var mapped:float=Mapper._command_axis(p.axes.filter(func(a:Dictionary):return a.target=="throttle")[0],device.axes[0].value)
  sample=m.sample(raw([],[],[device]),100000)
  check(m._takeover.throttle==(mapped>0.03) and sample.axes.throttle==(0.0 if mapped>0.03 else mapped),"joy_mapped_threshold_"+str(distance))
  device.axes[0].value=1.0
 # Exact threshold fixture: reversed source maps .9375 to .03125 exactly.
 # Independent requested values give below/equal/above .03, including equality.
 for pair in [[0.00225,false],[0.00125,false],[0.00025,true]]:
  device.axes[0].value=1.0
  m=fresh(p,raw([],[],[device]));m.sample(raw([],[],[device]),0)
  m.queue_pointer(gesture(m,"throttle","begin",float(pair[0])));m.queue_pointer(gesture(m,"throttle","end",float(pair[0])))
  device.axes[0].value=0.9375
  m.sample(raw([],[],[device]),0)
  check(m._takeover.throttle and not m._takeover.mixture,"exact_threshold_release_armed")
  if pair[0]==0.00125:check(0.03125-float(pair[0])==0.03,"threshold_fixture_exact_binary64_difference")
  sample=m.sample(raw([],[],[device]),0)
  check(m._takeover.throttle==pair[1] and sample.axes.throttle==(float(pair[0]) if pair[1] else 0.03125),"reversed_exact_threshold_"+str(pair[0]))
 # Same-session Apply retains release latches and invalidates old UI generations.
 m=fresh();m.queue_pointer(gesture(m,"engine.starter","begin",true));m.sample(raw([], [1]),0)
 old_end=gesture(m,"engine.starter","end",false)
 check(m.configure_v2(Mapper.default_preset_v2(),axes(),axes(),raw([], [1]),Preset.PISTON_PROFILE,actual).ok,"same_session_apply")
 check(m.bind_pointer_session("pointer-fixture-1").ok and m.pointer_view().rearm_buttons==[1],"same_session_binding_cannot_rearm_held")
 check(not m.resume_confirmed(raw([], [1])).ok and m.resume_confirmed(raw()).ok,"same_session_apply_requires_release")
 m.queue_pointer(gesture(m,"engine.starter","begin",true));before=state(m)
 check(m.queue_pointer(old_end).ok and state(m)==before,"apply_stale_release_cannot_retire_new")
 # Legacy configuration cannot acquire pointer controls or change its six-key sample.
 var legacy=Mapper.new();var legacy_axes:Dictionary=axes();legacy_axes.mixture=1.0
 check(legacy.configure(Mapper.default_preset(),legacy_axes,legacy_axes,raw()).ok,"legacy_fixture")
 check(not legacy.bind_pointer_session("pointer-fixture-legacy").ok and not legacy.pointer_view().error.is_empty() and legacy.pointer_view().session_id==null,"legacy_pointer_disabled")
 check(legacy.resume_confirmed(raw()).ok and legacy.sample(raw(),0).size()==6,"legacy_sample_shape_preserved")
 # A later rising edge during a still-owned switch gesture cannot oppose its chosen bool.
 m=fresh();m.queue_pointer(gesture(m,"engine.ignition_left","begin",true));m.sample(raw([], [1]),0)
 reject_sample(m,raw([KEY_F8],[1]),"later_switch_opposite_edge")
 # Host reconciles a lost GUI up through the ordinary explicit cancel seam.
 m=fresh();m.queue_pointer(gesture(m,"engine.starter","begin",true));m.queue_pointer(gesture(m,"engine.starter","cancel",null))
 check(not m.sample(raw(),0).systems["engine.starter"] and m.pointer_view().capture==null,"explicit_cancel_raw_released_no_starter")
 m.queue_pointer(gesture(m,"engine.starter","begin",true));m.sample(raw([], [1]),0)
 m.queue_pointer(gesture(m,"engine.starter","end",false));m.sample(raw([], [1]),0)
 check(m.pointer_view().capture==null and m.pointer_view().rearm_buttons==[1],"starter_leave_retires_but_real_button_held_rearm")
 reject_queue(m,gesture(m,"engine.starter","begin",true),"starter_leave_reentry_still_held")
 m.sample(raw(),0)
 check(m.pointer_view().rearm_buttons.is_empty() and m.queue_pointer(gesture(m,"engine.starter","begin",true)).ok,"starter_leave_real_release_fresh_gesture")
 # Queue resource defenses are structural primitive witnesses, not reachable event histories.
 m=fresh();m.queue_pointer(gesture(m));var filler:Dictionary=gesture(m,"throttle","move",0.2)
 m._pointer_pending.clear()
 for i in 15:m._pointer_pending.append(m._pointer_begin.duplicate(true))
 ended=gesture(m,"throttle","end",0.4)
 check(m.queue_pointer(ended).ok and m._pointer_pending.size()==16,"reserved_terminal_sixteenth_slot_primitive")
 m=fresh();m.queue_pointer(gesture(m));m._pointer_pending.clear()
 for i in 15:m._pointer_pending.append(m._pointer_begin.duplicate(true))
 check(not m.queue_pointer(filler).ok and not m.pointer_view().error.is_empty() and m.pointer_view().capture==null and m.pointer_view().rearm_buttons==[1],"overflow_retires_capture_latches_release_primitive")
 m=fresh();m._pointer_last_token=2147483647
 check(not m.queue_pointer(gesture(m)).ok,"token_no_wrap_closed_bound")
 bad=gesture(m);bad.token=2147483647
 check(not m.queue_pointer(bad).ok and m._pointer_disabled,"token_exhaustion_disables_primitive")
 m=fresh();m._pointer_last_token=2147483646
 check(m.queue_pointer(gesture(m,"engine.starter","begin",true)).ok,"last_representable_token_deliberate_begin")
 ended=gesture(m,"engine.starter","end",false)
 check(m.queue_pointer(ended).ok and not m.sample(raw(),0).systems["engine.starter"],"last_token_terminal_false")
 check(m._pointer_disabled and m.pointer_view().error.contains("fresh"),"last_token_consumed_disables_explicitly")
 before=state(m);check(m.queue_pointer(ended).ok and state(m)==before,"last_token_duplicate_terminal_still_inert")
 m.invalidate_pointer("widget retirement after exhaustion")
 check(m._pointer_disabled and m.pointer_view().error.contains("fresh"),"normal_lifecycle_cannot_hide_counter_fault")
 m=fresh();m._pointer_generation=2147483647;m.invalidate_pointer("exhaustion")
 check(m.pointer_view().generation==2147483647 and m._pointer_disabled and not m.queue_pointer(gesture(m)).ok,"generation_no_wrap_disables_primitive")
 return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Real mapper and synthetic complete Raw; no native/GUI/hardware acceptance. Resource saturation and counter exhaustion are explicitly primitive witnesses."}
