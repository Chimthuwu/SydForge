extends SceneTree

## Airborne physics regression for AI traffic vehicles.
##
## The previous controller overwrote velocity.y every physics tick, so a car
## that left a ledge accumulated only one frame of gravity and appeared to fly.
## These gates verify that both an ambulance and an ordinary sedan fall under
## gravity, preserve horizontal momentum, land without snapping, and resume
## route-following. Geometry is a minimal physics world so the numbers are
## deterministic; the Opera House case is covered in the canonical-world test
## below it.

const VehicleControllerScript := preload("res://sydney/ecosystem/vehicle_traffic_controller.gd")

## Emulates the pre-fix integration for an A/B measurement in the same scene.
class LegacyTrafficVehicle extends VehicleTrafficController:
	func _move_with_air_physics(horizontal: Vector3, step: float) -> void:
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		velocity.y = -9.8 * step # overwritten every tick; gravity never accumulates
		move_and_slide()


var _checks := 0
var _failures := 0
var test_root: Node


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


func _box(parent: Node, center: Vector3, size: Vector3, rotation_x: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	body.rotation.x = rotation_x
	parent.add_child(body)
	return body


func _make_vehicle(vclass: int) -> VehicleTrafficController:
	var vehicle := VehicleControllerScript.new()
	vehicle.vehicle_class = vclass
	test_root.add_child(vehicle)
	return vehicle


## Returns a record of the fall: y samples, vy samples and the landing frame.
func _fall(vehicle: VehicleTrafficController, frames: int = 150) -> Dictionary:
	var ys: Array[float] = []
	var vys: Array[float] = []
	var landing := -1
	for i in frames:
		await physics_frame
		ys.append(vehicle.global_position.y)
		vys.append(vehicle.velocity.y)
		if landing < 0 and vehicle.is_on_floor():
			landing = i
	return {"y": ys, "vy": vys, "landing": landing}


func _assert_fall(record: Dictionary, label: String, ground_y: float) -> void:
	var vys: Array[float] = record["vy"]
	var ys: Array[float] = record["y"]
	var landing: int = record["landing"]
	_check(landing >= 0, "%s: lands on the ground" % label)
	if landing < 0:
		return
	var freefall := mini(landing, 40)
	var monotonic := true
	var upward := false
	var max_step := 0.0
	for i in freefall:
		if i > 0 and vys[i] > vys[i - 1] + 0.02:
			monotonic = false
		if i > 1 and vys[i] > 0.01:
			upward = true
		if i > 0:
			max_step = maxf(max_step, absf(ys[i] - ys[i - 1]))
	_check(monotonic, "%s: vertical velocity becomes progressively more negative" % label)
	_check(not upward, "%s: no unexplained upward velocity in free fall" % label)
	_check(max_step < 1.2, "%s: no teleport/snap while falling (max step %.2f m)" % [label, max_step])
	_check(absf(ys[landing] - ground_y) < 1.5,
		"%s: settles at ground height (%.2f)" % [label, ys[landing]])
	_check(absf(vys[mini(landing + 3, vys.size() - 1)]) < 2.0,
		"%s: no excessive bouncing after landing" % label)


func _run() -> void:
	test_root = get_root()
	# Flat ground, then a kerb and a ramp as separate isolated worlds.
	var ground := _box(test_root, Vector3(0.0, -0.5, 0.0), Vector3(160.0, 1.0, 160.0))

	var ambulance := _make_vehicle(VehicleVisualBuilder.VehicleClass.AMBULANCE)
	ambulance.global_position = Vector3(0.0, 20.0, 0.0)
	ambulance.velocity = Vector3.ZERO
	var amb_record := await _fall(ambulance)
	_assert_fall(amb_record, "ambulance / flat ground", 1.0)
	ambulance.queue_free()

	var sedan := _make_vehicle(VehicleVisualBuilder.VehicleClass.SEDAN)
	sedan.global_position = Vector3(0.0, 20.0, 0.0)
	sedan.velocity = Vector3.ZERO
	_assert_fall(await _fall(sedan), "sedan / flat ground", 1.0)
	sedan.queue_free()
	await _frames(2)

	# Kerb: a 0.5 m step. The car must not gain upward velocity from its edge.
	var kerb := _box(test_root, Vector3(20.0, 0.25, 0.0), Vector3(8.0, 0.5, 8.0))
	var kerb_car := _make_vehicle(VehicleVisualBuilder.VehicleClass.SEDAN)
	kerb_car.global_position = Vector3(20.0, 14.0, 0.0)
	kerb_car.velocity = Vector3.ZERO
	var kerb_record := await _fall(kerb_car)
	_assert_fall(kerb_record, "sedan / kerb", 0.75)
	kerb_car.queue_free()

	# Small ramp: landing on a slope must not launch the vehicle.
	var ramp := _box(test_root, Vector3(-20.0, 1.0, 0.0), Vector3(8.0, 0.4, 8.0), -0.18)
	var ramp_car := _make_vehicle(VehicleVisualBuilder.VehicleClass.SEDAN)
	ramp_car.global_position = Vector3(-20.0, 14.0, 0.0)
	ramp_car.velocity = Vector3.ZERO
	_assert_fall(await _fall(ramp_car), "sedan / ramp", 1.4)
	ramp_car.queue_free()

	# Route-following while airborne: horizontal steering must not cancel fall.
	var routed := _make_vehicle(VehicleVisualBuilder.VehicleClass.SEDAN)
	var pts: Array[Vector3] = [Vector3(-60.0, 0.2, 0.0), Vector3(-20.0, 0.2, 0.0), Vector3(20.0, 0.2, 0.0)]
	routed.setup_route(pts, 1.9, true)
	routed.global_position = Vector3(-40.0, 16.0, 0.0)
	routed.velocity = Vector3.ZERO
	var routed_record := await _fall(routed, 180)
	_assert_fall(routed_record, "routed sedan / flat ground", 1.0)
	_check(absf(routed.global_position.z) < 8.0,
		"routed sedan keeps its lane while falling (z = %.2f)" % routed.global_position.z)
	routed.queue_free()

	# A/B: the same drop using the old overwrite formula stays almost at its
	# starting height after three seconds, proving the root cause.
	var legacy := LegacyTrafficVehicle.new()
	legacy.vehicle_class = VehicleVisualBuilder.VehicleClass.AMBULANCE
	test_root.add_child(legacy)
	legacy.global_position = Vector3(60.0, 20.0, 0.0)
	legacy.velocity = Vector3.ZERO
	var legacy_ys: Array[float] = []
	for i in 180:
		await physics_frame
		legacy_ys.append(legacy.global_position.y)
	var legacy_end: float = legacy_ys[legacy_ys.size() - 1]
	print("LEGACY_Y_AFTER_180_FRAMES %.2f (fixed ambulance landed at %.2f)" % [
		legacy_end, amb_record["y"][amb_record["landing"]]])
	_check(legacy_end > 15.0, "pre-fix formula floats: legacy ambulance stays above 15 m")
	legacy.queue_free()

	ground.queue_free()
	kerb.queue_free()
	ramp.queue_free()
	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
