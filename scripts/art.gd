class_name Art
extends RefCounted

static var materials: Dictionary = {}
static var meshes: Dictionary = {}

static func mat(color: Color) -> StandardMaterial3D:
	if materials.has(color):
		return materials[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	materials[color] = m
	return m

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%s:%s:%s" % [size.x, size.y, size.z]
	if meshes.has(key):
		return meshes[key]
	var shape := BoxMesh.new()
	shape.size = size
	meshes[key] = shape
	return shape

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh(size)
	mesh.material_override = mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		mesh.add_child(body)
		body.add_child(collision)
	return mesh

static func _cylinder_mesh(radius: float, height: float, top: float) -> CylinderMesh:
	var key := "cyl:%s:%s:%s" % [radius, height, top]
	if meshes.has(key):
		return meshes[key]
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = 12
	meshes[key] = shape
	return shape

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var top_radius := radius if top < 0 else top
	mesh.mesh = _cylinder_mesh(radius, height, top_radius)
	mesh.material_override = mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func label(parent: Node3D, pos: Vector3, words: String, size: int = 64) -> Label3D:
	var text := Label3D.new()
	text.text = words
	text.font_size = size
	text.pixel_size = 0.018
	text.outline_size = 8
	parent.add_child(text)
	text.position = pos
	return text

static func _sphere_mesh(radius: float) -> SphereMesh:
	var key := "sphere:%s" % [radius]
	if meshes.has(key):
		return meshes[key]
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	meshes[key] = mesh
	return mesh

static func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _sphere_mesh(radius)
	instance.material_override = mat(color)
	parent.add_child(instance)
	instance.position = pos
	return instance

static func _prism_mesh(size: Vector3) -> PrismMesh:
	var key := "prism:%s:%s:%s" % [size.x, size.y, size.z]
	if meshes.has(key):
		return meshes[key]
	var mesh := PrismMesh.new()
	mesh.size = size
	meshes[key] = mesh
	return mesh

static func prism(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _prism_mesh(size)
	instance.material_override = mat(color)
	parent.add_child(instance)
	instance.position = pos
	return instance

static func person(parent: Node3D, color: Color) -> Node3D:
	var model := Node3D.new()
	parent.add_child(model)
	box(model, Vector3(0,1.15,0), Vector3(0.65,0.65,0.38), color)
	sphere(model, Vector3(0,1.72,0),0.25,Color("f0ba83"))
	box(model,Vector3(0,1.96,0.03),Vector3(0.53,0.12,0.5),Color("172b46"))
	for side in [-1,1]:
		var leg := box(model,Vector3(side*0.19,0.45,0),Vector3(0.24,0.8,0.3),Color("24344e"))
		leg.name = "LegLeft" if side == -1 else "LegRight"
		box(model,Vector3(side*0.19,0.12,-0.1),Vector3(0.28,0.2,0.5),Color("172b46"))
		box(model,Vector3(side*0.43,1.12,0),Vector3(0.2,0.64,0.25),color)
	box(model,Vector3(0.43,1.05,-0.36),Vector3(0.13,0.18,0.5),Color("263444"))
	return model

static func _tapered_box_mesh(size: Vector3, top_size: Vector2) -> ArrayMesh:
	var key := "taper:%s:%s:%s:%s:%s" % [size.x, size.y, size.z, top_size.x, top_size.y]
	if meshes.has(key):
		return meshes[key]
	var x := size.x / 2.0
	var y := size.y / 2.0
	var z := size.z / 2.0
	var tx := top_size.x / 2.0
	var tz := top_size.y / 2.0
	var vertices := [Vector3(-x,-y,-z),Vector3(x,-y,-z),Vector3(x,-y,z),Vector3(-x,-y,z),Vector3(-tx,y,-tz),Vector3(tx,y,-tz),Vector3(tx,y,tz),Vector3(-tx,y,tz)]
	var faces := [[0,1,5,4],[3,7,6,2],[0,4,7,3],[1,2,6,5],[4,5,6,7],[0,3,2,1]]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		var a: Vector3 = vertices[face[0]]
		var b: Vector3 = vertices[face[1]]
		var c: Vector3 = vertices[face[2]]
		var normal := -(b - a).cross(c - a).normalized()
		for index in [0,1,2,0,2,3]:
			surface.set_normal(normal)
			surface.add_vertex(vertices[face[index]])
	var mesh := surface.commit()
	meshes[key] = mesh
	return mesh

static func tapered_box(parent: Node3D, pos: Vector3, size: Vector3, top_size: Vector2, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _tapered_box_mesh(size, top_size)
	instance.material_override = mat(color)
	parent.add_child(instance)
	instance.position = pos
	return instance
