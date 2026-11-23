extends SceneTree

## Pause-menu settings coverage: mouse sensitivity and inversion must change
## camera look, remapped bindings must reach InputMap, and the values must be
## written to user://settings.cfg.

const GameSettings := preload("res://scripts/game_settings.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var old_sensitivity := GameSettings.mouse_sensitivity
	var old_invert := GameSettings.invert_y
	var old_bindings := GameSettings.bindings.duplicate()

	# Look direction: mouse right turns right (negative yaw). Mouse down looks
	# down by default and up when inverted.
	GameSettings.mouse_sensitivity = 1.0
	GameSettings.invert_y = false
	var rig: Node3D = CameraRig.new()
	rig.yaw = 0.0
	rig.pitch = 0.0
	rig.apply_look(Vector2(100.0, 100.0))
	var normal_yaw: float = rig.yaw
	var normal_pitch: float = rig.pitch
	_check(normal_yaw < 0.0, "mouse right turns the camera right")
	_check(normal_pitch < 0.0, "mouse down looks down by default")

	rig.yaw = 0.0
	rig.pitch = 0.0
	GameSettings.mouse_sensitivity = 2.0
	rig.apply_look(Vector2(100.0, 100.0))
	_check(absf(rig.yaw) > absf(normal_yaw) * 1.8, "higher sensitivity turns further for the same movement")

	rig.yaw = 0.0
	rig.pitch = 0.0
	GameSettings.invert_y = true
	rig.apply_look(Vector2(100.0, 100.0))
	_check(rig.pitch > 0.0, "invert Y flips vertical look")

	# Remapping: assign Q to interact, then confirm InputMap carries it.
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	GameSettings.set_binding("interact", key)
	var mapped := false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Q:
			mapped = true
	_check(mapped, "a remapped key is applied to InputMap")
	_check(GameSettings.binding_text("interact") == "Q", "the controls screen shows the new binding")

	# Persistence: write, then read the config back from disk.
	GameSettings.mouse_sensitivity = 1.65
	GameSettings.invert_y = true
	GameSettings.music_db = -6.0
	GameSettings.sfx_db = -3.0
	GameSettings.save_settings()
	var config := ConfigFile.new()
	_check(config.load(GameSettings.PATH) == OK, "settings file loads")
	_check(is_equal_approx(float(config.get_value("input", "mouse_sensitivity", 0.0)), 1.65), "mouse sensitivity persists")
	_check(bool(config.get_value("input", "invert_y", false)), "invert Y persists")
	_check(is_equal_approx(float(config.get_value("audio", "music_db", 0.0)), -6.0), "music volume persists")
	_check(is_equal_approx(float(config.get_value("audio", "sfx_db", 0.0)), -3.0), "SFX volume persists")
	var saved_bindings: Dictionary = config.get_value("input", "bindings", {})
	_check(saved_bindings.has("interact"), "remapped bindings persist")

	# Restore the developer's pre-test values rather than leaving test state.
	GameSettings.mouse_sensitivity = old_sensitivity
	GameSettings.invert_y = old_invert
	GameSettings.bindings = old_bindings
	GameSettings.save_settings()

	rig.free()
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
