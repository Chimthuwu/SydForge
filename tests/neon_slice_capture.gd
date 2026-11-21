extends SceneTree

## Visual-direction vertical-slice captures (before/after the neon overhaul).
##   $env:SPLOOGE_SHOTS="neon_before"  (or neon_after)
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/neon_slice_capture.gd

var scene: Node3D
var review: Camera3D
var shots := "neon_before"
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
	await _settle(25)


func _set_weather(name: String) -> void:
	if weather_mgr != null and weather_mgr.has_method("set_weather_by_name"):
		weather_mgr.set_weather_by_name(name, true)
	await _settle(20)


func _move_player(x: float, z: float) -> void:
	if scene.player != null:
		scene.player.global_position = Vector3(x, 0.35, z)
		if scene.player.vehicle != null:
			scene.player.vehicle.global_position = Vector3(x, 0.5, z)
	await _settle(45)


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(75)
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	weather_mgr = scene.get_node_or_null("WeatherManager")

	review = Camera3D.new()
	review.fov = 64.0
	review.far = 6000.0
	review.near = 0.05
	scene.add_child(review)
	review.current = true
	await _settle(6)

	# 1. CBD skyline at night.
	await _set_time(22.0)
	await _set_weather("light_rain")
	_look(Vector3(620.0, 210.0, 540.0), Vector3(-120.0, 40.0, -520.0))
	await _capture("01_cbd_skyline_night", "CBD skyline at night")

	# 2. CBD street level (George St near Town Hall) at night in rain.
	await _move_player(-60.0, -300.0)
	_look(Vector3(-60.0, 1.7, -300.0), Vector3(-60.0, 2.4, -380.0))
	await _capture("02_cbd_street_night", "CBD street at night")

	# 3. Kings Cross nightlife.
	await _move_player(1510.0, 66.0)
	_look(Vector3(1510.0, 2.0, 82.0), Vector3(1510.0, 1.3, 48.0))
	await _capture("03_kings_cross_night", "Kings Cross nightlife")

	# 4. Wynyard underground concourse + platform (camera inside the hall).
	_look(Vector3(-202.5, -4.6, -771.0), Vector3(-202.5, -3.2, -787.0))
	await _capture("04_wynyard_concourse", "Wynyard concourse")
	_look(Vector3(-202.5, -9.1, -765.0), Vector3(-202.5, -9.4, -795.0))
	await _capture("05_wynyard_platform", "Wynyard platform")

	# 6. Opera House / harbour at night.
	_look(Vector3(420.0, 45.0, -1690.0), Vector3(658.7, 22.0, -1763.8))
	await _capture("06_opera_night", "Opera House at night")

	# 7. Circular Quay waterfront.
	_look(Vector3(210.0, 3.0, -1290.0), Vector3(600.0, 16.0, -1780.0))
	await _capture("07_circular_quay", "Circular Quay waterfront")

	# 8. Rain-soaked street close-up.
	await _set_weather("heavy_rain")
	await _move_player(-60.0, -300.0)
	_look(Vector3(-60.0, 0.9, -300.0), Vector3(-60.0, 0.02, -325.0))
	await _capture("08_wet_road", "rain-soaked road")

	# 9. Daytime city.
	await _set_weather("clear")
	await _set_time(13.0)
	_look(Vector3(-60.0, 1.7, -300.0), Vector3(-60.0, 2.4, -380.0))
	await _capture("09_daytime_street", "daytime city")

	# 10. Sunset transition.
	await _set_time(18.6)
	_look(Vector3(-60.0, 1.7, -300.0), Vector3(-60.0, 2.4, -380.0))
	await _capture("10_sunset", "sunset transition")

	scene.queue_free()
	await process_frame
	quit()
