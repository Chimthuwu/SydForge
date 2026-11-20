extends SceneTree

const OUTPUT_DIR := "Z:/Temp/opencode/splooge-train-check"
const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	call_deferred("run")

func settle(n: int) -> void:
	for _i in n:
		await process_frame

func capture(name: String) -> void:
	camera.current = true
	await settle(5)
	await RenderingServer.frame_post_draw
	var path := OUTPUT_DIR.path_join(name)
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " err=", err)

func run() -> void:
	scene = CbdDistrictScript.new()
	root.add_child(scene)
	await settle(50)
	var trains = scene.get_node("TrainManager")
	var car: Node3D = trains.trains[0]["cars"][0]
	print("TRAIN CAR POS ", car.global_position)
	camera = Camera3D.new()
	camera.far = 4000.0
	root.add_child(camera)
	camera.global_position = car.global_position + Vector3(30.0, 14.0, 34.0)
	camera.look_at(car.global_position + Vector3.UP * 2.0)
	await capture("kset_train_running.png")
	# Switch to the SMG and look at the first-person weapon.
	var player = scene.get("player")
	if player.vehicle != null:
		player.vehicle.exit_vehicle()
	player.equip_weapon(2)
	await settle(3)
	var rig = scene.get("rig")
	var smg = rig.get("smg_mount") as Node3D
	print("SMG MOUNT VISIBLE ", smg != null and smg.visible)
	camera.current = false
	rig.camera.current = true
	await settle(5)
	await RenderingServer.frame_post_draw
	var path := OUTPUT_DIR.path_join("smg_visible.png")
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " err=", err)
	scene.queue_free()
	await process_frame
	quit()
