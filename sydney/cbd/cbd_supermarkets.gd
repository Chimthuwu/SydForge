extends Node3D

## Enterable Woolworths and Coles stores.
##
## The street elevation is snapped onto a real OSM facade. The interior is a
## compact authored room placed away from the city (so it does not cut into the
## building or collide with the street), and the player is teleported in through
## the door interaction. Shelves are stocked by hand so shoplifting has visible
## consequences: products disappear, the total rises, and the alarm trips after
## three items.

const ArtUtil := preload("res://scripts/art.gd")
const StoreRuntime := preload("res://sydney/cbd/supermarket_store.gd")
## Real OSM business extract. The authored anchor only picks which mapped
## Woolworths/Coles branch is used; the actual position is the OSM POI.
const BUSINESS_PATH := "res://sydney/world/businesses.json"

const AUTHORED_LANDMARKS := [
	"way/104948253", "way/40717424", "way/16749128",
]

const STORES := [
	{
		"name": "WOOLWORTHS",
		"short": "Woolworths",
		"brand": "Woolworths",
		"color": Color("1c7a3c"),
		"lettering": Color("f4f1e5"),
		"anchor": Vector2(-112.0, 154.0),
	},
	{
		"name": "COLES",
		"short": "Coles",
		"brand": "Coles",
		"color": Color("c8232c"),
		"lettering": Color("ffffff"),
		"anchor": Vector2(-58.0, -250.0),
	},
]

var stats: Dictionary = {}
var stores: Array[Node3D] = []
var _player: Node


func build(world_data: Dictionary) -> void:
	name = "Supermarkets"
	var poi_rows := _load_business_pois()
	for index in STORES.size():
		var spec: Dictionary = STORES[index]
		var poi := _nearest_brand_poi(poi_rows, str(spec["brand"]), spec["anchor"])
		var anchor: Vector2 = spec["anchor"]
		if not poi.is_empty():
			anchor = Vector2(float(poi.get("x", anchor.x)), float(poi.get("z", anchor.y)))
		var facade := _nearest_facade(world_data, anchor)
		if facade.is_empty():
			push_warning("CbdSupermarkets: no facade near %s" % str(spec["name"]))
			continue
		_build_store(index, spec, facade, poi)
	stats = {
		"stores": stores.size(),
		"names": stores.map(func(store: Node3D) -> String: return str(store.get_meta("store_name"))),
		"interiors": stores.size(),
		"shoplifting": true,
		"osmIds": stores.map(func(store: Node3D) -> String: return str(store.get_meta("osm_id", ""))),
	}


func _load_business_pois() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUSINESS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return (parsed as Dictionary).get("pois", [])


## Closest mapped branch of the requested brand to the authored anchor. The
## anchor is only a selector, so the storefront still lands on a real POI.
func _nearest_brand_poi(rows: Array, brand: String, anchor: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for row: Dictionary in rows:
		if str(row.get("brand", "")) != brand:
			continue
		var point := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0)))
		var distance := point.distance_to(anchor)
		if distance < best_distance:
			best_distance = distance
			best = row
	return best


