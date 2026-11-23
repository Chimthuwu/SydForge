extends Node3D

## Real Sydney businesses at their mapped OpenStreetMap positions.
##
## `sydney/world/businesses.json` is an offline, attributed extract of OSM
## POIs inside the Stage B bounds. Each POI keeps its OSM type/id and WGS84
## coordinates, and is projected during import onto the same equirectangular
## plane as `stage_b/world.json`. Nothing here invents a location or assigns a
## brand to a random facade.
##
## Woolworths and Coles are owned by `cbd_supermarkets.gd`, and fuel stations by
## `cbd_petrol.gd`; this layer deliberately skips those to avoid duplication.
## Every other mapped chain gets a storefront snapped onto the closest plausible
## street-facing edge of the building that contains or neighbours the POI.
##
## The geometry is presentation only: no collision, no building changes. A POI
## with no reasonable facade inside its search radius is skipped and reported in
## `stats`, never silently moved somewhere convenient.

const ArtUtil := preload("res://scripts/art.gd")
const DATA_PATH := "res://sydney/world/businesses.json"

const AUTHORED_LANDMARKS := [
	"way/104948253", # Sydney Town Hall
	"way/40717424",  # Queen Victoria Building
	"way/16749128",  # St Mary's Cathedral
]
const LANDMARK_WORDS := ["cathedral", "town hall", "queen victoria", "opera house", "museum"]

## Brands whose buildings/shopfronts are already owned by another system.
const EXTERNAL_BRANDS := ["Woolworths", "Coles"]

## canonical brand -> [fascia colour, lettering colour, preferred frontage width]
const STYLES := {
	"McDonald's": [Color("b8171f"), Color("ffd447"), 7.4],
	"KFC": [Color("a51c23"), Color("f7efe2"), 7.0],
	"7-Eleven": [Color("ef6c00"), Color("ffffff"), 5.4],
	"Hungry Jack's": [Color("123f8f"), Color("ffcf4a"), 7.0],
	"Subway": [Color("12763b"), Color("ffe15a"), 6.0],
	"Domino's": [Color("103f8c"), Color("ffffff"), 6.0],
	"Guzman y Gomez": [Color("1b1b1b"), Color("f4d03f"), 6.4],
	"Oporto": [Color("b5232a"), Color("ffffff"), 6.0],
	"Grill'd": [Color("3f5a1e"), Color("f2e6b8"), 6.0],
	"Red Rooster": [Color("7c1a22"), Color("ffd98a"), 6.0],
	"Zambrero": [Color("c4471e"), Color("fff4dd"), 5.6],
	"Fishbowl": [Color("194e5c"), Color("e9f7f4"), 5.6],
	"Chemist Warehouse": [Color("d21f2b"), Color("ffffff"), 6.4],
	"Priceline": [Color("d81e6c"), Color("ffffff"), 5.8],
	"Terry White": [Color("0b5c9c"), Color("ffffff"), 5.6],
	"Officeworks": [Color("1f6fb2"), Color("ffe14a"), 8.0],
	"BWS": [Color("7a1f3d"), Color("f5e6c8"), 5.6],
	"Dan Murphy's": [Color("1d3b2a"), Color("e9d9a8"), 7.6],
	"Liquorland": [Color("1f6b3a"), Color("ffd34d"), 5.6],
	"IGA": [Color("c8232c"), Color("ffffff"), 9.0],
	"ALDI": [Color("12457f"), Color("ffffff"), 9.4],
	"Harris Farm": [Color("2f6b35"), Color("f4e6b8"), 8.4],
	"Bunnings": [Color("144d2e"), Color("ffffff"), 10.5],
	"EzyMart": [Color("e13a2f"), Color("ffffff"), 4.6],
	"City Convenience": [Color("1e4f8f"), Color("ffffff"), 4.4],
	"Quikstop": [Color("f2a71b"), Color("1b1b1b"), 4.4],
	"Friendly Grocer": [Color("2f7a3a"), Color("fff8dc"), 5.0],
	"Daiso Japan": [Color("b3222a"), Color("ffffff"), 5.4],
	"JB Hi-Fi": [Color("f7d117"), Color("1b1b1b"), 6.6],
	"Kathmandu": [Color("1b3a4b"), Color("ffffff"), 5.6],
	"Cotton On": [Color("1b1b1b"), Color("ffffff"), 5.6],
	"UNIQLO": [Color("d71920"), Color("ffffff"), 6.0],
	"Myer": [Color("1b1b1b"), Color("ffffff"), 8.4],
	"David Jones": [Color("1b1b1b"), Color("f0e6cf"), 8.4],
	"Kmart": [Color("d71920"), Color("ffffff"), 8.0],
	"Target": [Color("cc0000"), Color("ffffff"), 8.0],
	"Big W": [Color("0066b3"), Color("ffffff"), 8.4],
	"Starbucks": [Color("0b5b43"), Color("f2ecdc"), 5.2],
	"Gloria Jean's": [Color("4a1f2a"), Color("f0d9a8"), 5.2],
	"Boost Juice": [Color("e94e1b"), Color("ffffff"), 4.8],
}

