extends Node3D
const Assembler = preload("res://sydney/architecture/assembler.gd")
const MeshBuilder = preload("res://sydney/sydney_mesh.gd")

static func examples() -> Array:
	return [
		{"id": "small-1", "heightM": 9.6, "ring": [[0,0],[12,0],[12,12],[0,12]]},
		{"id": "medium-2", "architectureStyle": "stone", "heightM": 22.4, "ring": [[22,0],[42,0],[42,17],[22,17]]},
		{"id": "tower-3", "heightM": 70.4, "ring": [[54,0],[78,0],[78,22],[54,22]]},
		{"id": "corner-4", "heightM": 16.0, "ring": [[0,32],[16,32],[20,36],[20,50],[0,50]]},
		{"id": "alternate-6", "architectureStyle": "stone", "heightM": 19.2, "ring": [[32,32],[50,32],[50,48],[32,48]]},
	]

func _ready() -> void:
	var rows := examples()
	var hull := MeshBuilder.buildings(rows)
	var mesh := MeshInstance3D.new()
	mesh.mesh = MeshBuilder.engine_building_mesh(hull.mesh)
	add_child(mesh)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(MeshBuilder.engine_building_faces(hull.faces))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	add_child(Assembler.new().assemble(rows))
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(180, 0.2, 150)
	box.material = MeshBuilder.mat(Color("777c79"))
	ground.mesh = box
	ground.position = Vector3(35, -0.1, 20)
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a1b8c8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-52, 50, -72)
	camera.look_at(Vector3(32, 18, 20))
	camera.current = true
