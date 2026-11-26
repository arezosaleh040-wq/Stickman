extends Node

var wind_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer
var step_player: AudioStreamPlayer
var jump_player: AudioStreamPlayer
var bird_player: AudioStreamPlayer
var alert_player: AudioStreamPlayer
var beep_player: AudioStreamPlayer
var bird_timer := 4.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	wind_player = AudioStreamPlayer.new()
	wind_player.name = "AmbientWind"
	wind_player.stream = _make_noise_stream(5.0, 0.022, 0.16, true, 193)
	wind_player.volume_db = -28.0
	add_child(wind_player)
	wind_player.play()
	engine_player = AudioStreamPlayer.new()
	engine_player.name = "DistantTrafficRumble"
	engine_player.stream = _make_engine_loop()
	engine_player.volume_db = -37.0
	add_child(engine_player)
	engine_player.play()
	step_player = AudioStreamPlayer.new()
	step_player.name = "Footsteps"
	step_player.stream = _make_noise_stream(0.16, 0.24, 0.42, false, 77)
	step_player.volume_db = -13.0
	add_child(step_player)
	jump_player = AudioStreamPlayer.new()
	jump_player.name = "JumpWhoosh"
	jump_player.stream = _make_tone_stream(260.0, 0.14)
	jump_player.volume_db = -20.0
	add_child(jump_player)
	bird_player = AudioStreamPlayer.new()
	bird_player.name = "DistantBirdCalls"
	bird_player.stream = _make_bird_call_stream()
	bird_player.volume_db = -24.0
	add_child(bird_player)
	alert_player = AudioStreamPlayer.new()
	alert_player.name = "PoliceAlert"
	alert_player.stream = _make_tone_stream(520.0, 0.24)
	alert_player.volume_db = -12.0
	add_child(alert_player)
	beep_player = AudioStreamPlayer.new()
	beep_player.name = "CardReaderBeep"
	beep_player.stream = _make_tone_stream(880.0, 0.09)
	beep_player.volume_db = -16.0
	add_child(beep_player)

func _process(delta: float) -> void:
	bird_timer -= delta
	if bird_timer <= 0.0:
		bird_player.pitch_scale = rng.randf_range(0.88, 1.16)
		bird_player.play()
		bird_timer = rng.randf_range(8.0, 17.0)

func play_footstep() -> void:
	if step_player:
		step_player.pitch_scale = rng.randf_range(0.88, 1.12)
		step_player.play()

func play_jump() -> void:
	if jump_player:
		jump_player.play()

func play_alert() -> void:
	if alert_player:
		alert_player.play()

func play_card_beep() -> void:
	if beep_player:
		beep_player.play()

func _make_noise_stream(duration: float, smoothing: float, gain: float, should_loop: bool, seed_value: int) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(float(rate) * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed_value
	var filtered := 0.0
	for frame in range(frames):
		var white := local_rng.randf_range(-1.0, 1.0)
		filtered = lerpf(filtered, white, smoothing)
		var t := float(frame) / float(rate)
		var breeze := sin(t * 0.73) * 0.12 + sin(t * 1.17 + 1.8) * 0.07
		var edge := minf(1.0, minf(float(frame) / 900.0, float(frames - frame) / 900.0))
		var sample := clampf((filtered * 0.24 + breeze) * gain * edge, -0.95, 0.95)
		bytes.encode_s16(frame * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if should_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	return stream

func _make_engine_loop() -> AudioStreamWAV:
	var rate := 22050
	var duration := 2.0
	var frames := int(float(rate) * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for frame in range(frames):
		var t := float(frame) / float(rate)
		var hum := sin(TAU * 58.0 * t) * 0.055 + sin(TAU * 116.0 * t) * 0.018
		bytes.encode_s16(frame * 2, int(hum * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream

func _make_bird_call_stream() -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.48
	var frames := int(float(rate) * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var phase := 0.0
	for frame in range(frames):
		var t := float(frame) / float(rate)
		var frequency := 1500.0 + 620.0 * sin(TAU * 2.4 * t)
		phase += TAU * frequency / float(rate)
		var envelope := sin(PI * float(frame) / float(frames))
		var sample := sin(phase) * envelope * 0.13
		bytes.encode_s16(frame * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _make_tone_stream(frequency: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(float(rate) * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for frame in range(frames):
		var t := float(frame) / float(rate)
		var envelope := pow(1.0 - float(frame) / float(frames), 2.0)
		var sample := sin(TAU * frequency * t) * envelope * 0.22
		bytes.encode_s16(frame * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream
