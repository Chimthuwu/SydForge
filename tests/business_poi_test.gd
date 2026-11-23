extends SceneTree

## Real-business layer coverage:
##   * the committed OSM extract contains every requested brand;
##   * every POI is inside the Stage B bounds and projects back to its source
##     WGS84 coordinates;
##   * placement snaps onto a real building facade, refuses authored landmarks
##     and never duplicates a Woolworths/Coles storefront.

const BusinessLayer := preload("res://sydney/cbd/cbd_businesses.gd")
const DATA_PATH := "res://sydney/world/businesses.json"

const REQUIRED := ["McDonald's", "KFC", "7-Eleven", "Woolworths", "Coles"]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_check(typeof(parsed) == TYPE_DICTIONARY, "business dataset parses")
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish()
		return
	var data: Dictionary = parsed
	var pois: Array = data.get("pois", [])
	_check(pois.size() >= 150, "dataset has a meaningful number of mapped POIs (%d)" % pois.size())
	_check(str(data.get("license", "")) == "ODbL 1.0", "dataset keeps ODbL attribution")
	_check(str(data.get("source", "")) == "OpenStreetMap contributors", "dataset keeps OSM attribution")

	var counts: Dictionary = {}
	for row: Dictionary in pois:
		counts[str(row.get("brand", ""))] = int(counts.get(str(row.get("brand", "")), 0)) + 1
	for brand: String in REQUIRED:
		_check(int(counts.get(brand, 0)) > 0, "requested brand has mapped locations: %s (%d)" % [brand, int(counts.get(brand, 0))])

	var bounds: Dictionary = data.get("bounds", {})
	var geometry_ok := true
	var id_ok := true
	var ids: Dictionary = {}
	for row: Dictionary in pois:
		var x := float(row.get("x", 0.0))
		var z := float(row.get("z", 0.0))
		if x < float(bounds.get("minX", 0.0)) or x > float(bounds.get("maxX", 0.0)):
			geometry_ok = false
		if z < float(bounds.get("minZ", 0.0)) or z > float(bounds.get("maxZ", 0.0)):
			geometry_ok = false
		var expected_x := (float(row.get("lon", 0.0)) - 151.208) * 92459.893
		var expected_z := (float(row.get("lat", 0.0)) + 33.873) * 111019.656
		if absf(expected_x - x) > 1.0 or absf(expected_z - z) > 1.0:
			geometry_ok = false
		var osm := str(row.get("osm", ""))
		if osm.is_empty() or ids.has(osm):
			id_ok = false
		ids[osm] = true
	_check(geometry_ok, "every POI is inside the Stage B bounds and projects from its source coordinates")
	_check(id_ok, "every POI has a unique OSM type/id")

	# Synthetic placement: one real-looking OSM building with a POI inside.
	var world := {
		"buildings": [
			{
				"id": "way/999001",
				"ring": [[0.0, 0.0], [40.0, 0.0], [40.0, 24.0], [0.0, 24.0]],
				"heightM": 18.0,
			}
		]
	}
	var synthetic := [{
		"osm": "node/999001", "osmId": "999001", "brand": "McDonald's",
		"displayName": "McDonald's", "kind": "fast_food",
		"lat": -33.87, "lon": 151.21, "x": 20.0, "z": 12.0,
		"openingHours": "24/7", "brandWikidata": "Q38076",
	}]
	var root := Node3D.new()
	get_root().add_child(root)
	var layer: Node3D = BusinessLayer.new()
	root.add_child(layer)
	layer.build(world, synthetic)
	var stats: Dictionary = layer.stats
	_check(int(stats.get("placed", 0)) == 1, "a mapped POI inside a building places one storefront")
	_check(layer.get_child_count() == 1, "storefront node is added to the layer")
	if layer.get_child_count() == 1:
		var shop := layer.get_child(0) as Node3D
		_check(shop.is_in_group("business_poi"), "storefront joins the business_poi group")
		_check(str(shop.get_meta("osm_id")) == "node/999001", "storefront keeps its OSM source id")
		_check(str(shop.get_meta("brand")) == "McDonald's", "storefront keeps its real brand")
		_check(shop.find_children("BrandSign", "Label3D", true, false).size() == 1, "storefront has a brand sign")
		var flat := Vector2(shop.position.x, shop.position.z)
		var on_edge := absf(flat.y) < 0.4 or absf(flat.y - 24.0) < 0.4 or absf(flat.x) < 0.4 or absf(flat.x - 40.0) < 0.4
		_check(on_edge, "storefront is snapped onto the building facade")

	# Authored landmarks must never receive a chain sign.
	var landmark_world := {
		"buildings": [
			{
				"id": "way/104948253",
				"ring": [[100.0, 0.0], [140.0, 0.0], [140.0, 24.0], [100.0, 24.0]],
				"heightM": 22.0,
				"name": "Sydney Town Hall",
			}
		]
	}
	var landmark_rows := [{
		"osm": "node/999002", "osmId": "999002", "brand": "KFC",
		"displayName": "KFC", "kind": "fast_food",
		"lat": -33.87, "lon": 151.21, "x": 120.0, "z": 12.0,
	}]
	var landmark_layer: Node3D = BusinessLayer.new()
	root.add_child(landmark_layer)
	landmark_layer.build(landmark_world, landmark_rows)
	_check(int(landmark_layer.stats.get("placed", 0)) == 0, "authored heritage landmarks are never used for chain signage")

	# Woolworths/Coles are owned by the supermarket system and must be skipped.
	var external_layer: Node3D = BusinessLayer.new()
	root.add_child(external_layer)
	external_layer.build(world, [{
		"osm": "node/999003", "osmId": "999003", "brand": "Coles",
		"displayName": "Coles", "kind": "supermarket",
		"lat": -33.87, "lon": 151.21, "x": 20.0, "z": 12.0,
	}])
	_check(external_layer.get_child_count() == 0, "Woolworths/Coles are not duplicated by the business layer")

	root.queue_free()
	_finish()


func _finish() -> void:
	print("RESULT: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
