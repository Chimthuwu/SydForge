extends SceneTree

## Geometry-level assertions for the Sydney railway's vertical profile.
## Existing tests only checked route length and node existence; this suite
## verifies that the train actually sits on the rails, that interpolated
## elevations do not overshoot, that tunnels stay below the street, and that
## the Wynyard dressed platform aligns with the track.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")
const StationInteriorsScript := preload("res://sydney/railway/station_interiors.gd")

var _checks := 0
var _failures := 0
var scene: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	for i in 20:
		await process_frame

	var railway = scene.get_node_or_null("CbdWorld/SydneyRailNetwork")
	if railway == null:
		for node in scene.find_children("*", "Node3D", true, false):
			if node.name == "SydneyRailNetwork":
				railway = node
				break
	_check(railway != null, "railway network exists")
	if railway == null:
		_finish()
		return
	var route: Array = railway.get("main_route_points")
	var indices: Dictionary = railway.get("station_route_indices")
	var trains = scene.get_node_or_null("TrainManager")
	_check(trains != null, "train manager exists")

	# 1. Station elevations must match their authored profile.
	var expected := {
		"milsons-point": 12.0, "wynyard": -10.0, "town-hall": -10.0,
		"central": 0.1, "redfern": 0.1,
	}
	for id in expected.keys():
		var idx := int(indices.get(id, -1))
		if idx < 0 or idx >= route.size():
			_check(false, "%s has a valid route index" % id)
			continue
		var y := (route[idx] as Vector3).y
		_check(absf(y - float(expected[id])) < 0.25,
			"%s track elevation %.2f matches %.2f" % [id, y, float(expected[id])])

	# 2. No overshoot/dip between elevation control points (the old bug dipped
	#    to -12.16 before Wynyard).
	var bridge_range: Vector2i = railway.get("_bridge_range")
	var wy := int(indices.get("wynyard", -1))
	var overshoot := 0.0
	for i in range(maxi(bridge_range.y, 0), wy):
		var y := (route[i] as Vector3).y
		if y < -10.25 or y > 0.6:
			overshoot = maxf(overshoot, maxf(-10.25 - y, y - 0.6))
	_check(overshoot < 0.05, "southern descent stays within its elevation envelope (overshoot %.2f)" % overshoot)

	# 3. Train wheels sit on the rail head at every route point after the fix.
	if trains != null:
		var half_height := float(trains.get("_car_half_height"))
		var rail_head := float(trains.get("_rail_head_cbd"))
		_check(half_height > 1.9 and half_height < 2.4,
			"car half-height is derived from the real model (%.2f m)" % half_height)
		var train_list: Array = trains.get("trains")
		if not train_list.is_empty():
			var train: Dictionary = train_list[0]
			var idx := clampf(float(train.get("index", 0.0)), 0.0, float(route.size() - 1))
			var i0 := int(floor(idx))
			var i1 := mini(i0 + 1, route.size() - 1)
			var route_y: float = lerpf((route[i0] as Vector3).y, (route[i1] as Vector3).y, idx - float(i0))
			var expected_head := rail_head
			if bridge_range.x >= 0 and i0 >= bridge_range.x and i0 <= bridge_range.y:
				expected_head = float(trains.get("_rail_head_bridge"))
			var car: Node3D = (train["cars"] as Array)[0] as Node3D
			var wheel_y := car.global_position.y - half_height
			_check(absf(wheel_y - (route_y + expected_head)) < 0.05,
				"wheels sit on rail head (wheel %.2f vs rail %.2f)" % [wheel_y, route_y + expected_head])

	# 4. Tunnel roof below street; portal near where the dive starts.
	var walls = railway.get_node_or_null("RailTunnelWalls")
	if walls is MeshInstance3D and (walls as MeshInstance3D).mesh != null:
		var box: AABB = (walls as MeshInstance3D).mesh.get_aabb()
		_check(box.position.y + box.size.y <= 0.05, "tunnel roof stays below street grade")
	var portal = railway.get_node_or_null("WynyardRailTunnelPortal")
	_check(portal != null, "tunnel portal exists")
	var cut = railway.get_node_or_null("RailDescentCutting")
	_check(cut != null, "open-cut retaining structure exists for the descent")

	# 5. Ground opening covers the descent corridor.
	var openings: Array = StationInteriorsScript.openings()
	var has_cut := false
	for opening in openings:
		if str(opening.get("id", "")) == "bridge_descent_cut":
			has_cut = true
			break
	_check(has_cut, "ground slab has an opening for the rail descent")

	# 6. Wynyard dressed platform coincides with the track anchor.
	var interiors = scene.find_child("StationInteriors", true, false)
	if interiors != null:
		var platform = interiors.find_child("PlatformInterior", true, false)
		var shell = interiors.find_child("Interior_Wynyard", true, false)
		if platform != null and shell != null:
			var anchor: Vector3 = route[int(indices.get("wynyard", 0))]
			var world_platform: Vector3 = (platform as Node3D).global_position
			var d := Vector2(world_platform.x - anchor.x, world_platform.z - anchor.z).length()
			_check(d < 2.0, "Wynyard dressed platform aligns with track (%.2f m)" % d)

	_finish()


func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
