extends SceneTree

## L91 bounded step: scripted drive-over of every repaired rail-cutting road
## crossing. The P0 suite (rail_cut_road_collision_test.gd) ray-probes all 14
## crossings and drops a parked car on three; this one physically DRIVES a
## vehicle across every deck along its road heading and fails if the car
## drops toward the cutting floor or stalls short of the far side. Camera
## feel and the live drive still belong to the human sign-off pass.

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


## Walk BACK along the road polyline from the crossing point until the
## approach distance is covered; returns the start position on the carriageway.
func _walk_back(points: Array, seg: int, point: Vector2, dist: float) -> Vector2:
	var remaining := dist
	var cur := point
	var i := seg
	while remaining > 0.05 and i >= 0:
		var a_raw: Array = points[i]
		var a := Vector2(float(a_raw[0]), float(a_raw[1]))
		var to_a := cur.distance_to(a)
		if to_a >= remaining:
			var d := (cur - a).normalized()
			return cur - d * remaining
		remaining -= to_a
		cur = a
		i -= 1
	return cur

func _run() -> void:
	for action in ["forward", "back", "left", "right", "jump", "sprint"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	var world: Node3D = CbdWorldScript.new()
	if not world.load_world():
		_check(false, "Stage B world loads")
		_finish()
		return
	get_root().add_child(world)
	for i in 3:
		await process_frame

	# Same crossing discovery as the P0 suite, but keep each crossing's road
	# polyline so the car can be placed ON the carriageway (roads curve; a
	# straight-line back-step lands in grass or buildings).
	var path: Array = StationInteriors.descent_cut_path()
	var crossings: Array = []  # [{point: Vector2, points: Array, seg: int}]
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
				var point := Vector2(hit)
				var known := false
				for other: Dictionary in crossings:
					if other.point.distance_to(point) < 2.5:
						known = true
						break
				if not known:
					crossings.append({"point": point, "points": points, "seg": i})
	_check(crossings.size() >= 1, "cutting crossings discovered (%d)" % crossings.size())

	var car: ArcadeCar = CarScene.instantiate()
	world.add_child(car)

	var crossed := 0
	var index := 0
	for c: Dictionary in crossings:
		index += 1
		var point: Vector2 = c.point
		var row_points: Array = c.points
		var seg_i: int = c.seg
		var forward_start := _walk_back(row_points, seg_i, point, 15.0)
		var ahead_raw: Array = row_points[mini(seg_i + 1, row_points.size() - 1)]
		var ahead := Vector2(float(ahead_raw[0]), float(ahead_raw[1]))
		var dir := (ahead - point).normalized()
		if dir.length_squared() < 0.5:
			dir = (point - forward_start).normalized()
		# Try the natural heading first; if the car cannot roll (spawn wedged
		# beside a deck slab, or the polyline starts at the crossing), retry
		# from the other direction like a real driver would.
		var attempts := [[forward_start, dir], [_walk_back(row_points, seg_i, point, 15.0) * -1.0 + 2.0 * point, -dir]]
		var ok := false
		var best := ""
		for attempt: Array in attempts:
			var start: Vector2 = attempt[0]
			var heading: Vector2 = attempt[1]
			car.global_position = Vector3(start.x, 2.0, start.y)
			car.rotation = Vector3(0.0, atan2(-heading.x, -heading.y), 0.0)
			car.velocity = Vector3.ZERO
			car.speed = 0.0
			car.set("ai_controlled", true)
			car.set("ai_forward", 1.0)
			car.set("ai_turn", 0.0)
			var min_y := 2.0
			var progress := -1.0
			for frame in 240:
				await physics_frame
				min_y = minf(min_y, car.global_position.y)
				var rel := Vector2(car.global_position.x, car.global_position.z) - point
				progress = maxf(progress, rel.dot(heading))
				if progress > 12.0 and frame > 30:
					break
			if min_y > -1.0 and progress > 12.0:
				ok = true
				best = "min_y=%.2f progress=%.1f m" % [min_y, progress]
				break
			best = "min_y=%.2f progress=%.1f m start=(%.1f, %.1f)" % [min_y, progress, start.x, start.y]
			car.set("ai_controlled", false)
			car.set("ai_forward", 0.0)
		if ok:
			crossed += 1
		print("DRIVEOVER %s crossing %d/%d | %s" % ["PASS" if ok else "FAIL", index, crossings.size(), best])
		car.set("ai_controlled", false)
		car.set("ai_forward", 0.0)

	_check(crossed == crossings.size(), "drive-over holds street level at every crossing (%d/%d)" % [crossed, crossings.size()])
	_finish()

func _finish() -> void:
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
