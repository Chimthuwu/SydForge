extends SceneTree

## Canonical-world airborne verification: the player's ArcadeCar and a hijacked
## AI ambulance driven off the Opera House podium steps. Uses the real Sydney
## collision geometry, not synthetic boxes.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

const PODIUM_CENTRE := Vector3(658.72, 12.02, -1763.815)
## Positive axis points toward the harbour; steps descend toward -axis.
const STEPS_AXIS := Vector2(0.229723, -0.973256)

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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _sample(vehicle: Node3D, frames: int) -> Dictionary:
	var ys: Array[float] = []
	var vys: Array[float] = []
	var airborne_start := -1
	var landing := -1
	for i in frames:
		await physics_frame
		ys.append(vehicle.global_position.y)
		vys.append(vehicle.velocity.y)
		var grounded: bool = vehicle.is_on_floor()
		if airborne_start < 0 and not grounded:
			airborne_start = i
		elif airborne_start >= 0 and landing < 0 and grounded:
			landing = i
	return {"y": ys, "vy": vys, "air": airborne_start, "landing": landing}


func _assert_falls(record: Dictionary, label: String, ground_min: float, ground_max: float) -> void:
	var ys: Array[float] = record["y"]
	var vys: Array[float] = record["vy"]
	var air: int = record["air"]
	var landing: int = record["landing"]
	_check(air >= 0, "%s: loses ground contact" % label)
	if air < 0:
		return
	_check(landing >= 0, "%s: reaches ground contact again" % label)
	var flight_end := landing if landing >= 0 else ys.size()
	var monotonic := true
	for i in range(maxi(air + 1, 0), mini(flight_end, air + 90)):
		if vys[i] > vys[i - 1] + 0.05:
			monotonic = false
	_check(monotonic, "%s: vertical velocity keeps decreasing in free fall" % label)
	var min_vy := 0.0
	for i in range(air, flight_end):
		min_vy = minf(min_vy, vys[i])
	_check(min_vy < -3.0, "%s: gravity builds real downward speed (%.2f m/s)" % [label, min_vy])
	var max_up := 0.0
	for i in range(air, flight_end):
		max_up = maxf(max_up, vys[i])
	_check(max_up < 2.0, "%s: no unexplained upward launch (max %.2f m/s)" % [label, max_up])
	if landing >= 0:
		_check(ys[landing] >= ground_min and ys[landing] <= ground_max,
			"%s: lands on a solid surface (%.2f m)" % [label, ys[landing]])


## Scan the real stair band for a tread whose collision is OperaCollision and
## which is not buried inside one of the dense OSM building shells.
func _find_clear_stair_point(outward: Vector3) -> Dictionary:
	var space := scene.get_world_3d().direct_space_state
	for distance in range(40, 105, 2):
		var candidate: Vector3 = PODIUM_CENTRE + outward * float(distance)
		var down := PhysicsRayQueryParameters3D.create(
			candidate + Vector3.UP * 30.0, candidate - Vector3.UP * 35.0, 1, []
		)
		var hit := space.intersect_ray(down)
		if hit.is_empty():
			continue
		var collider: Object = hit.get("collider")
		if collider == null or (collider is Node and (collider as Node).name != "OperaCollision"):
			continue
		var hit_y: float = float(hit.get("position", Vector3.ZERO).y)
		if hit_y < 0.5 or hit_y > 11.5:
			continue
		var probe := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 5.0
		probe.shape = sphere
		probe.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * (hit_y + 1.0))
		var overlaps := space.intersect_shape(probe, 16)
		var blocked := false
		for overlap in overlaps:
			var other: Object = overlap.get("collider")
			if other is Node and (other as Node).name == "BuildingCollision":
				blocked = true
				break
		if blocked:
			continue
		return {"pos": Vector3(candidate.x, hit_y + 0.35, candidate.z), "y": hit_y}
	return {}


func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(30)

	# 1. Player ArcadeCar: verify gravity is preserved on the production car.
	var cars: Array = scene.get("vehicles")
	_check(cars.size() >= 1, "canonical world owns the player car fleet")
	if not cars.is_empty():
		var car: Node3D = cars[0]
		car.global_position = Vector3(270.0, 34.0, -300.0) # over Hyde Park
		car.velocity = Vector3.ZERO
		car.set("speed", 0.0)
		await _frames(3)
		var car_record := await _sample(car, 200)
		_assert_falls(car_record, "player ArcadeCar / Hyde Park drop", -1.0, 2.0)

	# 2. Hijacked AI ambulance driven off the Opera House podium steps.
	var ambulance := VehicleTrafficController.new()
	ambulance.vehicle_class = VehicleVisualBuilder.VehicleClass.AMBULANCE
	scene.add_child(ambulance)
	var outward := Vector3(-STEPS_AXIS.x, 0.0, -STEPS_AXIS.y)
	var placement := _find_clear_stair_point(outward)
	_check(placement.size() > 0, "found an Opera House stair tread clear of other buildings")
	if placement.is_empty():
		_finish()
		return
	var start: Vector3 = placement["pos"]
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(start + outward * (float(i) * 18.0))
	# Assign the route directly: setup_route() would teleport the car to road y.
	ambulance.road_points = pts
	ambulance.current_point_idx = 0
	ambulance.road_forward_dir = 1
	ambulance.lane_offset = 0.0
	ambulance.current_lane_offset = 0.0
	ambulance.target_lane_offset = 0.0
	ambulance.global_position = start
	ambulance.velocity = Vector3.ZERO
	ambulance.current_speed = 7.0
	await _frames(3)
	var start_y: float = ambulance.global_position.y
	_check(start_y > float(placement["y"]) - 1.0,
		"ambulance starts on an Opera House stair (y = %.2f)" % start_y)
	var stair_record := await _sample(ambulance, 300)
	_assert_falls(stair_record, "AI ambulance / Opera House stairs", 0.3, 12.5)
	_check(ambulance.global_position.y < start_y - 3.0,
		"ambulance actually left the stair tread (%.2f -> %.2f)" % [start_y, ambulance.global_position.y])

	_finish()
