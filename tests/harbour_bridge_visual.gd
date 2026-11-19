extends SceneTree
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func capture(label: String, pos: Vector3, target: Vector3, fov := 60.0) -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = pos
	camera.fov = fov
	camera.far = 5000
	camera.look_at(target)
	camera.current = true
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/bridge_"+label+".png")
	print("CAPTURE ",label)
	camera.queue_free()

func run() -> void:
	world = load("res://sydney/sydney_bridge_test.tscn").instantiate()
	root.add_child(world)
	for i in 150: await process_frame
	world.rig.set_process(false)
	var bridge = world.sydney_world.get_node("HarbourBridge")
	print("BRIDGE ",bridge.stats," WORLD ",world.sydney_world.build_times_ms)
	await capture("aerial",Vector3(1130,800,-2000),Vector3(170,25,-2370),70)
	await capture("harbour",Vector3(1000,55,-2040),Vector3(250,70,-2300),57)
	await capture("opera",Vector3(585,18,-1775),Vector3(247,78,-2300),66)
	await capture("road",bridge.point(-190,-7.5,53.7),bridge.point(50,-7.5,56),75)
	await capture("walkway",bridge.point(-130,21,53.8),bridge.point(100,21,55),75)
	await capture("pylon",bridge.point(-360,100,30),bridge.point(-282,20,47),62)
	await capture("milsons",Vector3(535,90,-2950),Vector3(360,35,-2530),65)
	await capture("south",Vector3(-20,90,-1610),Vector3(125,45,-2110),67)
	world.queue_free()
	await process_frame
	quit()
