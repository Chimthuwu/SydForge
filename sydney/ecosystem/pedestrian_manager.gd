class_name PedestrianManager
extends Node3D

## Spawns, manages, and culls pedestrians around the player using the Sydney pedestrian graph.
## Creates a diverse, district-aware population with lightweight routines and activities.

@export var max_active_pedestrians: int = 70
@export var spawn_radius: float = 130.0
@export var despawn_radius: float = 170.0

var sydney_world: SydneyWorld
var player_ref: Node3D

# Parsed pedestrian graph: node_id -> { "x": float, "z": float, "neighbors": Array[int] }
var graph_nodes: Dictionary = {}
var node_ids_list: Array[int] = []

var active_pedestrians: Array[PedestrianController] = []
var _update_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Diverse skin tones (contemporary Sydney, incl. Aboriginal and Torres Strait Islander)
const SKIN_TONES := [
	Color("f6dfcf"), Color("f1d0b5"), Color("e7be9a"), Color("ddb07e"),
	Color("d9a079"), Color("c68642"), Color("b7774f"), Color("a6653f"),
	Color("8d5524"), Color("7a4a2e"), Color("6b3f2a"), Color("5a3524"), Color("4a2c1f"),
]
const HAIR_TONES := [
	Color("0f0f10"), Color("1b1410"), Color("2a1c12"), Color("4a2c11"),
	Color("6b4a2b"), Color("8b6a4a"), Color("b5814c"), Color("5a5a5a"), Color("2b2b2b"),
]


func _ready() -> void:
	add_to_group("pedestrian_managers")
	_rng.randomize()


func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	_build_graph_lookup()


func _build_graph_lookup() -> void:
	graph_nodes.clear()
	node_ids_list.clear()
	if sydney_world == null or not ("data" in sydney_world):
		return
	var pg: Dictionary = sydney_world.data.get("pedestrianGraph", {})
	var raw_nodes: Array = pg.get("nodes", [])
	var raw_edges: Array = pg.get("edges", [])
	for n in raw_nodes:
		var nid: int = int(n.get("id", -1))
		if nid >= 0:
			graph_nodes[nid] = {
				"x": float(n.get("x", 0.0)),
				"z": float(n.get("z", 0.0)),
				"neighbors": []
			}
			node_ids_list.append(nid)
	for e in raw_edges:
		var from_id: int = int(e.get("from", -1))
		var to_id: int = int(e.get("to", -1))
		if from_id in graph_nodes and to_id in graph_nodes:
			graph_nodes[from_id]["neighbors"].append(to_id)
			graph_nodes[to_id]["neighbors"].append(from_id)


func _process(delta: float) -> void:
	if player_ref == null or graph_nodes.is_empty():
		return
	_update_timer += delta
	if _update_timer >= 1.0:
		_update_timer = 0.0
		_cull_distant_pedestrians()
		_spawn_pedestrians_near_player()


func _cull_distant_pedestrians() -> void:
	var p_pos := player_ref.global_position
	var i := active_pedestrians.size() - 1
	while i >= 0:
		var ped := active_pedestrians[i]
		if is_instance_valid(ped):
			if p_pos.distance_to(ped.global_position) > despawn_radius:
				active_pedestrians.remove_at(i)
				ped.queue_free()
		else:
			active_pedestrians.remove_at(i)
		i -= 1


func _spawn_pedestrians_near_player() -> void:
	if active_pedestrians.size() >= max_active_pedestrians:
		return
	var p_pos := player_ref.global_position
	var candidates: Array[int] = []
	for nid in node_ids_list:
		var n: Dictionary = graph_nodes[nid]
		var dx := float(n["x"]) - p_pos.x
		var dz := float(n["z"]) - p_pos.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq > 25.0 * 25.0 and dist_sq < spawn_radius * spawn_radius:
			if not n["neighbors"].is_empty():
				candidates.append(nid)
				if candidates.size() >= 40:
					break
	if candidates.is_empty():
		return
	var district_id := _district_at(p_pos)
	var hour := _current_hour()
	var spawns_to_attempt := mini(5, max_active_pedestrians - active_pedestrians.size())
	for s in spawns_to_attempt:
		var chosen_id: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var npos: Dictionary = graph_nodes[chosen_id]
		var spawn_pos := Vector3(float(npos["x"]), 0.0, float(npos["z"]))
		var local_district := _district_at(spawn_pos)
		var profile := _make_profile(local_district if not local_district.is_empty() else district_id, hour, spawn_pos)
		var ped := PedestrianController.new()
		add_child(ped)
		ped.setup(chosen_id, graph_nodes)
		ped.configure(profile)
		active_pedestrians.append(ped)


func _current_hour() -> float:
	var wtm := get_tree().get_first_node_in_group("world_time")
	if wtm != null and "current_hour" in wtm:
		return float(wtm.get("current_hour"))
	return 14.0


func _district_at(pos: Vector3) -> String:
	if sydney_world != null and sydney_world.has_method("district_at"):
		return str(sydney_world.call("district_at", pos.x, pos.z))
	return ""


