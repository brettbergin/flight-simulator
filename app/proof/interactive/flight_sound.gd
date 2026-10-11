extends Node
# Original MIT. Presentation-only synthesis; no aircraft acoustic qualification.
const Cues = preload("res://audio/audio_cues.gd")
const Options = preload("res://audio/audio_options.gd")
const Renderer = preload("res://audio/sample_renderer.gd")
var player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
# Retained preview fields/signatures. Ordinary flight uses observe instead.
var enabled: bool = true
var paused: bool = false
var throttle: float = 0.0
var speed: float = 0.0
var grounded: bool = true
var phase: float = 0.0
var level: float = 0.0
var wind: float = 0.0
var native_engine: bool = false
var native_running: bool = false
var native_shaft: float = 0.0
var random := RandomNumberGenerator.new()
var _renderer := Renderer.new()
var _options: Dictionary = {"enabled":true,"engine_gain":1.0,"airflow_gain":1.0,"show_panel_captions":true}
var _cues: Dictionary = Cues.from_readback({})
var _retiring: Array[WeakRef] = []
var _ordinary: bool = false
var _preview_started: bool = false
var _closed: bool = false

func _ready() -> void:
	random.seed=8017
	player=AudioStreamPlayer.new()
	player.volume_db=-12.0
	add_child(player)
	# Preview proofs require a real generator immediately. No samples are queued
	# until an explicit preview update; ordinary observe detaches this buffer.
	if not _closed and not _ordinary: _attach()
	elif not _closed: _activate()

func cue_view() -> Dictionary:
	return _cues.duplicate(true)

func options_view() -> Dictionary:
	return _options.duplicate(true)

func set_options(value: Variant) -> bool:
	var checked: Dictionary=Options.validate(value)
	if not checked.ok: return false
	if checked.value==_options: return true
	_options=checked.value
	enabled=_options.enabled
	if _closed: return true
	if _ordinary:
		_renderer.configure(_cues,_options)
		if not enabled: _detach()
		else: _activate()
	elif player!=null:
		player.stream_paused=not enabled or paused
	return true

func set_enabled(value: bool) -> void:
	var options: Dictionary=_options.duplicate(true)
	options.enabled=value
	set_options(options)

func observe(source: Variant) -> void:
	if _closed: return
	var incoming: Dictionary=Cues.from_readback(source)
	# Closed boundary admission is not a second native authority.
	if not Renderer._valid_cue(incoming): incoming=Cues.from_readback({})
	var changed: bool=not _ordinary or incoming.session_id!=_cues.session_id
	_ordinary=true
	_cues=incoming.duplicate(true)
	paused=_cues.state=="paused"
	native_engine=_cues.profile_id=="original-piston-prop-v1"
	native_running=_cues.engine_mode=="running"
	native_shaft=0.0 if _cues.shaft_radps==null else _cues.shaft_radps
	throttle=0.0 if _cues.legacy_throttle==null else _cues.legacy_throttle
	speed=0.0 if _cues.tas_mps==null else _cues.tas_mps
	if changed or not _eligible(): _detach()
	_renderer.configure(_cues,_options)
	_sync_preview_fields()
	_activate()

func _eligible() -> bool:
	return not _closed and _ordinary and _cues.state=="live" and _options.enabled

func _prune_retiring() -> void:
	for i in range(_retiring.size()-1,-1,-1):
		if _retiring[i].get_ref()==null: _retiring.remove_at(i)

func _detach() -> void:
	if playback!=null: _retiring.append(weakref(playback))
	if player!=null:
		player.stop()
		player.stream=null
		player.stream_paused=true
	playback=null
	generator=null
	_renderer.silence()
	_prune_retiring()

func _attach() -> void:
	if _closed or player==null or playback!=null: return
	_prune_retiring()
	if not _retiring.is_empty(): return
	generator=AudioStreamGenerator.new()
	generator.mix_rate=Renderer.SAMPLE_RATE
	generator.buffer_length=0.12
	player.stream=generator
	player.stream_paused=false
	player.play()
	playback=player.get_stream_playback() as AudioStreamGeneratorPlayback
	player.stream_paused=not enabled or paused

func _activate() -> void:
	if _eligible(): _attach()

func update_audio(native_throttle: float, speed_mps: float, is_paused: bool, is_grounded: bool) -> void:
	if _closed or _ordinary: return
	_preview_started=true
	native_engine=false
	throttle=clampf(native_throttle,0.0,1.0) if is_finite(native_throttle) else 0.0
	speed=clampf(speed_mps,0.0,150.0) if is_finite(speed_mps) else 0.0
	paused=is_paused
	grounded=is_grounded
	if player!=null: player.stream_paused=not enabled or paused

func update_engine_audio(engine_status: Dictionary, speed_mps: float, is_paused: bool, is_grounded: bool) -> void:
	if _closed or _ordinary: return
	_preview_started=true
	native_engine=true
	native_running=false
	native_shaft=0.0
	var readings: Variant=engine_status.get("readings",{})
	var shaft: Variant=readings.get("propeller.angular_speed",{}) if readings is Dictionary else {}
	var running: Variant=readings.get("engine.running",{}) if readings is Dictionary else {}
	if engine_status.get("state") in ["live","paused"] and shaft is Dictionary and shaft.get("valid")==true and shaft.get("unit")=="radps" and typeof(shaft.get("value"))==TYPE_FLOAT and is_finite(shaft.value) and shaft.value>=0.0:
		native_shaft=shaft.value
		native_running=running is Dictionary and running.get("valid")==true and running.get("unit")=="bool" and typeof(running.get("value"))==TYPE_BOOL and running.value
	speed=clampf(speed_mps,0.0,150.0) if is_finite(speed_mps) else 0.0
	paused=is_paused
	grounded=is_grounded
	if player!=null: player.stream_paused=not enabled or paused

func _preview_cue() -> Dictionary:
	# Explicit scalar preview compatibility, not ordinary Readback qualification.
	return {"session_id":"separate-preview","tick":"0","profile_id":"original-piston-prop-v1" if native_engine else "original-interactive-prototype",
		"state":"paused" if paused else "live","engine_mode":("running" if native_running else "rotating") if native_engine and native_shaft>0.0 else "stopped" if native_engine else "legacy",
		"shaft_radps":native_shaft if native_engine else null,"legacy_throttle":null if native_engine else throttle,"tas_mps":speed,"starved":false if native_engine else null,"error":""}

func _sync_preview_fields() -> void:
	phase=_renderer.phase
	level=_renderer.smoothed_throttle
	wind=_renderer.noise

func _process(_delta: float) -> void:
	if _closed: return
	if _ordinary:
		if not _eligible(): return
		_activate()
	else:
		if not _preview_started or not enabled or paused: return
		_renderer.configure(_preview_cue(),_options)
		# Existing standalone proofs deliberately set this public phase field.
		_renderer.phase=phase
	if playback==null: return
	var count: int=mini(playback.get_frames_available(),4096)
	if count<=0: return
	playback.push_buffer(_renderer.render(count))
	_sync_preview_fields()

func close() -> void:
	_closed=true
	set_process(false)
	_detach()
	_cues=Cues.from_readback({})
	_renderer.reset()
	_sync_preview_fields()

func shutdown() -> bool:
	close()
	var deadline: int=Time.get_ticks_usec()+2000000
	_prune_retiring()
	while not _retiring.is_empty() and Time.get_ticks_usec()<deadline:
		await get_tree().create_timer(0.025).timeout
		_prune_retiring()
	return _retiring.is_empty()

func _exit_tree() -> void:
	close()
