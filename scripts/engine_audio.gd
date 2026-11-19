class_name EngineAudio
extends Node3D

## Reusable vehicle audio driven by real vehicle state: RPM, throttle, speed and
## lateral slip. One engine loop, one tyre-slip loop and one road-noise loop per
## vehicle, all on the Vehicles bus with 3D attenuation.
##
## Profiles are deliberately different (cylinder count/character), not one
## sample repitched for every vehicle. AI traffic uses a much lower profile
## volume and shorter max distance so a busy street does not become a wall of
## engine noise.

const PROFILES := {
	"car": {
		"base_hz": 46.0, "pitch_min": 0.78, "pitch_max": 1.72,
		"volume_db": -18.0, "harmonics": [1.0, 0.42, 0.20, 0.10],
		"noise": 0.05, "character": 0.0,
	},
	"sports": {
		"base_hz": 62.0, "pitch_min": 0.72, "pitch_max": 2.20,
		"volume_db": -17.0, "harmonics": [1.0, 0.55, 0.34, 0.18],
		"noise": 0.04, "character": 0.2,
	},
	"suv": {
		"base_hz": 38.0, "pitch_min": 0.80, "pitch_max": 1.55,
		"volume_db": -18.0, "harmonics": [1.0, 0.38, 0.18, 0.08],
		"noise": 0.06, "character": -0.1,
	},
	"ute": {
		"base_hz": 42.0, "pitch_min": 0.78, "pitch_max": 1.62,
		"volume_db": -18.0, "harmonics": [1.0, 0.48, 0.24, 0.12],
		"noise": 0.06, "character": 0.05,
	},
	"motorbike": {
		"base_hz": 74.0, "pitch_min": 0.85, "pitch_max": 2.45,
		"volume_db": -19.0, "harmonics": [1.0, 0.62, 0.44, 0.26],
		"noise": 0.05, "character": 0.35,
	},
	"truck": {
		"base_hz": 28.0, "pitch_min": 0.76, "pitch_max": 1.42,
		"volume_db": -17.0, "harmonics": [1.0, 0.55, 0.30, 0.20],
		"noise": 0.08, "character": -0.3,
	},
	"bus": {
		"base_hz": 24.0, "pitch_min": 0.74, "pitch_max": 1.35,
		"volume_db": -16.0, "harmonics": [1.0, 0.50, 0.28, 0.22],
		"noise": 0.09, "character": -0.35,
	},
}

const LOOP_SECONDS := 1.0
const SAMPLE_RATE := 22050

## Streams are identical for every vehicle of a class, so bake once and share.
## Previously each spawned car re-synthesised four streams in GDScript (~50 ms).
static var _shared_streams: Dictionary = {}

var profile_id: String = "car"
var ai_mode: bool = false
var engine: AudioStreamPlayer3D
var tyre: AudioStreamPlayer3D
var road: AudioStreamPlayer3D
var horn_voice: AudioStreamPlayer3D

var engine_rpm: float = 0.0
var audible: bool = true
var _horn_time: float = 0.0
var _engine_volume: float = -80.0
var _peak_volume: float = -80.0
var _profile: Dictionary


func _ready() -> void:
	_profile = PROFILES.get(profile_id, PROFILES["car"])
	engine = _make_loop_player("EngineLoop", _shared_engine())
	tyre = _make_loop_player("TyreSlip", _shared_noise("tyre", 0.55, 2600.0, 1337))
	road = _make_loop_player("RoadNoise", _shared_noise("road", 0.22, 900.0, 4411))
	road.volume_db = -80.0
	tyre.volume_db = -80.0
	engine.volume_db = -80.0
	# Loops are started only while the vehicle is audible. AI traffic spends
	# most of its life silent, and 120 permanently-playing inaudible loops cost
	# audio mixing for no audible result.
	horn_voice = AudioStreamPlayer3D.new()
	horn_voice.name = "Horn"
	horn_voice.bus = "Vehicles"
	horn_voice.stream = _shared_horn()
	horn_voice.volume_db = -13.0
	horn_voice.unit_size = 10.0
	horn_voice.max_distance = 70.0
	add_child(horn_voice)


