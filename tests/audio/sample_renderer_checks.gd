extends RefCounted
# Original MIT. Production samples; spectral/bound assertions, no mirror mixer.
const Renderer = preload("res://audio/sample_renderer.gd")
const Sound = preload("res://interactive/flight_sound.gd")
var _checks: int=0
var _failures: Array[String]=[]

func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)

func _result() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate()}

static func _options(engine: float=1.0, airflow: float=1.0) -> Dictionary:
	return {"enabled":true,"engine_gain":engine,"airflow_gain":airflow,"show_panel_captions":true}

static func _cue(mode: String="running", frequency: float=1000.0, tas: float=0.0) -> Dictionary:
	return {"session_id":"sample-fixture","tick":"0","profile_id":"original-interactive-prototype" if mode=="legacy" else "original-piston-prop-v1",
		"state":"live","engine_mode":mode,"shaft_radps":null if mode=="legacy" else 0.0 if mode=="stopped" else frequency*PI,
		"legacy_throttle":1.0 if mode=="legacy" else null,"tas_mps":tas,"starved":null if mode=="legacy" else false,"error":""}

static func _amplitude(samples: PackedVector2Array, frequency: float) -> float:
	var real_part: float=0.0
	var imaginary: float=0.0
	for i in samples.size():
		var angle: float=TAU*frequency*float(i)/22050.0
		real_part+=samples[i].x*cos(angle)
		imaginary+=samples[i].x*sin(angle)
	return 2.0*sqrt(real_part*real_part+imaginary*imaginary)/samples.size()

func _bounded(samples: PackedVector2Array, bound: float, label: String) -> void:
	var finite: bool=true
	var stereo: bool=true
	var peak: float=0.0
	for frame in samples:
		finite=finite and is_finite(frame.x) and is_finite(frame.y)
		stereo=stereo and frame.x==frame.y
		peak=maxf(peak,absf(frame.x))
	_check(finite and stereo and peak<=bound+0.0000001,label)

func _partition() -> void:
	var a=Renderer.new()
	var b=Renderer.new()
	var schedule: Array=[[_cue("legacy",1000.0,90.0),_options(),311],[_cue("legacy",1000.0,14.0),_options(0.2,0.7),1501],[_cue("running",731.0,32.0),_options(),2211],[_cue("rotating",15.0,32.0),_options(0.6,0.1),997]]
	for event_index in schedule.size():
		var event: Array=schedule[event_index]
		_check(a.configure(event[0],event[1]) and b.configure(event[0],event[1]),"partition_event_admitted_"+str(event_index))
		var whole: PackedVector2Array=a.render(event[2])
		var chunks := PackedVector2Array()
		var remaining: int=event[2]
		var part: int=0
		while remaining>0:
			var count: int=mini(remaining,[1,73,8,509,3][part%5])
			chunks.append_array(b.render(count))
			remaining-=count
			part+=1
		_check(whole.to_byte_array()==chunks.to_byte_array(),"sample_identical_partition_"+str(event_index))
		_check(a.sample_cursor==b.sample_cursor and a.phase==b.phase and a.noise==b.noise,"sample_state_identical_partition_"+str(event_index))
	var paused: Dictionary=schedule[-1][0].duplicate(true)
	paused.state="paused"
	a.configure(paused,_options());b.configure(paused,_options())
	var position: Array=[a.phase,a.noise,a.sample_cursor]
	_bounded(a.render(513),0.0,"paused_samples_zero")
	b.render(1);b.render(512)
	_check(position==[a.phase,a.noise,a.sample_cursor] and position==[b.phase,b.noise,b.sample_cursor],"paused_does_not_advance_oscillator_rng_cursor")
	a.configure(schedule[-1][0],_options());b.configure(schedule[-1][0],_options())
	_check(a.render(419).to_byte_array()==b.render(419).to_byte_array(),"same_session_resume_partition_equivalent")
	var muted: Dictionary=_options();muted.enabled=false
	a.configure(_cue(),muted)
	position=[a.phase,a.noise,a.sample_cursor]
	_bounded(a.render(10),0.0,"muted_samples_zero")
	_check(position==[a.phase,a.noise,a.sample_cursor],"mute_no_silent_advancement")
	var fresh: Dictionary=_cue();fresh.session_id="fresh-session"
	a.configure(fresh,_options());b=Renderer.new();b.configure(fresh,_options())
	_check(a.render(1024).to_byte_array()==b.render(1024).to_byte_array(),"session_change_resets_seed_phase_envelopes_cursor")

