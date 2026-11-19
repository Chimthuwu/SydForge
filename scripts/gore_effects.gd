extends RefCounted

const DARK_BLOOD := Color("650812")
const FRESH_BLOOD := Color("bd1024")
const BRIGHT_BLOOD := Color("ec2637")
const FEATHER := Color("e9e6db")


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
