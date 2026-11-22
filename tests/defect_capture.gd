extends SceneTree

## Reproducible defect and skyline capture harness for the canonical Sydney scene.
##
## Usage (windowed; rendering is required):
##   SPLOOGE_SHOTS=defect_after "C:\...\Godot...console.exe" --path . \
##       --resolution 1280x720 --script res://tests/defect_capture.gd
##
## Optional:
##   SPLOOGE_HIDE="ArchitectureSlice,SkylineHeroes"  hide named nodes before capture
##   SPLOOGE_HIDE_UI=1                               hide every CanvasLayer (clean stills)
##   SPLOOGE_VIEWS=all|street|rail|tunnel           choose the view subset

var scene: Node3D
var review: Camera3D
var shots := "defect_after"
var time_mgr: Node
var weather_mgr: Node
var hide_list: Array = []
var views := "all"


func _initialize() -> void:
	var e := OS.get_environment("SPLOOGE_SHOTS")
	if not e.is_empty():
		shots = e
	var h := OS.get_environment("SPLOOGE_HIDE")
	if not h.is_empty():
		hide_list = h.split(",", false)
	var v := OS.get_environment("SPLOOGE_VIEWS")
	if not v.is_empty():
		views = v
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	review.look_at(at, Vector3.UP)


func _capture(file: String, label: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
	print("CAPTURED: ", label, " -> ", file)


func _conditions(hour: float, weather: String) -> void:
	if time_mgr != null:
		time_mgr.set_time(hour)
	if weather_mgr != null:
		weather_mgr.set_weather_by_name(weather, true)
	await _frames(25)


func _route_shot(route: Array, index: int, file: String) -> void:
	if index + 6 >= route.size():
		return
	var p: Vector3 = route[index]
	var ahead: Vector3 = route[index + 6]
	_look(p + Vector3.UP * 2.2, ahead + Vector3.UP * 1.6)
	await _capture(file, "route index %d" % index)


func _hide(names: Array) -> void:
	for n in names:
		var node := scene.find_child(str(n), true, false)
		if node != null and node is Node3D:
			(node as Node3D).visible = false
			print("HIDDEN: ", n)
	await _frames(10)


func _hide_ui() -> void:
	for node in scene.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
		print("HIDDEN UI: ", node.name)
	await _frames(10)


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(80)
	if not hide_list.is_empty():
		await _hide(hide_list)
	if not OS.get_environment("SPLOOGE_HIDE_UI").is_empty():
		await _hide_ui()
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	weather_mgr = scene.get_node_or_null("WeatherManager")
	review = Camera3D.new()
	review.fov = 68.0
	review.far = 12000.0
	scene.add_child(review)
	review.current = true
	await _frames(6)

	if views == "free":
		# Ad-hoc verification camera: SPLOOGE_CAM="x,y,z,tx,ty,tz"
		var cam := OS.get_environment("SPLOOGE_CAM")
		var parts := cam.split(",", false)
		if parts.size() == 6:
			var hour := OS.get_environment("SPLOOGE_HOUR")
			await _conditions(float(hour) if not hour.is_empty() else 11.0, "clear")
			_look(Vector3(float(parts[0]), float(parts[1]), float(parts[2])),
				Vector3(float(parts[3]), float(parts[4]), float(parts[5])))
			await _capture("00_free", "free camera")
		quit()
		return

	if views in ["all", "street"]:
		# 1. George Street north end, looking up the canyon (the reported street view).
		await _conditions(11.0, "clear")
		_look(Vector3(-40.9, 1.7, -1145.3), Vector3(-120.0, 60.0, -1260.0))
		await _capture("01_george_street_up", "George Street looking up")

		# 2. Wynyard towers from York Street.
		_look(Vector3(-230.5, 1.7, -984.0), Vector3(-160.0, 45.0, -820.0))
		await _capture("02_wynyard_street", "Wynyard street")

		# 3. Harbour approach from the southern end of the bridge deck.
		_look(Vector3(322.66, 60.0, -3097.79), Vector3(120.0, 40.0, -1600.0))
		await _capture("03_bridge_approach", "Harbour bridge approach")

	if views in ["all", "route"]:
		# Track-level views along the authored rail route. The route carries its
		# own authored elevation, so these are the only positions that actually
		# sit inside the cutting and the bore.
		await _conditions(11.0, "clear")
		var rail := scene.find_child("SydneyRailNetwork", true, false)
		if rail != null and "main_route_points" in rail:
			var route: Array = rail.get("main_route_points")
			print("route points: ", route.size())
			await _route_shot(route, 300, "07_route_cutting_300")
			await _route_shot(route, 340, "08_route_bore_mouth")
			await _route_shot(route, 380, "09_route_in_bore")
			await _route_shot(route, 420, "10_route_in_bore_far")
			await _route_shot(route, 470, "11_route_town_hall")
		else:
			print("route view requested but SydneyRailNetwork.main_route_points missing")

	if views in ["all", "rail"]:
		# 4. Rail corridor cutting through the CBD (open trench / tunnel portals).
		await _conditions(11.0, "clear")
		_look(Vector3(-60.0, 22.0, -1150.0), Vector3(-235.0, 0.0, -1330.0))
		await _capture("04_rail_corridor", "Rail corridor near the bridge")

		# 5. Wynyard underground approach looking into the bore.
		_look(Vector3(-120.0, 12.0, -1120.0), Vector3(-250.0, 0.0, -1360.0))
		await _capture("05_tunnel_portal", "Tunnel portal approach")

	if views in ["all", "tunnel"]:
		# 6. Inside the bore looking along the tracks.
		_look(Vector3(-209.0, 2.0, -1390.0), Vector3(-231.0, 2.0, -1120.0))
		await _capture("06_inside_bore", "Inside rail tunnel")

	quit()
