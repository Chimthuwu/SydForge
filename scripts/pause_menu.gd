extends CanvasLayer

## In-game pause overlay. Unlike `main_menu.gd` this is created after play
## starts: it pauses the tree, releases the mouse and persists the display,
## audio and input settings the world actually reads. Every node in the overlay
## uses PROCESS_MODE_ALWAYS so it keeps responding while the world is paused.
##
## Reopening it does not rebuild the settings defaults: `GameSettings` owns the
## static values and writes them to `user://settings.cfg`.

signal closed
signal return_requested

const GameSettings := preload("res://scripts/game_settings.gd")

const GOLD := Color("ffcb52")
const PANEL := Color(0.018, 0.030, 0.042, 0.97)
const TEXT := Color("e8ecea")
const TEXT_DIM := Color("9fb0b3")
const BUTTON_IDLE := Color(0.055, 0.085, 0.105, 0.95)

const CONTROL_ACTIONS := [
	["forward", "MOVE FORWARD"],
	["back", "MOVE BACK"],
	["left", "STRAFE LEFT"],
	["right", "STRAFE RIGHT"],
	["jump", "JUMP / HANDBRAKE"],
	["sprint", "SPRINT / NOS"],
	["interact", "INTERACT / ENTER VEHICLE"],
	["fire", "FIRE"],
	["aim", "AIM"],
	["weapon_pistol", "WEAPON 1"],
	["weapon_shotgun", "WEAPON 2"],
	["weapon_smg", "WEAPON 3"],
	["weapon_next", "NEXT WEAPON"],
	["reload", "RELOAD"],
	["flashlight", "TORCH / HEADLIGHTS"],
	["skateboard", "SKATEBOARD"],
	["grapple", "GRAPPLE"],
	["horn", "HORN"],
	["wheelie", "WHEELIE"],
	["skate_trick", "SKATE TRICK"],
]

