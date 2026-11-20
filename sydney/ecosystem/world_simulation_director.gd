class_name WorldSimulationDirector
extends Node3D

## Central coordination point for the living Sydney simulation.
##
## Ownership rule: this node does NOT spawn pedestrians, vehicles, wildlife,
## lights or weather. Those systems keep their existing managers and names so
## the canonical scene graph and the regression suites stay stable. The director
## owns three things only:
##   1. reusable activity profiles (what the city does at a given time/district);
##   2. a single world-event bus for player/world reactivity;
##   3. cross-system reactions and distance/district population budgets.
##
## Systems are discovered by their existing scene-tree groups. Every reaction is
## best-effort: a missing or incompatible manager is skipped rather than
## producing a hard dependency.

signal world_event(event_type: String, position: Vector3, severity: float, source: Object)
signal activity_period_changed(period: String)
signal district_changed(district_id: String)

enum WorldEvent {
	GUNFIRE,
	EXPLOSION,
	COLLISION,
	DANGEROUS_DRIVING,
	ROAD_BLOCKED,
	INCIDENT,
	POLICE_RESPONSE,
	AMBIENT_INTERRUPT,
}

const EVENT_NAMES := [
	"gunfire", "explosion", "collision", "dangerous_driving",
	"road_blocked", "incident", "police_response", "ambient_interrupt",
]

## One table drives traffic caps, pedestrian archetypes, venue ambience, event
## selection and audio layers. Managers may still refine by district; this is
## the single authoritative statement of the city's daily rhythm.
const ACTIVITY_PROFILES := {
	"morning": {
		"traffic_cap": 46, "ped_cap": 64, "vehicle_bias": "commuter",
		"ped_archetypes": ["commuter", "office", "cafe", "tourist"],
		"events": ["delivery_unload", "bus_boarding", "friends_greeting", "taxi_dropoff"],
		"emergency_bias": 0.35, "nightlife": 0.05,
		"audio": {"traffic": -23.0, "crowd": -27.0, "birds": -26.0, "nightlife": -45.0, "construction": -31.0},
	},
	"daytime": {
		"traffic_cap": 38, "ped_cap": 72, "vehicle_bias": "mixed",
		"ped_archetypes": ["tourist", "shopper", "office", "walker", "student"],
		"events": ["tourist_photo", "bus_boarding", "friends_greeting", "delivery_unload", "dog_walker"],
		"emergency_bias": 0.5, "nightlife": 0.0,
		"audio": {"traffic": -24.0, "crowd": -25.0, "birds": -29.0, "nightlife": -45.0, "construction": -29.0},
	},
	"afternoon": {
		"traffic_cap": 46, "ped_cap": 78, "vehicle_bias": "commuter",
		"ped_archetypes": ["commuter", "student", "shopper", "office", "family"],
		"events": ["friends_greeting", "bus_boarding", "taxi_dropoff", "delivery_unload"],
		"emergency_bias": 0.55, "nightlife": 0.05,
		"audio": {"traffic": -22.0, "crowd": -25.0, "birds": -31.0, "nightlife": -45.0, "construction": -32.0},
	},
	"evening": {
		"traffic_cap": 34, "ped_cap": 66, "vehicle_bias": "dining",
		"ped_archetypes": ["nightlife", "hospitality", "resident", "young_adult", "commuter"],
		"events": ["nightlife_exit", "friends_greeting", "taxi_dropoff", "bus_boarding"],
		"emergency_bias": 0.8, "nightlife": 0.6,
		"audio": {"traffic": -25.0, "crowd": -23.0, "birds": -45.0, "nightlife": -27.0, "construction": -45.0},
	},
	"night": {
		"traffic_cap": 22, "ped_cap": 48, "vehicle_bias": "nightlife",
		"ped_archetypes": ["nightlife", "homeless", "smoker", "resident", "police"],
		"events": ["nightlife_exit", "taxi_dropoff", "friends_greeting"],
		"emergency_bias": 1.0, "nightlife": 1.0,
		"audio": {"traffic": -28.0, "crowd": -29.0, "birds": -45.0, "nightlife": -24.0, "construction": -45.0},
	},
}

