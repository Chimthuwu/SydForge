extends RefCounted

const DARK_BLOOD := Color("4a0508")
const FRESH_BLOOD := Color("8f0b18")
const BRIGHT_BLOOD := Color("c71324")
const FEATHER := Color("e9e6db")
const SKIN := Color("d9a079")
const CLOTH := Color("3d4850")

## High-gore, physics-driven body destruction. Bodies rupture into multiple chunks
## with real momentum so impacts (especially shotguns/vehicles) throw parts and
## leave heavy blood traces.
static func spawn_body_destruction(
	parent: Node3D,
	position: Vector3,
	velocity: Vector3,
	skin_color: Color = SKIN,
	cloth_color: Color = CLOTH,
	feathers: bool = false
) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "BodyDebris"
	parent.add_child(root)
	root.global_position = position
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	var intensity := clampf(velocity.length() / 6.0, 1.0, 5.0)
	var parts: Array[Dictionary] = [
		{"size": Vector3(0.24, 0.26, 0.22), "color": skin_color, "offset": Vector3(0.0, 0.95, 0.0), "mass": 1.2}, # head
		{"size": Vector3(0.44, 0.34, 0.26), "color": cloth_color, "offset": Vector3(0.0, 0.48, 0.0), "mass": 2.2}, # upper torso
		{"size": Vector3(0.36, 0.28, 0.22), "color": cloth_color, "offset": Vector3(0.0, 0.12, 0.0), "mass": 1.8}, # pelvis
		{"size": Vector3(0.15, 0.62, 0.16), "color": cloth_color, "offset": Vector3(-0.22, 0.55, 0.0), "mass": 1.4}, # upper leg L
		{"size": Vector3(0.15, 0.62, 0.16), "color": cloth_color, "offset": Vector3(0.22, 0.55, 0.0), "mass": 1.4}, # upper leg R
		{"size": Vector3(0.13, 0.58, 0.14), "color": skin_color, "offset": Vector3(-0.28, -0.02, 0.02), "mass": 1.0}, # lower leg L
		{"size": Vector3(0.13, 0.58, 0.14), "color": skin_color, "offset": Vector3(0.28, -0.02, 0.02), "mass": 1.0}, # lower leg R
		{"size": Vector3(0.13, 0.56, 0.14), "color": skin_color, "offset": Vector3(-0.36, 0.92, 0.0), "mass": 0.9}, # upper arm L
		{"size": Vector3(0.13, 0.56, 0.14), "color": skin_color, "offset": Vector3(0.36, 0.92, 0.0), "mass": 0.9}, # upper arm R
		{"size": Vector3(0.11, 0.50, 0.12), "color": skin_color, "offset": Vector3(-0.42, 0.40, 0.0), "mass": 0.7}, # lower arm L
		{"size": Vector3(0.11, 0.50, 0.12), "color": skin_color, "offset": Vector3(0.42, 0.40, 0.0), "mass": 0.7}, # lower arm R
	]
	# Extra flesh/gib fragments for very gory destruction (shotguns, heavy impacts).
	for _i in clampi(int(10.0 + intensity * 6.0), 10, 28):
		var is_bone := rng.randf() < 0.25
		parts.append({
			"size": Vector3(
				rng.randf_range(0.05, 0.16),
				rng.randf_range(0.04, 0.18),
				rng.randf_range(0.05, 0.22)
			),
			"color": Color("e6dcc8") if is_bone else [DARK_BLOOD, FRESH_BLOOD, skin_color.darkened(0.1)][rng.randi() % 3],
			"offset": Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 1.0), rng.randf_range(-0.25, 0.25)),
			"mass": rng.randf_range(0.2, 0.7),
			"gib": true,
		})
	if feathers:
		for part: Dictionary in parts:
			if not bool(part.get("gib", false)):
				part["color"] = FEATHER
		for _index in 24:
			parts.append({
				"size": Vector3(0.05, 0.02, 0.22), "color": FEATHER,
				"offset": Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.2, 0.95), rng.randf_range(-0.25, 0.25)),
				"mass": 0.12,
			})
	for spec: Dictionary in parts:
		var chunk := RigidBody3D.new()
		chunk.name = "BodyChunk"
		var box := BoxMesh.new()
		box.size = spec["size"]
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec["color"]
		mat.roughness = 0.9
		mesh.material_override = mat
		chunk.add_child(mesh)
		var shape := CollisionShape3D.new()
		var body_shape := BoxShape3D.new()
		body_shape.size = spec["size"]
		shape.shape = body_shape
		chunk.add_child(shape)
		chunk.mass = float(spec.get("mass", 1.0))
		root.add_child(chunk)
		chunk.global_position = root.global_position + spec["offset"]
		var spread := 2.5 + intensity * 1.4
		var launch := velocity * rng.randf_range(0.45, 1.1)
		launch += Vector3(
			rng.randf_range(-spread, spread),
			rng.randf_range(1.5, 3.5 + intensity * 1.4),
			rng.randf_range(-spread, spread)
		)
		chunk.linear_velocity = launch
		chunk.angular_velocity = Vector3(
			rng.randf_range(-14.0, 14.0),
			rng.randf_range(-14.0, 14.0),
			rng.randf_range(-14.0, 14.0)
		)
		var settle_time := 2.8 if bool(spec.get("gib", false)) else 3.4
		var settle := parent.get_tree().create_timer(settle_time)
		settle.timeout.connect(func() -> void:
			if is_instance_valid(chunk):
				chunk.freeze = true
		)
	# Layered blood: heavy burst, secondary splatter, and multiple pools.
	_spawn_burst(root, position + Vector3.UP * 0.7, 3.2 * intensity, 70, feathers, true)
	_spawn_burst(root, position + Vector3.UP * 0.4, 2.4 * intensity, 45, feathers, true)
	_spawn_burst(parent, position + Vector3.UP * 0.9, 2.0 * intensity, 35, feathers, true)
	_spawn_pool(parent, position, 2.2 * intensity)
	_spawn_pool(parent, position + Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8)), 1.4 * intensity)
	_spawn_pool(parent, position + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2)), 1.0 * intensity)
	var cleanup := parent.get_tree().create_timer(12.0)
	cleanup.timeout.connect(root.queue_free)


