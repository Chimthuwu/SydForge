extends SceneTree

## City-wide cyberpunk review captures (actual canonical game).
##   $env:SPLOOGE_SHOTS="city_neon"  Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/neon_city_capture.gd

var scene: Node3D
var review: Camera3D
var shots := "city_neon"
var time_mgr: Node
var weather_mgr: Node


func _initialize() -> void:
	var env := OS.get_environment("SPLOOGE_SHOTS")
	if not env.is_empty():
		shots = env
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("run")


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	if from.distance_to(at) > 0.1:
		review.look_at(at, Vector3.UP)


func _capture(file: String, label: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
	print("CAPTURED: ", label, " -> ", file)


func _set_time(hour: float) -> void:
	if time_mgr != null:
		time_mgr.set_time(hour)
	await _settle(22)


func _set_weather(name: String) -> void:
	if weather_mgr != null:
		weather_mgr.set_weather_by_name(name, true)
	await _settle(18)


func _move_player(x: float, z: float) -> void:
	if scene.player != null:
		scene.player.global_position = Vector3(x, 0.35, z)
		if scene.player.vehicle != null:
			scene.player.vehicle.global_position = Vector3(x, 0.5, z)
	await _settle(40)


## Use the world's authored walkable viewpoint so the camera is on a street,
## not embedded in a building shell.
func _from_viewpoint(id: String) -> void:
	var vp: Dictionary = scene.cbd_world.viewpoints.get(id, {})
	if vp.is_empty():
		return
	var yaw := float(vp.get("yawRad", 0.0))
	var pos := Vector3(float(vp.get("x", 0.0)), float(vp.get("eyeHeightM", 1.7)), float(vp.get("z", 0.0)))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_look(pos, pos + forward * 60.0 + Vector3.UP * 1.5)


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(75)
	if OS.get_environment("ARCH_DISABLE") == "1":
		for n in scene.find_children("*", "Node3D", true, false):
			if n.name == "ArchitectureSlice":
				n.visible = false
				break
		await _settle(10)
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	weather_mgr = scene.get_node_or_null("WeatherManager")

	review = Camera3D.new()
	review.fov = 62.0
	review.far = 8000.0
	review.near = 0.05
	scene.add_child(review)
	review.current = true
	await _settle(6)

	await _set_time(22.0)
	await _set_weather("clear")

	# Skyline from the harbour approach (clear air so towers stay readable).
	_look(Vector3(300.0, 130.0, 250.0), Vector3(-120.0, 45.0, -600.0))
	await _capture("01_skyline_night", "CBD skyline at night")
	await _set_weather("light_rain")

	# CBD street.
	await _move_player(-60.0, -300.0)
	_look(Vector3(-60.0, 1.75, -300.0), Vector3(-60.0, 2.4, -380.0))
	await _capture("02_cbd_street", "CBD street")

	# District views from authored walkable viewpoints.
	await _move_player(1511.7, 62.8)
	await _from_viewpoint("kings_cross")
	await _capture("03_kings_cross", "Kings Cross")

	await _move_player(186.8, -1509.9)
	await _from_viewpoint("circular_quay")
	await _capture("04_circular_quay", "Circular Quay")

	await _move_player(17.6, -1528.3)
	await _from_viewpoint("the_rocks")
	await _capture("05_the_rocks", "The Rocks")

	await _move_player(-618.4, -1196.5)
	await _from_viewpoint("barangaroo")
	await _capture("06_barangaroo", "Barangaroo")

	await _move_player(-75.7, 1067.9)
	await _from_viewpoint("central")
	await _capture("07_central", "Central Station")

	# Wynyard concourse.
	_look(Vector3(-202.5, -4.6, -771.0), Vector3(-202.5, -3.2, -787.0))
	await _capture("08_wynyard", "Wynyard concourse")

	# Wet road close-up.
	await _set_weather("heavy_rain")
	await _move_player(-60.0, -300.0)
	_look(Vector3(-60.0, 0.9, -300.0), Vector3(-60.0, 0.03, -327.0))
	await _capture("09_wet_road", "Wet neon road")

	# Daylight.
	await _set_weather("clear")
	await _set_time(14.0)
	_look(Vector3(-60.0, 1.75, -300.0), Vector3(-60.0, 2.4, -380.0))
	await _capture("10_daylight", "Daylight city")

	scene.queue_free()
	await process_frame
	quit()
