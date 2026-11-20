class_name AmbientAudioDirector
extends Node

## Layered, shared Sydney soundscape.
##
## A fixed set of looping beds (never one source per NPC or car) is crossfaded
## from the current district, activity profile and weather. All beds are baked
## once into static cached streams. One-shot, genuinely spatial sounds (sirens,
## impacts, engines, footsteps) stay with AudioDirector / the actor itself.

signal layer_level_changed(layer: String, level_db: float)

const LAYERS := ["traffic", "crowd", "birds", "wind", "rain", "water", "construction", "nightlife"]
const SAMPLE_RATE := 22050
const DEFAULT_LEVELS := {
	"traffic": -30.0, "crowd": -34.0, "birds": -42.0, "wind": -36.0,
	"rain": -45.0, "water": -45.0, "construction": -45.0, "nightlife": -45.0,
}

static var _stream_cache: Dictionary = {}

var player_ref: Node3D
var _voices: Dictionary = {}
var _current_db: Dictionary = {}
var _target_db: Dictionary = {}
var _district: String = ""
var _profile: Dictionary = {}
var _rain: float = 0.0
var _night: float = 0.0
var _update_accum: float = 0.0


func _ready() -> void:
	add_to_group("ambient_audio")
	for layer in LAYERS:
		var voice := AudioStreamPlayer.new()
		voice.name = "Ambient_" + layer.capitalize()
		voice.bus = "NPC" if layer in ["crowd", "birds", "nightlife"] else "Environment"
		voice.stream = _bake_cached(layer)
		voice.volume_db = -60.0
		voice.autoplay = false
		add_child(voice)
		_voices[layer] = voice
		_current_db[layer] = -60.0
		_target_db[layer] = -60.0
	_connect_world()


func _connect_world() -> void:
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm: Node = time_mgrs[0]
		if tm.has_signal("night_mode_changed") and not tm.is_connected("night_mode_changed", _on_night_mode_changed):
			tm.connect("night_mode_changed", _on_night_mode_changed)
	_on_night_mode_changed(_night > 0.5)
	var weather_mgrs := get_tree().get_nodes_in_group("weather_managers")
	if not weather_mgrs.is_empty():
		var wm: Node = weather_mgrs[0]
		if wm.has_signal("rain_intensity_changed") and not wm.is_connected("rain_intensity_changed", _on_rain_changed):
			wm.connect("rain_intensity_changed", _on_rain_changed)


func setup(player: Node3D) -> void:
	player_ref = player
	_recalculate()


func _on_night_mode_changed(is_night: bool) -> void:
	_night = 1.0 if is_night else 0.0
	_recalculate()


func _on_rain_changed(intensity: float) -> void:
	_rain = clampf(intensity, 0.0, 1.0)
	_recalculate()