func _is_night(hour: float) -> bool:
	return hour >= 19.5 or hour < 5.5


func _is_evening(hour: float) -> bool:
	return hour >= 17.5 and hour < 19.5


func _make_profile(district_id: String, hour: float, pos: Vector3) -> Dictionary:
	var night := _is_night(hour)
	var evening := _is_evening(hour)
	var pool: Array = _archetype_pool(district_id, hour, night, evening)
	var archetype: String = pool[_rng.randi_range(0, pool.size() - 1)]
	var profile := _base_profile(archetype, district_id, night)
	_apply_activity_defaults(profile, archetype, night, evening)
	return profile


func _archetype_pool(district_id: String, hour: float, night: bool, evening: bool) -> Array:
	var d := district_id
	var pool: Array = ["civilian", "civilian", "commuter", "tourist", "shopper"]
	if d in ["cbd-core", "martin-place", "wynyard", "town-hall"]:
		pool += ["office", "office", "commuter", "commuter", "tourist", "shopper", "police"]
		if night: pool += ["nightlife", "homeless"]
	if d in ["circular-quay", "the-rocks", "barangaroo", "millers-point"]:
		pool += ["tourist", "tourist", "commuter", "hospitality", "police"]
		if evening or night: pool += ["nightlife", "nightlife"]
	if d in ["darling-quarter", "haymarket"]:
		pool += ["tourist", "family", "shopper", "hospitality"]
		if evening or night: pool += ["nightlife", "nightlife"]
	if d in ["kings-cross", "darlinghurst"]:
		pool += ["resident", "nightlife", "young_adult", "street_group", "police"]
		if evening or night:
			pool += ["nightlife", "nightlife", "drunk", "smoker", "street_group"]
		if d == "kings-cross":
			# User-requested strong Kings Cross presence (nightlife/sex work/drug-affected).
			if evening or night:
				pool += ["sex_worker", "sex_worker", "sex_worker", "drug_affected", "drug_affected"]
			else:
				pool += ["sex_worker", "drug_affected", "resident"]
	if d in ["surry-hills", "potts-point", "woolloomooloo"]:
		pool += ["resident", "cafe", "young_adult", "shopper"]
		if evening or night: pool += ["nightlife", "smoker"]
	if d in ["hyde-park", "the-domain", "botanic-garden"]:
		pool += ["walker", "tourist", "office", "resident", "family"]
		if night: pool = ["civilian", "walker", "homeless", "nightlife"]
	if d == "central":
		pool += ["commuter", "commuter", "student", "tourist", "traveller", "police"]
		if night: pool += ["homeless", "nightlife"]
	# Global sprinkling
	if _rng.randf() < 0.08:
		pool.append("homeless")
	if _rng.randf() < 0.06:
		pool.append("street_group")
	return pool


