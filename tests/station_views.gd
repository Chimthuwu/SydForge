extends SceneTree

## Station-interior review captures for the Sydney CBD scene.
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 \
##     --script res://tests/station_views.gd
## Set SPLOOGE_SHOTS=quality_stations (default) to choose the output folder.

var scene: Node3D
var review: Camera3D
var shots := "quality_stations"


func _initialize() -> void:
	var env := OS.get_environment("SPLOOGE_SHOTS")
	if not env.is_empty():
		shots = env
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("run")


func _settle(count: int) -> void:
	for i in count:
		await process_frame


func _capture(file: String, label: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
	print("CAPTURED: ", label, " -> ", file)


func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	if from.distance_to(at) > 0.1:
		review.look_at(at, Vector3.UP)


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(70)
	var time_manager := scene.get_node_or_null("WorldTimeManager")
	if time_manager != null:
		time_manager.set_time(13.0)
	await _settle(20)

	review = Camera3D.new()
	review.fov = 70.0
	review.far = 3000.0
	review.near = 0.05
	scene.add_child(review)
	review.current = true
	await _settle(6)

	# Surface/street-level context near key stations.
	_look(Vector3(-174.7, 1.7, 1174.0), Vector3(-174.7, 1.2, 1140.0))
	await _capture("01_central_street", "Central street/entrance context")
	_look(Vector3(-106.3, 1.7, 80.0), Vector3(-106.3, -2.0, 63.0))
	await _capture("02_town_hall_street", "Town Hall street/entrance context")
	_look(Vector3(-202.5, 1.7, -760.0), Vector3(-202.5, -2.0, -778.0))
	await _capture("03_wynyard_street", "Wynyard street/entrance context")
	_look(Vector3(221.0, 1.7, -1265.0), Vector3(221.0, 1.0, -1283.0))
	await _capture("04_circular_quay_street", "Circular Quay street context")

	# Underground concourses (depth 10 => concourse ~ -5.5).
	_look(Vector3(-106.3, -4.8, 70.0), Vector3(-106.3, -5.5, 55.0))
	await _capture("05_town_hall_concourse", "Town Hall concourse")
	_look(Vector3(-202.5, -4.8, -770.0), Vector3(-202.5, -5.5, -786.0))
	await _capture("06_wynyard_concourse", "Wynyard concourse")
	_look(Vector3(348.8, -4.8, -256.0), Vector3(348.8, -5.5, -272.0))
	await _capture("07_st_james_concourse", "St James concourse")
	_look(Vector3(178.3, -4.8, 341.0), Vector3(178.3, -5.5, 325.0))
	await _capture("08_museum_concourse", "Museum concourse")

	# Platform-level views.
	_look(Vector3(-106.3, -9.0, 75.0), Vector3(-106.3, -9.5, 45.0))
	await _capture("09_town_hall_platform", "Town Hall platform level")
	_look(Vector3(-202.5, -9.0, -765.0), Vector3(-202.5, -9.5, -795.0))
	await _capture("10_wynyard_platform", "Wynyard platform level")
	_look(Vector3(-174.7, 1.1, 1168.0), Vector3(-174.7, 0.8, 1140.0))
	await _capture("11_central_concourse", "Central concourse/platform area")
	_look(Vector3(-858.1, 1.1, 2142.0), Vector3(-858.1, 0.8, 2115.0))
	await _capture("12_redfern", "Redfern station area")

	scene.queue_free()
	await process_frame
	quit()
