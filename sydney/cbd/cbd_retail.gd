extends Node3D

## Parody retail frontage for the Sydney CBD.
##
## The Stage B export owns the building footprints. This layer snaps a small
## number of authored shopfronts onto existing street facades: fascia sign,
## glazing, door, awning and sill. The brands are deliberate parodies, not real
## trademarks. Signboards are fixed to the facade (not billboarded) so they read
## as part of the building as the player drives past.
##
## Nothing here changes collision or invents a building. If a site cannot find a
## plausible facade within reach, it is skipped and counted.

const ArtUtil := preload("res://scripts/art.gd")

const AUTHORED_LANDMARKS := [
	"way/104948253", # Sydney Town Hall
	"way/40717424",  # Queen Victoria Building
	"way/16749128",  # St Mary's Cathedral
]

## name, fascia colour, lettering colour. Names are invented parodies.
const BRANDS := [
	["McCUNTHEADS", Color("b51f2c"), Color("ffd34d")],
	["STARBLOKES", Color("0b5b43"), Color("f2ecdc")],
	["UNDERPASS SUBS", Color("12763b"), Color("ffe15a")],
	["KENTUCKY FRIED CHOOK", Color("a51c23"), Color("f7efe2")],
	["HUNGRY JASPERS", Color("22356f"), Color("ffcf4a")],
	["DOMINO DAN'S", Color("103f8c"), Color("ffffff")],
	["MUCHO NACHOS", Color("bd511d"), Color("ffe9c9")],
	["BUNNIN'S", Color("1f6b3a"), Color("ffe14a")],
	["CHEAP CHEMIST BARN", Color("146c75"), Color("ffffff")],
	["WOOLY'S FRESH", Color("1f7a3d"), Color("f3f0e5")],
	["COOK'S", Color("b3222a"), Color("ffffff")],
	["TELSTRAY", Color("0a4f9e"), Color("ffd34d")],
	["CASH MONSTERS", Color("e0a81e"), Color("1b1b1b")],
	["BIG BOOST", Color("df5f1b"), Color("fff4e0")],
	["OPORT-O", Color("b5232a"), Color("ffffff")],
	["ROYAL ROOSTER", Color("7c1a22"), Color("ffd98a")],
	["PIE FACE", Color("8a3b1e"), Color("ffe9c4")],
	["SUSHI HUB", Color("1d2b33"), Color("f2c94c")],
	["THE BOTTLE-O", Color("1d5b39"), Color("ffffff")],
	["KEBAB KINGDOM", Color("4a1f63"), Color("ffd36a")],
	["WOK THIS WAY", Color("9d1f24"), Color("ffe8b0")],
	["SALTY'S", Color("166b8a"), Color("ffffff")],
	["FERRY GOOD", Color("1c5f4c"), Color("f8e7b0")],
	["HARBOUR KITCHEN", Color("243742"), Color("ffcf7a")],
	["COCKLE BAY GRILL", Color("46251f"), Color("ffd9a0")],
	["SEA STRIFE AQUARIUM", Color("0b5d8a"), Color("ffffff")],
	["MADAME TWO-SODS", Color("5a174a"), Color("ffd76b")],
	["THE ROCKS ARMS", Color("3c2a1d"), Color("e8c882")],
	["OP SHOP", Color("7a3d22"), Color("f6e4c4")],
	["BARBER BRO'S", Color("222831"), Color("e6c15c")],
	["NAIL PALACE", Color("7d2b55"), Color("ffe8f0")],
	["PHONE GURU", Color("1c3a55"), Color("8fe3ff")],
	["BONZA BANK", Color("8c1c2b"), Color("fff2d0")],
	["PAWN & CO", Color("2d4d3a"), Color("e8d8a8")],
	["TAX BARN", Color("324a6b"), Color("ffffff")],
	["GYM BARN", Color("2b2b2b"), Color("d7ff47")],
	["VINNIE'S", Color("6b1d22"), Color("ffe8c2")],
	["PIZZA PLANE", Color("b23a1c"), Color("fff0d8")],
	["TATTOO PARLOUR", Color("1e1e28"), Color("d7b6ff")],
	["MONEY MART", Color("123b5e"), Color("ffcf4a")],
]