## District multipliers keep the CBD busy and residential streets quiet without
## spawning uniformly across all 5,000+ exported roads.
const DISTRICT_DENSITY := {
	"cbd-core": 1.25, "town-hall": 1.2, "martin-place": 1.2, "wynyard": 1.15,
	"circular-quay": 1.3, "the-rocks": 1.2, "barangaroo": 1.05,
	"darling-quarter": 1.25, "haymarket": 1.2, "kings-cross": 1.3,
	"darlinghurst": 1.0, "surry-hills": 0.9, "potts-point": 0.75,
	"woolloomooloo": 0.8, "central": 1.2,
	"hyde-park": 0.9, "the-domain": 0.8, "botanic-garden": 0.6,
}

const NIGHTLIFE_DISTRICTS := ["kings-cross", "darling-quarter", "haymarket", "the-rocks", "surry-hills"]
const RESIDENTIAL_DISTRICTS := ["potts-point", "woolloomooloo", "darlinghurst"]

var world: Node3D
var player: Node3D
var time_manager: Node
var traffic_manager: Node
var pedestrian_manager: Node
var wildlife_manager: Node
var business_manager: Node
var event_director: Node
var incident_manager: Node
var weather_manager: Node
var lights_manager: Node
var wanted_system: Node
var ambient_audio: Node

var current_district: String = ""
var _tick: float = 0.0
var _police_cooldown: float = 0.0
var _incident_cooldown: float = 0.0
var _last_activity_period: String = ""


func _ready() -> void:
	add_to_group("world_simulation")


## Called after every ecosystem manager has been added and set up. Discovery is
## by group so no node path is changed and existing tests keep working.
func setup(world_ref: Node3D, player_ref: Node3D) -> void:
	world = world_ref
	player = player_ref
	time_manager = _first("time_managers")
	traffic_manager = _first("traffic_managers")
	pedestrian_manager = _first("pedestrian_managers")
	wildlife_manager = _first("wildlife_managers")
	business_manager = _first("business_managers")
	event_director = _first("ambient_event_directors")
	incident_manager = _first("incident_managers")
	weather_manager = _first("weather_managers")
	lights_manager = _first("city_lights")
	wanted_system = _first("wanted_system")
	ambient_audio = _first("ambient_audio")

	_connect(time_manager, "activity_period_changed", _on_activity_period_changed)
	_connect(time_manager, "period_changed", _on_time_period_changed)
	_connect(incident_manager, "incident_started", _on_incident_started)
	_connect(event_director, "ambient_event_occurred", _on_ambient_event)
	_connect(wanted_system, "wanted_changed", _on_wanted_changed)

	_last_activity_period = activity_period()
	_on_activity_period_changed(_last_activity_period)
	_update_district(true)


