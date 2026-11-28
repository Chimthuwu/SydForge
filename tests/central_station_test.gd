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
	var landmarks = preload("res://sydney/cbd/cbd_landmarks.gd").new()
	landmarks.build({})
	var station: Node = landmarks.get_node_or_null("CentralStationLandmark")
	check(station != null, "Central Station landmark group builds from an empty world data")
	if station == null:
		quit(1)
		return
	var collision: Node = station.get_node_or_null("CentralStationCollision")
	check(collision != null, "the authored station has solid collision")
	var boxes: Array[BoxShape3D] = []
	if collision != null:
		for child in collision.get_children():
			var shape := (child as CollisionShape3D).shape as BoxShape3D
			if shape != null:
				boxes.append(shape)
	check(boxes.size() >= 2, "shell and clock tower each have a collision box (%d)" % boxes.size())

	# The XZ footprint of every collision box, from the actual shapes.
	var footprints: Array[Rect2] = []
	for child in collision.get_children():
		var shape := (child as CollisionShape3D).shape as BoxShape3D
		if shape == null:
			continue
		# The landmark is not inside a tree here, and the group sits at the
		# origin with world-space ArtUtil children, so local position is the
		# world-space position of each collision shape.
		var at: Vector3 = (child as CollisionShape3D).position
		footprints.append(Rect2(
			Vector2(at.x - shape.size.x * 0.5, at.z - shape.size.z * 0.5),
			Vector2(shape.size.x, shape.size.z)))

	var world := _load_stage_b()
	if world.is_empty():
		check(false, "stage B world.json loaded")
	else:
		check(true, "stage B world.json loaded")
		# The mapped 'Station Pickup/Dropoff' road and generated building
		# gen/central/463/0 used to render straight through the west wing.
		var wet_roads := 0
		var wet_roads_total := 0
		for road in world.get("roads", []):
			if bool(road.get("tunnel", false)):
				continue
			for point in road.get("points", []):
				var position := Vector2(float(point[0]), float(point[1]))
				for box in footprints:
					if box.grow(2.0).has_point(position):
						wet_roads_total += 1
						if box.has_point(position):
							wet_roads += 1
						break
		check(wet_roads == 0, "no mapped surface road renders inside the station shell (%d near misses within 2 m)" % wet_roads_total)
		check(wet_roads_total == 0, "the pickup loop clears the trimmed shell footprint")
		var clipped_buildings := 0
		for building in world.get("buildings", []):
			var ring = building.get("ring", building.get("rings", []))
			if ring is Dictionary:
				ring = ring.get("outer", [])
			if not (ring is Array) or (ring as Array).is_empty():
				continue
			for point in ring as Array:
				var position := Vector2(float(point[0]), float(point[1]))
				for box in footprints:
					if box.grow(1.0).has_point(position):
						clipped_buildings += 1
						break
				if clipped_buildings > 0:
					break
			if clipped_buildings > 0:
				print("   clipping building: ", building.get("id", "?"))
		check(clipped_buildings == 0, "no stage B building clips the station shell (%d)" % clipped_buildings)
		# The menu spawn viewpoint must not start inside the new collision.
		for viewpoint in world.get("viewpoints", []):
			if str(viewpoint.get("id", "")) == "central":
				var spawn := Vector2(float(viewpoint["x"]), float(viewpoint["z"]))
				var inside := false
				for box in footprints:
					if box.has_point(spawn):
						inside = true
						break
				check(not inside, "the central menu spawn is outside the station collision")
	landmarks.free()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


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
