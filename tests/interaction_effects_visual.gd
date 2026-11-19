extends SceneTree

const OUTPUT_DIR := "Z:/Temp/opencode/splooge-interaction-visuals"

var game: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	call_deferred("run")


func settle(frame_count: int) -> void:
	for _index in frame_count:
		await process_frame


func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUTPUT_DIR.path_join(filename)
	var error := image.save_png(path)
	print("CAPTURE: ",path," error=",error," size=",image.get_size())


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await settle(150)
	await capture("procedural-pistol.png")

	var player: BoomPlayer = game.get("player")
	var lights := game.get_node_or_null("WildlifeManager")
	if lights == null:
		push_error("Canonical world has no WildlifeManager")
		quit(1)
		return
	var forward: Vector3 = -game.get("rig").global_basis.z
	forward.y = 0.0
	var ibis := WildlifeController.new()
	ibis.kind = WildlifeController.WildlifeKind.IBIS
	lights.add_child(ibis)
	ibis.setup(WildlifeController.WildlifeKind.IBIS,player.global_position + forward.normalized() * 3.0,player)
	ibis.hit_by_vehicle(18.0,game.get("vehicles")[0])
	var splat_camera := Camera3D.new()
	game.add_child(splat_camera)
	splat_camera.position = ibis.global_position + Vector3(0,5,6)
	splat_camera.look_at(ibis.global_position)
	splat_camera.current = true
	await settle(3)
	await capture("bin-chicken-splat.png")
	game.queue_free()
	await process_frame
	quit()
