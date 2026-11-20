extends SceneTree

## Windowed gameplay verification of AI ambulance airborne physics on the real
## Opera House stair collision. Run without --headless.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")
const PODIUM_CENTRE := Vector3(658.72, 12.02, -1763.815)
const STEPS_AXIS := Vector2(0.229723, -0.973256)

var scene: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


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
		var blocked := false
		for overlap in space.intersect_shape(probe, 16):
			var other: Object = overlap.get("collider")
			if other is Node and (other as Node).name == "BuildingCollision":
				blocked = true
				break
		if blocked:
			continue
		return {"pos": Vector3(candidate.x, hit_y + 0.35, candidate.z), "y": hit_y}
	return {}


func _save(name: String) -> void:
	var img := get_root().get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path("res://tests/airborne_%s.png" % name))
		print("CAPTURE %s" % name)


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	for i in 30:
		await process_frame

	var outward := Vector3(-STEPS_AXIS.x, 0.0, -STEPS_AXIS.y)
	var placement := _find_clear_stair_point(outward)
	if placement.is_empty():
		print("NO CLEAR STAIR TREAD FOUND")
		quit(1)
		return
	var start: Vector3 = placement["pos"]

	var ambulance := VehicleTrafficController.new()
	ambulance.vehicle_class = VehicleVisualBuilder.VehicleClass.AMBULANCE
	scene.add_child(ambulance)
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(start + outward * (float(i) * 18.0))
	ambulance.road_points = pts
	ambulance.current_point_idx = 0
	ambulance.road_forward_dir = 1
	ambulance.lane_offset = 0.0
	ambulance.current_lane_offset = 0.0
	ambulance.target_lane_offset = 0.0
	ambulance.global_position = start
	ambulance.velocity = Vector3.ZERO
	ambulance.current_speed = 7.0

	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 2000.0
	scene.add_child(camera)
	camera.current = true

	var marks := [0, 20, 45, 75, 110, 150]
	for i in 165:
		await process_frame
		var target := ambulance.global_position + Vector3(0.0, 1.0, 0.0)
		camera.global_position = target + Vector3(13.0, 6.0, 17.0)
		camera.look_at(target, Vector3.UP)
		if marks.has(i):
			print("FLIGHT %d y=%.2f vy=%.2f speed=%.1f" % [
				i, ambulance.global_position.y, ambulance.velocity.y, ambulance.current_speed])
			_save("flight_%03d" % i)
	quit(0)