func _base_profile(archetype: String, district_id: String, night: bool) -> Dictionary:
	var skin: Color = SKIN_TONES[_rng.randi_range(0, SKIN_TONES.size() - 1)]
	var hair: Color = HAIR_TONES[_rng.randi_range(0, HAIR_TONES.size() - 1)]
	var height := _rng.randf_range(1.55, 1.95)
	var skirt := _rng.randf() < 0.22
	var bag := _rng.randf() < 0.35
	var outfit := "casual"
	var shirt := Color.from_hsv(_rng.randf(), _rng.randf_range(0.12, 0.7), _rng.randf_range(0.25, 0.95))
	var pants := Color.from_hsv(_rng.randf(), _rng.randf_range(0.04, 0.4), _rng.randf_range(0.12, 0.55))
	var shoe: Color = [Color("141414"), Color("f0ede6"), Color("6b4a2b"), Color("3a3a3a")][_rng.randi_range(0, 3)]
	var walk := _rng.randf_range(1.2, 1.6)

	match archetype:
		"office", "commuter":
			outfit = "office"
			var office_shirts: Array[Color] = [Color("f2f2ef"), Color("dfe7f2"), Color("2f4f6f"), Color("6b7280")]
			var office_pants: Array[Color] = [Color("1f2a38"), Color("2a3442"), Color("3a3a3a")]
			shirt = office_shirts[_rng.randi_range(0, office_shirts.size() - 1)]
			pants = office_pants[_rng.randi_range(0, office_pants.size() - 1)]
			bag = _rng.randf() < 0.55
			walk = _rng.randf_range(1.35, 1.7)
		"tourist", "traveller", "shopper", "family", "walker", "cafe", "resident", "hospitality", "student", "young_adult", "civilian":
			outfit = "casual"
			bag = _rng.randf() < 0.45
			if archetype == "tourist":
				bag = true
		"nightlife", "drunk":
			outfit = "nightlife"
			shirt = Color.from_hsv(_rng.randf(), _rng.randf_range(0.25, 0.85), _rng.randf_range(0.2, 0.9))
			walk = _rng.randf_range(1.0, 1.55)
			if archetype == "drunk":
				walk = _rng.randf_range(0.8, 1.25)
		"street_group":
			outfit = "streetwear"
			var street_shirts: Array[Color] = [Color("e6e1d6"), Color("2c3e50"), Color("7f1d1d"), Color("1f2937"), Color("d97706")]
			var street_pants: Array[Color] = [Color("1f2937"), Color("111827"), Color("374151")]
			shirt = street_shirts[_rng.randi_range(0, street_shirts.size() - 1)]
			pants = street_pants[_rng.randi_range(0, street_pants.size() - 1)]
			height = _rng.randf_range(1.62, 1.9)
		"homeless":
			outfit = "rough"
			shirt = shirt.darkened(_rng.randf_range(0.1, 0.35))
			pants = pants.darkened(_rng.randf_range(0.05, 0.3))
			walk = _rng.randf_range(0.85, 1.25)
			bag = _rng.randf() < 0.7
		"police":
			outfit = "police"
			skirt = false
			bag = false
			walk = _rng.randf_range(1.25, 1.55)
		"smoker":
			outfit = "casual"
		"sex_worker":
			# Nightlife/sex-work presence in Kings Cross: adult, nightlife styling, not caricatured.
			outfit = "nightlife"
			var sw_shirts: Array[Color] = [Color("c0265a"), Color("1f2937"), Color("7c3aed"), Color("b45309"), Color("e5e7eb")]
			var sw_pants: Array[Color] = [Color("111827"), Color("1f2937"), Color("3f3f46")]
			shirt = sw_shirts[_rng.randi_range(0, sw_shirts.size() - 1)]
			pants = sw_pants[_rng.randi_range(0, sw_pants.size() - 1)]
			skirt = _rng.randf() < 0.55
			bag = _rng.randf() < 0.45
			walk = _rng.randf_range(1.0, 1.45)
		"drug_affected":
			# People affected by drugs/substance use: loitering/restless, non-caricatured.
			outfit = "rough"
			shirt = shirt.darkened(_rng.randf_range(0.05, 0.25))
			pants = pants.darkened(_rng.randf_range(0.0, 0.2))
			walk = _rng.randf_range(0.75, 1.35)
			bag = _rng.randf() < 0.5

	return {
		"archetype": archetype,
		"district": district_id,
		"skin": skin,
		"hair": hair,
		"shirt": shirt,
		"pants": pants,
		"shoe": shoe,
		"height": height,
		"skirt": skirt,
		"bag": bag,
		"hat": _rng.randf() < 0.12,
		"outfit": outfit,
		"walk_speed": walk,
	}


func _apply_activity_defaults(profile: Dictionary, archetype: String, night: bool, evening: bool) -> void:
	var act := PedestrianController.Activity.WALK
	var time := _rng.randf_range(3.0, 12.0)
	match archetype:
		"smoker":
			act = PedestrianController.Activity.SMOKE
			time = _rng.randf_range(6.0, 16.0)
		"homeless":
			act = [PedestrianController.Activity.SIT, PedestrianController.Activity.LOITER, PedestrianController.Activity.STAND, PedestrianController.Activity.WALK][_rng.randi_range(0, 3)]
		"police":
			act = [PedestrianController.Activity.WALK, PedestrianController.Activity.WALK, PedestrianController.Activity.STAND][_rng.randi_range(0, 2)]
		"sex_worker":
			act = [PedestrianController.Activity.STAND, PedestrianController.Activity.TALK, PedestrianController.Activity.LOITER, PedestrianController.Activity.SMOKE, PedestrianController.Activity.WALK][_rng.randi_range(0, 4)]
			if not (night or evening):
				act = [PedestrianController.Activity.STAND, PedestrianController.Activity.WALK, PedestrianController.Activity.LOITER][_rng.randi_range(0, 2)]
		"drug_affected":
			act = [PedestrianController.Activity.LOITER, PedestrianController.Activity.STAND, PedestrianController.Activity.WALK, PedestrianController.Activity.SIT][_rng.randi_range(0, 3)]
			profile["walk_speed"] = _rng.randf_range(0.7, 1.3)
		"drunk":
			act = [PedestrianController.Activity.WALK, PedestrianController.Activity.LOITER, PedestrianController.Activity.STAND, PedestrianController.Activity.TALK][_rng.randi_range(0, 3)]
		"commuter", "office":
			act = [PedestrianController.Activity.WALK, PedestrianController.Activity.PHONE, PedestrianController.Activity.WALK][_rng.randi_range(0, 2)]
		"tourist":
			act = [PedestrianController.Activity.WALK, PedestrianController.Activity.PHONE, PedestrianController.Activity.STAND][_rng.randi_range(0, 2)]
		_:
			act = [PedestrianController.Activity.WALK, PedestrianController.Activity.WALK, PedestrianController.Activity.STAND, PedestrianController.Activity.PHONE][_rng.randi_range(0, 3)]
	# Adult-context smoking only for certain archetypes/activities.
	if act == PedestrianController.Activity.SMOKE and archetype in ["family", "student"]:
		act = PedestrianController.Activity.WALK
	profile["activity"] = act
	profile["activity_time"] = time
