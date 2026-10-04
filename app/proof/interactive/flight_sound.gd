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
	throttle=clampf(native_throttle,0,1)
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
		phase=fposmod(phase+TAU*(43+level*72)/22050.0,TAU)
		wind=lerpf(wind,random.randf_range(-1,1),0.07)
		var engine: float=(sin(phase)+0.36*sin(phase*2)+0.12*sin(phase*4))*(0.08+0.13*level)
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

func _exit_tree() -> void:
	close()
