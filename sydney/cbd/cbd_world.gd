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
const CbdLandmarks := preload("res://sydney/cbd/cbd_landmarks.gd")
const FACADE_SHADER := preload("res://shaders/facade.gdshader")
const ASPHALT_SHADER := preload("res://shaders/asphalt.gdshader")
const CbdRailNetwork := preload("res://sydney/cbd/cbd_rail_network.gd")

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
	var railway: Node3D = CbdRailNetwork.new()
	railway.name = "SydneyRailNetwork"
	if railway.build(data, get_node_or_null("HarbourBridge")):
		add_child(railway)
		geometry_counts["SydneyRailNetwork"] = railway.stats
	else:
		railway.free()
	elapsed = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["SydneyRailNetwork"] = elapsed
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
	for row in source_rows:
		if String(row.get("id", "")) in AUTHORED_LANDMARK_BUILDINGS:
			authored_landmark_masses += 1
			continue
		if String(row.get("id", "")) in OPERA_HOUSE_SITE_OVERLAPS:
			removed_site_overlaps += 1
			continue
		rows.append(row)
	var builder = CbdBuildings.new()
	var result: Dictionary = builder.build(rows, player_spawn)
	building_stats = result.get("stats", {})
	building_stats["operaHouseSiteOverlapsRemoved"] = removed_site_overlaps
	building_stats["authoredLandmarkMasses"] = authored_landmark_masses
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
## its documented size.
func _build_ground() -> void:
	var min_x := float(bounds["minX"])
	var max_x := float(bounds["maxX"])
	var min_z := float(bounds["minZ"])
	var max_z := float(bounds["maxZ"])
	var size := Vector3(max_x - min_x + 300.0, 1.0, max_z - min_z + 300.0)
	var center := Vector3((min_x + max_x) * 0.5, -0.5, (min_z + max_z) * 0.5)
	var instance := MeshInstance3D.new()
	instance.name = "Ground"
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 6000.0, 0.4, size.z + 6000.0)
	instance.mesh = box
	instance.material_override = SydneyMesh.mat(Color("6c7060"))
	instance.position = Vector3(center.x, -0.22, center.z)
	add_child(instance)
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = center
	body.add_child(collider)


## The inherited asphalt colour is almost black at Sydney's scale and reads as a
## hole in the street. Same shared ribbon geometry, warmer asphalt.
func _build_roads() -> void:
	super()
	var roads := get_node_or_null("Roads") as MeshInstance3D
	if roads != null:
		roads.material_override = _asphalt_material(Color("33383d"), 0.82)
	# Footpaths and crossings read as concrete, not the same flat strip as the
	# carriageway. The same shader with lighter, rougher values is enough.
	for node_name in ["Footpaths", "Crossings", "Parking"]:
		var surface := get_node_or_null(node_name) as MeshInstance3D
		if surface != null:
			surface.material_override = _asphalt_material(Color("7a786f"), 0.94)


func _facade_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FACADE_SHADER
	material.set_shader_parameter("night_factor", 0.0)
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
	var greenery = CbdGreenery.new()
	var node: Node3D = greenery.build(data.get("parks", []), data.get("roads", []))
	add_child(node)
	greenery_stats = greenery.stats
	geometry_counts["Vegetation"] = greenery_stats