static func spawn_hit_spray(
	parent: Node3D,
	position: Vector3,
	intensity: float = 1.0,
	shot_direction: Vector3 = Vector3.FORWARD
) -> void:
	if not is_instance_valid(parent):
		return
	var power := clampf(intensity, 0.6, 6.0)
	_spawn_impact_mark(parent, position, shot_direction, power)
	_spawn_burst(parent, position, power, clampi(int(24.0 + power * 10.0), 24, 90), false, power >= 1.6)
	if power >= 1.4:
		_spawn_burst(parent, position + shot_direction.normalized() * 0.15, power * 0.8, clampi(int(14.0 + power * 6.0), 14, 60), false, false)
	if power >= 2.2:
		_spawn_pool(parent, position, 0.55 + power * 0.18)


static func spawn_death_splatter(
	parent: Node3D,
	position: Vector3,
	intensity: float = 1.0,
	feathers: bool = false
) -> void:
	if not is_instance_valid(parent):
		return
	var power := clampf(intensity, 0.8, 5.0)
	_spawn_pool(parent, position, 1.8 * power)
	_spawn_pool(parent, position + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)), 1.1 * power)
	_spawn_burst(parent, position + Vector3.UP * 0.8 * power, power, clampi(int(60.0 + power * 18.0), 60, 140), feathers, true)
	_spawn_burst(parent, position + Vector3.UP * 0.35, power * 0.9, clampi(int(30.0 + power * 10.0), 30, 90), feathers, true)


