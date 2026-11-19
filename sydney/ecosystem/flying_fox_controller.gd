extends Node3D

## A small, distant flying-fox silhouette flock that circles the player at night.

var center_ref: Node3D
var orbit_phase: float = 0.0
var orbit_radius: float = 14.0
var altitude: float = 18.0
var angular_speed: float = 0.35
var anchor_offset := Vector3.ZERO
var wing_left: Node3D
var wing_right: Node3D
var flight_time: float = 0.0


func setup(center: Node3D, index: int) -> void:
	center_ref = center
	orbit_phase = TAU * float(index) / 8.0
	orbit_radius = randf_range(12.0,26.0)
	altitude = randf_range(14.0,23.0)
	angular_speed = randf_range(0.22,0.43) * (1.0 if index % 2 == 0 else -1.0)
	anchor_offset = Vector3(randf_range(-8.0,8.0),0.0,randf_range(-8.0,8.0))
	_build_visual()


func _build_visual() -> void:
	var fur := Color("33242a")
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.42
	body.mesh = body_mesh
	body.position = Vector3(0.0,0.0,0.0)
	body.scale = Vector3(0.78,0.7,1.3)
	body.material_override = _material(fur)
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.24
	head.mesh = head_mesh
	head.position = Vector3(0.0,0.04,-0.22)
	head.material_override = _material(Color("24191e"))
	add_child(head)
	for side in [-1.0,1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius = 0.0
		ear_mesh.bottom_radius = 0.055
		ear_mesh.height = 0.16
		ear_mesh.radial_segments = 5
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.085,0.15,-0.22)
		ear.material_override = _material(Color("2d1c21"))
		add_child(ear)

	wing_left = _make_wing(-1.0,fur)
	wing_right = _make_wing(1.0,fur)
	add_child(wing_left)
	add_child(wing_right)


func _make_wing(side: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * 0.13,0.015,0.015)
	var outline: Array[Vector2] = [
		Vector2(0.0,0.0),Vector2(0.20,0.10),Vector2(0.34,-0.015),
		Vector2(0.47,0.16),Vector2(0.59,-0.025),Vector2(0.73,0.13),
		Vector2(0.84,-0.035),Vector2(1.02,0.08),Vector2(1.12,-0.07),
		Vector2(0.88,-0.17),Vector2(0.62,-0.15),Vector2(0.37,-0.105),
		Vector2(0.18,-0.08)
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		var a := Vector3(outline[index].x * side,outline[index].y,0.0)
		var b_point: Vector2 = outline[(index + 1) % outline.size()]
		var b := Vector3(b_point.x * side,b_point.y,0.0)
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(a)
		surface.add_vertex(b)
		# Double-sided membrane so the wing remains dark against either sky or ground.
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(b)
		surface.add_vertex(a)
	surface.generate_normals()
	var mesh := surface.commit()
	var membrane := MeshInstance3D.new()
	membrane.mesh = mesh
	membrane.material_override = _material(color)
	pivot.add_child(membrane)
	return pivot


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _process(delta: float) -> void:
	if center_ref == null or not is_instance_valid(center_ref) or not visible:
		return
	flight_time += delta
	orbit_phase += angular_speed * delta
	var center := center_ref.global_position + anchor_offset
	var next_position := center + Vector3(
		cos(orbit_phase) * orbit_radius,
		altitude + sin(flight_time * 0.6 + orbit_phase) * 1.6,
		sin(orbit_phase) * orbit_radius
	)
	global_position = next_position
	var tangent := Vector3(-sin(orbit_phase) * angular_speed,0.0,cos(orbit_phase) * angular_speed)
	if tangent.length_squared() > 0.001:
		look_at(global_position + tangent,Vector3.UP)
	var flap := sin(flight_time * 13.0 + orbit_phase) * 0.7
	wing_left.rotation.z = flap
	wing_right.rotation.z = -flap
