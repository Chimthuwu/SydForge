class_name DevTools
extends Node

## Bug-reporting aid: F8 toggles a live "where am I" coordinate readout;
## F9 opens a numbered list of known landmarks (stations, bridge ends,
## vehicle spawns) to teleport to instantly, so a reported glitch can be
## pinned to an exact x/y/z instead of a screenshot and a guess.

const LANDMARKS := [
	{"name": "Milsons Point (station)", "x": 350.4, "z": -3014.8},
	{"name": "Harbour Bridge · north end", "x": 318.2, "z": -3175.2},
	{"name": "Harbour Bridge · south end", "x": -141.5, "z": -1549.4},
	{"name": "Wynyard (station)", "x": -202.5, "z": -778.2},
	{"name": "Town Hall (station)", "x": -106.3, "z": 62.9},
	{"name": "St James (station)", "x": 348.8, "z": -263.9},
	{"name": "Museum (station)", "x": 178.3, "z": 333.0},
	{"name": "Central (station)", "x": -174.7, "z": 1156.8},
	{"name": "Redfern (station)", "x": -858.1, "z": 2130.0},
	{"name": "Circular Quay (station)", "x": 221.0, "z": -1283.0},
]

var world: Node
var player: Node3D
var coords_label: Label
var menu_label: Label
var menu_open: bool = false


func setup(world_node: Node, player_node: Node3D, canvas_layer: CanvasLayer) -> void:
	world = world_node
	player = player_node
	coords_label = Label.new()
	coords_label.add_theme_font_size_override("font_size", 13)
	coords_label.add_theme_color_override("font_color", Color("9be38a"))
	coords_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	coords_label.position = Vector2(26, 46)
	coords_label.visible = false
	canvas_layer.add_child(coords_label)

	menu_label = Label.new()
	menu_label.add_theme_font_size_override("font_size", 13)
	menu_label.add_theme_color_override("font_color", Color("ffe9a8"))
	menu_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_label.visible = false
	canvas_layer.add_child(menu_label)

	var keys := {"dev_coords": KEY_F8, "dev_teleport": KEY_F9}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("dev_coords"):
		coords_label.visible = not coords_label.visible
	if event.is_action_pressed("dev_teleport"):
		menu_open = not menu_open
		menu_label.visible = menu_open
		if menu_open:
			_render_menu()
		return
	if menu_open and event is InputEventKey and event.pressed and not event.echo:
		var index := _digit_index(event.keycode)
		if index >= 0 and index < LANDMARKS.size():
			_teleport_to(LANDMARKS[index])
			menu_open = false
			menu_label.visible = false
		elif event.keycode == KEY_ESCAPE:
			menu_open = false
			menu_label.visible = false


func _digit_index(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	if keycode == KEY_0:
		return 9
	return -1


func _render_menu() -> void:
	var lines: Array[String] = ["DEV TELEPORT · press a number, ESC to cancel"]
	for i in LANDMARKS.size():
		var spot: Dictionary = LANDMARKS[i]
		lines.append("%d  %s  (%.1f, %.1f)" % [(i + 1) % 10, str(spot["name"]), float(spot["x"]), float(spot["z"])])
	menu_label.text = "\n".join(lines)


func _teleport_to(spot: Dictionary) -> void:
	var pos := Vector3(float(spot["x"]), 2.0, float(spot["z"]))
	if player.has_method("respawn"):
		player.set("spawn", pos)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	if world != null:
		world.message = "DEV TELEPORT · %s  (%.2f, %.2f, %.2f)" % [
			str(spot["name"]), pos.x, pos.y, pos.z
		]


func _process(_dt: float) -> void:
	if coords_label.visible and player != null:
		var p: Vector3 = player.global_position
		coords_label.text = "DEV x=%.2f  y=%.2f  z=%.2f   yaw=%.1f°" % [
			p.x, p.y, p.z, rad_to_deg(player.rotation.y)
		]