static func _spawn_burst(
	parent: Node3D,
	position: Vector3,
	intensity: float,
	fragment_count: int,
	feathers: bool,
	heavy: bool
) -> void:
	if not is_instance_valid(parent):
		return
	var burst := Node3D.new()
	burst.name = "GoreBurst"
	parent.add_child(burst)
	burst.global_position = position
	var count := clampi(fragment_count, 1, 220)
	for index in count:
		var is_feather := feathers and index % 4 == 0
		var fragment := MeshInstance3D.new()
		var shape_roll := randf()
		if is_feather:
			var feather_mesh := BoxMesh.new()
			feather_mesh.size = Vector3(0.045, 0.018, 0.22)
			fragment.mesh = feather_mesh
		elif heavy and shape_roll < 0.35:
			var chunk_mesh := BoxMesh.new()
			chunk_mesh.size = Vector3(
				randf_range(0.03, 0.09),
				randf_range(0.03, 0.09),
				randf_range(0.04, 0.14)
			)
			fragment.mesh = chunk_mesh
		else:
			var gore_mesh := SphereMesh.new()
			gore_mesh.radius = 0.5
			gore_mesh.height = 1.0
			gore_mesh.radial_segments = 6
			gore_mesh.rings = 3
			fragment.mesh = gore_mesh
		var material := StandardMaterial3D.new()
		if is_feather:
			material.albedo_color = FEATHER
		else:
			material.albedo_color = [DARK_BLOOD, FRESH_BLOOD, BRIGHT_BLOOD][index % 3]
			material.roughness = 0.95
		fragment.material_override = material
		var base_size := randf_range(0.05, 0.18) * clampf(intensity, 0.6, 6.0)
		if heavy and index % 5 == 0:
			base_size *= 1.8
		if is_feather:
			fragment.scale = Vector3(base_size, base_size, base_size * 2.6)
		elif fragment.mesh is BoxMesh:
			fragment.scale = Vector3(base_size * 1.4, base_size * 1.4, base_size * 1.4)
		else:
			fragment.scale = Vector3(base_size, base_size, base_size * randf_range(0.8, 2.0))
		fragment.position = Vector3(randf_range(-0.08, 0.08), randf_range(0.0, 0.35), randf_range(-0.08, 0.08))
		burst.add_child(fragment)
		var direction := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.35) if heavy else randf_range(-0.05, 0.9),
			randf_range(-1.0, 1.0)
		).normalized()
		var travel := randf_range(0.45, 2.6) * clampf(intensity, 0.6, 6.0) if heavy else randf_range(0.25, 0.9) * clampf(intensity, 0.6, 4.0)
		var flight_time := randf_range(0.35, 1.1) if heavy else randf_range(0.22, 0.45)
		var tween := burst.create_tween()
		tween.parallel().tween_property(
			fragment, "position",
			fragment.position + direction * travel + Vector3.DOWN * (0.35 * clampf(intensity, 0.6, 4.0)),
			flight_time
		)
		tween.parallel().tween_property(fragment, "scale", Vector3.ZERO, flight_time + 0.25)
		tween.tween_callback(fragment.queue_free)
	var cleanup := parent.get_tree().create_timer(2.2 if not heavy else 3.4)
	cleanup.timeout.connect(burst.queue_free)


static func _spawn_pool(parent: Node3D, position: Vector3, radius: float) -> void:
	var pool := MeshInstance3D.new()
	pool.name = "BloodPool"
	var r := clampf(radius, 0.2, 6.0)
	var disk := CylinderMesh.new()
	disk.top_radius = r * 0.86
	disk.bottom_radius = r
	disk.height = 0.03
	disk.radial_segments = 20
	pool.mesh = disk
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.003, 0.014, 0.94)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	pool.material_override = material
	parent.add_child(pool)
	pool.global_position = position + Vector3.UP * randf_range(0.028, 0.04)
	pool.rotation.y = randf() * TAU
	var cleanup := parent.get_tree().create_timer(28.0)
	cleanup.timeout.connect(pool.queue_free)


static func _spawn_impact_mark(
	parent: Node3D,
	position: Vector3,
	shot_direction: Vector3,
	intensity: float
) -> void:
	var mark := MeshInstance3D.new()
	mark.name = "BloodImpactMark"
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	mark.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.006, 0.02, 0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	mark.material_override = material
	parent.add_child(mark)
	var normal := shot_direction.normalized()
	if normal.length_squared() < 0.01:
		normal = Vector3.FORWARD
	mark.global_position = position + normal * 0.03
	mark.look_at(mark.global_position + normal, Vector3.UP)
	var s := clampf(intensity, 0.6, 6.0)
	mark.scale = Vector3(0.30, 0.24, 0.04) * s
	var tween := parent.create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(mark, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(mark.queue_free)
