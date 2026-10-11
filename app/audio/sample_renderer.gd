extends RefCounted
# Original MIT. Artistic ADR020 synthesis, not calibrated aircraft acoustics.
# Every state transition below is indexed by rendered samples, never draw time.
const Options = preload("res://audio/audio_options.gd")
const SAMPLE_RATE: float = 22050.0
const ENVELOPE_SECONDS: float = 0.020
const SEED: int = 8017
const CUTOFF: float = SAMPLE_RATE * 0.45
const KEYS: Array = ["session_id","tick","profile_id","state","engine_mode","shaft_radps","legacy_throttle","tas_mps","starved","error"]
var phase: float = 0.0
var noise: float = 0.0
var smoothed_throttle: float = 0.0
var sample_cursor: int = 0
var _legacy: float = 0.0
var _running: float = 0.0
var _rotating: float = 0.0
var _air: float = 0.0
var _random := RandomNumberGenerator.new()
var _cues: Dictionary = {}
var _options: Dictionary = {}
var _alpha: float = 1.0-exp(-1.0/(SAMPLE_RATE*ENVELOPE_SECONDS))

func _init() -> void:
	reset()

func reset() -> void:
	phase=0.0
	noise=0.0
	smoothed_throttle=0.0
	sample_cursor=0
	_random.seed=SEED
	silence()

func silence() -> void:
	# Fresh buffer resumes from zero envelope, without advancing phase or RNG.
	_legacy=0.0
	_running=0.0
	_rotating=0.0
	_air=0.0

static func _number(value: Variant, maximum: float=INF) -> bool:
	return typeof(value)==TYPE_FLOAT and is_finite(value) and value>=0.0 and value<=maximum

static func _tick(value: Variant) -> bool:
	if typeof(value)!=TYPE_STRING or value.is_empty() or value.length()>20: return false
	if value.length()>1 and value.begins_with("0"): return false
	for c in value:
		if c<"0" or c>"9": return false
	return value.length()<20 or value<="18446744073709551615"

static func _valid_cue(value: Variant) -> bool:
	# Internal boundary shared by this renderer and its owning Sound leaf only.
	if not value is Dictionary or value.size()!=KEYS.size(): return false
	for key in value:
		if typeof(key)!=TYPE_STRING or key not in KEYS: return false
	if typeof(value.state)!=TYPE_STRING or value.state not in ["live","paused","historical","unavailable"]: return false
	if typeof(value.engine_mode)!=TYPE_STRING or value.engine_mode not in ["legacy","running","rotating","stopped","unavailable"]: return false
	if typeof(value.error)!=TYPE_STRING or value.error.length()>1024: return false
	if value.state=="unavailable":
		for key in ["session_id","tick","profile_id","shaft_radps","legacy_throttle","tas_mps","starved"]:
			if value[key]!=null: return false
		return value.engine_mode=="unavailable" and not value.error.is_empty()
	if typeof(value.session_id)!=TYPE_STRING or value.session_id.is_empty() or not _tick(value.tick): return false
	if typeof(value.profile_id)!=TYPE_STRING or value.profile_id not in ["original-interactive-prototype","original-piston-prop-v1"]: return false
	if value.tas_mps!=null and not _number(value.tas_mps): return false
	if value.starved!=null and typeof(value.starved)!=TYPE_BOOL: return false
	if value.profile_id=="original-interactive-prototype":
		if value.engine_mode!="legacy" or not _number(value.legacy_throttle,1.0) or value.shaft_radps!=null or value.starved!=null: return false
	else:
		if value.legacy_throttle!=null or value.engine_mode=="legacy": return false
		if value.engine_mode=="unavailable":
			if value.shaft_radps!=null: return false
		elif not _number(value.shaft_radps): return false
		elif (value.engine_mode=="stopped")!=(value.shaft_radps==0.0): return false
	var missing: bool=value.engine_mode=="unavailable" or value.tas_mps==null or (value.profile_id=="original-piston-prop-v1" and value.starved==null)
	return value.error.is_empty()!=missing

func configure(cues: Variant, options: Variant) -> bool:
	var checked: Dictionary=Options.validate(options)
	if not _valid_cue(cues) or not checked.ok:
		_cues={}
		_options={}
		reset()
		return false
	var was_active: bool=_active()
	if _cues.get("session_id")!=cues.session_id or cues.state in ["historical","unavailable"]:
		reset()
	_cues=cues.duplicate(true)
	_options=checked.value
	if not was_active or not _active(): silence()
	return true

func _active() -> bool:
	return _cues.get("state")=="live" and _options.get("enabled")==true

func render(count: int) -> PackedVector2Array:
	var buffer := PackedVector2Array()
	if count<0: return buffer
	buffer.resize(count)
	if not _active(): return buffer
	var mode: String=_cues.engine_mode
	var legacy_target: float=_options.engine_gain if mode=="legacy" else 0.0
	var running_target: float=_options.engine_gain if mode=="running" else 0.0
	var rotating_target: float=_options.engine_gain if mode=="rotating" else 0.0
	var air_target: float=0.0 if _cues.tas_mps==null else 0.13*clampf(_cues.tas_mps/90.0,0.0,1.0)*_options.airflow_gain
	for i in count:
		smoothed_throttle=lerpf(smoothed_throttle,0.0 if _cues.legacy_throttle==null else _cues.legacy_throttle,_alpha)
		_legacy=lerpf(_legacy,legacy_target,_alpha)
		_running=lerpf(_running,running_target,_alpha)
		_rotating=lerpf(_rotating,rotating_target,_alpha)
		_air=lerpf(_air,air_target,_alpha)
		var frequency: float=43.0+72.0*smoothed_throttle if mode=="legacy" else 0.0 if _cues.shaft_radps==null else _cues.shaft_radps/TAU*2.0
		# Reduction before multiplication keeps even finite extreme shafts finite.
		phase=fposmod(phase+TAU*(fposmod(frequency,SAMPLE_RATE)/SAMPLE_RATE),TAU)
		noise=lerpf(noise,_random.randf_range(-1.0,1.0),0.07)
		var fundamental: float=sin(phase) if frequency<CUTOFF else 0.0
		var harmonic: float=fundamental
		if frequency<CUTOFF/2.0: harmonic+=0.36*sin(phase*2.0)
		if frequency<CUTOFF/4.0: harmonic+=0.12*sin(phase*4.0)
		# Convex mode weights avoid a transition summing two full engine mixes.
		var engine: float=harmonic*((0.08+0.13*smoothed_throttle)*_legacy+0.17*_running)+fundamental*0.04*_rotating
		var sample: float=engine+noise*_air
		buffer[i]=Vector2(sample,sample)
		sample_cursor+=1
	return buffer