## Site anchors: x, z, brand index. They are street-side positions, not exact
## frontage coordinates; the nearest real OSM facade is chosen at build time.
const SITES := [
	[-114.0, 86.0, 0], [-114.0, 116.0, 1], [-114.0, 148.0, 4],
	[-114.0, 182.0, 10], [-114.0, 220.0, 3], [-114.0, 258.0, 6],
	[-114.0, -66.0, 11], [-114.0, -98.0, 12], [-100.0, -152.0, 13],
	[-60.0, -218.0, 8], [-60.0, -250.0, 7], [-60.0, -286.0, 2],
	[-60.0, -322.0, 14], [-60.0, -358.0, 17], [-60.0, -396.0, 18],
	[50.0, -76.0, 0], [50.0, -126.0, 19], [44.0, -176.0, 20],
	[-12.0, 492.0, 21], [-12.0, 526.0, 29], [-12.0, 560.0, 31],
	[420.0, 182.0, 22], [455.0, 218.0, 27], [492.0, 252.0, 28],
	[418.0, -492.0, 15], [408.0, -560.0, 16], [398.0, -628.0, 30],
	[180.0, -1468.0, 22], [226.0, -1468.0, 33], [274.0, -1468.0, 1],
	[322.0, -1468.0, 23], [366.0, -1468.0, 12], [214.0, -1352.0, 34],
	[30.0, -1478.0, 27], [18.0, -1512.0, 28], [46.0, -1536.0, 1],
	[-598.0, -324.0, 24], [-598.0, -384.0, 25], [-598.0, -444.0, 26],
	[-598.0, -504.0, 13], [-598.0, -564.0, 0], [-598.0, -624.0, 24],
	[-590.0, -684.0, 23], [-402.0, -462.0, 9], [-306.0, -468.0, 5],
	[-210.0, -470.0, 32], [-94.0, -472.0, 35], [-580.0, -288.0, 25],
]

var stats: Dictionary = {}
var _materials: Dictionary = {}
var _used_edges: Dictionary = {}
var _placed_points: Array[Vector2] = []


func build(world_data: Dictionary) -> void:
	name = "RetailChains"
	var shops := 0
	var skipped := 0
	var labels := 0
	var by_brand: Dictionary = {}
	var buildings: Dictionary = {}
	for site: Array in SITES:
		if site.size() < 3:
			continue
		var site_point := Vector2(float(site[0]), float(site[1]))
		var brand_index := int(site[2]) % BRANDS.size()
		var candidate := _nearest_facade(world_data, site_point)
		if candidate.is_empty():
			skipped += 1
			continue
		var key := "%s:%d" % [str(candidate["building_id"]), int(candidate["edge_index"])]
		if _used_edges.has(key):
			skipped += 1
			continue
		var shop_point: Vector2 = candidate["point"]
		var too_close := false
		for existing: Vector2 in _placed_points:
			if existing.distance_to(shop_point) < 7.0:
				too_close = true
				break
		if too_close:
			skipped += 1
			continue
		var shop := _build_shop(
			shop_point,
			candidate["outward"],
			float(candidate["width"]),
			brand_index,
		)
		if shop == null:
			skipped += 1
			continue
		_used_edges[key] = true
		_placed_points.append(shop_point)
		buildings[str(candidate["building_id"])] = true
		shops += 1
		labels += 1
		var brand_name := str(BRANDS[brand_index][0])
		by_brand[brand_name] = int(by_brand.get(brand_name, 0)) + 1
	stats = {
		"shops": shops,
		"labels": labels,
		"skippedSites": skipped,
		"buildings": buildings.size(),
		"byBrand": by_brand,
		"parody": true,
	}


