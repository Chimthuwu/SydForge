extends SceneTree

const OUTPUT_DIR := "Z:/Temp/opencode/splooge-bridge-seam"
const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")

var camera: Camera3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	call_deferred("run")

func settle(n: int) -> void:
	for _i in n:
		await process_frame

func run() -> void:
	var world = CbdWorldScript.new()
	if not world.load_world():
		push_error("Stage B failed to load")
		quit(1)
		return
	root.add_child(world)
	await settle(25)
	var bridge = world.get_node("HarbourBridge")
	var connector = bridge.get_node_or_null("SouthernCityConnector")
	print("CONNECTOR PRESENT: ", connector != null)
	camera = Camera3D.new()
	camera.far = 5000.0
	root.add_child(camera)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("6b8ba0")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("cfe0ea")
	settings.ambient_light_energy = 0.65
	env.environment = settings
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -25.0, 0.0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var start: Vector3 = bridge.route[0]
	camera.global_position = start + Vector3(45.0, 42.0, 70.0)
	camera.look_at(start + Vector3(0.0, 0.0, 55.0))
	camera.current = true
	await settle(8)
	await RenderingServer.frame_post_draw
	var path := OUTPUT_DIR.path_join("bridge_to_city_seam.png")
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE: ", path, " error=", error)
	world.queue_free()
	await process_frame
	quit()