const SUPERMARKET_KINDS := ["supermarket", "warehouse", "department"]

var stats: Dictionary = {}
var pois: Array[Dictionary] = []
var _used_edges: Dictionary = {}
var _placed_points: Array[Vector2] = []
var _not_placed: Array[Dictionary] = []
## Spatial edge index: cell key -> facade records. The naive full-building scan
## cost ~17 s for 189 POIs against 11k footprints, so placement now visits only
## the cells a POI can plausibly reach.
const CELL_SIZE := 48.0
const MAX_SEARCH := 34.0
var _edge_index: Dictionary = {}
var _building_edges: Dictionary = {}
var _building_cells: Dictionary = {}
var _building_rings: Dictionary = {}
var _index_built := false


## Frontage positions owned by real POIs. Other presentation layers use this to
## avoid putting a fictional brand on top of a mapped business.
func placed_points() -> Array[Vector2]:
	return _placed_points.duplicate()


## `rows_override` lets the headless test exercise placement with a synthetic
## building without rewriting the committed OSM dataset.
func build(world_data: Dictionary, rows_override: Array = []) -> void:
	name = "BusinessPOIs"
	var rows: Array = rows_override
	var source := "synthetic"
	var license := "test"
	if rows.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("CbdBusinesses: %s missing or invalid" % DATA_PATH)
			stats = {"error": "business data missing"}
			return
		var data: Dictionary = parsed
		rows = data.get("pois", [])
		source = str(data.get("source", "OpenStreetMap contributors"))
		license = str(data.get("license", "ODbL 1.0"))
	_build_edge_index(world_data)
	var placed := 0
	var skipped := 0
	var by_brand: Dictionary = {}
	# Place large-format stores first so a small takeaway cannot take the only
	# usable wide frontage on the block.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_kind := str(a.get("kind", ""))
		var b_kind := str(b.get("kind", ""))
		var a_rank := 0 if a_kind in SUPERMARKET_KINDS else (1 if a_kind == "pharmacy" else 2)
		var b_rank := 0 if b_kind in SUPERMARKET_KINDS else (1 if b_kind == "pharmacy" else 2)
		return a_rank < b_rank
	)
	for row: Dictionary in rows:
		var brand := str(row.get("brand", ""))
		if brand in EXTERNAL_BRANDS:
			continue
		var point := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0)))
		var candidate := _nearest_facade(world_data, point, str(row.get("kind", "retail")))
		if candidate.is_empty():
			skipped += 1
			_not_placed.append({"osm": row.get("osm", ""), "brand": brand, "reason": "no facade"})
			continue
		var key := "%s:%d" % [str(candidate["building_id"]), int(candidate["edge_index"])]
		if _used_edges.has(key):
			# Try the other side of the same building before giving up: several
			# POIs inside one centre can legitimately face different streets.
			candidate = _nearest_facade(world_data, point, str(row.get("kind", "retail")), key)
		if candidate.is_empty():
			skipped += 1
			_not_placed.append({"osm": row.get("osm", ""), "brand": brand, "reason": "frontage used"})
			continue
		key = "%s:%d" % [str(candidate["building_id"]), int(candidate["edge_index"])]
		var shop_point: Vector2 = candidate["point"]
		var too_close := false
		for existing: Vector2 in _placed_points:
			if existing.distance_to(shop_point) < 5.0:
				too_close = true
				break
		if too_close:
			skipped += 1
			_not_placed.append({"osm": row.get("osm", ""), "brand": brand, "reason": "too close"})
			continue
		if _build_storefront(row, candidate) == null:
			skipped += 1
			_not_placed.append({"osm": row.get("osm", ""), "brand": brand, "reason": "geometry"})
			continue
		_used_edges[key] = true
		_placed_points.append(shop_point)
		pois.append({"osm": row.get("osm", ""), "brand": brand, "node": self.get_child(self.get_child_count() - 1)})
		placed += 1
		by_brand[brand] = int(by_brand.get(brand, 0)) + 1

	stats = {
		"found": rows.size(),
		"placed": placed,
		"skipped": skipped,
		"byBrand": by_brand,
		"notPlaced": _not_placed,
		"source": source,
		"license": license,
		"externalBrands": EXTERNAL_BRANDS,
	}


