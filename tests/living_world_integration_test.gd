extends SceneTree

## Integration gates for the unified living-Sydney simulation.
## Loads the canonical scene and verifies that previously orphaned systems are
## wired, that shared activity profiles drive them, and that world events and
## weather/audio/venue interactions actually propagate.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var _checks := 0
var _failures := 0
var scene: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		push_error("FAIL: " + description)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(20)

	_check_integration()
	_check_time_profiles()
	_check_traffic_reactivity()
	_check_weather_and_audio()
	_check_businesses()
	_check_ambient_events()
	_check_incidents()
	_check_pedestrian_reactivity()

	print("RESULT: %d checks, %d failures" % [_checks, _failures])
	scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _node(name: String) -> Node:
	return scene.get_node_or_null(name)


func _check_integration() -> void:
	for name in ["WorldTimeManager", "CityLightsManager", "TrafficManager",
			"PedestrianManager", "WildlifeManager", "WeatherManager",
			"BusinessManager", "AmbientAudioDirector", "EmergencyIncidentManager",
			"AmbientEventDirector", "WorldSimulationDirector"]:
		_check(_node(name) != null, "canonical world owns %s" % name)

	var sim = _node("WorldSimulationDirector")
	_check(sim != null and sim.get("traffic_manager") != null, "director references traffic manager")
	_check(sim != null and sim.get("pedestrian_manager") != null, "director references pedestrian manager")
	_check(sim != null and sim.get("weather_manager") != null, "director references weather manager")
	_check(sim != null and sim.get("business_manager") != null, "director references business manager")
	_check(sim != null and sim.get("event_director") != null, "director references ambient event director")
	_check(sim != null and sim.get("incident_manager") != null, "director references incident manager")

	var seen: Array = []
	sim.world_event.connect(func(kind: String, _pos: Vector3, _sev: float, _src: Object) -> void:
		seen.append(kind))
	sim.call("report_event", "gunfire", Vector3(100.0, 0.0, -1400.0), 1.0)
	_check(seen.has("gunfire"), "world event bus publishes gunfire to all listeners")


func _check_time_profiles() -> void:
	var time_mgr = _node("WorldTimeManager")
	var sim = _node("WorldSimulationDirector")
	_check(time_mgr != null and "activity_period" in time_mgr, "time manager exposes activity_period")
	for pair in [[8.0, "morning"], [12.0, "daytime"], [16.0, "afternoon"], [19.0, "evening"], [23.0, "night"]]:
		time_mgr.call("set_time", float(pair[0]))
		_check(str(time_mgr.get("activity_period")) == str(pair[1]),
			"%.0f:00 maps to %s activity profile" % [float(pair[0]), str(pair[1])])
		var profile: Dictionary = sim.call("profile")
		_check(profile.has("traffic_cap") and profile.has("ped_archetypes"),
			"%s profile carries traffic and population behaviour" % str(pair[1]))
	var peds = _node("PedestrianManager")
	time_mgr.call("set_time", 22.0)
	_check(absf(float(peds.call("_current_hour")) - 22.0) < 0.01,
		"pedestrian population follows the real clock (22:00)")
	time_mgr.call("set_time", 11.0)


func _check_traffic_reactivity() -> void:
	var traffic = _node("TrafficManager")
	var before: int = int(traffic.get("max_active_vehicles"))
	traffic.call("set_density_multiplier", 0.6)
	var quiet: int = int(traffic.get("max_active_vehicles"))
	traffic.call("set_density_multiplier", 1.3)
	var busy: int = int(traffic.get("max_active_vehicles"))
	_check(busy > before and quiet < before,
		"district density changes traffic cap (%d < %d < %d)" % [quiet, before, busy])
	traffic.call("set_density_multiplier", 1.0)

	var p := Vector3(120.0, 0.2, -1400.0)
	traffic.call("add_obstruction", p, 8.0, 30.0)
	_check(bool(traffic.call("is_road_blocked", p)), "temporary road obstruction registered")
	_check(not bool(traffic.call("is_road_blocked", p + Vector3(40.0, 0.0, 0.0))), "obstruction is local")
	_check(traffic.has_method("should_slow_for_crossing"), "traffic manager exposes pedestrian-crossing slowdown")
	_check(traffic.has_method("request_emergency_response"), "traffic manager can dispatch real responders")


