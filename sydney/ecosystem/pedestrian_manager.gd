class_name PedestrianManager
extends Node3D

## Spawns, manages, and culls pedestrians around the player using the Sydney pedestrian graph.
## Manages density based on district (CBD, Circular Quay, Darling Harbour vs suburbs).

@export var max_active_pedestrians: int = 50
@export var spawn_radius: float = 120.0
@export var despawn_radius: float = 160.0

var sydney_world: SydneyWorld
var player_ref: Node3D

# Parsed pedestrian graph: node_id -> { "x": float, "z": float, "neighbors": Array[int] }
var graph_nodes: Dictionary = {}
var node_ids_list: Array[int] = []

var active_pedestrians: Array[PedestrianController] = []
var _update_timer: float = 0.0

func _ready() -> void:
	add_to_group("pedestrian_managers")

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
			var dist := p_pos.distance_to(ped.global_position)
			if dist > despawn_radius:
				active_pedestrians.remove_at(i)
				ped.queue_free()
		else:
			active_pedestrians.remove_at(i)
		i -= 1

func _spawn_pedestrians_near_player() -> void:
	if active_pedestrians.size() >= max_active_pedestrians:
		return
	
	var p_pos := player_ref.global_position
	# Find candidate nodes within spawn ring (e.g. 25m to 120m)
	var candidates: Array[int] = []
	for nid in node_ids_list:
		var n: Dictionary = graph_nodes[nid]
		var dx := float(n["x"]) - p_pos.x
		var dz := float(n["z"]) - p_pos.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq > 25.0 * 25.0 and dist_sq < spawn_radius * spawn_radius:
			if not n["neighbors"].is_empty():
				candidates.append(nid)
				if candidates.size() >= 30: # Limit candidate pool for speed
					break
	
	if candidates.is_empty():
		return
	
	var spawns_to_attempt := mini(4, max_active_pedestrians - active_pedestrians.size())
	for s in spawns_to_attempt:
		var chosen_id := candidates[randi() % candidates.size()]
		var ped := PedestrianController.new()
		add_child(ped)
		ped.setup(chosen_id, graph_nodes)
		active_pedestrians.append(ped)
