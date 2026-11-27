extends SceneTree

## Phase C/D coverage: the AI headlight budget is bounded and distance-ranked,
## and the pause overlay exposes the settings it persists. This does not boot
## the world; it exercises the managers directly.

const CityLightsManagerScript := preload("res://sydney/ecosystem/city_lights_manager.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

var checks := 0
var failures := 0


class FakeCar:
	extends Node3D
	var driver = null
	var spot: SpotLight3D
	var rear: OmniLight3D
	var managed := false
	var lights_on := false

	func _init() -> void:
		spot = SpotLight3D.new()
		rear = OmniLight3D.new()
		add_child(spot)
		add_child(rear)

	func set_light_budget_managed(value: bool) -> void:
		managed = value

	func apply_light_budget(active: bool) -> void:
		lights_on = active
		spot.visible = active
		rear.visible = active


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
	GameSettingsScript.headlight_budget = 6
	var manager: Node3D = CityLightsManagerScript.new()
	var player := Node3D.new()
	player.name = "Player"
	root.add_child(player)
	root.add_child(manager)
	manager.set("_player_ref", player)
	manager.set("_lighting_factor", 1.0)

	var cars: Array[FakeCar] = []
	for index in 10:
		var car := FakeCar.new()
		car.name = "FakeCar%d" % index
		car.position = Vector3(float(index) * 10.0, 0.0, 0.0)
		car.add_to_group("traffic_vehicles")
		root.add_child(car)
		cars.append(car)
	# A car the player drives keeps its own lights and is not budgeted.
	cars[0].driver = player
	manager.call("_update_ai_headlights")

	var enabled := 0
	for car in cars:
		if car.lights_on:
			enabled += 1
	_check(enabled == 6, "only six AI headlights are live (got %d)" % enabled)
	_check(cars[1].lights_on and cars[2].lights_on, "nearest AI cars keep headlights")
	_check(not cars[8].lights_on, "an AI car beyond the budget is dark")
	_check(cars[9].managed, "far AI cars are still marked manager-owned")
	_check(not cars[0].managed, "player-driven traffic car stays outside the budget")

	GameSettingsScript.headlight_budget = 0
	manager.call("_update_ai_headlights")
	var any_ai := false
	for index in range(1, cars.size()):
		if cars[index].lights_on:
			any_ai = true
	_check(not any_ai, "setting the budget to zero turns every AI headlight off")

	GameSettingsScript.headlight_budget = 6
	GameSettingsScript.master_db = -8.0
	GameSettingsScript.fullscreen = false
	GameSettingsScript.apply()
	var master := AudioServer.get_bus_index("Master")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master), -8.0), "master volume is applied")

	var menu: CanvasLayer = PauseMenuScript.new()
	root.add_child(menu)
	await process_frame
	_check(menu.get_node_or_null("PauseRoot") != null, "pause overlay builds its root")
	_check(menu.find_children("*", "HSlider", true, false).size() >= 4, "pause overlay has master/music/SFX/sensitivity sliders")
	_check(menu.find_children("*", "OptionButton", true, false).size() == 1, "pause overlay has the headlight option")
	_check(menu.find_children("*", "CheckButton", true, false).size() >= 2, "pause overlay has invert-Y and fullscreen toggles")
	var settings_button := menu.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Button).text == "SETTINGS"
	)
	_check(settings_button.size() == 1, "pause overlay exposes a settings section")
	var controls_button := menu.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Button).text == "CONTROLS"
	)
	_check(controls_button.size() == 1, "pause overlay exposes a controls section")
	var respawn_button := menu.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Button).text == "RESPAWN"
	)
	_check(respawn_button.size() == 1, "pause overlay exposes respawn")
	var menu_button := menu.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Button).text == "RETURN TO MENU"
	)
	_check(menu_button.size() == 1, "pause overlay exposes return to menu")
	var quit_button := menu.find_children("*", "Button", true, false).filter(
		func(node: Node) -> bool: return (node as Button).text == "QUIT GAME"
	)
	_check(quit_button.size() == 1, "pause overlay exposes quit game")
	var closed := [false]
	menu.connect("closed", func() -> void: closed[0] = true)
	# The tree is paused while this overlay is up, so it must own Esc itself.
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame
	_check(closed[0], "Esc closes the pause overlay")
	_check(not is_instance_valid(menu), "closed pause overlay frees itself")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