func _nearest_facade(world_data: Dictionary, point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 24.0
	for row: Dictionary in world_data.get("buildings", []):
		var building_id := str(row.get("id", ""))
		if building_id in AUTHORED_LANDMARKS:
			continue
		if float(row.get("heightM", 0.0)) < 3.5:
			continue
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var orientation := _ring_orientation(ring)
		for index in ring.size():
			var a_raw: Array = ring[index]
			var b_raw: Array = ring[(index + 1) % ring.size()]
			if a_raw.size() < 2 or b_raw.size() < 2:
				continue
			var a := Vector2(float(a_raw[0]), float(a_raw[1]))
			var b := Vector2(float(b_raw[0]), float(b_raw[1]))
			var edge := b - a
			var edge_length := edge.length()
			if edge_length < 5.2:
				continue
			var tangent := edge / edge_length
			var outward := Vector2(tangent.y, -tangent.x) * orientation
			var t := clampf((point - a).dot(tangent), 0.0, edge_length)
			var projection := a + tangent * t
			var distance := projection.distance_to(point)
			if distance >= best_distance:
				continue
			# Keep the whole shopfront on this facade, clear of both corners.
			var width := minf(_desired_width(int(point.x) + index), edge_length - 1.0)
			if width < 3.6:
				continue
			var along := clampf(t, width * 0.5 + 0.4, edge_length - width * 0.5 - 0.4)
			best_distance = distance
			best = {
				"building_id": building_id,
				"edge_index": index,
				"point": a + tangent * along,
				"outward": outward,
				"edge_length": edge_length,
				"width": width,
			}
	return best


func _ring_orientation(ring: Array) -> float:
	var area := 0.0
	for index in ring.size():
		var a: Array = ring[index]
		var b: Array = ring[(index + 1) % ring.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return 1.0 if area > 0.0 else -1.0


func _desired_width(seed_value: int) -> float:
	return 5.4 + float(absi(seed_value) % 4) * 0.65


func _build_shop(
	point: Vector2,
	outward: Vector2,
	width: float,
	brand_index: int,
) -> Node3D:
	var brand: Array = BRANDS[brand_index]
	var label_text := str(brand[0])
	if width < 4.2:
		return null
	var shop := Node3D.new()
	shop.name = "Shop_%s_%d" % [label_text.replace(" ", "").replace("'", ""), get_child_count()]
	shop.position = Vector3(point.x, 0.0, point.y) + Vector3(outward.x, 0.0, outward.y) * 0.20
	# Local +Z is the street normal, so all shopfront detail is authored in one
	# consistent facade space.
	shop.rotation.y = atan2(outward.x, outward.y)
	add_child(shop)
	shop.set_meta("brand", label_text)
	shop.set_meta("outward", Vector3(outward.x, 0.0, outward.y))
	shop.add_to_group("retail_shop")

	var fascia: Color = brand[1]
	var lettering: Color = brand[2]
	var stone := Color("8d897d")
	var trim := fascia.lightened(0.22)
	var glass := _material(Color("27434a"), Color("ffb85c"), 0.18)
	var warm := _material(Color("e7c58d"), Color("ffd39a"), 0.55)

	# Stone pilasters frame the shop and keep it tied to the host facade.
	for side in [-1.0, 1.0]:
		ArtUtil.box(shop, Vector3(side * width * 0.5, 2.0, 0.10), Vector3(0.42, 4.0, 0.34), stone)
		ArtUtil.box(shop, Vector3(side * width * 0.5, 4.08, 0.10), Vector3(0.52, 0.20, 0.42), trim)
	# Recessed shop window and door.
	_box_mesh(shop, Vector3(-width * 0.10, 1.42, 0.02), Vector3(width * 0.62, 2.24, 0.12), glass)
	ArtUtil.box(shop, Vector3(width * 0.31, 1.33, 0.03), Vector3(width * 0.20, 2.06, 0.14), Color("233a40"))
	_box_mesh(shop, Vector3(width * 0.31, 1.33, 0.11), Vector3(width * 0.14, 1.72, 0.06), warm)
	# Warm interior card behind the glazing reads as a lit shop at night.
	_box_mesh(shop, Vector3(-width * 0.10, 1.45, -0.04), Vector3(width * 0.50, 1.82, 0.06), warm)
	for index in 3:
		var x := -width * 0.10 + (float(index) - 1.0) * width * 0.18
		ArtUtil.box(shop, Vector3(x, 1.42, 0.09), Vector3(0.09, 2.24, 0.08), Color("4e5b5c"))
	ArtUtil.box(shop, Vector3(-width * 0.10, 0.28, 0.12), Vector3(width * 0.68, 0.22, 0.24), stone.darkened(0.10))
	ArtUtil.box(shop, Vector3(0.0, 0.06, 0.45), Vector3(width + 0.5, 0.12, 0.75), Color("a39b8a"))

	# Fascia board and fixed lettering.
	var fascia_width := width + 0.5
	ArtUtil.box(shop, Vector3(0.0, 3.55, 0.20), Vector3(fascia_width, 1.02, 0.26), fascia)
	ArtUtil.box(shop, Vector3(0.0, 4.08, 0.24), Vector3(fascia_width + 0.16, 0.13, 0.34), trim)
	ArtUtil.box(shop, Vector3(0.0, 3.02, 0.24), Vector3(fascia_width + 0.10, 0.10, 0.32), trim.darkened(0.25))
	var sign := Label3D.new()
	sign.text = label_text
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
	sign.position = Vector3(0.0, 3.56, 0.36)
	sign.name = "ShopSign"
	shop.add_child(sign)
	# If the name is wider than the board, shrink the lettering rather than
	# letting it run past the fascia.
	var estimated := float(label_text.length()) * 0.31
	if estimated > fascia_width - 0.5:
		sign.font_size = int(clampf(52.0 * (fascia_width - 0.6) / estimated, 26.0, 52.0))

	# Sloped awning with a striped valance.
	var awning := ArtUtil.box(shop, Vector3(0.0, 2.86, 0.72), Vector3(width + 0.2, 0.12, 1.38), trim)
	awning.rotation.x = 0.22
	ArtUtil.box(shop, Vector3(0.0, 2.60, 1.37), Vector3(width + 0.2, 0.30, 0.10), trim.darkened(0.18))
	for index in int(width / 1.1):
		var stripe_x := -width * 0.5 + 0.55 + float(index) * 1.1
		if stripe_x > width * 0.5 - 0.3:
			break
		ArtUtil.box(shop, Vector3(stripe_x, 2.61, 1.43), Vector3(0.34, 0.24, 0.04), lettering)
	# Door step and a small opening-hours plate.
	_box_mesh(shop, Vector3(width * 0.31, 2.62, 0.14), Vector3(width * 0.15, 0.24, 0.08), warm)
	return shop


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
	var key := "%s|%s|%.2f" % [color.to_html(), emission.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	_materials[key] = material
	return material
