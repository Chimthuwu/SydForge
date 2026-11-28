class_name HarbourBoats
extends Node3D

## Procedural harbour traffic. Boats follow authored routes in Sydney Harbour
## and animate a small wake/light rig. They are visual actors: no collision body
## touches the land, roads or player, so the shoreline barrier remains intact.

const ART := preload("res://scripts/art.gd")

enum BoatKind { FERRY, SMALL_CRAFT, TUG }

var boats: Array[Dictionary] = []
var stats: Dictionary = {}
var _player_ref: Node3D


func setup(player: Node3D) -> void:
	_player_ref = player
	_spawn_all()
	stats = {
		"boats": boats.size(),
		"ferries": _count_kind(BoatKind.FERRY),
		"smallCraft": _count_kind(BoatKind.SMALL_CRAFT),
		"tugs": _count_kind(BoatKind.TUG),
	}


func _spawn_all() -> void:
	_add_boat(BoatKind.FERRY, [
		Vector3(168.0, 0.0, -1400.0),
		Vector3(576.0, 0.0, -1792.0),
	], 9.0)
	_add_boat(BoatKind.FERRY, [
		Vector3(712.0, 0.0, -1688.0),
		Vector3(720.0, 0.0, -1696.0),
		Vector3(752.0, 0.0, -1800.0),
		Vector3(752.0, 0.0, -1832.0),
		Vector3(744.0, 0.0, -1856.0),
		Vector3(712.0, 0.0, -1888.0),
		Vector3(72.0, 0.0, -2168.0),
		Vector3(16.0, 0.0, -2176.0),
		Vector3(-128.0, 0.0, -2160.0),
		Vector3(-688.0, 0.0, -1960.0),
		Vector3(-720.0, 0.0, -1928.0),
		Vector3(-728.0, 0.0, -1920.0),
		Vector3(-736.0, 0.0, -1896.0),
		Vector3(-752.0, 0.0, -1696.0),
		Vector3(-744.0, 0.0, -1624.0),
		Vector3(-736.0, 0.0, -1600.0),
		Vector3(-720.0, 0.0, -1584.0),
		Vector3(-648.0, 0.0, -1544.0),
		Vector3(-608.0, 0.0, -1544.0),
		Vector3(-576.0, 0.0, -1560.0),
	], 8.2)
	_add_boat(BoatKind.SMALL_CRAFT, [
		Vector3(224.0, 0.0, -1872.0),
		Vector3(688.0, 0.0, -1896.0),
		Vector3(712.0, 0.0, -1888.0),
		Vector3(744.0, 0.0, -1856.0),
		Vector3(752.0, 0.0, -1816.0),
		Vector3(744.0, 0.0, -1752.0),
		Vector3(720.0, 0.0, -1696.0),
		Vector3(712.0, 0.0, -1688.0),
	], 6.5)
	_add_boat(BoatKind.SMALL_CRAFT, [
		Vector3(-624.0, 0.0, -520.0),
		Vector3(-632.0, 0.0, -528.0),
		Vector3(-712.0, 0.0, -1024.0),
		Vector3(-752.0, 0.0, -1736.0),
		Vector3(-736.0, 0.0, -1904.0),
		Vector3(-728.0, 0.0, -1920.0),
		Vector3(-696.0, 0.0, -1952.0),
		Vector3(-688.0, 0.0, -1960.0),
		Vector3(-128.0, 0.0, -2160.0),
		Vector3(40.0, 0.0, -2176.0),
		Vector3(88.0, 0.0, -2160.0),
		Vector3(160.0, 0.0, -2112.0),
		Vector3(200.0, 0.0, -2072.0),
		Vector3(264.0, 0.0, -1952.0),
		Vector3(232.0, 0.0, -1424.0),
		Vector3(176.0, 0.0, -1392.0),
		Vector3(168.0, 0.0, -1384.0),
	], 7.4)
	_add_boat(BoatKind.TUG, [
		Vector3(-696.0, 0.0, -1136.0),
		Vector3(-704.0, 0.0, -1144.0),
		Vector3(-752.0, 0.0, -1736.0),
		Vector3(-736.0, 0.0, -1904.0),
		Vector3(-728.0, 0.0, -1920.0),
		Vector3(-696.0, 0.0, -1952.0),
		Vector3(-688.0, 0.0, -1960.0),
		Vector3(-104.0, 0.0, -2168.0),
		Vector3(40.0, 0.0, -2176.0),
		Vector3(88.0, 0.0, -2160.0),
		Vector3(160.0, 0.0, -2112.0),
		Vector3(200.0, 0.0, -2072.0),
		Vector3(264.0, 0.0, -1952.0),
		Vector3(248.0, 0.0, -1640.0),
		Vector3(232.0, 0.0, -1608.0),
		Vector3(224.0, 0.0, -1600.0),
	], 5.6)


