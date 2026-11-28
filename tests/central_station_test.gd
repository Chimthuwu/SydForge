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

	# The clock tower rises from the forecourt: some collision box under the
	# clocktower point must reach the ground and stand ~67 m tall, not hang
	# from the roof line with a void below it.
	var tower_to_ground := false
	for child in collision.get_children():
		var shape := (child as CollisionShape3D).shape as BoxShape3D
		if shape == null:
			continue
		var at: Vector3 = (child as CollisionShape3D).position
		if shape.size.y >= 60.0 and at.y - shape.size.y * 0.5 <= 0.5 \
				and absf(at.x - (-187.6)) < 8.0 and absf(at.z - 1034.1) < 8.0:
			tower_to_ground = true
	check(tower_to_ground, "the clock tower collision stands on the ground (~67 m tall)")

	# Meshes are merged per material, so the merged batches' AABBs verify the
	# platform yard geometrically: canopy columns grounded, real slabs, tracks
	# and parked carriages under them.
	var batch_aabbs: Array[AABB] = []
	var central_labels := 0
	var east_sign := false
	for child in station.get_children():
		if child is MeshInstance3D:
			batch_aabbs.append((child as MeshInstance3D).get_aabb())
		if child is Label3D and (child as Label3D).text == "CENTRAL":
			central_labels += 1
			if (child as Label3D).position.x > -124.0:
				east_sign = true
	check(central_labels >= 3, "three CENTRAL signs (west, east, south band) built (%d)" % central_labels)
	check(east_sign, "a CENTRAL sign faces the menu spawn on the east face")

	var columns_grounded := false
	var slabs_built := false
	var tracks_built := false
	var carriages_parked := false
	for aabb in batch_aabbs:
		# Canopy columns: grounded, topping out at the roof line. The merged
		# steel batch spans all four canopy rows (~55 m wide).
		if aabb.position.y <= 0.5 and aabb.end.y >= 11.5 and aabb.end.y <= 12.5:
			columns_grounded = true
		# Platform slabs: ~1.1 m tall, 190 m long.
		if aabb.position.y >= -0.1 and aabb.end.y <= 1.5 and aabb.size.z >= 185.0:
			slabs_built = true
		# Ballast + rails: flat strips running the full yard length.
		if aabb.end.y <= 0.5 and aabb.size.z >= 185.0 and aabb.size.x >= 70.0:
			tracks_built = true
		# Parked carriages: three 19 m bodies end to end at platform level.
		if aabb.position.y >= 0.2 and aabb.end.y <= 4.6 and aabb.size.z >= 55.0:
			carriages_parked = true
	check(columns_grounded, "canopy columns stand on the ground (no floating roof posts)")
	check(slabs_built, "platform slabs exist under the canopies")
	check(tracks_built, "track wells with ballast and rails run the yard")
	check(carriages_parked, "static carriages are parked at the platforms")
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