func _shared_engine() -> AudioStreamWAV:
	var key := "engine:%s" % profile_id
	var stream: AudioStreamWAV = _shared_streams.get(key)
	if stream == null:
		stream = _bake_engine_loop(_profile)
		_shared_streams[key] = stream
	return stream


func _shared_noise(key: String, level: float, cutoff_bias: float, seed_value: int) -> AudioStreamWAV:
	var stream: AudioStreamWAV = _shared_streams.get(key)
	if stream == null:
		stream = _bake_noise_loop(level, cutoff_bias, seed_value)
		_shared_streams[key] = stream
	return stream


func _shared_horn() -> AudioStreamWAV:
	var stream: AudioStreamWAV = _shared_streams.get("horn")
	if stream == null:
		stream = _bake_horn()
		_shared_streams["horn"] = stream
	return stream


func _make_loop_player(node_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer3D:
	var player_voice := AudioStreamPlayer3D.new()
	player_voice.name = node_name
	player_voice.bus = "Vehicles"
	player_voice.stream = stream
	player_voice.unit_size = 8.0
	player_voice.max_distance = 55.0
	player_voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player_voice)
	return player_voice


func _bake_engine_loop(profile: Dictionary) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * LOOP_SECONDS)
	var base_hz := float(profile["base_hz"])
	# Snap the fundamental to whole cycles in the loop so it wraps seamlessly.
	var cycles := maxf(1.0, round(base_hz * LOOP_SECONDS))
	var hz := cycles / LOOP_SECONDS
	var harmonics: Array = profile["harmonics"]
	var noise_amount := float(profile["noise"])
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2201 + profile_id.hash()
	var low := 0.0
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var phase := TAU * hz * time
		var value := 0.0
		for harmonic_index in harmonics.size():
			var multiple := float(harmonic_index + 1)
			# Slight detune on upper harmonics gives the mechanical beat.
			var detune := 1.0 + float(harmonic_index) * 0.0015
			value += sin(phase * multiple * detune) * float(harmonics[harmonic_index])
		# Sub-thump every other crank rotation.
		value += sin(phase * 0.5) * 0.22
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
		value += low * noise_amount
		# Combustion irregularity, not a pure synthesiser tone.
		value *= 1.0 + sin(phase * 0.25) * 0.06
		samples[index] = tanh(value * 0.85)
	samples = _crossfade_loop(samples, 0.05)
	return _to_stream(samples, 0.52)


func _bake_noise_loop(level: float, cutoff_bias: float, seed_value: int) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * LOOP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var low := 0.0
	var smooth := 0.12 if cutoff_bias > 1500.0 else 0.3
	for index in count:
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, smooth)
		samples[index] = low * level
	samples = _crossfade_loop(samples, 0.08)
	return _to_stream(samples, 0.45)


func _bake_horn() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.55)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var envelope := minf(1.0, time * 40.0) * clampf((0.55 - time) * 12.0, 0.0, 1.0)
		var value := sin(TAU * 392.0 * time) * 0.55 + sin(TAU * 494.0 * time) * 0.45
		value += sin(TAU * 784.0 * time) * 0.12
		samples[index] = tanh(value) * envelope
	return _to_stream(samples, 0.4)


func _crossfade_loop(samples: PackedFloat32Array, fade_seconds: float) -> PackedFloat32Array:
	var fade := int(SAMPLE_RATE * fade_seconds)
	for index in fade:
		var t := float(index) / float(maxi(fade, 1))
		var tail := samples.size() - fade + index
		var blended := lerpf(samples[tail], samples[index], t)
		samples[index] = blended
		samples[tail] = blended
	return samples