func _first(group: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null


func _connect(target: Node, signal_name: String, callback: Callable) -> void:
	if target != null and target.has_signal(signal_name) and not target.is_connected(signal_name, callback):
		target.connect(signal_name, callback)


func _process(delta: float) -> void:
	_police_cooldown = maxf(0.0, _police_cooldown - delta)
	_incident_cooldown = maxf(0.0, _incident_cooldown - delta)
	_tick += delta
	if _tick >= 0.5:
		_tick = 0.0
		_update_district(false)


## ------------------------------------------------------------- activity --
func activity_period() -> String:
	if time_manager != null and "activity_period" in time_manager:
		return str(time_manager.get("activity_period"))
	return _period_from_hour(current_hour())


func _period_from_hour(hour: float) -> String:
	if hour >= 6.0 and hour < 11.5:
		return "morning"
	if hour >= 11.5 and hour < 15.0:
		return "daytime"
	if hour >= 15.0 and hour < 17.5:
		return "afternoon"
	if hour >= 17.5 and hour < 21.0:
		return "evening"
	return "night"


func current_hour() -> float:
	if time_manager != null and "current_time_hours" in time_manager:
		return float(time_manager.get("current_time_hours"))
	return 11.0


func profile() -> Dictionary:
	return profile_for(activity_period())


func profile_for(period: String) -> Dictionary:
	var key := period if ACTIVITY_PROFILES.has(period) else "daytime"
	return ACTIVITY_PROFILES[key]


func activity_signal_for_period(period: String) -> String:
	var p := profile_for(period)
	var events: Array = p.get("events", [])
	return str(events[randi() % events.size()]) if not events.is_empty() else "friends_greeting"


func _on_activity_period_changed(period: String) -> void:
	if period == _last_activity_period and not _last_activity_period.is_empty():
		# Still refresh budgets; the district may have changed.
		_apply_profile(period)
		return
	_last_activity_period = period
	_apply_profile(period)
	activity_period_changed.emit(period)


func _on_time_period_changed(_detailed_period: String) -> void:
	_apply_profile(activity_period())


func _apply_profile(period: String) -> void:
	var p := profile_for(period)
	if traffic_manager != null and traffic_manager.has_method("set_density_multiplier"):
		traffic_manager.call("set_density_multiplier", 1.0)
	if pedestrian_manager != null and pedestrian_manager.has_method("set_density_multiplier"):
		pedestrian_manager.call("set_density_multiplier", 1.0)
	if ambient_audio != null and ambient_audio.has_method("apply_activity_profile"):
		ambient_audio.call("apply_activity_profile", p)
	if event_director != null and event_director.has_method("set_activity_period"):
		event_director.call("set_activity_period", period)
	if business_manager != null and business_manager.has_method("set_activity_period"):
		business_manager.call("set_activity_period", period)
	_update_district(true)


## Distance/district budgeting: busy CBD and entertainment districts get more
## actors; quiet residential and park districts get fewer.
func _update_district(force: bool) -> void:
	var district := _district_at_player()
	if district == current_district and not force:
		return
	current_district = district
	district_changed.emit(district)

	var density: float = float(DISTRICT_DENSITY.get(district, 0.85))
	var period := activity_period()
	var nightlife := float(profile_for(period).get("nightlife", 0.0))
	if district in NIGHTLIFE_DISTRICTS and nightlife > 0.4:
		density *= 1.0 + nightlife * 0.3
	elif district in RESIDENTIAL_DISTRICTS and nightlife > 0.4:
		density *= 0.55

	if traffic_manager != null and traffic_manager.has_method("set_density_multiplier"):
		traffic_manager.call("set_density_multiplier", density)
	if pedestrian_manager != null and pedestrian_manager.has_method("set_density_multiplier"):
		pedestrian_manager.call("set_density_multiplier", density)
	if ambient_audio != null and ambient_audio.has_method("set_district"):
		ambient_audio.call("set_district", district)


func _district_at_player() -> String:
	if player == null:
		return ""
	if world != null and world.has_method("district_at"):
		return str(world.call("district_at", player.global_position.x, player.global_position.z))
	return ""


## ---------------------------------------------------------- event bus --
func report_event(event_type: String, position: Vector3, severity: float = 1.0, source: Object = null) -> void:
	var kind := event_type.to_lower()
	world_event.emit(kind, position, severity, source)
	_react(kind, position, severity, source)


func report(event: int, position: Vector3, severity: float = 1.0, source: Object = null) -> void:
	if event >= 0 and event < EVENT_NAMES.size():
		report_event(EVENT_NAMES[event], position, severity, source)


func _react(kind: String, pos: Vector3, severity: float, _source: Object) -> void:
	match kind:
		"gunfire", "explosion":
			_alert_pedestrians(pos, 70.0 * severity)
			_interrupt_events(pos, 60.0)
			_request_police(pos, severity)
		"collision", "road_blocked":
			_add_obstruction(pos, 6.0 + 3.0 * severity, 45.0)
			_alert_pedestrians(pos, 28.0)
			_play_distant_siren(pos, 0.15 * severity)
		"dangerous_driving":
			_alert_pedestrians(pos, 35.0)
			_warn_traffic(pos, 45.0)
		"incident", "police_response":
			_add_obstruction(pos, 5.0, 60.0)
			_play_distant_siren(pos, 0.1)
		"ambient_interrupt":
			_interrupt_events(pos, 50.0)


func _alert_pedestrians(pos: Vector3, radius: float) -> void:
	if pedestrian_manager == null:
		return
	if pedestrian_manager.has_method("alert_nearby"):
		pedestrian_manager.call("alert_nearby", pos, radius)
		return
	for ped in get_tree().get_nodes_in_group("pedestrians"):
		if ped is Node3D and (ped as Node3D).global_position.distance_to(pos) < radius:
			if ped.has_method("react_to_threat"):
				ped.call("react_to_threat", pos)


func _warn_traffic(pos: Vector3, radius: float) -> void:
	if traffic_manager == null or not traffic_manager.has_method("warn_nearby"):
		return
	traffic_manager.call("warn_nearby", pos, radius)


func _add_obstruction(pos: Vector3, radius: float, ttl: float) -> void:
	if traffic_manager != null and traffic_manager.has_method("add_obstruction"):
		traffic_manager.call("add_obstruction", pos, radius, ttl)


func _interrupt_events(pos: Vector3, radius: float) -> void:
	if event_director != null and event_director.has_method("interrupt_nearby"):
		event_director.call("interrupt_nearby", pos, radius)


func _request_police(pos: Vector3, severity: float) -> void:
	if _police_cooldown > 0.0:
		return
	_police_cooldown = 22.0 + 12.0 / maxf(severity, 0.25)
	if incident_manager != null and incident_manager.has_method("request_police_response"):
		incident_manager.call("request_police_response", pos, severity)


func _play_distant_siren(pos: Vector3, scale: float) -> void:
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("play_distant_siren") and scale > 0.01:
		audio.call("play_distant_siren", pos)


func _on_wanted_changed(stars: int) -> void:
	if stars <= 0 or player == null or incident_manager == null:
		return
	if incident_manager.has_method("set_patrol_intensity"):
		incident_manager.call("set_patrol_intensity", clampf(float(stars) / 5.0, 0.0, 1.0))


func _on_incident_started(_type: String, pos: Vector3) -> void:
	report_event("incident", pos, 0.6)
	if _incident_cooldown <= 0.0:
		_incident_cooldown = 12.0
		_play_distant_siren(pos, 0.25)


func _on_ambient_event(_name: String, _district: String) -> void:
	# Ambient events are presentation, not gameplay events; they are reported to
	# the audio director only and never feed back into the incident system.
	pass


## ------------------------------------------------------------- testing --
func set_time(hours: float) -> void:
	if time_manager != null and time_manager.has_method("set_time"):
		time_manager.call("set_time", hours)
	_last_activity_period = ""
	_on_activity_period_changed(activity_period())


func set_weather(name: String) -> void:
	if weather_manager != null and weather_manager.has_method("set_weather_by_name"):
		weather_manager.call("set_weather_by_name", name, true)


func find_pedestrian_point_near(pos: Vector3, min_dist: float, max_dist: float) -> Vector3:
	if pedestrian_manager == null or not ("graph_nodes" in pedestrian_manager):
		return pos
	var graph: Dictionary = pedestrian_manager.get("graph_nodes")
	var best := pos
	var best_score := INF
	for nid in graph:
		var node: Dictionary = graph[nid]
		var point := Vector3(float(node.get("x", 0.0)), 0.15, float(node.get("z", 0.0)))
		var d := point.distance_to(pos)
		if d < min_dist or d > max_dist:
			continue
		# Prefer points nearest the requested distance band, with a small random
		# tiebreak so repeated calls do not always pick the same node.
		var score := absf(d - (min_dist + max_dist) * 0.5) + randf() * 3.0
		if score < best_score:
			best_score = score
			best = point
	return best