func _add_boat(kind: int, points: Array[Vector3], speed: float) -> void:
	if points.size() < 2:
		return
	var root := Node3D.new()
	root.name = "HarbourBoat_%d" % boats.size()
	add_child(root)
	var body := Node3D.new()
	body.name = "BoatBody"
	root.add_child(body)
	var hull_color: Color
	var length: float
	var width: float
	match kind:
		BoatKind.FERRY:
			hull_color = Color("d7d9d4")
			length = 22.0
			width = 6.2
			ART.box(body, Vector3(0.0, 0.55, 0.0), Vector3(width, 1.1, length), hull_color)
			ART.box(body, Vector3(0.0, 1.5, -0.4), Vector3(width * 0.9, 1.2, length * 0.56), Color("2d4855"))
			ART.box(body, Vector3(0.0, 1.55, -length * 0.5 + 0.1), Vector3(width * 0.8, 0.8, 0.1), Color("14232b"))
			ART.box(body, Vector3(0.0, 2.35, 1.2), Vector3(width * 0.5, 0.35, 3.0), Color("f0c541"))
			ART.label(body, Vector3(0.0, 2.35, 1.35), "FERRY", 22)
		BoatKind.TUG:
			hull_color = Color("b5422d")
			length = 14.0
			width = 5.0
			ART.box(body, Vector3(0.0, 0.5, 0.0), Vector3(width, 1.0, length), hull_color)
			ART.box(body, Vector3(0.0, 1.4, 2.0), Vector3(width * 0.8, 1.3, 4.0), Color("e8ddc4"))
			ART.cylinder(body, Vector3(0.0, 2.5, 2.0), 0.08, 3.0, Color("30383d"))
		_:
			hull_color = Color("e8e5da")
			length = 8.0
			width = 2.6
			ART.box(body, Vector3(0.0, 0.35, 0.0), Vector3(width, 0.7, length), hull_color)
			ART.box(body, Vector3(0.0, 0.95, -0.4), Vector3(width * 0.8, 0.6, 2.6), Color("244b5c"))
	root.global_position = points[0]
	root.look_at(points[1], Vector3.UP)
	var wake := _make_wake()
	root.add_child(wake)
	boats.append({
		"root": root,
		"body": body,
		"wake": wake,
		"points": points,
		"index": 1,
		"speed": speed,
		"kind": kind,
	})


func _make_wake() -> Node3D:
	var wake := Node3D.new()
	wake.name = "Wake"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("dcecf0", 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.02, 9.0)
		strip.mesh = box
		strip.material_override = material
		strip.position = Vector3(side * 1.2, -0.25, 8.0)
		wake.add_child(strip)
	return wake


func _process(delta: float) -> void:
	for boat: Dictionary in boats:
		var root: Node3D = boat["root"]
		var points: Array = boat["points"]
		var target_index: int = boat["index"]
		var target: Vector3 = points[target_index]
		var direction := target - root.global_position
		direction.y = 0.0
		var distance := direction.length()
		var move: float = boat["speed"] * delta
		if distance <= move + 0.5:
			# Out and back along the surveyed channel. Wrapping from the last
			# point to the first drew a straight line across the shore.
			var heading: int = boat.get("heading", 1)
			if target_index + heading < 0 or target_index + heading >= points.size():
				heading = -heading
				boat["heading"] = heading
			boat["index"] = target_index + heading
			root.global_position = target
		else:
			root.global_position += direction.normalized() * move
			root.look_at(root.global_position + direction, Vector3.UP)
		var body: Node3D = boat["body"]
		body.position.y = 0.08 + sin(Time.get_ticks_msec() * 0.0016 + root.global_position.x) * 0.06
		body.rotation.z = sin(Time.get_ticks_msec() * 0.0012 + root.global_position.z) * 0.025
		var wake: Node3D = boat["wake"]
		wake.visible = _player_ref == null or root.global_position.distance_to(_player_ref.global_position) < 330.0


func _count_kind(kind: int) -> int:
	var count := 0
	for boat: Dictionary in boats:
		if int(boat["kind"]) == kind:
			count += 1
	return count