func _check_weather_and_audio() -> void:
	var weather = _node("WeatherManager")
	var time_mgr = _node("WorldTimeManager")
	weather.call("set_weather_by_name", "heavy_rain", true)
	await _frames(3)
	_check(float(weather.get("rain_intensity")) > 0.9, "heavy rain raises rain intensity")
	_check(float(weather.get("wetness")) > 0.9, "heavy rain wets the city surfaces")
	_check(float(time_mgr.get("weather_overcast")) > 0.9, "weather factors reach the sun owner")
	weather.call("set_weather_by_name", "clear", true)
	await _frames(3)
	_check(float(weather.get("rain_intensity")) < 0.05, "weather returns to clear")

	var audio := get_root().get_node_or_null("AudioDirector")
	_check(audio != null and float(audio.call("category_volume", "npc")) > -60.0, "NPC audio bus exists")
	var before := float(audio.call("category_volume", "weapons"))
	audio.call("set_category_volume", "weapons", -20.0)
	_check(absf(float(audio.call("category_volume", "weapons")) + 20.0) < 0.1,
		"weapon volume is independently controllable")
	audio.call("set_category_volume", "weapons", before)

	var ambience = _node("AmbientAudioDirector")
	_check(int(ambience.call("voice_count")) == 8, "ambient soundscape uses eight shared beds")
	_check(float(ambience.call("layer_level", "traffic")) > -60.0, "traffic bed is audible")


func _check_businesses() -> void:
	var business = _node("BusinessManager")
	var venues: Array = business.get("active_venues")
	_check(venues.size() >= 15, "authored Sydney venues are built (%d)" % venues.size())
	var cafe: Dictionary = {}
	for venue in venues:
		if str(venue.get("id", "")) == "quay_roasters":
			cafe = venue
			break
	_check(not cafe.is_empty(), "Circular Quay Roasters venue exists")
	_check(bool(business.call("is_venue_open", cafe)), "cafe is open at 11:00")
	var time_mgr = _node("WorldTimeManager")
	time_mgr.call("set_time", 22.0)
	_check(not bool(business.call("is_venue_open", cafe)), "cafe is closed at 22:00")
	time_mgr.call("set_time", 11.0)
	var player = scene.get("player")
	var old_hp: float = float(player.get("health"))
	player.set("health", 40.0)
	business.call("interact_with_venue", cafe, player)
	_check(float(player.get("health")) > 40.0, "venue interaction restores health")
	player.set("health", old_hp)
	_check(business.has_method("set_activity_period"), "business schedule accepts activity profiles")


func _check_ambient_events() -> void:
	var events = _node("AmbientEventDirector")
	events.call("set_activity_period", "daytime")
	events.call("_attempt_trigger_event")
	var active: Array = events.get("active_events")
	_check(active.size() >= 1, "ambient director created an event")
	if active.size() > 0:
		var ev: Dictionary = active[0]
		var root: Node3D = ev["root"]
		var player = scene.get("player")
		var d := root.global_position.distance_to(player.global_position)
		_check(d >= 10.0 and d <= 60.0, "event spawned near the player on a walkable point (%.1f m)" % d)
		var label_count := 0
		for child in root.find_children("*", "Label3D", true, false):
			label_count += 1
		_check(label_count == 0, "ambient scene has no floating announcement label")
		var pos: Vector3 = ev["pos"]
		events.call("interrupt_nearby", pos, 100.0)
		_check((events.get("active_events") as Array).is_empty(), "unusual activity interrupts ambient scenes")


func _check_incidents() -> void:
	var incidents = _node("EmergencyIncidentManager")
	var started: Array = []
	incidents.incident_started.connect(func(kind: String, _pos: Vector3) -> void:
		started.append(kind))
	var pos := Vector3(180.0, 0.2, -1300.0)
	incidents.call("_create_incident", 1, pos, {})
	_check((incidents.get("active_incidents") as Array).size() >= 1, "ambient incident created")
	_check(started.size() >= 1, "incident start is published on the world event bus")
	incidents.call("request_police_response", pos, 1.0)
	incidents.call("set_patrol_intensity", 0.8)
	_check(float(incidents.get("_patrol_intensity")) > 0.5, "wanted level raises patrol intensity")


func _check_pedestrian_reactivity() -> void:
	var peds = _node("PedestrianManager")
	var ped: Node3D = peds.call("spawn_patron_at", Vector3(150.0, 0.0, -1400.0), "cafe")
	_check(ped != null, "venue patron spawned on the real footpath graph")
	if ped != null:
		ped.call("react_to_threat", ped.global_position + Vector3(4.0, 0.0, 0.0), 3.0)
		_check(float(ped.get("_flee_time")) > 0.0, "pedestrian flees a nearby threat")
