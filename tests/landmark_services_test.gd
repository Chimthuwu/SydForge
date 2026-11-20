extends SceneTree

## Focused checks for the civic rebuild, parody retail, OSM petrol stations,
## enterable supermarkets and named street definitions.

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func settle(count: int) -> void:
	for _index in count:
		await process_frame


func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await settle(12)

	var town_hall := game.find_child("SydneyTownHall", true, false)
	var hyde := game.find_child("HydeParkLandmarks", true, false)
	var quay := game.find_child("CircularQuayLandmarks", true, false)
	var darling := game.find_child("DarlingHarbourLandmarks", true, false)
	check(town_hall != null, "Town Hall authored group exists")
	check(hyde != null, "Hyde Park authored group exists")
	check(quay != null, "Circular Quay authored group exists")
	check(darling != null, "Darling Harbour authored group exists")
	check(town_hall != null and town_hall.get_child_count() > 8, "Town Hall has substantial architecture")
	check(hyde.get_child_count() > 15 if hyde != null else false, "Hyde Park has paths/furniture/monuments")
	check(quay.get_child_count() >= 5 if quay != null else false, "Circular Quay has five wharf structures")
	check(darling.get_child_count() >= 3 if darling != null else false, "Darling Harbour has boardwalk/pavilions")

	var shops := get_nodes_in_group("retail_shop")
	var brands: Array[String] = []
	for shop: Node in shops:
		brands.append(str(shop.get_meta("brand", "")))
	check(shops.size() >= 20, "parody retail shops placed (%d)" % shops.size())
	check("McCUNTHEADS" in brands, "McCuntheads brand is present")

	var markets := get_nodes_in_group("supermarket")
	var market_names: Array[String] = []
	for market: Node in markets:
		market_names.append(str(market.get_meta("store_name", "")))
	check(markets.size() >= 2, "two enterable supermarkets built")
	check("WOOLWORTHS" in market_names, "Woolworths is in the game")
	check("COLES" in market_names, "Coles is in the game")

	var stations := get_nodes_in_group("petrol_station")
	check(stations.size() >= 4, "OSM petrol stations built (%d)" % stations.size())
	var petrol := game.find_child("PetrolStations", true, false)
	check(petrol != null and str(petrol.get("stats").get("source", "")).contains("openstreetmap"), "petrol data carries OSM attribution")
	var parks := game.find_child("Parks", true, false) as MeshInstance3D
	var grass_material: ShaderMaterial = null
	if parks != null:
		grass_material = parks.material_override as ShaderMaterial
	check(grass_material != null and grass_material.shader != null \
		and grass_material.shader.resource_path.ends_with("grass.gdshader"), "park surface uses the grass shader")

	var signs := game.find_child("StreetSignage", true, false)
	var sign_stats: Dictionary = signs.get("stats") if signs != null else {}
	check(bool(sign_stats.get("georgeStreetDefined", false)), "George Street is defined")
	check(bool(sign_stats.get("parramattaRoadDefined", false)), "Parramatta Road is defined")
	check(int(sign_stats.get("georgeStreetBlades", 0)) >= 2, "George Street blades placed on real road points")

	var player: Node3D = get_first_node_in_group("player")
	check(player != null, "player exists")
	if not markets.is_empty() and player != null:
		var market := markets[0] as Node3D
		market.call("enter", player)
		await settle(2)
		check(player.get("in_supermarket") == market, "player can enter Woolworths/Coles interior")
		var shelves: Array = market.get_meta("shelves", [])
		check(not shelves.is_empty(), "store has stocked shelves")
		if not shelves.is_empty():
			var shelf := shelves[0] as Node3D
			player.global_position = shelf.global_position + Vector3(0.0, 1.1, 1.0)
			market.call("steal", player)
			market.call("steal", player)
			check(int(player.get("shoplift_total")) > 0, "shoplifting adds loot value")
			market.call("steal", player)
			check(bool(market.get_meta("alarm", false)), "third theft trips the alarm")
		market.call("leave", player)
		await settle(1)
		check(player.get("in_supermarket") == null, "player can leave the supermarket")
		var outward := Vector3(sin(market.rotation.y), 0.0, cos(market.rotation.y))
		player.global_position = market.global_position + outward * 3.0 + Vector3.UP * 0.2
		game.call("interact")
		await settle(2)
		check(player.get("in_supermarket") == market, "E interaction enters the street-facing store")
		market.call("leave", player)

	if not stations.is_empty() and player != null:
		var station := stations[0] as Node3D
		station.call("sniff", player)
		check(float(player.get("damage_boost")) > 1.0, "petrol sniff grants a damage bonus")
		check(float(player.get("trip_time")) > 0.0, "petrol trip timer is active")
		var overlay := game.find_child("PetrolTripOverlay", true, false)
		check(overlay != null and (overlay as Control).visible, "petrol visual trip overlay is visible")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
