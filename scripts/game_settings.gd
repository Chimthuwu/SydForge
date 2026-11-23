extends Node

## Persisted player settings shared by the pause menu and the lighting systems.
## Kept as plain static state because the pause overlay is created and freed on
## demand; it must not be the only owner of the values.

const PATH := "user://settings.cfg"

static var master_db: float = 0.0
static var music_db: float = 0.0
static var sfx_db: float = 0.0
static var mouse_sensitivity: float = 1.0
static var invert_y: bool = false
static var headlight_budget: int = 6
static var fullscreen: bool = false
## action -> { type: "key"/"mouse", code: int, location: int }
static var bindings: Dictionary = {}

static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	master_db = clampf(float(config.get_value("audio", "master_db", master_db)), -40.0, 12.0)
	music_db = clampf(float(config.get_value("audio", "music_db", music_db)), -40.0, 6.0)
	sfx_db = clampf(float(config.get_value("audio", "sfx_db", sfx_db)), -40.0, 6.0)
	mouse_sensitivity = clampf(float(config.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 3.0)
	invert_y = bool(config.get_value("input", "invert_y", invert_y))
	headlight_budget = clampi(int(config.get_value("video", "headlight_budget", headlight_budget)), 0, 12)
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	var saved_bindings: Variant = config.get_value("input", "bindings", {})
	if typeof(saved_bindings) == TYPE_DICTIONARY:
		bindings = saved_bindings


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_db", master_db)
	config.set_value("audio", "music_db", music_db)
	config.set_value("audio", "sfx_db", sfx_db)
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("input", "bindings", bindings)
	config.set_value("video", "headlight_budget", headlight_budget)
	config.set_value("video", "fullscreen", fullscreen)
	config.save(PATH)


static func apply() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, master_db)
	_set_bus("Music", music_db)
	# SFX is one player-facing control over every non-music category; each bus
	# keeps its own authored base trim.
	for bus_name in ["Weapons", "Movement", "Vehicles", "Environment", "NPC", "UI"]:
		_set_bus(bus_name, sfx_db)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


static func _set_bus(bus_name: String, offset_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	# Offsets are relative to the bus's authored trim in AudioDirector. The
	# default zero offset therefore leaves the existing mix untouched.
	if bus_name == "Music":
		AudioServer.set_bus_volume_db(index, -9.0 + offset_db)
	else:
		AudioServer.set_bus_volume_db(index, offset_db)


## Re-apply saved bindings after the district has created its InputMap actions.
static func apply_bindings() -> void:
	for action: String in bindings.keys():
		if not InputMap.has_action(action):
			continue
		var binding: Dictionary = bindings[action]
		var event: InputEvent = _event_from_binding(binding)
		if event == null:
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


static func set_binding(action: String, event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		bindings[action] = {
			"type": "key",
			"code": int(key.physical_keycode),
			"location": int(key.location),
		}
	elif event is InputEventMouseButton:
		bindings[action] = {"type": "mouse", "code": int((event as InputEventMouseButton).button_index)}
	else:
		return
	apply_bindings()
	save_settings()


static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.physical_keycode != 0:
				var text := OS.get_keycode_string(key.physical_keycode)
				if key.location == KEY_LOCATION_RIGHT:
					text = "RIGHT " + text
				return text
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			return "MOUSE %d" % mouse.button_index
	return "—"


static func _event_from_binding(binding: Dictionary) -> InputEvent:
	if str(binding.get("type", "")) == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(binding.get("code", 0))
		key.location = int(binding.get("location", KEY_LOCATION_UNSPECIFIED))
		return key
	if str(binding.get("type", "")) == "mouse":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(binding.get("code", MOUSE_BUTTON_LEFT))
		return mouse
	return null
