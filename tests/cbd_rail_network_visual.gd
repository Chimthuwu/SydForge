extends SceneTree

## Windowed captures of the canonical Stage B Sydney world and rail content.
## Run with the bundled Godot 4.7.2 executable:
##   Godot_v4.7.2-stable_win64_console.exe --path . \
##     --script res://tests/cbd_rail_network_visual.gd

const OUTPUT_DIR := "Z:/Temp/opencode/splooge-rail-network"
const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")

var world: CbdWorld
var camera: Camera3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	call_deferred("run")


func settle(frame_count: int) -> void:
	for _index in frame_count:
		await process_frame


func capture(filename: String, from: Vector3, to: Vector3, fov: float = 58.0) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	camera.fov = fov
	camera.current = true
	await settle(10)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT_DIR.path_join(filename)
	var error := image.save_png(path)
	print("RAIL CAPTURE: ", path, " error=", error, " size=", image.get_size())


func run() -> void:
	world = CbdWorldScript.new()
	if not world.load_world():
		push_error("Stage B world did not load")
		quit(1)
		return
	root.add_child(world)
	await settle(35)
	var railway := world.get_node_or_null("SydneyRailNetwork")
	if railway == null:
		push_error("Stage B world did not create SydneyRailNetwork")
		quit(1)
		return
	print("RAIL VISUAL STATS: ", railway.get("stats"))

	camera = Camera3D.new()
	camera.name = "RailReviewCamera"
	camera.far = 8500.0
	camera.near = 0.2
	root.add_child(camera)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("141c26")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a9b7c6")
	settings.ambient_light_energy = 0.8
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -25.0, 0.0)
	sun.light_energy = 0.9
	root.add_child(sun)

	await capture(
		"milsons_bridge_connection.png",
		Vector3(520.0, 118.0, -2850.0),
		Vector3(160.0, 30.0, -2290.0),
		62.0
	)
	await capture(
		"wynyard_station_entrances.png",
		Vector3(-222.0, 3.0, -842.0),
		Vector3(-184.0, 1.0, -800.0),
		46.0
	)
	for node_name in [
		"Ground", "Buildings", "Roads", "Footpaths", "Crossings",
		"Parks", "Vegetation", "HarbourWater",
	]:
		var surface := world.get_node_or_null(node_name)
		if surface is VisualInstance3D:
			(surface as VisualInstance3D).visible = false
	var wynyard_station := railway.station_nodes["wynyard"] as Node3D
	var wynyard_position := wynyard_station.global_position
	await capture(
		"wynyard_platform_cutaway.png",
		wynyard_position + Vector3(23.0, -3.0, 32.0),
		wynyard_position + Vector3(0.0, -9.0, 0.0),
		48.0
	)
	for node_name in [
		"Ground", "Buildings", "Roads", "Footpaths", "Crossings",
		"Parks", "Vegetation", "HarbourWater",
	]:
		var surface := world.get_node_or_null(node_name)
		if surface is VisualInstance3D:
			(surface as VisualInstance3D).visible = true
	var redfern_index := int(railway.get_station_route_index("redfern"))
	var redfern_position: Vector3 = railway.get("main_route_points")[redfern_index]
	await capture(
		"redfern_station_approach.png",
		redfern_position + Vector3(26.0, 125.0, 36.0),
		redfern_position,
		62.0
	)
	await capture(
		"whole_route_overview.png",
		Vector3(1250.0, 2050.0, -2800.0),
		Vector3(-260.0, 0.0, 0.0),
		64.0
	)

	world.queue_free()
	camera.queue_free()
	environment.queue_free()
	sun.queue_free()
	await process_frame
	quit()