## Called by WorldSimulationDirector when the daily activity profile changes.
func apply_activity_profile(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	_recalculate()


func set_district(district_id: String) -> void:
	_district = district_id
	_recalculate()


func _recalculate() -> void:
	var base: Dictionary = _profile.get("audio", {})
	for layer in LAYERS:
		var level := float(base.get(layer, DEFAULT_LEVELS.get(layer, -45.0)))
		# Locality: harbourfront carries ferries and water; construction follows
		# the CBD and inner-west; cafes/pub beds sit under entertainment venues.
		match layer:
			"water":
				if _district in ["circular-quay", "barangaroo", "the-rocks", "darling-quarter", "millers-point", "pyrmont"]:
					level = -27.0
			"construction":
				if _district in ["cbd-core", "town-hall", "haymarket", "central", "inner-west"]:
					level += 5.0
			"nightlife":
				level += 6.0 if _night > 0.5 else -10.0
				if _district in ["kings-cross", "darling-quarter", "haymarket", "surry-hills"]:
					level += 5.0
			"birds":
				level -= 8.0 * _night
			"traffic":
				level += 4.0 * (1.0 - _night)
		# Rain masks birds/wind and brings the rain bed forward.
		if layer == "rain":
			level = -45.0 + 26.0 * _rain
		elif layer in ["birds", "wind"]:
			level -= 10.0 * _rain
		_target_db[layer] = clampf(level, -60.0, -12.0)
	_recalculate_immediate_if_unstarted()


func _recalculate_immediate_if_unstarted() -> void:
	for layer in LAYERS:
		var voice: AudioStreamPlayer = _voices.get(layer)
		if voice == null:
			continue
		if not voice.playing:
			voice.volume_db = _target_db[layer]
			_current_db[layer] = _target_db[layer]
			voice.play()
			layer_level_changed.emit(layer, _target_db[layer])


func _process(delta: float) -> void:
	_update_accum += delta
	if _update_accum < 0.1:
		return
	var step := _update_accum
	_update_accum = 0.0
	for layer in LAYERS:
		var voice: AudioStreamPlayer = _voices.get(layer)
		if voice == null:
			continue
		var next := move_toward(float(_current_db.get(layer, -60.0)), float(_target_db.get(layer, -60.0)), 2.5 * step)
		if not is_equal_approx(next, _current_db[layer]):
			_current_db[layer] = next
			voice.volume_db = next


func layer_level(layer: String) -> float:
	return float(_current_db.get(layer, -60.0))


func voice_count() -> int:
	var count := 0
	for layer in LAYERS:
		var voice: AudioStreamPlayer = _voices.get(layer)
		if voice != null and voice.playing:
			count += 1
	return count


## --------------------------------------------------------- stream bake --
func _bake_cached(layer: String) -> AudioStreamWAV:
	if _stream_cache.has(layer):
		return _stream_cache[layer]
	var stream := _bake_bed(layer)
	_stream_cache[layer] = stream
	return stream


func _bake_bed(layer: String) -> AudioStreamWAV:
	var seconds := 3.0
	var count := int(SAMPLE_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + layer.hash()
	var low := 0.0
	var mid := 0.0
	var chirp_phase := 0.0
	var pulse := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.02 if layer == "wind" else 0.12)
		mid = lerpf(mid, noise, 0.25)
		var value := 0.0
		match layer:
			"traffic":
				var swell := 0.55 + 0.25 * sin(TAU * 0.13 * t) + 0.12 * sin(TAU * 0.31 * t + 1.7)
				value = (low * 0.75 + mid * 0.25) * swell
			"crowd":
				var murmur := 0.5 + 0.5 * sin(TAU * 1.7 * t) * sin(TAU * 0.43 * t)
				value = (mid * 0.65 + low * 0.35) * murmur
				if fmod(t, 1.7) < 0.06:
					value += sin(TAU * 420.0 * t) * 0.05
			"birds":
				chirp_phase += 0.0
				var window := fmod(t, 2.7)
				if window < 0.18:
					var f := 1800.0 + 900.0 * sin(window * 22.0)
					value = sin(TAU * f * t) * sin(window / 0.18 * PI) * 0.35
				elif window < 0.42:
					value = sin(TAU * 2400.0 * t) * 0.16 * (1.0 - (window - 0.18) / 0.24)
			"wind":
				value = low * (0.7 + 0.3 * sin(TAU * 0.09 * t))
			"rain":
				value = (noise * 0.55 + mid * 0.45) * 0.7
			"water":
				value = (low * 0.8 + noise * 0.2) * (0.6 + 0.4 * sin(TAU * 0.17 * t))
			"construction":
				var engine := low * 0.6 + mid * 0.2
				pulse = maxf(0.0, pulse - 0.9 / SAMPLE_RATE)
				if fmod(t, 2.2) < 0.02:
					pulse = 1.0
				value = engine + sin(TAU * 210.0 * t) * pulse * exp(-fmod(t, 2.2) * 12.0) * 0.25
			"nightlife":
				var beat := pow(maxf(0.0, sin(TAU * 1.9 * t)), 6.0)
				value = low * 0.5 + sin(TAU * 78.0 * t) * beat * 0.35 + mid * 0.2
		value = clampf(value, -1.0, 1.0)
		var int_val := int(value * 0.5 * 32767.0)
		data.encode_s16(i * 2, int_val)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream
