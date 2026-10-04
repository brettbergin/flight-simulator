extends Node
# Original synthesized presentation only: no sampled assets, measured RPM,
# propeller/engine physics, warning system or aviation-fidelity assertion.
var player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
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
var native_starter: bool = false
var random := RandomNumberGenerator.new()

func _ready() -> void:
	random.seed=8017
	generator=AudioStreamGenerator.new()
	generator.mix_rate=22050
	generator.buffer_length=0.12
	player=AudioStreamPlayer.new()
	player.stream=generator
	player.volume_db=-12
	add_child(player)
	player.play()
	playback=player.get_stream_playback() as AudioStreamGeneratorPlayback
	player.stream_paused=not enabled or paused

func set_enabled(value: bool) -> void:
	enabled=value
	if player!=null:
		player.stream_paused=not enabled or paused

func update_audio(native_throttle: float, speed_mps: float, is_paused: bool, is_grounded: bool) -> void:
	native_engine=false
	throttle=clampf(native_throttle,0,1)
	speed=clampf(speed_mps,0,150)
	paused=is_paused
	grounded=is_grounded
	if player!=null:
		player.stream_paused=not enabled or paused

func update_engine_audio(engine_status: Dictionary, speed_mps: float, is_paused: bool, is_grounded: bool) -> void:
	native_engine=true
	native_running=false
	native_starter=false
	native_shaft=0.0
	# The host supplies the identity-qualified producer. Missing channels mute
	# engine cues; wind is independent of combustion and still follows airspeed.
	var readings: Dictionary=engine_status.get("readings",{})
	var shaft: Dictionary=readings.get("propeller.angular_speed",{})
	var running: Dictionary=readings.get("engine.running",{})
	var starter: Dictionary=readings.get("engine.starter",{})
	if engine_status.get("state") in ["live","paused"] and shaft.get("valid")==true and shaft.get("unit")=="radps" and typeof(shaft.get("value"))==TYPE_FLOAT and is_finite(shaft.value) and shaft.value>=0.0:
		native_shaft=shaft.value
		native_running=running.get("valid")==true and running.get("unit")=="bool" and typeof(running.get("value"))==TYPE_BOOL and running.value
		native_starter=starter.get("valid")==true and starter.get("unit")=="bool" and typeof(starter.get("value"))==TYPE_BOOL and starter.value
	speed=clampf(speed_mps,0,150)
	paused=is_paused
	grounded=is_grounded
	if player!=null:
		player.stream_paused=not enabled or paused

func _process(_delta: float) -> void:
	if playback==null or not enabled or paused:
		return
	var count: int=mini(playback.get_frames_available(),4096)
	var buffer := PackedVector2Array()
	buffer.resize(count)
	for i in range(count):
		level=lerpf(level,throttle,0.0006)
		var frequency: float=43+level*72
		if native_engine:
			frequency=native_shaft/TAU*2.0
		phase=fposmod(phase+TAU*frequency/22050.0,TAU)
		wind=lerpf(wind,random.randf_range(-1,1),0.07)
		var engine: float=(sin(phase)+0.36*sin(phase*2)+0.12*sin(phase*4))*(0.08+0.13*level)
		if native_engine:
			engine=(sin(phase)+0.36*sin(phase*2)+0.12*sin(phase*4))*0.17 if native_running and native_shaft>0.0 else 0.0
			if native_starter and not native_running and native_shaft>0.0:
				engine=sin(phase)*0.04
		var air: float=wind*clampf(speed/90.0,0,1)*0.32
		var sample: float=clampf(engine+air,-0.5,0.5)
		buffer[i]=Vector2(sample,sample)
	playback.push_buffer(buffer)

func close() -> void:
	set_process(false)
	if player!=null:
		player.stop()
		player.stream=null
	playback=null
	generator=null

func shutdown() -> bool:
	# Godot's audio mixer can hold a stopped playback briefly. Explicit quits
	# await actual retirement; no timeout means "passed" and no leak suppression.
	var retiring: WeakRef=weakref(playback) if playback!=null else null
	close()
	var deadline: int=Time.get_ticks_usec()+2000000
	while retiring!=null and retiring.get_ref()!=null and Time.get_ticks_usec()<deadline:
		await get_tree().create_timer(0.025).timeout
	return retiring==null or retiring.get_ref()==null

func _exit_tree() -> void:
	close()