func _spectral() -> void:
	var renderer=Renderer.new()
	renderer.configure(_cue(),_options())
	renderer.render(22050)
	var samples: PackedVector2Array=renderer.render(22050)
	var fundamental: float=_amplitude(samples,1000.0)
	_check(absf(fundamental-0.17)<0.00001,"actual_running_fundamental_1000Hz_amplitude")
	_check(absf(_amplitude(samples,2000.0)/fundamental-0.36)<0.00001,"actual_second_harmonic_coefficient")
	_check(absf(_amplitude(samples,4000.0)/fundamental-0.12)<0.00001,"actual_fourth_harmonic_coefficient")
	for frequency in [6000.0,9850.0]:
		renderer=Renderer.new();renderer.configure(_cue("running",frequency),_options());renderer.render(22050)
		samples=renderer.render(22050)
		_check(absf(_amplitude(samples,frequency)-0.17)<0.00001,"near_Nyquist_fundamental_retained_"+str(frequency))
		_check(_amplitude(samples,absf(22050.0-frequency*2.0))<0.00001,"second_harmonic_alias_omitted_"+str(frequency))
		_check(_amplitude(samples,absf(44100.0-frequency*4.0))<0.00001,"fourth_harmonic_alias_omitted_"+str(frequency))
	for frequency in [10000.0,Renderer.CUTOFF]:
		renderer=Renderer.new();renderer.configure(_cue("running",frequency),_options())
		_bounded(renderer.render(2048),0.0,"at_or_above_cutoff_omits_all_engine_"+str(frequency))
	var extreme: Dictionary=_cue();extreme.shaft_radps=1.7976931348623157e308
	renderer=Renderer.new();_check(renderer.configure(extreme,_options()),"finite_extreme_shaft_admitted")
	_bounded(renderer.render(2048),0.0,"extreme_shaft_no_overflow_alias_or_clipping")
	_check(is_finite(renderer.phase),"extreme_shaft_phase_finite")

func _envelopes_and_admission() -> void:
	for mode in ["legacy","running","rotating","stopped"]:
		var renderer=Renderer.new();renderer.configure(_cue(mode,137.0,90.0),_options())
		_bounded(renderer.render(44100),{"legacy":0.4408,"running":0.3816,"rotating":0.17,"stopped":0.13}[mode],"authored_component_peak_"+mode)
	var renderer=Renderer.new();renderer.configure(_cue("rotating",1000.0),_options())
	renderer.render(441)
	# 441 samples = exactly one 20ms time constant. This measures actual state,
	# rather than regenerating a second mixer waveform in the test.
	_check(absf(renderer._rotating-(1.0-exp(-1.0)))<0.00000000001,"20ms_per_sample_envelope_time_constant")
	var before: float=renderer._rotating
	renderer.configure(_cue("running",1000.0),_options())
	renderer.render(1)
	_check(renderer._rotating<before and renderer._running>0.0 and renderer._legacy+renderer._running+renderer._rotating<=1.0,"mode_transition_convex_not_full_mix_sum")
	var cue: Dictionary=_cue("stopped",0.0,90.0)
	var options: Dictionary=_options()
	renderer=Renderer.new();renderer.configure(cue,options)
	cue.tas_mps=0.0;options.airflow_gain=0.0
	var samples: PackedVector2Array=renderer.render(4096)
	_check(_amplitude(samples,937.0)>0.0,"renderer_owns_source_options_copies")
	var identical=Renderer.new();identical.configure(_cue("stopped",0.0,90.0),_options())
	_check(samples.to_byte_array()==identical.render(4096).to_byte_array(),"original_seed_repeatable")
	var partial: Dictionary=_cue();partial.tas_mps=null;partial.starved=null;partial.error="Airflow and starvation unavailable"
	_check(renderer.configure(partial,_options()),"partial_channels_admitted_without_guessing")
	_check(_amplitude(renderer.render(22050),1000.0)>0.1,"missing_air_starved_does_not_mute_qualified_engine")
	for invalid in [null,{},_cue()]:
		var bad: Variant=invalid.duplicate(true) if invalid is Dictionary else invalid
		if bad is Dictionary and not bad.is_empty(): bad.extra=true
		_check(not renderer.configure(bad,_options()),"closed_cue_reject_"+str(typeof(invalid))+str(bad!=null and bad is Dictionary and bad.has("extra")))
		_bounded(renderer.render(9),0.0,"rejection_clears_prior_samples")
	for change in [{"shaft_radps":1},{"state":"LIVE"},{"engine_mode":"stopped"},{"tick":"01"},{"tick":"18446744073709551616"},{"starved":0},{"error":"unexpected"}]:
		var bad: Dictionary=_cue();bad.merge(change,true)
		_check(not renderer.configure(bad,_options()),"strict_cue_negative_"+str(change.keys()[0])+str(change.values()[0]))
	var bad_options: Dictionary=_options();bad_options.engine_gain=1
	_check(not renderer.configure(_cue(),bad_options),"renderer_rejects_coerced_options")
	_check(renderer.render(-1).is_empty(),"negative_count_not_rendered")

