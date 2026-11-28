extends SceneTree

## Regression checks for the second civic-silhouette pass (DECISION 9459065):
## St Andrew's Cathedral beside the Town Hall spawn, and the Sydney GPO on
## Martin Place. Both must keep their real OSM footprint (bespoke mass with
## walk-blocking collision), stay inside their mapped bounds, and raise the
## authored silhouette well above the generic 16-30 m shell.

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
	var world := _load_stage_b()
	landmarks.build(world)

	var st_andrews: Node = landmarks.get_node_or_null("StAndrewsCathedral")
	check(st_andrews != null, "St Andrew's Cathedral landmark group builds")
	var gpo: Node = landmarks.get_node_or_null("GeneralPostOffice")
	check(gpo != null, "General Post Office landmark group builds")

	_check_osm_mass(st_andrews, "St Andrew's", Color("c7b79b"), Vector2(53.0, 49.0), 25.0)
	_check_osm_mass(gpo, "the GPO", Color("d3c6ae"), Vector2(97.0, 45.0), 12.0)

	_check_st_andrews_silhouette(st_andrews)
	_check_gpo_silhouette(gpo)

	landmarks.free()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


## Every authored landmark keeps its real footprint as a bespoke mass with
## collision, so the player cannot walk through it. Meshes are merged per
## material at build time, so the mass is identified by its unique tint batch
## spanning the mapped footprint.
func _check_osm_mass(group: Node, label: String, tint: Color, extent: Vector2, height_min: float) -> void:
	if group == null:
		check(false, label + " group exists for the mass check")
		return
	var body := group.get_node_or_null("LandmarkCollision")
	check(body != null and body is StaticBody3D, label + " has walk-blocking collision on its footprint")
	var mass := false
	for child in group.get_children():
		if not child is MeshInstance3D:
			continue
		var instance := child as MeshInstance3D
		var material := instance.mesh.surface_get_material(0) if instance.mesh != null and instance.mesh.get_surface_count() > 0 else null
		if material == null or not material is StandardMaterial3D:
			continue
		if not (material as StandardMaterial3D).albedo_color.is_equal_approx(tint):
			continue
		var aabb := instance.get_aabb()
		if aabb.size.x >= extent.x * 0.9 and aabb.size.z >= extent.y * 0.9 and aabb.size.y >= height_min:
			mass = true
	check(mass, label + " keeps its mapped OSM footprint as an authored mass")


func _group_aabbs(group: Node) -> Array[AABB]:
	var aabbs: Array[AABB] = []
	if group == null:
		return aabbs
	for child in group.get_children():
		if child is MeshInstance3D:
			aabbs.append((child as MeshInstance3D).get_aabb())
	return aabbs


func _check_st_andrews_silhouette(group: Node) -> void:
	if group == null:
		check(false, "St Andrew's group exists for the silhouette check")
		return
	# The mapped footprint is way/104948254: x -188..-135, z 84..133, and the
	# Town Hall colonnade tops out just south of Druitt Street (z <= 52), so
	# nothing of the cathedral may cross into it.
	var all: AABB = AABB()
	var first := true
	for aabb in _group_aabbs(group):
		if first:
			all = aabb
			first = false
		else:
			all = all.merge(aabb)
	check(all.position.x >= -195.0 and all.end.x <= -128.0 and all.position.z >= 78.0,
		"St Andrew's stays on its mapped block, clear of the Town Hall colonnade")
	# Twin spires: slate batch crowns well above the 30 m shell; the gold
	# finials top it.
	var spires := false
	var finials := false
	for aabb in _group_aabbs(group):
		if aabb.end.y >= 68.0 and aabb.end.y <= 73.0:
			spires = true
		if aabb.end.y >= 73.0:
			finials = true
	check(spires, "twin spires rise ~40 m above the mapped shell")
	check(finials, "gold finials crown the spires")


func _check_gpo_silhouette(group: Node) -> void:
	if group == null:
		check(false, "GPO group exists for the silhouette check")
		return
	# The mapped footprint is way/282238525: x -78..19, z -599..-554.
	var all: AABB = AABB()
	var first := true
	for aabb in _group_aabbs(group):
		if first:
			all = aabb
			first = false
		else:
			all = all.merge(aabb)
	check(all.position.x >= -84.0 and all.end.x <= 25.0 and all.end.z <= -548.0,
		"the GPO stays on its mapped Martin Place block")
	# The colonnade batch runs ground to entablature across the frontage, and
	# the campanile (same sandstone batch) clears ~48 m.
	var colonnade := false
	var campanile := false
	for aabb in _group_aabbs(group):
		if aabb.position.y <= 0.5 and aabb.end.y >= 13.0 and aabb.size.x >= 85.0:
			colonnade = true
		if aabb.end.y >= 48.0 and aabb.end.y <= 54.0 and aabb.size.x <= 14.0:
			campanile = true
	check(colonnade, "the Martin Place colonnade runs the full frontage from the ground")
	check(campanile, "the clock-tower campanile rises ~35 m above the arcade roof")
	# Four clock faces: a dark disk batch centred ~40 m up the campanile.
	var clock_faces := false
	for aabb in _group_aabbs(group):
		if aabb.position.y >= 35.0 and aabb.end.y <= 46.0 and aabb.size.z >= 4.0:
			clock_faces = true
	check(clock_faces, "clock faces encircle the campanile shaft")


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
