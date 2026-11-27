extends CanvasLayer

## Opening menu for the Sydney world. Chooses a time of day and a spawn
## location before play starts. Built as an overlay so the world is already
## loaded and the selection can be applied without reloading the CBD.
##
## The menu is only created when this scene is the actual running game (the
## district script checks that); headless suites and `--script` capture tools
## keep starting with the canonical defaults. The Inner West district is not a
## menu choice: its standalone playtest world builds tens of thousands of
## footpaths/buildings synchronously and is not practical to add here.
##
signal start_requested(hours: float, spawn_id: String)

const TIME_OPTIONS := [
	{"id": "morning", "label": "Morning", "clock": "07:30", "hours": 7.5},
	{"id": "midday", "label": "Midday", "clock": "12:30", "hours": 12.5},
	{"id": "afternoon", "label": "Afternoon", "clock": "16:00", "hours": 16.0},
	{"id": "evening", "label": "Evening", "clock": "18:30", "hours": 18.5},
]

const SPAWN_OPTIONS := [
	{"id": "bridge", "label": "Harbour Bridge", "hint": "Sports car on the bridge deck"},
	{"id": "central", "label": "Central Station", "hint": "Railway Square and the station"},
	{"id": "town_hall", "label": "Town Hall", "hint": "George Street, civic centre"},
	{"id": "circular_quay", "label": "Circular Quay", "hint": "Ferries, the promenade and the Opera House"},
	{"id": "the_rocks", "label": "The Rocks", "hint": "Historic waterfront lanes"},
	{"id": "barangaroo", "label": "Barangaroo", "hint": "Waterfront towers and the reserve"},
]

const GOLD := Color("ffcb52")
const PANEL := Color(0.018, 0.030, 0.042, 0.96)
const BUTTON_IDLE := Color(0.055, 0.085, 0.105, 0.95)
const BUTTON_HOVER := Color(0.10, 0.16, 0.19, 1.0)
const BORDER_IDLE := Color(0.22, 0.32, 0.34, 1.0)
const TEXT := Color("e8ecea")
const TEXT_DIM := Color("9fb0b3")

var _hours := 12.5
var _spawn_id := "bridge"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.010, 0.016, 0.90)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880.0, 560.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL
	panel_style.border_color = Color(0.13, 0.20, 0.22, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", panel_style)
	centre.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "SYDFORGE"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", GOLD)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "SYDNEY · FREE ROAM — choose when you arrive and where you start"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	column.add_child(subtitle)

	var rule := ColorRect.new()
	rule.color = Color(0.16, 0.24, 0.26, 1.0)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 44)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)

	var time_column := VBoxContainer.new()
	time_column.add_theme_constant_override("separation", 8)
	time_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(time_column)
	_add_header(time_column, "TIME OF DAY")
	var time_group := ButtonGroup.new()
	time_group.allow_unpress = false
	for option: Dictionary in TIME_OPTIONS:
		var button := _add_choice(time_column, option, time_group)
		button.pressed.connect(_select_time.bind(float(option["hours"])))
		if absf(float(option["hours"]) - _hours) < 0.01:
			button.button_pressed = true

	var spawn_column := VBoxContainer.new()
	spawn_column.add_theme_constant_override("separation", 8)
	spawn_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(spawn_column)
	_add_header(spawn_column, "SPAWN LOCATION")
	var spawn_group := ButtonGroup.new()
	spawn_group.allow_unpress = false
	for option: Dictionary in SPAWN_OPTIONS:
		var button := _add_choice(spawn_column, option, spawn_group)
		button.pressed.connect(_select_spawn.bind(str(option["id"])))
		if str(option["id"]) == _spawn_id:
			button.button_pressed = true

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)
	var note := Label.new()
	note.text = "WASD move · SPACE jump · E enter vehicles · RIGHT ALT skateboard\nY street race (in a car) · F6 host / F7 join multiplayer · F10 scoreboard"
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", TEXT_DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)

	var start := Button.new()
	start.text = "START"
	start.custom_minimum_size = Vector2(210.0, 54.0)
	start.add_theme_font_size_override("font_size", 22)
	_style_button(start, true)
	start.pressed.connect(_start)
	footer.add_child(start)
	start.grab_focus()

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(120.0, 54.0)
	quit.add_theme_font_size_override("font_size", 18)
	_style_button(quit, false)
	quit.pressed.connect(func() -> void: get_tree().quit())
	footer.add_child(quit)


func _add_header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", GOLD)
	parent.add_child(label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(gap)


func _add_choice(parent: VBoxContainer, option: Dictionary, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(340.0, 48.0)
	button.add_theme_font_size_override("font_size", 15)
	var text := str(option.get("label", ""))
	if option.has("clock"):
		text += "    " + str(option["clock"])
	button.text = text
	if option.has("hint"):
		button.tooltip_text = str(option["hint"])
	_style_button(button, false)
	parent.add_child(button)
	return button


func _style_button(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD if primary else BUTTON_IDLE
	normal.border_color = GOLD if primary else BORDER_IDLE
	normal.set_border_width_all(1)
	normal.set_border_width_all(1)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.set_corner_radius_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = GOLD.lightened(0.12) if primary else BUTTON_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = GOLD
	pressed.border_color = GOLD.lightened(0.2)
	# A selected toggle keeps the gold fill while hovered so the active choice
	# never looks unselected under the cursor.
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	if primary:
		button.add_theme_color_override("font_color", Color("131a1c"))
		button.add_theme_color_override("font_hover_color", Color("131a1c"))
		button.add_theme_color_override("font_pressed_color", Color("131a1c"))
	else:
		button.add_theme_color_override("font_color", TEXT)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color("131a1c"))
		button.add_theme_color_override("font_hover_pressed_color", Color("131a1c"))
		button.add_theme_color_override("font_focus_color", TEXT)


func _select_time(hours: float) -> void:
	_hours = hours


func _select_spawn(spawn_id: String) -> void:
	_spawn_id = spawn_id


func _start() -> void:
	start_requested.emit(_hours, _spawn_id)
