class_name CbdWorld
extends SydneyWorld

## Expanded Sydney CBD world (Phase 6B).
##
## `SydneyWorld` is the Stage A importer and stays the shared foundation: it
## owns the JSON schema checks, projection, ground, water, shoreline collision,
## parks, roads, footpaths, crossings, the Opera House and the Harbour Bridge.
## This subclass changes exactly two build steps and adds indexing:
##
##   `_build_buildings()`  -> the district-aware facade builder
##                            (`sydney/cbd/cbd_buildings.gd`) instead of the
##                            plain extruded shell
##   `_build_parks()`      -> the same OSM park polygons plus vegetation
##                            (`sydney/cbd/cbd_greenery.gd`)
##
## Everything else — roads, footpaths, crossings, connectivity, landmarks,
## vehicle/player/enemy spawns, collision conventions — is inherited unchanged.
## The scene, the player, the camera, combat and the HUD are not touched.
##
## Data: `sydney/world/stage_b/world.json`, built by
## `sydney-osm-world/scripts/build_stage_b.py`. Stage A is never modified.

const STAGE_B_PATH := "res://sydney/world/stage_b/world.json"
const STAGE_LABEL := "STAGE B"

const CbdBuildings := preload("res://sydney/cbd/cbd_buildings.gd")
const CbdGreenery := preload("res://sydney/cbd/cbd_greenery.gd")
## Generated parcel fills that overlap the Opera House podium. Most are largely
## outside the legacy first-vertex filter even though their footprints intrude
## into the authored landmark site.
const OPERA_HOUSE_SITE_OVERLAPS := [
	"gen/circular-quay/198/8",
	"gen/circular-quay/198/10",
	"gen/circular-quay/198/14",
	"gen/circular-quay/198/15",
	"gen/circular-quay/198/16",
	"gen/circular-quay/198/17",
	"gen/circular-quay/198/18",
]
## These three OSM footprints are retained as authored landmark masses by
## CbdLandmarks, where their facades and rooflines are modeled explicitly.
const AUTHORED_LANDMARK_BUILDINGS := [
	"way/40717424", # Queen Victoria Building
	"way/104948253", # Sydney Town Hall
	"way/16749128", # St Mary's Cathedral
]
## Generated infill on top of the Town Hall forecourt hid the authored east
## elevation and clock tower from George Street. The OSM Town Hall footprint is
## kept; only the generated blocks inside this protected frontage are removed.
const TOWN_HALL_FORECOURT := Rect2(-127.0, -8.0, 60.0, 45.0)
## Keep the Milsons Point-Wynyard rail corridor clear of generated/baked
## building footprints so the bridge descent and underground approach are not
## obstructed by buildings intersecting the trainline/tunnel envelope.
const RAIL_CORRIDOR_CLEARANCE_M := 18.0
const RAIL_CORRIDOR_POLYLINE: Array[Vector2] = [
	Vector2(322.66, -3097.79),
	Vector2(329.81, -3064.81),
	Vector2(351.76, -2994.86),
	Vector2(372.10, -2939.47),
	Vector2(-152.24, -1562.58),
	Vector2(-162.43, -1541.83),
	Vector2(-177.50, -1505.41),
	Vector2(-192.31, -1457.24),
	Vector2(-208.32, -1397.30),
	Vector2(-234.92, -1325.05),
	Vector2(-247.37, -1281.14),
	Vector2(-255.78, -1231.93),
	Vector2(-257.89, -1198.81),
	Vector2(-256.86, -1152.05),
	Vector2(-249.72, -1102.05),
	Vector2(-237.87, -1009.72),
	Vector2(-230.58, -941.60),
	Vector2(-227.29, -868.50),
	Vector2(-221.30, -809.17),
	Vector2(-199.88, -595.03),
	Vector2(-197.62, -576.70),
]
const CbdLandmarks := preload("res://sydney/cbd/cbd_landmarks.gd")
const CbdRetail := preload("res://sydney/cbd/cbd_retail.gd")
const CbdPetrol := preload("res://sydney/cbd/cbd_petrol.gd")
const CbdSupermarkets := preload("res://sydney/cbd/cbd_supermarkets.gd")
const CbdStreetSigns := preload("res://sydney/cbd/cbd_street_signs.gd")
const FACADE_SHADER := preload("res://shaders/facade.gdshader")
const ASPHALT_SHADER := preload("res://shaders/asphalt.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const BRICK_TEXTURE := preload("res://sydney/architecture/megakit/T_RedBrick_BaseColor.png")
const CbdRailNetwork := preload("res://sydney/cbd/cbd_rail_network.gd")
const StationInteriorsScript := preload("res://sydney/railway/station_interiors.gd")
## Cyberpunk visual-direction vertical slice (presentation only, no gameplay change).
const NeonSliceScript := preload("res://sydney/cbd/cbd_neon_slice.gd")
## City-wide extension of the neon system: district signage, skyline, landmarks.
const NeonCityScript := preload("res://sydney/cbd/cbd_neon_city.gd")
## Authored architectural skyline landmarks (facade panels + distinctive crowns).
const SkylineHeroesScript := preload("res://sydney/cbd/cbd_skyline_heroes.gd")
## Designed district anchor installations for underdressed areas.
const DistrictAnchorsScript := preload("res://sydney/cbd/cbd_district_anchors.gd")
## Representative CBD architectural rebuild (vertical slice, acceptance gate).
const ArchSliceScript := preload("res://sydney/cbd/cbd_arch_slice.gd")

var district_centres: Dictionary = {}
var viewpoints: Dictionary = {}
var building_stats: Dictionary = {}
var greenery_stats: Dictionary = {}


func load_world(path: String = STAGE_B_PATH) -> bool:
	var ok: bool = super(path)
	if ok:
		_index_content()
	return ok


func _build() -> void:
	super()
	var start := Time.get_ticks_usec()
	var landmarks := CbdLandmarks.new()
	landmarks.build(data)
	add_child(landmarks)
	geometry_counts["CBDLandmarks"] = landmarks.stats
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["CBDLandmarks"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed
	start = Time.get_ticks_usec()
	var retail := CbdRetail.new()
	retail.build(data)
	add_child(retail)
	geometry_counts["RetailChains"] = retail.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["RetailChains"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed
	start = Time.get_ticks_usec()
	var petrol := CbdPetrol.new()
	petrol.build()
	add_child(petrol)
	geometry_counts["PetrolStations"] = petrol.stats
	var supermarkets := CbdSupermarkets.new()
	supermarkets.build(data)
	add_child(supermarkets)
	geometry_counts["Supermarkets"] = supermarkets.stats
	var street_signs := CbdStreetSigns.new()
	street_signs.build(data)
	add_child(street_signs)
	geometry_counts["StreetSignage"] = street_signs.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["CivicServices"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed
	start = Time.get_ticks_usec()
	var railway: Node3D = CbdRailNetwork.new()
	railway.name = "SydneyRailNetwork"
	if railway.build(data, get_node_or_null("HarbourBridge")):
		add_child(railway)
		geometry_counts["SydneyRailNetwork"] = railway.stats
		var interiors = StationInteriorsScript.new()
		interiors.build(railway, data)
		add_child(interiors)
		geometry_counts["StationInteriors"] = interiors.stats
	else:
		railway.free()
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["SydneyRailNetwork"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed

	# Cyberpunk vertical slice: George Street CBD + Wynyard underground.
	start = Time.get_ticks_usec()
	var neon_slice := NeonSliceScript.new()
	neon_slice.build(data)
	add_child(neon_slice)
	geometry_counts["NeonVerticalSlice"] = neon_slice.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["NeonVerticalSlice"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed

	start = Time.get_ticks_usec()
	var neon_city := NeonCityScript.new()
	neon_city.build(data, get_node_or_null("HarbourBridge"))
	add_child(neon_city)
	geometry_counts["NeonCity"] = neon_city.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["NeonCity"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed

	start = Time.get_ticks_usec()
	var skyline_heroes := SkylineHeroesScript.new()
	skyline_heroes.build(data)
	add_child(skyline_heroes)
	geometry_counts["SkylineHeroes"] = skyline_heroes.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["SkylineHeroes"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed

	start = Time.get_ticks_usec()
	var anchors := DistrictAnchorsScript.new()
	anchors.build()
	add_child(anchors)
	geometry_counts["DistrictAnchors"] = anchors.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["DistrictAnchors"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed

	start = Time.get_ticks_usec()
	var arch_slice := ArchSliceScript.new()
	arch_slice.build(data)
	add_child(arch_slice)
	geometry_counts["ArchitectureSlice"] = arch_slice.stats
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["ArchitectureSlice"] = elapsed
	build_times_ms["Total"] = float(build_times_ms.get("Total", 0.0)) + elapsed


func _index_content() -> void:
	district_centres.clear()
	for row in data.get("districts", []):
		district_centres[str(row.get("id", ""))] = {
			"name": str(row.get("name", "")),
			"character": str(row.get("character", "")),
			"x": float(row.get("x", 0.0)),
			"z": float(row.get("z", 0.0)),
			"buildable": bool(row.get("buildable", true)),
		}
	viewpoints.clear()
	for row in data.get("viewpoints", []):
		viewpoints[str(row.get("id", ""))] = row


## Nearest exported district to a world position. Used by tests and by the
## capture pass to label what a view is looking at; the HUD keeps using the
## exported spawn district, exactly as Stage A did.
func district_at(x: float, z: float) -> String:
	var best := ""
	var best_distance := INF
	for district_id in district_centres:
		var centre: Dictionary = district_centres[district_id]
		var distance := Vector2(x - float(centre["x"]), z - float(centre["z"])).length()
		if distance < best_distance:
			best = district_id
			best_distance = distance
	return best


func _build_buildings() -> void:
	# Suppress anything under the Opera House podium before decorating, so the
	# landmark keeps its own site. This is the same filter Stage A uses.
	var source_rows: Array = OperaHouseLandmark.filtered_buildings(data.get("buildings", []), landmark_podium)
	var rows: Array = []
	var removed_site_overlaps := 0
	var authored_landmark_masses := 0
	var removed_town_hall_infill := 0
	var removed_rail_corridor := 0
	for row in source_rows:
		if String(row.get("id", "")) in AUTHORED_LANDMARK_BUILDINGS:
			authored_landmark_masses += 1
			continue
		if String(row.get("id", "")) in OPERA_HOUSE_SITE_OVERLAPS:
			removed_site_overlaps += 1
			continue
		if _clears_town_hall_forecourt(row):
			removed_town_hall_infill += 1
			continue
		if _intersects_rail_corridor(row):
			removed_rail_corridor += 1
			continue
		rows.append(row)
	var builder = CbdBuildings.new()
	var result: Dictionary = builder.build(rows, player_spawn)
	building_stats = result.get("stats", {})
	building_stats["operaHouseSiteOverlapsRemoved"] = removed_site_overlaps
	building_stats["authoredLandmarkMasses"] = authored_landmark_masses
	building_stats["townHallForecourtInfillRemoved"] = removed_town_hall_infill
	building_stats["railCorridorBuildingsRemoved"] = removed_rail_corridor
	var mesh = result.get("mesh")
	if mesh != null:
		_add_mesh("Buildings", SydneyMesh.engine_building_mesh(mesh))
	var buildings_instance := get_node_or_null("Buildings") as MeshInstance3D
	if buildings_instance != null:
		# The merged shell stays cheap; the facade shader supplies window depth,
		# shopfronts, frames and night lighting without millions of extra tris.
		buildings_instance.material_override = _facade_material()
		buildings_instance.add_to_group("facade_surfaces")
	var night_windows := result.get("nightWindows") as ArrayMesh
	if night_windows != null and night_windows.get_surface_count() > 0:
		var windows_instance := MeshInstance3D.new()
		windows_instance.name = "NightWindows"
		windows_instance.mesh = night_windows
		# Superseded by the aligned procedural windows in the facade shader.
		windows_instance.visible = false
		add_child(windows_instance)
	var counts: Dictionary = geometry_counts.get("Buildings", {}).duplicate()
	var faces: PackedVector3Array = result.get("faces", PackedVector3Array())
	counts["triangles"] = int(building_stats.get("triangles", counts.get("triangles", 0)))
	counts["vertices"] = int(counts.get("vertices", 0))
	counts["collisionTriangles"] = faces.size() / 3
	counts["built"] = int(building_stats.get("built", 0))
	counts["skipped"] = int(building_stats.get("skipped", 0))
	counts["degenerateTriangles"] = int(building_stats.get("degenerateTriangles", 0))
	counts["detachedPodiums"] = int(building_stats.get("detachedPodiums", 0))
	counts["nightWindowQuads"] = int(building_stats.get("nightWindowQuads", 0))
	counts["byStyle"] = building_stats.get("byStyle", {})
	geometry_counts["Buildings"] = counts
	geometry_counts["Architecture"] = {
		"converted": 0,
		"fallback": 0,
		"buildings": building_stats.get("byStyle", {}),
		"note": "Phase 6B uses the CBD facade builder instead of the kit pilot",
	}
	if int(building_stats.get("degenerateTriangles", 0)) > 0:
		push_warning("CbdWorld: %d degenerate facade triangles rejected" % int(building_stats.get("degenerateTriangles", 0)))
	if faces.size() >= 3:
		var body := StaticBody3D.new()
		body.name = "BuildingCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		# Same engine-boundary winding conversion as every other building mesh.
		shape.set_faces(SydneyMesh.engine_building_faces(faces))
		collider.shape = shape
		body.add_child(collider)


## Presentation overrides only: the shared importer still owns the geometry and
## the collision. Stage B is five kilometres across, so the inherited 300 m
## margin left the map edge visible as a dark band on the horizon; the visual
## ground is extended well past the playable bounds while the collision box keeps
## its documented size. Underground station interiors require rectangular
## openings cut through both the visual ground and its collision.
func _build_ground() -> void:
	var min_x := float(bounds["minX"])
	var max_x := float(bounds["maxX"])
	var min_z := float(bounds["minZ"])
	var max_z := float(bounds["maxZ"])
	var size := Vector3(max_x - min_x + 300.0, 1.0, max_z - min_z + 300.0)
	var center := Vector3((min_x + max_x) * 0.5, -0.5, (min_z + max_z) * 0.5)
	var base_rect := Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)
	var hole_rects: Array[Rect2] = []
	for opening in StationInteriorsScript.openings():
		var ow := float(opening.get("w", 0.0))
		var oh := float(opening.get("h", 0.0))
		if ow <= 0.0 or oh <= 0.0:
			continue
		hole_rects.append(Rect2(float(opening["x"]) - ow * 0.5, float(opening["z"]) - oh * 0.5, ow, oh))
	var cells := _subtract_ground_rects(base_rect, hole_rects)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	add_child(body)
	for i in cells.size():
		var rect: Rect2 = cells[i]
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(rect.size.x, 1.0, rect.size.y)
		collider.shape = shape
		collider.position = Vector3(rect.position.x + rect.size.x * 0.5, -0.5, rect.position.y + rect.size.y * 0.5)
		body.add_child(collider)

	var mat := SydneyMesh.mat(Color("53574e"))
	for i in cells.size():
		var rect: Rect2 = cells[i]
		var instance := MeshInstance3D.new()
		instance.name = "Ground_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x, 0.4, rect.size.y)
		instance.mesh = box
		instance.material_override = mat
		instance.position = Vector3(rect.position.x + rect.size.x * 0.5, -0.22, rect.position.y + rect.size.y * 0.5)
		add_child(instance)

	# Extended visual ground beyond the playable/collision bounds, split so it
	# does not cover station openings inside the base rect.
	var outer := Rect2(center.x - (size.x + 6000.0) * 0.5, center.z - (size.z + 6000.0) * 0.5, size.x + 6000.0, size.z + 6000.0)
	var outer_cells: Array[Rect2] = _subtract_ground_rects(outer, [base_rect])
	for i in outer_cells.size():
		var rect: Rect2 = outer_cells[i]
		var instance := MeshInstance3D.new()
		instance.name = "GroundOuter_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x, 0.4, rect.size.y)
		instance.mesh = box
		instance.material_override = mat
		instance.position = Vector3(rect.position.x + rect.size.x * 0.5, -0.22, rect.position.y + rect.size.y * 0.5)
		add_child(instance)


func _subtract_ground_rects(base: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var rects: Array[Rect2] = [base]
	for hole in holes:
		var next: Array[Rect2] = []
		for rect in rects:
			var inter := rect.intersection(hole)
			if inter.size.x <= 0.01 or inter.size.y <= 0.01:
				next.append(rect)
				continue
			# Left strip
			if inter.position.x > rect.position.x + 0.01:
				next.append(Rect2(rect.position.x, rect.position.y, inter.position.x - rect.position.x, rect.size.y))
			# Right strip
			var right_x := inter.position.x + inter.size.x
			var rect_right := rect.position.x + rect.size.x
			if right_x < rect_right - 0.01:
				next.append(Rect2(right_x, rect.position.y, rect_right - right_x, rect.size.y))
			# Top strip (above hole in -Z? Rect2 y is min_z here)
			if inter.position.y > rect.position.y + 0.01:
				next.append(Rect2(inter.position.x, rect.position.y, inter.size.x, inter.position.y - rect.position.y))
			# Bottom strip
			var bottom_y := inter.position.y + inter.size.y
			var rect_bottom := rect.position.y + rect.size.y
			if bottom_y < rect_bottom - 0.01:
				next.append(Rect2(inter.position.x, bottom_y, inter.size.x, rect_bottom - bottom_y))
		rects = next
	return rects


## The inherited asphalt colour is almost black at Sydney's scale and reads as a
## hole in the street. Same shared ribbon geometry, warmer asphalt.
func _build_roads() -> void:
	super()
	var roads := get_node_or_null("Roads") as MeshInstance3D
	if roads != null:
		roads.material_override = _asphalt_material(Color("2a2e32"), 0.91)
	# Footpaths and crossings read as concrete, not the same flat strip as the
	# carriageway. The same shader with lighter, rougher values is enough.
	for node_name in ["Footpaths", "Crossings", "Parking"]:
		var surface := get_node_or_null(node_name) as MeshInstance3D
		if surface != null:
			surface.material_override = _asphalt_material(Color("66645c"), 0.95)


func _clears_town_hall_forecourt(row: Dictionary) -> bool:
	if not str(row.get("id", "")).begins_with("gen/town-hall/"):
		return false
	var ring: Array = row.get("ring", [])
	if ring.is_empty():
		return false
	var center := Vector2.ZERO
	for point: Array in ring:
		center += Vector2(float(point[0]), float(point[1]))
	center /= float(ring.size())
	return TOWN_HALL_FORECOURT.has_point(center)


func _intersects_rail_corridor(row: Dictionary) -> bool:
	var ring: Array = row.get("ring", [])
	if ring.is_empty() or RAIL_CORRIDOR_POLYLINE.size() < 2:
		return false
	var center := Vector2.ZERO
	for point: Array in ring:
		center += Vector2(float(point[0]), float(point[1]))
	center /= float(ring.size())
	var radius := 0.0
	for point: Array in ring:
		radius = maxf(radius, center.distance_to(Vector2(float(point[0]), float(point[1]))))
	var clearance := RAIL_CORRIDOR_CLEARANCE_M + radius
	for i in range(RAIL_CORRIDOR_POLYLINE.size() - 1):
		var a: Vector2 = RAIL_CORRIDOR_POLYLINE[i]
		var b: Vector2 = RAIL_CORRIDOR_POLYLINE[i + 1]
		if _distance_point_to_segment(center, a, b) <= clearance:
			return true
	return false


func _distance_point_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _facade_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FACADE_SHADER
	material.set_shader_parameter("night_factor", 0.0)
	material.set_shader_parameter("brick_texture", BRICK_TEXTURE)
	return material


func _grass_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	return material


func _asphalt_material(color: Color, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ASPHALT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("roughness_base", roughness)
	material.set_shader_parameter("patch_strength", 0.14 if roughness > 0.9 else 0.22)
	return material


func _build_parks() -> void:
	var rings: Array = []
	for park in data.get("parks", []):
		for ring in park.get("rings", []):
			rings.append(ring)
	# Sydney's parks are not one flat green: mown turf in Hyde Park, denser
	# planting in the Botanic Garden and The Domain. The exporter keeps the OSM
	# polygon; the tint below is presentation.
	var mesh := SydneyMesh.flat_polygons(rings, 0.04, Color("5c8f4e"))
	_add_mesh("Parks", mesh)
	var parks := get_node_or_null("Parks") as MeshInstance3D
	if parks != null:
		parks.material_override = _grass_material()
		parks.add_to_group("grass_surfaces")
	var greenery = CbdGreenery.new()
	var node: Node3D = greenery.build(data.get("parks", []), data.get("roads", []))
	add_child(node)
	greenery_stats = greenery.stats
	geometry_counts["Vegetation"] = greenery_stats
