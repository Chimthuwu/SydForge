extends SceneTree
const Assembler = preload("res://sydney/architecture/assembler.gd")

func _initialize() -> void:
	call_deferred("run")

func capture(camera: Camera3D, label: String, target: Vector3, position: Vector3) -> void:
	camera.position = position
	camera.look_at(target)
	camera.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/architecture_" + label + ".png")
	print("CAPTURE ", label, " eye=", position, " target=", target)

func run() -> void:
	var prototype: Node3D = load("res://sydney/architecture/prototype.tscn").instantiate()
	root.add_child(prototype)
	var camera := Camera3D.new()
	prototype.add_child(camera)
	camera.far = 4000
	await capture(camera, "prototype", Vector3(32,18,20), Vector3(-52,50,-72))
	await capture(camera, "prototype_detail", Vector3(10,6,2), Vector3(18,8,-17))
	prototype.queue_free()
	await process_frame
	var district: Node3D = load("res://scenes/district.tscn").instantiate()
	root.add_child(district)
	for i in 30:
		await process_frame
	district.rig.set_process(false)
	district.enemy.set_physics_process(false)
	district.hit_time = 0.0
	camera = Camera3D.new()
	district.add_child(camera)
	camera.far = 4000
	var spawn: Vector3 = district.player.spawn
	await capture(camera, "george_street", spawn + Vector3(100,4,15), spawn + Vector3(0,1.8,3))
	await capture(camera, "town_hall", spawn + Vector3(0,10,-40), spawn + Vector3(90,95,100))
	await capture(camera, "aerial", spawn + Vector3(0,0,-160), spawn + Vector3(400,440,500))
	var selected := Assembler.pilot(district.sydney_world.data.buildings, spawn)
	var tallest: Dictionary = selected[0]
	for row in selected:
		if row.heightM > tallest.heightM:
			tallest = row
	for pair in [["facade", selected[0]], ["corner", selected[0]], ["tall", tallest]]:
		var row: Dictionary = pair[1]
		var p := Assembler.plan(row)
		var a: Vector2 = p.ring[0]
		var b: Vector2 = p.ring[1]
		var normal := Vector2((b-a).y, -(b-a).x).normalized() * signf(SydneyMesh._signed_area(p.ring))
		var mid := (a+b)*0.5
		var target := Vector3(mid.x, minf(8, p.height * 0.5), mid.y)
		var eye := target + Vector3(normal.x,0,normal.y)*18
		if pair[0] == "corner":
			target = Vector3(a.x, p.height*0.5, a.y)
			eye = target + Vector3(normal.x,0.12,normal.y)*7 + Vector3((b-a).normalized().x,0,(b-a).normalized().y)*3
		if pair[0] == "tall":
			target.y = p.height*0.5
			eye = target + Vector3(normal.x,0.25,normal.y)*maxf(45,p.height)
		await capture(camera, pair[0], target, eye)
	print("ARCHITECTURE ", district.sydney_world.geometry_counts.Architecture)
	print("TIMINGS ", district.sydney_world.build_times_ms)
	district.queue_free()
	await process_frame
	quit()
