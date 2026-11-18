class_name Art
extends RefCounted

static var materials: Dictionary = {}

static func mat(color: Color) -> StandardMaterial3D:
	if materials.has(color):
		return materials[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	materials[color] = m
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
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

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0 else top
	shape.height = height
	shape.radial_segments = 12
	mesh.mesh = shape
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

static func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	mesh.radial_segments = 12
	mesh.rings = 6
	instance.mesh = mesh
	instance.material_override = mat(color)
	parent.add_child(instance)
	instance.position = pos
	return instance

static func prism(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	instance.mesh = mesh
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

static func tapered_box(parent: Node3D, pos: Vector3, size: Vector3, top_size: Vector2, color: Color) -> MeshInstance3D:
	var x := size.x/2
	var y := size.y/2
	var z := size.z/2
	var tx := top_size.x/2
	var tz := top_size.y/2
	var vertices := [Vector3(-x,-y,-z),Vector3(x,-y,-z),Vector3(x,-y,z),Vector3(-x,-y,z),Vector3(-tx,y,-tz),Vector3(tx,y,-tz),Vector3(tx,y,tz),Vector3(-tx,y,tz)]
	var faces := [[0,1,5,4],[3,7,6,2],[0,4,7,3],[1,2,6,5],[4,5,6,7],[0,3,2,1]]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		var a: Vector3 = vertices[face[0]]
		var b: Vector3 = vertices[face[1]]
		var c: Vector3 = vertices[face[2]]
		var normal := -(b-a).cross(c-a).normalized()
		for index in [0,1,2,0,2,3]:
			surface.set_normal(normal)
			surface.add_vertex(vertices[face[index]])
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = mat(color)
	parent.add_child(instance)
	instance.position = pos
	return instance
