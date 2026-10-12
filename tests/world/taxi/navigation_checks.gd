extends RefCounted
# Original MIT. Root supplies real qualified paused publications; no sessions
# or authority pins are fabricated here. Mutated copies below are NEGATIVES.
const Navigation = preload("res://world/taxi/taxi_navigation.gd")
const Layout = preload("res://world/taxi/taxi_layout.gd")
const Checks = preload("res://taxi_tests/layout_checks.gd")

static func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes.hex_encode()

static func _foreign(nav: RefCounted, readback: Dictionary) -> Dictionary:
	var observed: Variant = nav.observe(readback)
	var replied: Dictionary = nav.next(readback)
	nav.retire()
	return {"observed":observed,"replied":replied}

static func run(readbacks: Array) -> Dictionary:
	var result: Dictionary = Checks.receipt("Actual navigation state machine over Root-supplied full paused apron Readbacks; pure frozen metrics separate; no taxi movement/initialization proof")
	var reference: Dictionary = Checks.references(result)
	if reference.is_empty(): return result
	for row in reference.metrics:
		var dx: float = str(row.delta_x_binary64_le).hex_decode().decode_double(0)
		var dz: float = str(row.delta_z_binary64_le).hex_decode().decode_double(0)
		var expected_range: float = str(row.range_binary64_le).hex_decode().decode_double(0)
		var actual: Dictionary = Navigation._metrics(dx,dz)
		Checks.check(result,not actual.is_empty(),"metric_exists_"+row.id)
		if actual.is_empty(): continue
		if row.id in ["coincident","tiny_east"]:
			Checks.check(result,_bits(actual.range)==row.range_binary64_le,"exact_zero_or_subnormal_"+row.id)
		else:
			Checks.check(result,absf(actual.range-expected_range)<=1e-7,"independent_range_"+row.id)
		if row.anchor_bearing_deg_binary64_le==null:
			Checks.check(result,actual.bearing==null,"coincident_no_bearing")
		else:
			var bearing: float = str(row.anchor_bearing_deg_binary64_le).hex_decode().decode_double(0)
			Checks.check(result,actual.bearing!=null and absf(actual.bearing-bearing)<=1e-7,"independent_bearing_"+row.id)
	Checks.check(result,Navigation._metrics(INF,0.0).is_empty() and Navigation._metrics(1.7976931348623157e308,1.7976931348623157e308).is_empty(),"nonfinite_and_overflow_fail_closed")
	var loaded: Dictionary = Layout.load()
	Checks.check(result,loaded.ok,"layout_admitted_for_navigation")
	if not loaded.ok: return result
	var seen: Dictionary = {}
	for input in readbacks:
		if typeof(input)!=TYPE_DICTIONARY:
			Checks.check(result,false,"Root_Readback_must_be_Dictionary")
			continue
		var rb: Dictionary = input.duplicate(true)
		var before: Dictionary = input.duplicate(true)
		var name: String = rb.get("named_start","")
		Checks.check(result,name in ["apron-ready","piston-cold-apron"] and not seen.has(name),"required_unique_actual_apron_start_"+name)
		if not name in ["apron-ready","piston-cold-apron"] or seen.has(name): continue
		seen[name]=true
		var nav := Navigation.new()
		Checks.check(result,nav.observe(rb)==null and nav.next(rb).error=="not_configured","before_configure_null_"+name)
		Checks.check(result,nav.configure(loaded.value).ok,"configure_"+name)
		var fresh: Dictionary = nav.fresh_session(rb)
		Checks.check(result,fresh.ok and fresh.view.qualified and fresh.view.paused and fresh.view.state=="empty" and not fresh.view.aids_visible,"actual_full_current_source_admission_"+name)
		if not fresh.ok: continue
		Checks.check(result,not nav.configure(loaded.value).ok,"bound_reconfigure_refused_"+name)
		for itinerary in loaded.value.itineraries:
			var reply: Dictionary = nav.choose(itinerary.id,rb)
			Checks.check(result,reply.ok and reply.view.available and reply.view.aids_visible and reply.view.point_index==0,"explicit_begin_"+name+itinerary.id)
			for index in itinerary.points.size():
				var view: Dictionary = nav.observe(rb)
				Checks.check(result,view.point_index==index and view.target_eus_m==itinerary.points[index].point_eus_m and view.points==itinerary.points,"manual_target_"+name+itinerary.id+str(index))
				Checks.check(result,nav.observe(rb)==view,"observation_never_advances_"+name+itinerary.id+str(index))
				reply=nav.next(rb)
				Checks.check(result,reply.ok,"next_once_"+name+itinerary.id+str(index))
			var ended: Dictionary = nav.observe(rb)
			Checks.check(result,ended.state=="manual-ended" and ended.point_index==itinerary.points.size()-1 and ended.points.is_empty() and ended.target_eus_m==null and ended.planar_range_m==null and not ended.available,"manual_end_not_arrival_"+name+itinerary.id)
			Checks.check(result,nav.next(rb).error=="no_active_itinerary" and nav.observe(rb)==ended,"ended_next_refused_without_mutation_"+name+itinerary.id)
			Checks.check(result,nav.choose(itinerary.id,rb).view.point_index==0,"same_itinerary_explicit_restart_"+name+itinerary.id)
		nav.choose("outbound-36",rb)
		var retained: Dictionary = nav.observe(rb)
		var copy: Dictionary = nav.observe(rb)
		copy.points[0].point_eus_m[0]=-999.0
		Checks.check(result,nav.observe(rb)==retained,"owned_view_nested_copies_"+name)
		Checks.check(result,not nav.choose(StringName("outbound-18"),rb).ok and nav.observe(rb)==retained,"StringName_selection_rejected_"+name)
		Checks.check(result,not nav.set_aids_visible(1,rb).ok and nav.observe(rb)==retained,"actual_BOOL_aid_only_"+name)
		var foreign: Dictionary = rb.duplicate(true)
		foreign.session_id="synthetic-negative-foreign-session"
		foreign.aircraft.session_id=foreign.session_id
		foreign.atmosphere.session_id=foreign.session_id
		var unavailable: Dictionary = nav.observe(foreign)
		Checks.check(result,not unavailable.qualified and unavailable.session_id==null and unavailable.target_eus_m==null and unavailable.points.is_empty() and unavailable.error=="session_mismatch" and nav.observe(rb)==retained,"foreign_observation_suppresses_without_rebind_"+name)
		Checks.check(result,nav.next(foreign).error=="session_mismatch" and nav.observe(rb)==retained,"stale_mutator_retains_state_"+name)
		var wrong_source: Dictionary = rb.duplicate(true)
		wrong_source.native_source_fingerprint="0".repeat(64)
		Checks.check(result,nav.next(wrong_source).error=="source_unqualified" and not nav.observe(wrong_source).available and nav.observe(rb)==retained,"complete_source_pin_required_"+name)
		var wrong_pose: Dictionary = rb.duplicate(true)
		wrong_pose.canonical.anchor_eus_position_m[0]+=0.001
		Checks.check(result,nav.next(wrong_pose).error=="invalid_readback" and nav.observe(rb)==retained,"canonical_rederived_not_trusted_"+name)
		var live: Dictionary = rb.duplicate(true)
		live.host_mode="live"
		live.paused=false
		live.native_outcome="completed"
		Checks.check(result,nav.next(live).error=="not_paused" and nav.observe(rb)==retained,"live_mutation_refused_"+name)
		var thread := Thread.new()
		Checks.check(result,thread.start(_foreign.bind(nav,rb.duplicate(true)))==OK,"foreign_thread_started_"+name)
		if thread.is_started():
			var returned: Dictionary = thread.wait_to_finish()
			Checks.check(result,returned.observed==null and returned.replied=={"ok":false,"error":"wrong_thread","view":null} and nav.observe(rb)==retained,"foreign_thread_no_reads_mutation_or_retire_"+name)
		Checks.check(result,nav.set_aids_visible(false,rb).ok and nav.observe(rb).point_index==retained.point_index,"aid_toggle_never_begins_"+name)
		Checks.check(result,nav.stop(rb).ok and nav.observe(rb).state=="empty" and not nav.observe(rb).aids_visible,"stop_preserves_hidden_preference_"+name)
		Checks.check(result,nav.set_aids_visible(true,rb).ok and nav.stop(rb).ok and nav.observe(rb).state=="empty" and nav.observe(rb).aids_visible,"stop_preserves_visible_preference_"+name)
		nav.choose("return-middle",rb)
		Checks.check(result,nav.fresh_session(rb).ok and nav.observe(rb).state=="empty" and not nav.observe(rb).aids_visible,"successful_fresh_adoption_resets_only_view_state_"+name)
		nav.retire()
		Checks.check(result,nav.observe(rb).error=="session_mismatch" and nav.fresh_session(rb).ok,"retire_keeps_configured_layout_"+name)
		Checks.check(result,input==before and rb==before,"complete_caller_Readback_unchanged_"+name)
	Checks.check(result,seen.size()==2 and seen.has("apron-ready") and seen.has("piston-cold-apron"),"both_actual_apron_profiles_required_no_vacuous_pass")
	return result
