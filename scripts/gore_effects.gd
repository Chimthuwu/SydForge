extends RefCounted

const DARK_BLOOD := Color("650812")
const FRESH_BLOOD := Color("bd1024")
const BRIGHT_BLOOD := Color("ec2637")
const FEATHER := Color("e9e6db")
const SKIN := Color("d9a079")
const CLOTH := Color("3d4850")

## Physics-driven body destruction. Limbs are separate RigidBody3D chunks with
## real mass and momentum, so a vehicle strike throws body parts instead of
## dissolving the character into a puff of red spheres.
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
	var parts := [
		{"size": Vector3(0.22, 0.26, 0.22), "color": skin_color, "offset": Vector3(0.0, 0.9, 0.0)},
		{"size": Vector3(0.42, 0.5, 0.24), "color": cloth_color, "offset": Vector3(0.0, 0.25, 0.0)},
		{"size": Vector3(0.16, 0.7, 0.18), "color": cloth_color, "offset": Vector3(-0.22, 0.5, 0.0)},
		{"size": Vector3(0.16, 0.7, 0.18), "color": cloth_color, "offset": Vector3(0.22, 0.5, 0.0)},
		{"size": Vector3(0.14, 0.65, 0.16), "color": skin_color, "offset": Vector3(-0.34, 0.85, 0.0)},
		{"size": Vector3(0.14, 0.65, 0.16), "color": skin_color, "offset": Vector3(0.34, 0.85, 0.0)},
	]
	if feathers:
		for part: Dictionary in parts:
			part["color"] = FEATHER
		for index in 10:
			parts.append({
				"size": Vector3(0.05, 0.02, 0.22), "color": FEATHER,
				"offset": Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.2, 0.9), rng.randf_range(-0.2, 0.2))
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
		mat.roughness = 0.85
		mesh.material_override = mat
		chunk.add_child(mesh)
		var shape := CollisionShape3D.new()
		var body_shape := BoxShape3D.new()
		body_shape.size = spec["size"]
		shape.shape = body_shape
		chunk.add_child(shape)
		chunk.mass = 0.8 if spec["size"].y < 0.3 else 1.8
		root.add_child(chunk)
		chunk.global_position = root.global_position + spec["offset"]
		var launch := velocity * rng.randf_range(0.35, 0.85)
		launch += Vector3(
			rng.randf_range(-3.5, 3.5),
			rng.randf_range(2.0, 6.5),
			rng.randf_range(-3.5, 3.5)
		)
		chunk.linear_velocity = launch
		chunk.angular_velocity = Vector3(
			rng.randf_range(-9.0, 9.0),
			rng.randf_range(-9.0, 9.0),
			rng.randf_range(-9.0, 9.0)
		)
	_spawn_burst(root, position, 2.2, 26, false, true)
	_spawn_pool(parent, position, 1.8)
	var cleanup := parent.get_tree().create_timer(9.0)
	cleanup.timeout.connect(root.queue_free)


static func spawn_hit_spray(
	parent: Node3D,
	position: Vector3,
	intensity: float = 1.0,
	shot_direction: Vector3 = Vector3.FORWARD
) -> void:
	if not is_instance_valid(parent):
		return
	_spawn_impact_mark(parent,position,shot_direction,intensity)
	_spawn_burst(parent,position,intensity,18,false,false)


static func spawn_death_splatter(
	parent: Node3D,
	position: Vector3,
	intensity: float = 1.0,
	feathers: bool = false
) -> void:
	if not is_instance_valid(parent):
		return
	_spawn_pool(parent,position,1.25 * intensity)
	_spawn_burst(parent,position + Vector3.UP * 0.8 * intensity,intensity,40,feathers,true)


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
	for index in fragment_count:
		var is_feather := feathers and index % 4 == 0
		var fragment := MeshInstance3D.new()
		if is_feather:
			var feather_mesh := BoxMesh.new()
			feather_mesh.size = Vector3(0.045,0.018,0.2)
			fragment.mesh = feather_mesh
		else:
			var gore_mesh := SphereMesh.new()
			gore_mesh.radius = 0.5
			gore_mesh.height = 1.0
			gore_mesh.radial_segments = 8
			gore_mesh.rings = 4
			fragment.mesh = gore_mesh
		var material := StandardMaterial3D.new()
		if is_feather:
			material.albedo_color = FEATHER
		else:
			material.albedo_color = [DARK_BLOOD,FRESH_BLOOD,BRIGHT_BLOOD][index % 3]
		fragment.material_override = material
		var size := randf_range(0.055,0.15) * intensity
		if heavy and index % 7 == 0:
			size *= 1.65
		fragment.scale = Vector3(size,size,size * (2.4 if is_feather else randf_range(0.8,1.8)))
		fragment.position = Vector3(0,randf_range(0.0,0.3),0)
		burst.add_child(fragment)
		var direction := Vector3(
			randf_range(-1.0,1.0),
			randf_range(0.15,1.15) if heavy else randf_range(-0.1,0.8),
			randf_range(-1.0,1.0)
		).normalized()
		var travel := randf_range(0.35,1.8) * intensity if heavy else randf_range(0.2,0.65)
		var flight_time := randf_range(0.35,0.95) if heavy else 0.35
		var tween := burst.create_tween()
		tween.parallel().tween_property(
			fragment,"position",
			fragment.position + direction * travel + Vector3.DOWN * 0.25 * intensity,
			flight_time
		)
		tween.parallel().tween_property(fragment,"scale",Vector3.ZERO,flight_time + 0.2)
		tween.tween_callback(fragment.queue_free)
	var cleanup := parent.get_tree().create_timer(2.0 if not heavy else 3.0)
	cleanup.timeout.connect(burst.queue_free)


static func _spawn_pool(parent: Node3D, position: Vector3, radius: float) -> void:
	var pool := MeshInstance3D.new()
	pool.name = "BloodPool"
	var disk := CylinderMesh.new()
	disk.top_radius = radius * 0.86
	disk.bottom_radius = radius
	disk.height = 0.035
	disk.radial_segments = 20
	pool.mesh = disk
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34,0.004,0.018,0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	pool.material_override = material
	parent.add_child(pool)
	pool.global_position = position + Vector3.UP * 0.035
	var cleanup := parent.get_tree().create_timer(22.0)
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
	mesh.radial_segments = 12
	mesh.rings = 6
	mark.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.52,0.008,0.025,0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	mark.material_override = material
	parent.add_child(mark)
	var normal := shot_direction.normalized()
	if normal.length_squared() < 0.01:
		normal = Vector3.FORWARD
	mark.global_position = position + normal * 0.025
	mark.look_at(mark.global_position + normal,Vector3.UP)
	mark.scale = Vector3(0.24,0.20,0.035) * intensity
	var tween := parent.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(mark,"scale",Vector3.ZERO,0.25)
	tween.tween_callback(mark.queue_free)