var _settings_box: VBoxContainer
var _controls_box: VBoxContainer
var _control_buttons: Dictionary = {}
var _rebind_action := ""
var _rebind_button: Button
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	GameSettings.load_settings()
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
			get_viewport().set_input_as_handled()
			return
		GameSettings.set_binding(_rebind_action, key)
		_finish_rebind()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		GameSettings.set_binding(_rebind_action, mouse)
		_finish_rebind()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not _rebind_action.is_empty():
			_cancel_rebind()
		else:
			close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _build() -> void:
	var root := Control.new()
	root.name = "PauseRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.008, 0.012, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color(0.13, 0.20, 0.22, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "SYDNEY · FREE ROAM"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	column.add_child(subtitle)

	var rule := ColorRect.new()
	rule.color = Color(0.16, 0.24, 0.26, 1.0)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(rule)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(0.0, 48.0)
	resume.add_theme_font_size_override("font_size", 19)
	resume.pressed.connect(close)
	column.add_child(resume)
	resume.grab_focus()

	var respawn := Button.new()
	respawn.text = "RESPAWN"
	respawn.custom_minimum_size = Vector2(0.0, 40.0)
	respawn.add_theme_font_size_override("font_size", 15)
	respawn.pressed.connect(_on_respawn)
	column.add_child(respawn)

	var settings_toggle := _toggle_button(column, "SETTINGS")
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 8)
	_settings_box.visible = false
	column.add_child(_settings_box)
	_build_settings(_settings_box)
	settings_toggle.toggled.connect(_on_settings_toggled)

	var controls_toggle := _toggle_button(column, "CONTROLS")
	_controls_box = VBoxContainer.new()
	_controls_box.add_theme_constant_override("separation", 5)
	_controls_box.visible = false
	column.add_child(_controls_box)
	_build_controls(_controls_box)
	controls_toggle.toggled.connect(_on_controls_toggled)

	var menu := Button.new()
	menu.text = "RETURN TO MENU"
	menu.custom_minimum_size = Vector2(0.0, 40.0)
	menu.add_theme_font_size_override("font_size", 15)
	menu.pressed.connect(_on_return_to_menu)
	column.add_child(menu)

	var quit := Button.new()
	quit.text = "QUIT GAME"
	quit.custom_minimum_size = Vector2(0.0, 40.0)
	quit.add_theme_font_size_override("font_size", 15)
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)

	_status = Label.new()
	_status.text = "ESC resume · F torch/headlights · click a binding to remap it"
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _toggle_button(parent: VBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_font_size_override("font_size", 15)
	parent.add_child(button)
	return button


func _build_settings(parent: VBoxContainer) -> void:
	_add_slider(parent, "MASTER VOLUME", -40.0, 6.0, 2.0, GameSettings.master_db, "%d dB",
		func(value: float) -> void:
			GameSettings.master_db = value
			GameSettings.apply()
			GameSettings.save_settings())
	_add_slider(parent, "MUSIC VOLUME", -40.0, 6.0, 2.0, GameSettings.music_db, "%d dB",
		func(value: float) -> void:
			GameSettings.music_db = value
			GameSettings.apply()
			GameSettings.save_settings())
	_add_slider(parent, "SFX VOLUME", -40.0, 6.0, 2.0, GameSettings.sfx_db, "%d dB",
		func(value: float) -> void:
			GameSettings.sfx_db = value
			GameSettings.apply()
			GameSettings.save_settings())
	_add_slider(parent, "MOUSE SENSITIVITY", 0.2, 3.0, 0.05, GameSettings.mouse_sensitivity, "%.2f×",
		func(value: float) -> void:
			GameSettings.mouse_sensitivity = value
			GameSettings.save_settings())

	var invert := CheckButton.new()
	invert.text = "INVERT MOUSE Y"
	invert.button_pressed = GameSettings.invert_y
	invert.add_theme_font_size_override("font_size", 13)
	invert.add_theme_color_override("font_color", TEXT)
	invert.toggled.connect(
		func(pressed: bool) -> void:
			GameSettings.invert_y = pressed
			GameSettings.save_settings())
	parent.add_child(invert)

	var headlights_row := HBoxContainer.new()
	headlights_row.add_theme_constant_override("separation", 12)
	parent.add_child(headlights_row)
	var headlights_label := Label.new()
	headlights_label.text = "AI HEADLIGHTS"
	headlights_label.add_theme_font_size_override("font_size", 13)
	headlights_label.add_theme_color_override("font_color", TEXT)
	headlights_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headlights_row.add_child(headlights_label)
	var headlights := OptionButton.new()
	headlights.add_item("OFF", 0)
	headlights.add_item("NEAREST 3", 1)
	headlights.add_item("NEAREST 6", 2)
	headlights.selected = 0 if GameSettings.headlight_budget <= 0 else (1 if GameSettings.headlight_budget <= 3 else 2)
	headlights.item_selected.connect(
		func(index: int) -> void:
			GameSettings.headlight_budget = [0, 3, 6][index]
			GameSettings.save_settings())
	headlights_row.add_child(headlights)

	var fullscreen := CheckButton.new()
	fullscreen.text = "FULLSCREEN"
	fullscreen.button_pressed = GameSettings.fullscreen
	fullscreen.add_theme_font_size_override("font_size", 13)
	fullscreen.add_theme_color_override("font_color", TEXT)
	fullscreen.toggled.connect(
		func(pressed: bool) -> void:
			GameSettings.fullscreen = pressed
			GameSettings.apply()
			GameSettings.save_settings())
	parent.add_child(fullscreen)


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	min_value: float,
	max_value: float,
	step: float,
	value: float,
	format: String,
	on_change: Callable,
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label := Label.new()
	value_label.text = format % value
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", GOLD)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0.0, 24.0)
	slider.value_changed.connect(
		func(new_value: float) -> void:
			value_label.text = format % new_value
			on_change.call(new_value))
	parent.add_child(slider)


func _build_controls(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 330.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for entry: Array in CONTROL_ACTIONS:
		var action := str(entry[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		rows.add_child(row)
		var label := Label.new()
		label.text = str(entry[1])
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = GameSettings.binding_text(action)
		button.custom_minimum_size = Vector2(150.0, 30.0)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func() -> void: _start_rebind(action, button))
		row.add_child(button)
		_control_buttons[action] = button
	var note := Label.new()
	note.text = "Click a binding, then press a key or mouse button. ESC cancels."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


func _start_rebind(action: String, button: Button) -> void:
	if not _rebind_action.is_empty():
		_cancel_rebind()
	_rebind_action = action
	_rebind_button = button
	button.text = "PRESS…"
	_status.text = "Press a key or mouse button for %s · ESC cancels" % action


func _finish_rebind() -> void:
	if _rebind_button != null and is_instance_valid(_rebind_button):
		_rebind_button.text = GameSettings.binding_text(_rebind_action)
	_rebind_action = ""
	_rebind_button = null
	_status.text = "Binding saved."


func _cancel_rebind() -> void:
	if _rebind_button != null and is_instance_valid(_rebind_button):
		_rebind_button.text = GameSettings.binding_text(_rebind_action)
	_rebind_action = ""
	_rebind_button = null
	_status.text = "Binding unchanged."


func _on_settings_toggled(expanded: bool) -> void:
	_settings_box.visible = expanded
	if expanded:
		_controls_box.visible = false


func _on_controls_toggled(expanded: bool) -> void:
	_controls_box.visible = expanded
	if expanded:
		_settings_box.visible = false


func _on_respawn() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("respawn"):
		player.call("respawn")
	close()


func _on_return_to_menu() -> void:
	return_requested.emit()
	close()