func _build_edge_index(world_data: Dictionary) -> void:
	_edge_index.clear()
	_building_edges.clear()
	_building_cells.clear()
	_building_rings.clear()
	_index_built = true
	for row: Dictionary in world_data.get("buildings", []):
		var building_id := str(row.get("id", ""))
		if building_id in AUTHORED_LANDMARKS:
			continue
		if _is_landmark_name(str(row.get("name", ""))):
			continue
		if float(row.get("heightM", 0.0)) < 3.4:
			continue
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var orientation := _ring_orientation(ring)
		_building_rings[building_id] = ring
		for index in ring.size():
			var a_raw: Array = ring[index]
			var b_raw: Array = ring[(index + 1) % ring.size()]
			if a_raw.size() < 2 or b_raw.size() < 2:
				continue
			var a := Vector2(float(a_raw[0]), float(a_raw[1]))
			var b := Vector2(float(b_raw[0]), float(b_raw[1]))
			var edge := b - a
			var edge_length := edge.length()
			if edge_length < 4.4:
				continue
			var tangent := edge / edge_length
			var record := {
				"building_id": building_id,
				"edge_index": index,
				"a": a,
				"b": b,
				"tangent": tangent,
				"outward": Vector2(tangent.y, -tangent.x) * orientation,
				"edge_length": edge_length,
			}
			if not _building_edges.has(building_id):
				_building_edges[building_id] = []
			(_building_edges[building_id] as Array).append(record)
			# Index the edge in every 48 m cell its segment touches.
			var min_x := int(floor(minf(a.x, b.x) / CELL_SIZE))
			var max_x := int(floor(maxf(a.x, b.x) / CELL_SIZE))
			var min_z := int(floor(minf(a.y, b.y) / CELL_SIZE))
			var max_z := int(floor(maxf(a.y, b.y) / CELL_SIZE))
			for cx in range(min_x, max_x + 1):
				for cz in range(min_z, max_z + 1):
					var key := Vector2i(cx, cz)
					if not _edge_index.has(key):
						_edge_index[key] = []
					(_edge_index[key] as Array).append(record)
		# Record which cells each footprint's bounding box covers, so a POI
		# deep inside a shopping centre can be matched to its containing mall.
		var xs: Array = []
		var zs: Array = []
		for vertex: Array in ring:
			if vertex.size() >= 2:
				xs.append(float(vertex[0]))
				zs.append(float(vertex[1]))
		if not xs.is_empty():
			var bmin_x := int(floor(float(xs.min()) / CELL_SIZE))
			var bmax_x := int(floor(float(xs.max()) / CELL_SIZE))
			var bmin_z := int(floor(float(zs.min()) / CELL_SIZE))
			var bmax_z := int(floor(float(zs.max()) / CELL_SIZE))
			for bx in range(bmin_x, bmax_x + 1):
				for bz in range(bmin_z, bmax_z + 1):
					var bkey := Vector2i(bx, bz)
					if not _building_cells.has(bkey):
						_building_cells[bkey] = []
					var bucket: Array = _building_cells[bkey]
					if not bucket.has(building_id):
						bucket.append(building_id)


## Nearest plausible street-facing building edge. `avoid_edge` lets a second
## POI on the same building choose a different frontage.
func _nearest_facade(
	world_data: Dictionary,
	point: Vector2,
	kind: String,
	avoid_edge: String = "",
) -> Dictionary:
	if not _index_built:
		_build_edge_index(world_data)
	# A POI inside a shopping centre belongs to that footprint even if the
	# centre is deep. Prefer the containing building's own exterior edges.
	var containing := _containing_building(point)
	if not containing.is_empty():
		var inside := _best_edge(_building_edges.get(containing, []), point, kind, avoid_edge, 160.0)
		if not inside.is_empty():
			return inside
	# Fallback: nearest facade within 45 m, which covers street-front addresses
	# whose OSM node sits a little behind the building line.
	var cell := Vector2i(int(floor(point.x / CELL_SIZE)), int(floor(point.y / CELL_SIZE)))
	var seen: Dictionary = {}
	var candidates: Array = []
	for cx in range(cell.x - 2, cell.x + 3):
		for cz in range(cell.y - 2, cell.y + 3):
			for record: Dictionary in _edge_index.get(Vector2i(cx, cz), []):
				var record_key := "%s:%d" % [str(record["building_id"]), int(record["edge_index"])]
				if seen.has(record_key):
					continue
				seen[record_key] = true
				candidates.append(record)
	return _best_edge(candidates, point, kind, avoid_edge, 45.0)


