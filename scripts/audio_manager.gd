extends Node

## Global audio director: bus mix, pooled weapon voices and procedural combat
## sounds.
##
## The old gunshot path built a fresh AudioStreamPlayer at 0 dB for every shot,
## at sample peaks near full scale. That is why automatic fire clipped and
## dominated the mix. Every weapon now has a measured profile (peak amplitude,
## voice cap, 2D level) and shares a compressed, limited Weapons bus.

const BUS_LAYOUT := {
	"Music": -9.0,
	"Weapons": -6.0,
	"Movement": -11.0,
	"Vehicles": -7.0,
	"Environment": -13.0,
	"UI": -8.0,
}

## peak: normalised sample peak of the generated stream.
## volume_db: playback level for the player's own weapon (2D).
## world_db: level for the optional 3D report.
## min_gap_ms: hard de-duplication window so one key press cannot stack voices.
const WEAPON_PROFILES := {
	"pistol": {
		"peak": 0.58, "volume_db": -14.0, "world_db": -20.0,
		"min_gap_ms": 45, "duration": 0.34, "body_hz": 96.0,
		"body_decay": 17.0, "crack_decay": 70.0, "tail": 0.20,
	},
	"smg": {
		"peak": 0.48, "volume_db": -16.0, "world_db": -22.0,
		"min_gap_ms": 32, "duration": 0.22, "body_hz": 118.0,
		"body_decay": 26.0, "crack_decay": 92.0, "tail": 0.10,
	},
	"shotgun": {
		"peak": 0.66, "volume_db": -12.5, "world_db": -19.0,
		"min_gap_ms": 70, "duration": 0.56, "body_hz": 58.0,
		"body_decay": 9.0, "crack_decay": 42.0, "tail": 0.32,
	},
}

const IMPACT_KINDS := ["concrete", "metal", "flesh"]

var _streams: Dictionary = {}
var _pools: Dictionary = {}
var _pool_cursor: Dictionary = {}
var _last_shot_ms: Dictionary = {}
var _world_pools: Dictionary = {}
var _world_cursor: Dictionary = {}
var _impact_streams: Dictionary = {}

var master_volume_db: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_weapon_streams()
	_build_impact_streams()
	_apply_mix()


func _ensure_buses() -> void:
	# Master already exists. Add the game's controlled groups behind it.
	for bus_name in BUS_LAYOUT:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	if AudioServer.get_bus_effect_count(0) == 0:
		# A single limiter on Master catches the rare overlap of gunfire,
		# engines and impacts without flattening normal play.
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -6.0
		limiter.soft_clip_db = -2.0
		limiter.soft_clip_ratio = 2.0
		AudioServer.add_bus_effect(0, limiter)
	var weapons := AudioServer.get_bus_index("Weapons")
	if weapons != -1 and AudioServer.get_bus_effect_count(weapons) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -16.0
		compressor.ratio = 3.0
		compressor.gain = -1.0
		AudioServer.add_bus_effect(weapons, compressor)


func _apply_mix() -> void:
	AudioServer.set_bus_volume_db(0, master_volume_db)
	for bus_name in BUS_LAYOUT:
		var index := AudioServer.get_bus_index(bus_name)
		if index != -1:
			AudioServer.set_bus_volume_db(index, float(BUS_LAYOUT[bus_name]))


## ---------------------------------------------------------------- weapons --
func _build_weapon_streams() -> void:
	for kind in WEAPON_PROFILES:
		var profile: Dictionary = WEAPON_PROFILES[kind]
		_streams[kind] = _bake_gunshot(kind, profile)
		var pool: Array[AudioStreamPlayer] = []
		# Three voices per weapon: automatic fire stays full but can never
		# stack into a wall of identical shots.
		for voice in 3:
			var player_voice := AudioStreamPlayer.new()
			player_voice.name = "Weapon_%s_%d" % [kind, voice]
			player_voice.bus = "Weapons"
			player_voice.stream = _streams[kind]
			player_voice.volume_db = float(profile["volume_db"])
			add_child(player_voice)
			pool.append(player_voice)
		_pools[kind] = pool
		_pool_cursor[kind] = 0
		_last_shot_ms[kind] = -1000
		# A second, very low 3D report gives distance to the world without the
		# player's own shot ever becoming a stereo blast.
		var world_pool: Array[AudioStreamPlayer3D] = []
		for voice in 3:
			var world_voice := AudioStreamPlayer3D.new()
			world_voice.name = "WeaponWorld_%s_%d" % [kind, voice]
			world_voice.bus = "Weapons"
			world_voice.stream = _streams[kind]
			world_voice.volume_db = float(profile["world_db"])
			world_voice.unit_size = 7.0
			world_voice.max_distance = 90.0
			world_voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			add_child(world_voice)
			world_pool.append(world_voice)
		_world_pools[kind] = world_pool
		_world_cursor[kind] = 0


