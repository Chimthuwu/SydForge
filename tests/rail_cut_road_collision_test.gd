extends SceneTree

## P0 regression: where a road crosses the open rail cutting, the street must be
## solid. Previously the road ribbon was drawn over the cut with only the ground
## slab removed underneath, so a ray (and a car) dropped six metres to the
## cutting floor. This suite builds the real Stage B world, finds every road
## segment that crosses the cut centreline, and verifies a bridge deck exists
## with collision.

const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")
const StationInteriors := preload("res://sydney/railway/station_interiors.gd")
const CarScene := preload("res://scenes/vehicles/comet.tscn")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var world: Node3D = CbdWorldScript.new()
	if not world.load_world():
		_check(false, "Stage B world loads")
		_finish()
		return
	get_root().add_child(world)
	for i in 3:
		await process_frame

	var path: Array = StationInteriors.descent_cut_path()
	var crossings: Array[Vector2] = []
	for row: Dictionary in world.data.get("roads", []):
		var points: Array = row.get("points", [])
		for i in range(points.size() - 1):
			var p0_raw: Array = points[i]
			var p1_raw: Array = points[i + 1]
			if p0_raw.size() < 2 or p1_raw.size() < 2:
				continue
			var p0 := Vector2(float(p0_raw[0]), float(p0_raw[1]))
			var p1 := Vector2(float(p1_raw[0]), float(p1_raw[1]))
			for j in range(path.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(p0, p1, path[j], path[j + 1])
				if hit == null:
					continue
				var point: Vector2 = hit
				var known := false
				for other: Vector2 in crossings:
					if other.distance_to(point) < 2.5:
						known = true
						break
				if not known:
					crossings.append(point)

	_check(crossings.size() > 0, "roads cross the rail cutting (%d crossings)" % crossings.size())
	var decks: Node = world.get_node_or_null("RailCutRoadDecks")
	_check(decks != null, "road bridge decks exist over the cutting")
	if decks != null:
		_check(decks.get_child_count() >= crossings.size(), "every crossing has a deck collider (%d decks / %d crossings)" % [decks.get_child_count(), crossings.size()])

	var solid := 0
	for point: Vector2 in crossings:
		var from := Vector3(point.x, 40.0, point.y)
		var to := Vector3(point.x, -20.0, point.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and float(hit.position.y) > -0.35:
			solid += 1
	_check(solid == crossings.size(), "every road crossing stays at street level (%d/%d solid)" % [solid, crossings.size()])

	# A real vehicle dropped on three crossings must land on the deck, not fall
	# into the trench. This exercises the collision shape, not just a ray.
	for action in ["forward", "back", "left", "right", "jump", "sprint"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var car: ArcadeCar = CarScene.instantiate()
	world.add_child(car)
	var landed := 0
	var tested := mini(3, crossings.size())
	for index in tested:
		var point := crossings[index]
		car.global_position = Vector3(point.x, 2.0, point.y)
		car.velocity = Vector3.ZERO
		car.speed = 0.0
		var min_y := 2.0
		for frame in 90:
			await physics_frame
			min_y = minf(min_y, car.global_position.y)
		if min_y > -1.0:
			landed += 1
	_check(landed == tested, "dropped cars land on every tested road deck (%d/%d)" % [landed, tested])

	_finish()


func _finish() -> void:
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
