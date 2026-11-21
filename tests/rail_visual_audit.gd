extends SceneTree

## Moving-train visual audit of the canonical Sydney railway.
## Run windowed (no --headless). Captures a K Set carriage at every key point.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var scene: Node3D
var trains: Node
var camera: Camera3D
var route_size: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _capture(index: int, label: String) -> void:
	var train: Dictionary = trains.get("trains")[0]
	train["index"] = float(index)
	trains.call("_update_consist", train, true)
	await _frames(3)
	var car: Node3D = (train["cars"] as Array)[0] as Node3D
	var target := car.global_position + Vector3.UP * 0.5
	camera.global_position = target + Vector3(23.0, 8.0, 24.0)
	camera.look_at(target, Vector3.UP)
	await _frames(2)
	var img := get_root().get_viewport().get_texture().get_image()
	if img != null:
		var path := "res://tests/rail_audit_%02d_%s.png" % [index, label]
		img.save_png(ProjectSettings.globalize_path(path))
		print("CAPTURE %s carY=%.2f" % [label, car.global_position.y])


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(30)
	trains = scene.get_node_or_null("TrainManager")
	if trains == null:
		print("NO TRAIN MANAGER")
		quit(1)
		return
	route_size = (trains.get("_route") as Array).size()
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 5000.0
	scene.add_child(camera)
	camera.current = true
	# Freeze train motion so each view is deterministic.
	trains.set("process_mode", Node.PROCESS_MODE_DISABLED)
	var labels := {
		0: "milsons_point", 20: "bridge_north", 121: "bridge_centre",
		220: "bridge_south", 270: "descent", 330: "tunnel",
		358: "wynyard", 479: "town_hall", 660: "central", 821: "redfern",
	}
	for index in labels.keys():
		await _capture(int(index), str(labels[index]))
	quit(0)