func _best_edge(
	records: Array,
	point: Vector2,
	kind: String,
	avoid_edge: String,
	max_distance: float,
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_distance
	for record: Dictionary in records:
		var record_key := "%s:%d" % [str(record["building_id"]), int(record["edge_index"])]
		if record_key == avoid_edge:
			continue
		var a: Vector2 = record["a"]
		var tangent: Vector2 = record["tangent"]
		var edge_length: float = float(record["edge_length"])
		var t := clampf((point - a).dot(tangent), 0.0, edge_length)
		var projection := a + tangent * t
		var distance := projection.distance_to(point)
		if distance >= best_distance:
			continue
		var width := _desired_width(kind, edge_length, str(record["building_id"]), int(record["edge_index"]))
		if width < 3.4:
			continue
		var along := clampf(t, width * 0.5 + 0.4, edge_length - width * 0.5 - 0.4)
		best_distance = distance
		best = {
			"building_id": str(record["building_id"]),
			"edge_index": int(record["edge_index"]),
			"point": a + tangent * along,
			"outward": record["outward"],
			"edge_length": edge_length,
			"width": width,
		}
	return best


func _containing_building(point: Vector2) -> String:
	var cell := Vector2i(int(floor(point.x / CELL_SIZE)), int(floor(point.y / CELL_SIZE)))
	for building_id: String in _building_cells.get(cell, []):
		if _point_in_ring(point, _building_rings.get(building_id, [])):
			return building_id
	return ""


func _point_in_ring(point: Vector2, ring: Array) -> bool:
	if ring.size() < 3:
		return false
	var inside := false
	for index in ring.size():
		var a: Array = ring[index]
		var b: Array = ring[(index + 1) % ring.size()]
		if a.size() < 2 or b.size() < 2:
			continue
		var az := float(a[1])
		var bz := float(b[1])
		if (az > point.y) == (bz > point.y):
			continue
		var cross_x := float(a[0]) + (point.y - az) * (float(b[0]) - float(a[0])) / (bz - az)
		if point.x < cross_x:
			inside = not inside
	return inside


func _is_landmark_name(building_name: String) -> bool:
	var low := building_name.to_lower()
	for word: String in LANDMARK_WORDS:
		if low.contains(word):
			return true
	return false


func _desired_width(kind: String, edge_length: float, building_id: String, index: int) -> float:
	var style: Array = STYLES.get("_default", [Color("40484a"), Color("ffffff"), 5.2])
	var width := float(style[2])
	var preferred := {
		"supermarket": 9.6, "warehouse": 10.5, "department": 8.6,
		"fast_food": 6.4, "convenience": 4.6, "pharmacy": 5.6,
		"liquor": 5.6, "cafe": 5.0, "retail": 5.6,
	}
	width = float(preferred.get(kind, width))
	# Keep the shopfront inside the facade even on a short edge.
	width = minf(width, edge_length - 1.0)
	# A deterministic nudge avoids every shop on a block using the same width.
	var seed_value := absi(building_id.hash() + index * 17)
	return width - float(seed_value % 3) * 0.35


func _ring_orientation(ring: Array) -> float:
	var area := 0.0
	for index in ring.size():
		var a: Array = ring[index]
		var b: Array = ring[(index + 1) % ring.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return 1.0 if area > 0.0 else -1.0


func _build_storefront(row: Dictionary, candidate: Dictionary) -> Node3D:
	var brand := str(row.get("brand", "SHOP"))
	var display := str(row.get("displayName", brand)).to_upper()
	var kind := str(row.get("kind", "retail"))
	var style: Array = STYLES.get(brand, [Color("40484a"), Color("ffffff"), 5.2])
	var fascia: Color = style[0]
	var lettering: Color = style[1]
	var width: float = float(candidate["width"])
	if width < 3.4:
		return null

	var shop := Node3D.new()
	shop.name = "Business_%s_%s" % [brand.replace(" ", "").replace("'", ""), str(row.get("osmId", ""))]
	var point: Vector2 = candidate["point"]
	var outward: Vector2 = candidate["outward"]
	shop.position = Vector3(point.x, 0.0, point.y) + Vector3(outward.x, 0.0, outward.y) * 0.22
	shop.rotation.y = atan2(outward.x, outward.y)
	add_child(shop)
	shop.set_meta("brand", brand)
	shop.set_meta("display_name", display)
	shop.set_meta("kind", kind)
	shop.set_meta("osm_id", str(row.get("osm", "")))
	shop.set_meta("source_lat", float(row.get("lat", 0.0)))
	shop.set_meta("source_lon", float(row.get("lon", 0.0)))
	shop.set_meta("world_x", float(row.get("x", 0.0)))
	shop.set_meta("world_z", float(row.get("z", 0.0)))
	shop.set_meta("opening_hours", str(row.get("openingHours", "")))
	shop.set_meta("brand_wikidata", str(row.get("brandWikidata", "")))
	shop.add_to_group("business_poi")

	var stone := Color("8d897d")
	var trim := fascia.lightened(0.22)
	var glass := _material(Color("264148"), Color("ffb85c"), 0.18)
	var warm := _material(Color("e7c58d"), Color("ffd39a"), 0.6)
	var fascia_y := 3.55
	var glazing_height := 2.24
	var glazing_y := 1.42
	if kind in SUPERMARKET_KINDS:
		fascia_y = 4.55
		glazing_height = 2.75
		glazing_y = 1.7
	elif kind == "fast_food":
		fascia_y = 3.8
		glazing_height = 2.1

	# Stone pilasters tie the storefront to the host facade.
	for side in [-1.0, 1.0]:
		ArtUtil.box(shop, Vector3(side * width * 0.5, 2.0, 0.10), Vector3(0.40, 4.0, 0.34), stone)
		ArtUtil.box(shop, Vector3(side * width * 0.5, fascia_y + 0.52, 0.10), Vector3(0.50, 0.18, 0.42), trim)
	# Glazing and a door on the right, with a warm interior card.
	_box_mesh(shop, Vector3(-width * 0.10, glazing_y, 0.02), Vector3(width * 0.62, glazing_height, 0.12), glass)
	ArtUtil.box(shop, Vector3(width * 0.31, 1.33, 0.03), Vector3(width * 0.20, 2.06, 0.14), Color("233a40"))
	_box_mesh(shop, Vector3(width * 0.31, 1.33, 0.11), Vector3(width * 0.14, 1.72, 0.06), warm)
	_box_mesh(shop, Vector3(-width * 0.10, glazing_y + 0.03, -0.04), Vector3(width * 0.50, glazing_height * 0.82, 0.06), warm)
	for index in 3:
		var x := -width * 0.10 + (float(index) - 1.0) * width * 0.18
		ArtUtil.box(shop, Vector3(x, glazing_y, 0.09), Vector3(0.09, glazing_height, 0.08), Color("4e5b5c"))
	ArtUtil.box(shop, Vector3(-width * 0.10, 0.28, 0.12), Vector3(width * 0.68, 0.22, 0.24), stone.darkened(0.10))
	ArtUtil.box(shop, Vector3(0.0, 0.06, 0.45), Vector3(width + 0.5, 0.12, 0.75), Color("a39b8a"))

	# Fascia board, sign and an under-lit soffit.
	ArtUtil.box(shop, Vector3(0.0, fascia_y, 0.20), Vector3(width + 0.5, 1.02, 0.26), fascia)
	ArtUtil.box(shop, Vector3(0.0, fascia_y + 0.53, 0.24), Vector3(width + 0.66, 0.13, 0.34), trim)
	ArtUtil.box(shop, Vector3(0.0, fascia_y - 0.53, 0.24), Vector3(width + 0.60, 0.10, 0.32), trim.darkened(0.25))
	var sign := Label3D.new()
	sign.text = _sign_text(display, kind, brand)
	sign.font_size = 52
	sign.pixel_size = 0.011
	sign.outline_size = 7
	sign.modulate = lettering
	sign.outline_modulate = fascia.darkened(0.55)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.double_sided = false
	sign.shaded = false
	sign.position = Vector3(0.0, fascia_y + 0.01, 0.36)
	sign.name = "BrandSign"
	shop.add_child(sign)
	var estimated := float(sign.text.length()) * 0.31
	if estimated > width - 0.4:
		sign.font_size = int(clampf(52.0 * (width - 0.5) / estimated, 22.0, 52.0))
	# Horizontal logo bar for fast food and convenience brands; keeps the
	# storefront legible from a moving car where the lettering alone is small.
	if kind in ["fast_food", "convenience"]:
		ArtUtil.box(shop, Vector3(0.0, fascia_y, 0.34), Vector3(width * 0.92, 0.12, 0.03), lettering)

	if kind in SUPERMARKET_KINDS:
		# Trolley bay and wide automatic doors read as a supermarket, not a
		# takeaway with a bigger sign.
		for index in 3:
			ArtUtil.box(shop, Vector3(-width * 0.42 + float(index) * 0.62, 0.62, 1.5), Vector3(0.52, 0.58, 0.8), Color("8c9693"))
			ArtUtil.box(shop, Vector3(-width * 0.42 + float(index) * 0.62, 0.98, 1.5), Vector3(0.46, 0.1, 0.76), Color("3a4544"))
		ArtUtil.box(shop, Vector3(0.0, 1.55, 0.30), Vector3(2.4, 2.7, 0.10), Color("aeb8b1"))
		ArtUtil.box(shop, Vector3(0.0, 1.55, 0.37), Vector3(0.10, 2.5, 0.08), Color("596b66"))
	elif kind == "fast_food":
		# Menu board and a bench under the awning.
		ArtUtil.box(shop, Vector3(-width * 0.34, 1.45, 0.32), Vector3(0.75, 1.05, 0.08), Color("1b2528"))
		ArtUtil.box(shop, Vector3(-width * 0.34, 1.68, 0.37), Vector3(0.62, 0.16, 0.03), lettering)
		ArtUtil.box(shop, Vector3(width * 0.22, 0.52, 0.95), Vector3(1.35, 0.12, 0.42), Color("6d6f68"))
	elif kind == "pharmacy":
		# Green cross, the standard Australian pharmacy marker.
		ArtUtil.box(shop, Vector3(width * 0.42, 4.35, 0.42), Vector3(0.16, 0.95, 0.08), Color("2ecc71"))
		ArtUtil.box(shop, Vector3(width * 0.42, 4.35, 0.42), Vector3(0.78, 0.20, 0.08), Color("2ecc71"))
	elif kind == "liquor":
		ArtUtil.box(shop, Vector3(-width * 0.30, 2.1, 0.34), Vector3(0.9, 0.5, 0.06), lettering)

	# Awning above the shopfront.
	var awning := ArtUtil.box(shop, Vector3(0.0, fascia_y - 0.72, 0.72), Vector3(width + 0.2, 0.12, 1.38), trim)
	awning.rotation.x = 0.22
	ArtUtil.box(shop, Vector3(0.0, fascia_y - 0.98, 1.37), Vector3(width + 0.2, 0.30, 0.10), trim.darkened(0.18))
	# A small opening-hours plate beside the door, where OSM supplied one.
	if not str(row.get("openingHours", "")).is_empty():
		var plate := Label3D.new()
		plate.text = str(row.get("openingHours", "")).to_upper().substr(0, 28)
		plate.font_size = 26
		plate.pixel_size = 0.008
		plate.modulate = Color("d9f0c0")
		plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		plate.position = Vector3(width * 0.30, 2.55, 0.20)
		shop.add_child(plate)
	return shop


func _sign_text(display: String, kind: String, brand: String) -> String:
	if brand == "7-Eleven":
		return "7-ELEVEN"
	if brand == "McDonald's":
		return "McDONALD'S"
	if brand == "Hungry Jack's":
		return "HUNGRY JACK'S"
	if brand == "Domino's":
		return "DOMINO'S"
	if brand == "Grill'd":
		return "GRILL'D"
	if brand == "Chemist Warehouse" or brand == "Terry White":
		return "CHEMIST WAREHOUSE" if brand == "Chemist Warehouse" else "TERRY WHITE"
	# Drop a trailing locality qualifier that does not fit a fascia ("... Metro",
	# "... Express") but keep the recognisable chain name.
	for suffix in [" METRO", " EXPRESS", " LOCAL", " TOWN HALL"]:
		if display.ends_with(suffix):
			display = display.substr(0, display.length() - suffix.length())
	return display


func _box_mesh(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	parent.add_child(instance)
	instance.position = position
	return instance


func _material(color: Color, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	return material
