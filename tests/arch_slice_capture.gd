extends SceneTree

## Architectural vertical-slice review: same views before/after the rebuild.
## $env:SPLOOGE_SHOTS="arch_before"|"arch_after"
## Godot ... --path . --resolution 1600x900 --script res://tests/arch_slice_capture.gd

var scene: Node3D
var review: Camera3D
var shots := "arch_before"
var time_mgr: Node
var weather_mgr: Node

func _initialize() -> void:
	var e := OS.get_environment("SPLOOGE_SHOTS")
	if not e.is_empty(): shots = e
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	review.look_at(at, Vector3.UP)

func _capture(file: String, label: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
	print("CAPTURED: ", label, " -> ", file)

func _conditions(hour: float, weather: String) -> void:
	if time_mgr != null: time_mgr.set_time(hour)
	if weather_mgr != null: weather_mgr.set_weather_by_name(weather, true)
	await _frames(25)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(80)
	if OS.get_environment("ARCH_DISABLE") == "1":
		for n in scene.find_children("*", "Node3D", true, false):
			if n.name == "ArchitectureSlice":
				n.visible = false
				break
		await _frames(10)
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	weather_mgr = scene.get_node_or_null("WeatherManager")
	review = Camera3D.new()
	review.fov = 62.0
	review.far = 8000.0
	scene.add_child(review)
	review.current = true
	await _frames(6)

	# 1. Street level looking at the hero glass tower.
	await _conditions(22.0, "light_rain")
	_look(Vector3(-170.0, 1.7, -245.0), Vector3(-198.4, 40.0, -275.7))
	await _capture("01_street_night", "CBD block street at night")

	# 2. Elevated view over the whole representative block.
	_look(Vector3(-40.0, 90.0, -120.0), Vector3(-120.0, 30.0, -360.0))
	await _capture("02_elevated", "CBD block elevated")

	# 3. Long-distance harbour view.
	_look(Vector3(300.0, 130.0, 250.0), Vector3(-120.0, 45.0, -600.0))
	await _capture("03_harbour", "CBD block from harbour")

	# 4. Daylight street.
	await _conditions(14.0, "clear")
	_look(Vector3(-170.0, 1.7, -245.0), Vector3(-198.4, 40.0, -275.7))
	await _capture("04_street_day", "CBD block street daylight")

	# 5. Sunset.
	await _conditions(18.6, "clear")
	_look(Vector3(-170.0, 1.7, -245.0), Vector3(-198.4, 40.0, -275.7))
	await _capture("05_sunset", "CBD block sunset")
	quit()