func _independent_gains() -> void:
	for mode in ["running","stopped"]:
		var full=Renderer.new();var half=Renderer.new();var off=Renderer.new()
		var cue: Dictionary=_cue(mode,1000.0,90.0 if mode=="stopped" else 0.0)
		full.configure(cue,_options())
		half.configure(cue,_options(0.5 if mode=="running" else 0.0,0.5 if mode=="stopped" else 0.0))
		off.configure(cue,_options(0.0,0.0))
		var full_samples: PackedVector2Array=full.render(8192)
		var half_samples: PackedVector2Array=half.render(8192)
		var linear: bool=true
		for i in full_samples.size():
			linear=linear and half_samples[i]==full_samples[i]*0.5
		_check(linear,"independent_gain_half_exact_"+mode)
		_bounded(off.render(8192),0.0,"zero_gains_silence_"+mode)
	var engine_missing: Dictionary=_cue("stopped",0.0,90.0)
	engine_missing.engine_mode="unavailable";engine_missing.shaft_radps=null;engine_missing.error="Engine unavailable"
	var partial=Renderer.new();var air_only=Renderer.new()
	_check(partial.configure(engine_missing,_options()),"missing_engine_retains_airflow_admission")
	air_only.configure(_cue("stopped",0.0,90.0),_options())
	_check(partial.render(4096).to_byte_array()==air_only.render(4096).to_byte_array(),"missing_engine_does_not_mute_airflow")
	var history: Dictionary=_cue();history.state="historical"
	partial.configure(history,_options())
	_bounded(partial.render(113),0.0,"historical_source_cannot_sound")
	_check(partial.phase==0.0 and partial.sample_cursor==0 and partial.noise==0.0,"historical_invalidation_discards_stale_render_state")
	var caption_options: Dictionary=_options();caption_options.show_panel_captions=false
	partial=Renderer.new();air_only=Renderer.new()
	partial.configure(_cue(),caption_options);air_only.configure(_cue(),_options())
	_check(partial.render(117).to_byte_array()==air_only.render(117).to_byte_array(),"panel_caption_choice_never_changes_samples")

static func run() -> Dictionary:
	var suite=new()
	suite._partition()
	suite._spectral()
	suite._envelopes_and_admission()
	suite._independent_gains()
	return suite._result()

static func run_sound(host: Node, source: Dictionary) -> Dictionary:
	# Root supplies one actual adopted, live Readback. No facade/native mutations.
	var suite=new()
	var sound=Sound.new();host.add_child(sound);sound.set_process(false)
	suite._check(sound.playback!=null,"preview_real_generator_available")
	var preview: AudioStreamGeneratorPlayback=sound.playback
	sound.observe({})
	suite._check(sound.playback==null and sound.player.stream==null,"invalid_observe_synchronously_detaches_preview")
	sound.observe(source)
	suite._check(sound.cue_view().state=="live","provided_actual_source_live_required")
	suite._check(sound.playback==null,"held_old_playback_blocks_restart")
	preview=null
	var deadline: int=Time.get_ticks_usec()+2000000
	while sound.playback==null and Time.get_ticks_usec()<deadline:
		await host.get_tree().create_timer(0.025).timeout
		sound._process(0.0)
	suite._check(sound.playback!=null,"actual_retirement_allows_one_fresh_buffer")
	var options: Dictionary=sound.options_view();var unchanged: Dictionary=options.duplicate(true)
	options.engine_gain=1
	suite._check(not sound.set_options(options) and sound.options_view()==unchanged,"invalid_options_atomic")
	var cues: Dictionary=sound.cue_view();cues.state="historical"
	suite._check(sound.cue_view().state=="live","cue_readback_owned")
	var retained: AudioStreamGeneratorPlayback=sound.playback
	var phase_before: float=sound.phase
	sound.set_enabled(false)
	suite._check(sound.playback==null and sound.player.stream==null and not sound.options_view().enabled,"mute_synchronous_detach_single_master")
	sound._process(10.0)
	suite._check(sound.phase==phase_before,"mute_process_no_sample_advancement")
	sound.set_enabled(true)
	suite._check(sound.playback==null,"unmute_waits_retained_reference")
	suite._check(not await sound.shutdown(),"actual_two_second_timeout_reports_unretired_reference")
	retained=null
	suite._check(await sound.shutdown(),"all_retirements_join_after_external_reference_released")
	sound.observe(source);sound.set_enabled(true);sound.update_audio(1.0,90.0,false,true);sound._process(0.0)
	suite._check(sound.playback==null and sound.cue_view().state=="unavailable","closed_node_cannot_revive")
	suite._check(sound.get_child_count()==1 and sound.player is AudioStreamPlayer,"at_most_one_nonspatial_emitter")
	sound.free()
	return suite._result()
