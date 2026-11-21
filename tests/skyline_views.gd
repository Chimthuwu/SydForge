extends SceneTree

## Multi-viewpoint skyline review of the canonical game.
## $env:SPLOOGE_SHOTS="skyline_v2"; Godot ... --script res://tests/skyline_views.gd

var scene: Node3D
var review: Camera3D
var shots := "skyline_v2"
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

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(75)
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	weather_mgr = scene.get_node_or_null("WeatherManager")
	if time_mgr != null: time_mgr.set_time(22.0)
	if weather_mgr != null: weather_mgr.set_weather_by_name("clear", true)
	await _frames(25)
	review = Camera3D.new()
	review.fov = 60.0
	review.far = 9000.0
	scene.add_child(review)
	review.current = true
	await _frames(6)

	_look(Vector3(300.0, 130.0, 250.0), Vector3(-120.0, 45.0, -600.0))
	await _capture("01_harbour_approach", "harbour approach")
	_look(Vector3(658.0, 120.0, -1500.0), Vector3(-150.0, 40.0, -500.0))
	await _capture("02_from_quay", "from Circular Quay")
	_look(Vector3(-700.0, 140.0, -1200.0), Vector3(-100.0, 45.0, -400.0))
	await _capture("03_from_barangaroo", "from Barangaroo")
	_look(Vector3(1510.0, 90.0, 60.0), Vector3(-100.0, 40.0, -400.0))
	await _capture("04_from_kings_cross", "from Kings Cross")
	quit()
