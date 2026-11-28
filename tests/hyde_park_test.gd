extends SceneTree

## Owner bug: Hyde Park had a forest of overlapping tree grids, trees on the
## walks and benches in the middle of Park Street.
##
## Run windowed (no --headless) with `-- --shot=<path.png>` for an aerial image.
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/hyde_park_test.gd

const D := preload("res://scripts/sydney_cbd_district.gd")
const Layout := preload("res://sydney/cbd/hyde_park_layout.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		# MultiMesh transforms read back empty from the dummy renderer.
		print("SKIP: hyde_park_test needs a window (run without --headless)")
		quit(0)
		return
	var scene = D.new()
	get_root().add_child(scene)
	for i in 20:
		await process_frame
	var world = scene.find_child("SydneyRailNetwork", true, false).get_parent()
	var data: Dictionary = world.data
	var rings: Array = []
	for park: Dictionary in data.parks:
		if str(park.id) in Layout.PARK_IDS:
			for ring: Array in park.rings:
				var polygon := PackedVector2Array()
				for p: Array in ring:
					polygon.append(Vector2(p[0], p[1]))
				rings.append(polygon)
	var inside := func(spot: Vector2) -> bool:
		for ring: PackedVector2Array in rings:
			if Geometry2D.is_point_in_polygon(spot, ring):
				return true
		return false

	var trunks := scene.find_child("TreeTrunks", true, false) as MultiMeshInstance3D
	var trees: Array[Vector2] = []
	for i in trunks.multimesh.instance_count:
		var at := trunks.multimesh.get_instance_transform(i).origin
		if inside.call(Vector2(at.x, at.z)):
			trees.append(Vector2(at.x, at.z))
	_check(trees.size() > 80 and trees.size() < 420, "Hyde Park is planted but not a forest (%d trees)" % trees.size())
	var on_paving := 0
	for tree: Vector2 in trees:
		if Layout.near_path(tree, 0.8) or Layout.near_road(tree, data.roads, 0.8) or Layout.on_monument(tree, 0.0):
			on_paving += 1
			print("TREE ", tree, Layout.near_path(tree, 0.8), Layout.near_road(tree, data.roads, 0.8), Layout.on_monument(tree, 0.0))
	_check(on_paving == 0, "no tree stands on a walk, road or monument (%d)" % on_paving)

	var civic = scene.find_child("SydneyCivicLandmarks", true, false)
	var benches: Array = civic.bench_spots
	_check(benches.size() >= 12, "benches line the walks (%d)" % benches.size())
	var bad := 0
	for bench: Vector2 in benches:
		if Layout.near_road(bench, data.roads, 1.5) or not inside.call(bench):
			bad += 1
	_check(bad == 0, "no bench is on a road or outside the park (%d)" % bad)
	_check(scene.find_children("HydeParkLandmarks", "Node3D", true, false).size() == 1, "Hyde Park is built once, not twice")

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.far = 4000.0
			camera.fov = 55.0
			for shot in [["_top", Vector3(300, 560, 40.5), Vector3(300, 0, 40)], ["", Vector3(470, 300, 330), Vector3(295, 0, 60)], ["_avenue", Vector3(321, 7, -60), Vector3(330, 3, -178)]]:
				camera.global_position = shot[1]
				camera.look_at(shot[2], Vector3.FORWARD if shot[0] == "_top" else Vector3.UP)
				camera.fov = 70.0 if shot[0] == "_top" else 55.0
				camera.current = true
				for i in 40:
					await process_frame
				get_root().get_viewport().get_texture().get_image().save_png(arg.substr(7).replace(".png", shot[0] + ".png"))

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