func _to_stream(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index in samples.size():
		data.encode_s16(index * 2, int(clampf(samples[index] * peak, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	return stream


## RPM model with gear steps: the pitch climbs inside a gear, drops on the
## change, then climbs again. Enough for an arcade V8 feel without a simulator.
static func gear_rpm(speed: float, top_speed: float) -> float:
	var normalised := clampf(absf(speed) / maxf(top_speed, 1.0), 0.0, 1.15)
	var boundaries := [0.0, 0.17, 0.34, 0.55, 0.78, 1.02]
	var gear := 0
	for index in range(1, boundaries.size()):
		if normalised > float(boundaries[index]):
			gear = index
	var low := float(boundaries[gear])
	var high := float(boundaries[mini(gear + 1, boundaries.size() - 1)])
	var within := clampf((normalised - low) / maxf(high - low, 0.001), 0.0, 1.0)
	return clampf(0.28 + within * 0.72, 0.0, 1.0)


func update_audio(delta: float, speed: float, rpm: float, throttle: float, slip: float, airborne: bool) -> void:
	engine_rpm = clampf(rpm, 0.0, 1.0)
	_horn_time = maxf(0.0, _horn_time - delta)
	if _horn_time <= 0.0 and horn_voice.playing:
		horn_voice.stop()
	if not audible:
		_fade_to(-80.0, delta * 3.0)
		if _engine_volume < -70.0:
			_stop_loops()
		return
	var profile := _profile
	var base_volume := float(profile["volume_db"])
	if ai_mode:
		base_volume -= 9.0
	var load := clampf(throttle * 0.55 + engine_rpm * 0.45, 0.0, 1.0)
	var speed_ratio := clampf(absf(speed) / 22.0, 0.0, 1.0)
	var target_pitch := lerpf(
		float(profile["pitch_min"]), float(profile["pitch_max"]), engine_rpm
	)
	engine.pitch_scale = lerpf(engine.pitch_scale, target_pitch, 1.0 - exp(-9.0 * delta))
	_peak_volume = base_volume + load * 2.2 + speed_ratio * 1.4
	_engine_volume = lerpf(_engine_volume, _peak_volume, 1.0 - exp(-5.0 * delta))
	engine.volume_db = _engine_volume

	var slip_target := -80.0
	if slip > 3.0 and not airborne:
		slip_target = clampf(-24.0 + slip * 0.55, -30.0, -12.0)
	tyre.volume_db = lerpf(tyre.volume_db, slip_target, 1.0 - exp(-8.0 * delta))
	tyre.pitch_scale = clampf(0.85 + slip * 0.025, 0.8, 1.5)

	var road_target := -80.0
	if absf(speed) > 2.0 and not airborne:
		road_target = base_volume - 2.0 + speed_ratio * 2.0
	road.volume_db = lerpf(road.volume_db, road_target, 1.0 - exp(-4.0 * delta))


func honk() -> void:
	if not horn_voice.playing:
		horn_voice.play()
	_horn_time = 0.55


func impact(strength: float) -> void:
	if strength < 3.0:
		return
	# Reuse the horn voice for a short metallic collision report.
	horn_voice.stream = _bake_collision()
	horn_voice.volume_db = clampf(-24.0 + strength * 0.5, -24.0, -10.0)
	horn_voice.play()
	_horn_time = 0.0


func _bake_collision() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.28)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	var low := 0.0
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.15)
		var value := low * exp(-time * 18.0) * 0.7
		value += (noise - low) * exp(-time * 65.0) * 0.4
		samples[index] = tanh(value)
	return _to_stream(samples, 0.55)


func set_audible(value: bool) -> void:
	audible = value
	if value:
		_start_loops()


func _start_loops() -> void:
	for voice in [engine, tyre, road]:
		if voice != null and not voice.playing:
			voice.play()


func _stop_loops() -> void:
	for voice in [engine, tyre, road]:
		if voice != null and voice.playing:
			voice.stop()


func _fade_to(target_db: float, rate: float) -> void:
	_engine_volume = lerpf(_engine_volume, target_db, clampf(rate, 0.0, 1.0))
	engine.volume_db = _engine_volume
	tyre.volume_db = lerpf(tyre.volume_db, -80.0, clampf(rate, 0.0, 1.0))
	road.volume_db = lerpf(road.volume_db, -80.0, clampf(rate, 0.0, 1.0))


static func profile_for_class(vehicle_class: int) -> String:
	match vehicle_class:
		1:
			return "sports"
		3:
			return "suv"
		4:
			return "ute"
		5:
			return "ute"
		6, 7, 8:
			return "truck"
		10:
			return "bus"
		11, 12:
			return "motorbike"
		_:
			return "car"
