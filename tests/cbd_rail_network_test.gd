extends SceneTree

const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1


func run() -> void:
	var world = CbdWorldScript.new()
	check(world.load_world(), "Stage B world loads with the rail corridor")
	root.add_child(world)
	await process_frame

	var railway: Node3D = world.get_node_or_null("SydneyRailNetwork")
	check(railway != null, "canonical CBD world includes SydneyRailNetwork")
	if railway == null:
		quit(1)
		return
	var route: Array[Vector3] = railway.get("main_route_points")
	var station_nodes: Dictionary = railway.get("station_nodes")
	var station_indices: Dictionary = railway.get("station_route_indices")
	var source_stations: Array = railway.get("source").get("stations", [])
	check(route.size() > 100, "Milsons Point–Redfern route has detailed waypoints")
	check(station_nodes.size() == 5, "five named stations are present")
	for station_id in ["milsons-point", "wynyard", "town-hall", "central", "redfern"]:
		check(station_nodes.has(station_id), "station node exists: " + station_id)
		check(station_indices.has(station_id), "route reaches station: " + station_id)
		var station_position := _station_position(source_stations, station_id)
		var route_index := int(station_indices.get(station_id, -1))
		var route_position: Vector3 = route[clampi(route_index, 0, route.size() - 1)]
		var station_distance := Vector2(
			route_position.x - station_position.x,
			route_position.z - station_position.z
		).length()
		check(station_distance < 200.0,
			"track reaches the %s station precinct (%.1f m)" % [station_id, station_distance])
	var ordered := true
	var order := ["milsons-point", "wynyard", "town-hall", "central", "redfern"]
	for index in range(order.size() - 1):
		if int(station_indices[order[index]]) >= int(station_indices[order[index + 1]]):
			ordered = false
	check(ordered, "station order follows the Milsons Point–Redfern route")

	var milsons := _station_position(source_stations, "milsons-point")
	var redfern := _station_position(source_stations, "redfern")
	print("RAIL ENDPOINTS: start=", route[0], " target=", milsons,
		" end=", route[-1], " target=", redfern)
	check(route[0].distance_to(milsons) < 35.0, "route starts at Milsons Point")
	check(route[-1].distance_to(redfern) < 35.0, "route ends at Redfern")
	var largest_gap := 0.0
	for index in range(route.size() - 1):
		largest_gap = maxf(largest_gap, route[index].distance_to(route[index + 1]))
	check(largest_gap <= 9.0, "route geometry has no large gaps (max %.1f m)" % largest_gap)

	check(railway.get_node_or_null("RailBallast") != null, "ballast mesh is built")
	check(railway.get_node_or_null("RailSleepers") != null, "sleepers are built")
	check(railway.get_node_or_null("RailSteel") != null, "double-track steel rails are built")
	check(railway.get_node_or_null("WynyardRailTunnelPortal") != null,
		"rail tunnel portal is visible at the Harbour Bridge approach")
	check(railway.get("stats").get("tunnelWays", 0) >= 4, "sourced tunnel sections are included")
	check(railway.get("stats").get("bridgeIntegration", false), "route joins the existing Harbour Bridge track")
	print("RAIL STATS: ", railway.get("stats"))
	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _station_position(stations: Array, wanted_id: String) -> Vector3:
	for station: Dictionary in stations:
		if String(station.get("id", "")) == wanted_id:
			return Vector3(float(station["x"]), 0.0, float(station["z"]))
	return Vector3.INF