func _bake_gunshot(kind: String, profile: Dictionary) -> AudioStreamWAV:
	const SAMPLE_RATE := 44100
	var duration := float(profile["duration"])
	var count := int(SAMPLE_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717 + kind.hash()
	var low := 0.0
	var body_hz := float(profile["body_hz"])
	var body_decay := float(profile["body_decay"])
	var crack_decay := float(profile["crack_decay"])
	var tail_amount := float(profile["tail"])
	var energy := 0.0
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.10)
		var high := noise - low
		# Three intentional layers: supersonic crack, chest body, action clack.
		var crack := high * exp(-time * crack_decay)
		var body := sin(TAU * (body_hz - minf(time * 70.0, 40.0)) * time) * exp(-time * body_decay)
		var mid := low * exp(-time * 21.0)
		var tail := low * exp(-time * 6.5) * tail_amount
		var action_time := 0.048
		var action := 0.0
		if time >= action_time:
			var after := time - action_time
			action = sin(TAU * 1150.0 * after) * exp(-after * 95.0) * 0.12
			action += sin(TAU * 720.0 * after) * exp(-after * 70.0) * 0.08
		var value := crack * 0.62 + body * 0.44 + mid * 0.42 + tail * 0.65 + action
		# Soft saturation prevents the harsh digital peaks of the old stream.
		value = tanh(value * 1.15)
		samples[index] = value
		energy = maxf(energy, absf(value))
	var normalise := 1.0
	if energy > 0.0001:
		normalise = float(profile["peak"]) / energy
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in count:
		data.encode_s16(index * 2, int(clampf(samples[index] * normalise, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream


func play_weapon(kind: String = "pistol") -> void:
	if not WEAPON_PROFILES.has(kind):
		kind = "pistol"
	var now := Time.get_ticks_msec()
	var profile: Dictionary = WEAPON_PROFILES[kind]
	if now - int(_last_shot_ms[kind]) < int(profile["min_gap_ms"]):
		return
	_last_shot_ms[kind] = now
	var pool: Array = _pools[kind]
	var cursor := int(_pool_cursor[kind])
	var voice: AudioStreamPlayer = pool[cursor]
	_pool_cursor[kind] = (cursor + 1) % pool.size()
	voice.pitch_scale = randf_range(0.965, 1.035)
	if voice.playing:
		voice.stop()
	voice.play()


func play_weapon_world(kind: String, world_position: Vector3) -> void:
	if not _world_pools.has(kind):
		return
	var pool: Array = _world_pools[kind]
	var cursor := int(_world_cursor[kind])
	var voice: AudioStreamPlayer3D = pool[cursor]
	_world_cursor[kind] = (cursor + 1) % pool.size()
	voice.global_position = world_position + Vector3.UP * 1.3
	voice.pitch_scale = randf_range(0.95, 1.04)
	voice.play()


## ------------------------------------------------ impact / mechanical bed --
func _build_impact_streams() -> void:
	for kind in IMPACT_KINDS:
		_impact_streams[kind] = _bake_impact(kind)
	var pool: Array[AudioStreamPlayer3D] = []
	for voice in 8:
		var player_voice := AudioStreamPlayer3D.new()
		player_voice.name = "Impact_%d" % voice
		player_voice.bus = "Weapons"
		player_voice.volume_db = -19.0
		player_voice.unit_size = 4.0
		player_voice.max_distance = 40.0
		add_child(player_voice)
		pool.append(player_voice)
	_world_pools["impact"] = pool
	_world_cursor["impact"] = 0


func _bake_impact(kind: String) -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	var duration := 0.22 if kind == "metal" else 0.16
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + kind.hash()
	var low := 0.0
	var peak := 0.0
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		var time := float(index) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.22 if kind == "flesh" else 0.5)
		var value := 0.0
		match kind:
			"metal":
				value = (noise - low) * exp(-time * 50.0) * 0.55
				value += sin(TAU * 1650.0 * time) * exp(-time * 26.0) * 0.22
				value += sin(TAU * 980.0 * time) * exp(-time * 19.0) * 0.16
			"flesh":
				value = low * exp(-time * 28.0) * 0.7
				value += sin(TAU * 92.0 * time) * exp(-time * 24.0) * 0.3
			_:
				value = (noise - low) * exp(-time * 55.0) * 0.38
				value += low * exp(-time * 30.0) * 0.3
				value += sin(TAU * 140.0 * time) * exp(-time * 30.0) * 0.12
		value = tanh(value)
		samples[index] = value
		peak = maxf(peak, absf(value))
	var normalise := 0.4 / maxf(peak, 0.001)
	for index in count:
		data.encode_s16(index * 2, int(clampf(samples[index] * normalise, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream


func play_impact(kind: String, world_position: Vector3) -> void:
	if not _impact_streams.has(kind):
		kind = "concrete"
	var pool: Array = _world_pools["impact"]
	var cursor := int(_world_cursor["impact"])
	var voice: AudioStreamPlayer3D = pool[cursor]
	_world_cursor["impact"] = (cursor + 1) % pool.size()
	voice.stream = _impact_streams[kind]
	voice.global_position = world_position
	voice.pitch_scale = randf_range(0.9, 1.1)
	voice.play()


## ---------------------------------------------------------------- settings --
## Master volume in dB, clamped to a hearing-safe range. Used by the HUD
## shortcut so the mix can be adjusted without editing project files.
func set_master_volume(db: float) -> void:
	master_volume_db = clampf(db, -40.0, 3.0)
	AudioServer.set_bus_volume_db(0, master_volume_db)


func adjust_master_volume(delta_db: float) -> float:
	set_master_volume(master_volume_db + delta_db)
	return master_volume_db


func bus_volume(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return -80.0
	return AudioServer.get_bus_volume_db(index)


func weapon_peak(kind: String) -> float:
	return float(WEAPON_PROFILES.get(kind, {}).get("peak", 0.0))


func active_weapon_voices() -> int:
	var total := 0
	for kind in _pools:
		for voice: AudioStreamPlayer in _pools[kind]:
			if voice.playing:
				total += 1
	return total
