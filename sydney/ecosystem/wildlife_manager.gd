class_name WildlifeManager
extends Node3D

const FlyingFoxControllerScript := preload("res://sydney/ecosystem/flying_fox_controller.gd")

## Spawns and manages Sydney Australian White Ibis ("bin chickens"), seagulls, and pigeons.
## Places ibis near parks (Hyde Park, Domain, Botanic Garden), waterfront promenades
## (Circular Quay, Darling Harbour, Barangaroo), and wheelie bins / rubbish bins.

@export var max_active_wildlife: int = 40
@export var spawn_radius: float = 90.0
@export var despawn_radius: float = 130.0

var sydney_world: SydneyWorld
var player_ref: Node3D

var active_wildlife: Array[WildlifeController] = []
var bin_props: Array[Node3D] = []
var park_centers: Array[Vector3] = []
var flying_foxes: Array[Node3D] = []
var is_night: bool = false

var _spawn_timer: float = 0.0

func _ready() -> void:
	add_to_group("wildlife_managers")

func setup(world: SydneyWorld, player: Node3D) -> void:
	sydney_world = world
	player_ref = player
	_index_habitats()
	_spawn_wheelie_bins()
	_connect_world_time()
	_spawn_flying_foxes()

func _connect_world_time() -> void:
	var time_managers := get_tree().get_nodes_in_group("time_managers")
	if time_managers.is_empty():
		return
	var time_manager: Node = time_managers[0]
	is_night = bool(time_manager.get("is_night"))
	if not time_manager.is_connected("night_mode_changed",_on_night_mode_changed):
		time_manager.connect("night_mode_changed",_on_night_mode_changed)
	_set_flying_fox_visibility()

func _spawn_flying_foxes() -> void:
	if not flying_foxes.is_empty() or player_ref == null:
		return
	for index in 8:
		var fox: Node3D = FlyingFoxControllerScript.new()
		add_child(fox)
		fox.call("setup",player_ref,index)
		flying_foxes.append(fox)
	_set_flying_fox_visibility()

func _on_night_mode_changed(night: bool) -> void:
	is_night = night
	_set_flying_fox_visibility()

func _set_flying_fox_visibility() -> void:
	for fox: Node3D in flying_foxes:
		if is_instance_valid(fox):
			fox.visible = is_night

func _index_habitats() -> void:
	park_centers.clear()
	if sydney_world == null or not ("data" in sydney_world):
		return
	
	var raw_parks: Array = sydney_world.data.get("parks", [])
	for p in raw_parks:
		var rings: Array = p.get("rings", [])
		if not rings.is_empty():
			var outer: Array = rings[0]
			var sx := 0.0
			var sz := 0.0
			for pt in outer:
				sx += float(pt[0])
				sz += float(pt[1])
			var count := maxf(1.0, float(outer.size()))
			park_centers.append(Vector3(sx / count, 0.2, sz / count))

func _spawn_wheelie_bins() -> void:
	# Add iconic green/yellow/red lid Aussie wheelie bins in parks and waterfront areas
	# where bin chickens love to congregate
	var bin_locations := [
		# Hyde Park & Circular Quay hotspots
		Vector3(210.0, 0.2, -1745.0), # Circular Quay West
		Vector3(260.0, 0.2, -1730.0), # Circular Quay East
		Vector3(340.0, 0.2, -1690.0), # Quay promenade
		Vector3(120.0, 0.2, -750.0),  # Hyde Park North
		Vector3(150.0, 0.2, -680.0),  # Hyde Park Central
		Vector3(110.0, 0.2, -590.0),  # Hyde Park South
		Vector3(-250.0, 0.2, -1100.0), # Darling Harbour / Barangaroo
		Vector3(-180.0, 0.2, -950.0),  # Darling Harbour promenade
	]
	
	for loc in bin_locations:
		var bin_node := Node3D.new()
		bin_node.position = loc
		add_child(bin_node)
		
		# Wheelie bin body (Dark green plastic)
		Art.box(bin_node, Vector3(0, 0.5, 0), Vector3(0.55, 1.0, 0.55), Color("1b5e20"))
		# Bin lid (Yellow or Red)
		var lid_col := Color("fbc02d") if randf() > 0.5 else Color("d32f2f")
		Art.box(bin_node, Vector3(0, 1.03, 0), Vector3(0.58, 0.08, 0.58), lid_col)
		# Wheels
		Art.cylinder(bin_node, Vector3(-0.25, 0.1, 0.22), 0.1, 0.05, Color("111111"))
		Art.cylinder(bin_node, Vector3(0.25, 0.1, 0.22), 0.1, 0.05, Color("111111"))
		
		bin_props.append(bin_node)

func _process(delta: float) -> void:
	if player_ref == null:
		return
	
	_spawn_timer += delta
	if _spawn_timer >= 1.0:
		_spawn_timer = 0.0
		_cull_distant_wildlife()
		_spawn_wildlife_near_player()

func _cull_distant_wildlife() -> void:
	var p_pos := player_ref.global_position
	var i := active_wildlife.size() - 1
	while i >= 0:
		var w := active_wildlife[i]
		if is_instance_valid(w):
			var dist := p_pos.distance_to(w.global_position)
			if dist > despawn_radius:
				active_wildlife.remove_at(i)
				w.queue_free()
		else:
			active_wildlife.remove_at(i)
		i -= 1

func _spawn_wildlife_near_player() -> void:
	if active_wildlife.size() >= max_active_wildlife:
		return
	
	var p_pos := player_ref.global_position
	
	# Priority 1: Near wheelie bins (bin chickens!)
	for bin in bin_props:
		var dist := p_pos.distance_to(bin.global_position)
		if dist < spawn_radius and dist > 8.0:
			if randf() < 0.4 and active_wildlife.size() < max_active_wildlife:
				var offset := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
				_spawn_one(WildlifeController.WildlifeKind.IBIS, bin.global_position + offset)
	
	# Priority 2: General park / waterfront / open area roaming
	if active_wildlife.size() < max_active_wildlife:
		var angle := randf() * TAU
		var dist := randf_range(15.0, spawn_radius * 0.8)
		var spawn_pos := p_pos + Vector3(cos(angle) * dist, 0.2, sin(angle) * dist)
		
		# Determine kind based on location / probability:
		# Waterfront (Z < -1400) -> Seagulls & Ibis
		# Parks / general -> Ibis & Pigeons
		var kind := WildlifeController.WildlifeKind.IBIS
		var roll := randf()
		if spawn_pos.z < -1400.0:
			kind = WildlifeController.WildlifeKind.SEAGULL if roll < 0.55 else WildlifeController.WildlifeKind.IBIS
		else:
			if roll < 0.50:
				kind = WildlifeController.WildlifeKind.IBIS
			elif roll < 0.80:
				kind = WildlifeController.WildlifeKind.PIGEON
			else:
				kind = WildlifeController.WildlifeKind.SEAGULL
		
		_spawn_one(kind, spawn_pos)

func _spawn_one(kind: int, pos: Vector3) -> void:
	var w := WildlifeController.new()
	add_child(w)
	w.setup(kind, pos, player_ref)
	active_wildlife.append(w)
