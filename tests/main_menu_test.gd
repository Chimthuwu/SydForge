extends SceneTree

## Menu audit coverage: the opening menu must expose STREET RACE, the
## multiplayer host/join modes and a QUIT button, and START must emit the
## selected mode to the district.

const MainMenuScript := preload("res://scripts/main_menu.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)


func _run() -> void:
	var menu: CanvasLayer = MainMenuScript.new()
	root.add_child(menu)
	await process_frame

	var buttons := menu.find_children("*", "Button", true, false)
	var texts: Array[String] = []
	for node: Node in buttons:
		texts.append((node as Button).text)

	_check(texts.has("STREET RACE"), "main menu exposes a STREET RACE mode")
	_check(texts.has("HOST MULTIPLAYER"), "main menu exposes HOST MULTIPLAYER")
	_check(texts.has("JOIN MULTIPLAYER"), "main menu exposes JOIN MULTIPLAYER")
	_check(texts.has("QUIT"), "main menu exposes a QUIT button")
	_check(texts.has("START"), "main menu exposes START")

	# Selecting STREET RACE and pressing START must emit mode="street_race".
	var emitted: Array = []
	menu.connect("start_requested", func(hours: float, spawn_id: String, mode: String) -> void:
		emitted.append([hours, spawn_id, mode]))
	for node: Node in buttons:
		if (node as Button).text == "STREET RACE":
			(node as Button).pressed.emit()
	for node: Node in menu.find_children("*", "Button", true, false):
		if (node as Button).text == "START":
			(node as Button).pressed.emit()
	_check(emitted.size() == 1, "START emits exactly one start_requested")
	if emitted.size() == 1:
		_check(str(emitted[0][2]) == "street_race", "START emits the selected street_race mode")

	menu.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
