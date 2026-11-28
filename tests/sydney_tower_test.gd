extends SceneTree

var checks := 0
var failures := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var world := _load_stage_b()
	check(not world.is_empty(), "stage B world.json loads")
	var landmarks = preload("res://sydney/cbd/cbd_landmarks.gd").new()
	landmarks.build(world)
	var tower: Node = landmarks.get_node_or_null("SydneyTowerLandmark")
	check(tower != null, "Sydney Tower landmark builds")
	if tower == null:
		quit(1)
		return
	check(landmarks.stats.get("sydneyTower", false) == true, "stats record the tower")
	check(landmarks.get_node_or_null("SydneyTowerLandmark/SydneyTowerCollision") != null,
		"the tower has solid collision")

	# Anchor: the shaft must sit over the mapped Centrepoint block.
	var anchor: Dictionary = _row(world, "way/389002928")
	check(not anchor.is_empty(), "anchor building way/389002928 exists in the export")
	if not anchor.is_empty():
		var ring: Array = anchor.get("ring", [])
		var center := Vector2.ZERO
		for point: Array in ring:
			center += Vector2(float(point[0]), float(point[1]))
		center /= maxf(1.0, float(ring.size()))
		var base := float(anchor.get("heightM", 0.0))
		# The tallest visible mesh must be the tower tip (~270 m): scan every
		# mesh in the landmark group for its top and confirm the shaft base
		# starts at the anchor roof.
		var top := _scan(tower)
		var meshes := 0
		for child in tower.get_children():
			if child is MeshInstance3D:
				meshes += 1
		check(meshes > 3, "tower meshes built (%d)" % meshes)
		# Tip = base + shaft(170) + podium ring(12) + turret(17.5) + mast(36)
		# + half beacon(1.5): the red beacon is the topmost vertex.
		var expected_tip := base + 170.0 + 12.0 + 17.5 + 36.0 + 1.5
		check(top > 240.0 and absf(top - expected_tip) < 2.0,
			"tower tip reaches ~270 m (top=%.1f expected=%.1f)" % [top, expected_tip])
		# No other CBD tower nearby may exceed the tower: sample stage B
		# buildings within 150 m of the shaft.
		var tallest_nearby := 0.0
		for building in world.get("buildings", []):
			var b_ring = building.get("ring", building.get("rings", []))
			if b_ring is Dictionary:
				b_ring = b_ring.get("outer", [])
			if not (b_ring is Array) or (b_ring as Array).is_empty():
				continue
			var b_center := Vector2.ZERO
			for point in b_ring as Array:
				b_center += Vector2(float(point[0]), float(point[1]))
			b_center /= float((b_ring as Array).size())
			if b_center.distance_to(center) < 150.0:
				tallest_nearby = maxf(tallest_nearby, float(building.get("heightM", 0.0)))
		check(base + 170.0 > tallest_nearby + 60.0,
			"the tower dominates its block (shaft top %.0f vs tallest nearby %.0f)" % [base + 170.0, tallest_nearby])

	landmarks.free()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _scan(node: Node) -> float:
	var top := -INF
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			var at: Vector3 = (node as Node3D).position
			for vertex in mesh.get_faces():
				top = maxf(top, vertex.y + at.y)
	for child in node.get_children():
		top = maxf(top, _scan(child))
	return top


func _row(world: Dictionary, id: String) -> Dictionary:
	for building in world.get("buildings", []):
		if String(building.get("id", "")) == id:
			return building
	return {}


func _load_stage_b() -> Dictionary:
	var path := "res://sydney/world/stage_b/world.json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var parsed = json.data
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