func _nearest_facade(world_data: Dictionary, point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	# A supermarket POI often sits in the middle of a large centre (The Galeries,
	# Central Park), so its exterior frontage can be well over 26 m away.
	var best_distance := 70.0
	for row: Dictionary in world_data.get("buildings", []):
		var id := str(row.get("id", ""))
		if id in AUTHORED_LANDMARKS:
			continue
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var orientation := _orientation(ring)
		for index in ring.size():
			var a_raw: Array = ring[index]
			var b_raw: Array = ring[(index + 1) % ring.size()]
			if a_raw.size() < 2 or b_raw.size() < 2:
				continue
			var a := Vector2(float(a_raw[0]), float(a_raw[1]))
			var b := Vector2(float(b_raw[0]), float(b_raw[1]))
			var edge := b - a
			var length := edge.length()
			# OSM splits long facades at every entrance, so a 13 m frontage must
			# be allowed to shrink onto a shorter segment instead of skipping.
			if length < 6.0:
				continue
			var tangent := edge / length
			var outward := Vector2(tangent.y, -tangent.x) * orientation
			var t := clampf((point - a).dot(tangent), 0.0, length)
			var projection := a + tangent * t
			var distance := projection.distance_to(point)
			if distance >= best_distance:
				continue
			var width := minf(13.0, length - 1.0)
			if width < 6.0:
				continue
			var along := clampf(t, width * 0.5 + 0.6, length - width * 0.5 - 0.6)
			best_distance = distance
			best = {
				"point": a + tangent * along,
				"outward": outward,
				"building": id,
				"width": width,
			}
	return best


func _orientation(ring: Array) -> float:
	var area := 0.0
	for index in ring.size():
		var a: Array = ring[index]
		var b: Array = ring[(index + 1) % ring.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return 1.0 if area > 0.0 else -1.0


func _build_store(index: int, spec: Dictionary, facade: Dictionary, poi: Dictionary = {}) -> void:
	var store := Node3D.new()
	store.name = "Store_%s" % str(spec["short"])
	store.add_to_group("supermarket")
	store.set_meta("store_name", str(spec["name"]))
	store.set_meta("shoplifting", true)
	store.set_meta("osm_id", str(poi.get("osm", "")))
	store.set_meta("source_lat", float(poi.get("lat", 0.0)))
	store.set_meta("source_lon", float(poi.get("lon", 0.0)))
	store.set_meta("world_x", float(poi.get("x", facade["point"].x)))
	store.set_meta("world_z", float(poi.get("z", facade["point"].y)))
	var point: Vector2 = facade["point"]
	var outward: Vector2 = facade["outward"]
	store.position = Vector3(point.x, 0.0, point.y) + Vector3(outward.x, 0.0, outward.y) * 0.24
	store.rotation.y = atan2(outward.x, outward.y)
	store.set_script(StoreRuntime)
	add_child(store)

	var color: Color = spec["color"]
	var lettering: Color = spec["lettering"]
	var width: float = float(facade.get("width", 13.0))
	var door := Node3D.new()
	door.name = "Entrance"
	door.position = Vector3(0.0, 0.0, 0.55)
	store.add_child(door)
	# Shopfront: fascia, glazing, automatic doors, trolley bay.
	ArtUtil.box(store, Vector3(0.0, 4.25, 0.25), Vector3(width, 1.3, 0.35), color)
	ArtUtil.box(store, Vector3(0.0, 4.98, 0.28), Vector3(width + 0.3, 0.16, 0.45), color.lightened(0.25))
	var sign := ArtUtil.label(store, Vector3(0.0, 4.28, 0.46), str(spec["name"]), 62)
	sign.modulate = lettering
	sign.outline_modulate = color.darkened(0.5)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ArtUtil.box(store, Vector3(-3.3, 1.7, 0.18), Vector3(5.3, 2.9, 0.16), Color("273f47"))
	ArtUtil.box(store, Vector3(3.3, 1.7, 0.18), Vector3(5.3, 2.9, 0.16), Color("273f47"))
	ArtUtil.box(store, Vector3(-3.3, 1.7, 0.28), Vector3(4.8, 2.4, 0.08), Color("e5c785"))
	ArtUtil.box(store, Vector3(3.3, 1.7, 0.28), Vector3(4.8, 2.4, 0.08), Color("e5c785"))
	ArtUtil.box(store, Vector3(0.0, 1.55, 0.30), Vector3(2.4, 2.7, 0.10), Color("aeb8b1"))
	ArtUtil.box(store, Vector3(0.0, 1.55, 0.37), Vector3(0.10, 2.5, 0.08), Color("596b66"))
	for x in [-1.0, 1.0]:
		ArtUtil.cylinder(store, Vector3(x * 3.9, 0.65, 1.4), 0.05, 1.3, Color("69706a"))
		ArtUtil.box(store, Vector3(x * 3.9, 1.3, 1.4), Vector3(1.0, 0.08, 0.7), Color("8a8f88"))
	for trolley in 3:
		ArtUtil.box(store, Vector3(-5.8 + float(trolley) * 0.7, 0.62, 1.7), Vector3(0.55, 0.6, 0.85), Color("8c9693"))
		ArtUtil.box(store, Vector3(-5.8 + float(trolley) * 0.7, 1.0, 1.7), Vector3(0.50, 0.1, 0.80), Color("3a4544"))

	# Interior room, placed in an unused authored pocket so it cannot intersect
	# the city. Player collision is real; the entrance/exit is a teleport.
	var base := Vector3(9100.0 + float(index) * 70.0, 24.0, 9100.0)
	var interior := Node3D.new()
	interior.name = "Interior"
	interior.position = base
	# Keep the interior in world space. Parenting it to the rotated storefront
	# would rotate the 9 km offset and leave the player staring at empty sky.
	add_child(interior)
	ArtUtil.box(interior, Vector3(0.0, -0.18, 0.0), Vector3(28.0, 0.36, 22.0), Color("d8d3c6"), true)
	# Four wall slabs, not one solid shell: a filled box would place its collision
	# through the room the player is meant to walk around in.
	for wall in [
		[Vector3(0.0, 2.8, -11.0), Vector3(28.0, 5.6, 0.4)],
		[Vector3(0.0, 2.8, 11.0), Vector3(28.0, 5.6, 0.4)],
		[Vector3(-14.0, 2.8, 0.0), Vector3(0.4, 5.6, 22.0)],
		[Vector3(14.0, 2.8, 0.0), Vector3(0.4, 5.6, 22.0)],
	]:
		ArtUtil.box(interior, wall[0], wall[1], Color("b9b4a7"), true)
	ArtUtil.box(interior, Vector3(0.0, 5.5, 0.0), Vector3(28.0, 0.25, 22.0), Color("ddd8cc"))
	for light_x in [-7.0, 7.0]:
		for light_z in [-5.0, 5.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(light_x, 4.8, light_z)
			light.light_color = Color("fff1d0")
			light.light_energy = 1.5
			light.omni_range = 13.0
			interior.add_child(light)
	ArtUtil.box(interior, Vector3(0.0, 5.1, -10.7), Vector3(10.0, 0.8, 0.2), color)
	var inner_sign := ArtUtil.label(interior, Vector3(0.0, 5.1, -10.55), str(spec["name"]), 58)
	inner_sign.modulate = lettering
	inner_sign.outline_modulate = color.darkened(0.45)
	inner_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var exit_door := ArtUtil.box(interior, Vector3(0.0, 1.3, 10.8), Vector3(2.4, 2.6, 0.12), Color("2f454c"))
	exit_door.name = "ExitDoor"
	var exit_label := ArtUtil.label(interior, Vector3(0.0, 3.25, 10.55), "EXIT  ·  E", 30)
	exit_label.modulate = Color("d9f0c0")
	exit_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var shelf_nodes: Array[Node3D] = []
	for row in 3:
		var z := -4.0 + float(row) * 4.6
		for column in 4:
			var x := -9.0 + float(column) * 6.0
			var shelf := Node3D.new()
			shelf.position = Vector3(x, 0.0, z)
			interior.add_child(shelf)
			ArtUtil.box(shelf, Vector3(0.0, 1.1, 0.0), Vector3(4.2, 2.2, 0.9), Color("5f6b67"))
			for level in 4:
				ArtUtil.box(shelf, Vector3(0.0, 0.38 + float(level) * 0.48, 0.50), Vector3(4.0, 0.08, 0.7), Color("a7afa9"))
				for product in 3:
					var product_box := ArtUtil.box(
						shelf,
						Vector3(-1.3 + float(product) * 1.3, 0.50 + float(level) * 0.48, 0.50),
						Vector3(0.72, 0.27, 0.38),
						[Color("d7a541"), Color("c84b3a"), Color("487d9c"), Color("dfd6b6")][(level + product) % 4],
					)
					product_box.add_to_group("shop_product")
			shelf_nodes.append(shelf)
	store.set_meta("shelves", shelf_nodes)
	store.set_meta("interior_spawn", base + Vector3(0.0, 1.10, 8.4))
	store.set_meta("interior_exit", base + Vector3(0.0, 1.10, 10.0))
	store.set_meta("saved_transform", Transform3D.IDENTITY)
	store.set_meta("steals", 0)
	store.set_meta("loot", 0)
	store.set_meta("alarm", false)
	store.set_meta("entry_cooldown", 0.0)
	stores.append(store)


## District delegates the E interaction here. Outside, the call enters; inside,
## it steals the nearest product or leaves through the marked door.
func interact(player: Node3D) -> void:
	if player == null:
		return
	if player.get("in_supermarket") == self:
		if player.global_position.distance_to(get_meta("interior_exit")) < 3.2:
			leave(player)
		else:
			steal(player)
		return
	if player.global_position.distance_to(global_position) < 8.0:
		enter(player)


func enter(player: Node3D) -> void:
	if player.get("in_supermarket") != null:
		return
	set_meta("saved_transform", player.global_transform)
	set_meta("entry_cooldown", 0.45)
	player.set("in_supermarket", self)
	player.set("vehicle", null)
	player.global_position = get_meta("interior_spawn")
	player.velocity = Vector3.ZERO
	var world: Object = player.get("world")
	if world != null:
		world.set("message", "%s · E AT SHELF: SHOPLIFT · E AT DOOR: LEAVE" % get_meta("store_name"))
		if world.get("rig") != null:
			world.get("rig").set("yaw", PI)


func leave(player: Node3D) -> void:
	var saved: Transform3D = get_meta("saved_transform")
	player.global_position = saved.origin + Vector3.UP * 0.25
	player.velocity = Vector3.ZERO
	player.set("in_supermarket", null)
	var world: Object = player.get("world")
	if world != null:
		world.set("message", "%s · come again" % get_meta("store_name"))


func steal(player: Node3D) -> void:
	if player.get("in_supermarket") != self:
		return
	var nearest: Node3D = null
	var nearest_distance := 3.2
	for shelf: Node3D in get_meta("shelves"):
		var distance := player.global_position.distance_to(shelf.global_position)
		if distance < nearest_distance:
			nearest = shelf
			nearest_distance = distance
	if nearest == null:
		return
	var product: Node3D = null
	for child: Node in nearest.get_children():
		if child.is_in_group("shop_product") and child.visible:
			product = child as Node3D
			break
	if product == null:
		return
	product.visible = false
	var value: int = 7 + (absi(int(get_meta("steals"))) * 6 + int(Time.get_ticks_msec()) % 17)
	var total: int = int(get_meta("loot")) + value
	set_meta("loot", total)
	set_meta("steals", int(get_meta("steals")) + 1)
	if player.has_method("add_shoplift"):
		player.call("add_shoplift", value)
	if int(get_meta("steals")) >= 3 and not bool(get_meta("alarm")):
		set_meta("alarm", true)
		var world: Node = player.get("world")
		if world != null:
			world.set("message", "ALARM! SECURITY IS COMING · GET TO THE DOOR")
			if world.has_method("sound"):
				world.call("sound", 780.0, 0.35)


func _process(dt: float) -> void:
	var cooldown: float = maxf(0.0, float(get_meta("entry_cooldown", 0.0)) - dt)
	set_meta("entry_cooldown", cooldown)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var world: Object = player.get("world")
	if player.get("in_supermarket") == self:
		if player.global_position.distance_to(get_meta("interior_exit")) < 3.2:
			world.set("message", "E: LEAVE %s" % get_meta("store_name"))
		elif bool(get_meta("alarm")):
			world.set("message", "SHOPLIFTED $%d · ALARM · E NEAR SHELF TO GRAB MORE" % int(get_meta("loot")))
		else:
			world.set("message", "%s · SHOPLIFTED $%d · E NEAR SHELF" % [get_meta("store_name"), int(get_meta("loot"))])
	elif player.global_position.distance_to(global_position) < 8.0:
		world.set("message", "E: ENTER %s" % get_meta("store_name"))
