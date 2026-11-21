class_name BusinessManager
extends Node3D

## Manages Sydney businesses, cafes, pubs, restaurants, takeaways, bus stops,
## outdoor dining, loading bays, and street-level building occupancy.
## Connects venue operating hours to WorldTimeManager, provides interactive entrances
## (buying coffee/food/drinks), and populates ambient seated/dining pedestrians.

signal business_interacted(venue_name: String, action: String)

enum VenueType {
	CAFE,
	RESTAURANT,
	PUB_CLUB,
	CONVENIENCE_TAKEAWAY,
	BUS_STOP,
	LOADING_BAY
}

const VENUE_TYPE_NAMES := [
	"Cafe",
	"Restaurant",
	"Pub / Club",
	"Convenience / Takeaway",
	"Bus Stop",
	"Loading Bay"
]

## Predefined authentic Sydney venues mapped to real coordinates
const AUTHORED_VENUES: Array[Dictionary] = [
	# The Rocks & Circular Quay (Historic & waterfront dining/pubs)
	{
		"id": "fortune_of_war", "name": "Fortune of War Pub · The Rocks",
		"type": VenueType.PUB_CLUB, "pos": Vector3(18.0, 0.2, -1530.0),
		"open": 11.0, "close": 24.0, "district": "the-rocks",
		"desc": "Sydney's oldest pub. Patrons drinking schooners outside.",
		"item": "Pint of Reschs Draught", "heal": 15.0, "rep": 35
	},
	{
		"id": "quay_roasters", "name": "Circular Quay Roasters · Cafe",
		"type": VenueType.CAFE, "pos": Vector3(220.0, 0.2, -1450.0),
		"open": 6.0, "close": 16.5, "district": "circular-quay",
		"desc": "Busy waterfront espresso bar with outdoor umbrellas.",
		"item": "Flat White & Croissant", "heal": 20.0, "rep": 15
	},
	{
		"id": "harbour_kitchen", "name": "Harbour Kitchen Seafood",
		"type": VenueType.RESTAURANT, "pos": Vector3(260.0, 0.2, -1420.0),
		"open": 12.0, "close": 23.0, "district": "circular-quay",
		"desc": "Fresh Sydney rock oysters and fish & chips by the water.",
		"item": "Barramundi & Chips", "heal": 40.0, "rep": 25
	},
	{
		"id": "circular_quay_bus", "name": "Circular Quay Bus Interchange · Stand B",
		"type": VenueType.BUS_STOP, "pos": Vector3(195.0, 0.2, -1390.0),
		"open": 0.0, "close": 24.0, "district": "circular-quay",
		"desc": "Major transit hub with waiting commuters.",
		"item": "Opal Card Tap", "heal": 0.0, "rep": 10
	},

	# George Street / Town Hall / CBD Core (Retail, cafes, transit)
	{
		"id": "single_o_cbd", "name": "Single O Coffee Stand · George St",
		"type": VenueType.CAFE, "pos": Vector3(-110.0, 0.2, 70.0),
		"open": 6.5, "close": 16.0, "district": "town-hall",
		"desc": "Specialty Sydney filter coffee and outdoor bench seats.",
		"item": "Batch Brew Coffee", "heal": 18.0, "rep": 20
	},
	{
		"id": "town_hall_pub", "name": "The Edinburgh Castle Hotel · Pub",
		"type": VenueType.PUB_CLUB, "pos": Vector3(-130.0, 0.2, -40.0),
		"open": 12.0, "close": 24.0, "district": "town-hall",
		"desc": "Classic two-storey heritage pub with craft beers on tap.",
		"item": "Chicken Parmigiana & Schooner", "heal": 45.0, "rep": 30
	},
	{
		"id": "ezy_mart_george", "name": "EZY-Mart 24/7 · Convenience",
		"type": VenueType.CONVENIENCE_TAKEAWAY, "pos": Vector3(-112.0, 0.2, 120.0),
		"open": 0.0, "close": 24.0, "district": "town-hall",
		"desc": "All-night drinks, snacks, meat pies and durries.",
		"item": "Four'N Twenty Meat Pie & Red Bull", "heal": 30.0, "rep": 10
	},
	{
		"id": "qvb_bus_stop", "name": "Queen Victoria Building Bus Stand",
		"type": VenueType.BUS_STOP, "pos": Vector3(-125.0, 0.2, -110.0),
		"open": 0.0, "close": 24.0, "district": "town-hall",
		"desc": "Sheltered stop along the George Street transit corridor.",
		"item": "Check Timetable", "heal": 0.0, "rep": 5
	},

	# Chinatown & Haymarket (Takeaway, dumplings, market life)
	{
		"id": "chinatown_dumplings", "name": "Golden Century Dumpling House",
		"type": VenueType.RESTAURANT, "pos": Vector3(-430.0, 0.2, 670.0),
		"open": 11.5, "close": 24.0, "district": "haymarket",
		"desc": "Steaming dim sum baskets and late-night noodles.",
		"item": "Pork Dumplings & Jasmine Tea", "heal": 35.0, "rep": 25
	},
	{
		"id": "haymarket_kebab", "name": "Ali's King Kebab & Pide",
		"type": VenueType.CONVENIENCE_TAKEAWAY, "pos": Vector3(-410.0, 0.2, 710.0),
		"open": 10.0, "close": 4.0, "district": "haymarket",
		"desc": "Late night halal snack packs and donor kebabs.",
		"item": "Halal Snack Pack (HSP)", "heal": 50.0, "rep": 20
	},

	# Darling Harbour & Cockle Bay (Entertainment, bars, dining)
	{
		"id": "cockle_bay_grill", "name": "Cockle Bay Waterfront Steakhouse",
		"type": VenueType.RESTAURANT, "pos": Vector3(-600.0, 0.2, -380.0),
		"open": 12.0, "close": 23.5, "district": "darling-quarter",
		"desc": "Promenade dining tables overlooking the marina.",
		"item": "Wagyu Sirloin Steak", "heal": 55.0, "rep": 40
	},
	{
		"id": "darling_nightclub", "name": "Home Nightclub · Darling Harbour",
		"type": VenueType.PUB_CLUB, "pos": Vector3(-620.0, 0.2, -320.0),
		"open": 20.0, "close": 4.5, "district": "darling-quarter",
		"desc": "Multi-level dance club with bouncers and queues outside.",
		"item": "Energy Drink & Entry Stamp", "heal": 20.0, "rep": 50
	},

	# Surry Hills & Crown Street (Hipster cafes, terrace pubs)
	{
		"id": "crown_hotel", "name": "The Crown Hotel · Surry Hills",
		"type": VenueType.PUB_CLUB, "pos": Vector3(320.0, 0.2, 1720.0),
		"open": 12.0, "close": 24.0, "district": "surry-hills",
		"desc": "Art deco pub with sidewalk seating under leafy trees.",
		"item": "Craft Pale Ale Pint", "heal": 15.0, "rep": 30
	},
	{
		"id": "surry_cafe", "name": "Paramount Coffee Project · Cafe",
		"type": VenueType.CAFE, "pos": Vector3(340.0, 0.2, 1680.0),
		"open": 7.0, "close": 15.5, "district": "surry-hills",
		"desc": "Sunny terrace tables with sourdough toast and iced lattes.",
		"item": "Avocado Toast & Long Black", "heal": 25.0, "rep": 20
	},

	# Kings Cross (Nightlife, neon, late night takeaway)
	{
		"id": "cross_club", "name": "The World Bar / Kings Cross Hotel",
		"type": VenueType.PUB_CLUB, "pos": Vector3(1500.0, 0.2, 70.0),
		"open": 18.0, "close": 4.5, "district": "kings-cross",
		"desc": "Historic neon illuminated nightlife spot with outdoor crowd.",
		"item": "Teapot Cocktail", "heal": 20.0, "rep": 45
	},
	{
		"id": "cross_pizza", "name": "Cross Slice Pizza By The Slice",
		"type": VenueType.CONVENIENCE_TAKEAWAY, "pos": Vector3(1515.0, 0.2, 50.0),
		"open": 11.0, "close": 4.5, "district": "kings-cross",
		"desc": "Hot pizza slices under glowing neon lights.",
		"item": "Pepperoni Slice & Coke", "heal": 28.0, "rep": 15
	},

	# CBD Back-alley Loading Bay & Deliveries
	{
		"id": "cbd_loading_dock", "name": "Pitt St Commercial Loading Dock",
		"type": VenueType.LOADING_BAY, "pos": Vector3(-50.0, 0.2, -180.0),
		"open": 5.0, "close": 19.0, "district": "cbd-core",
		"desc": "Active delivery zone with parked van, pallets, and crates.",
		"item": "Borrow Hand Trolley", "heal": 0.0, "rep": 10
	}
]

var active_venues: Array[Dictionary] = []
var venue_nodes: Dictionary = {}
var player_ref: Node3D
var current_time_hours: float = 11.0
var activity_period: String = "daytime"
var _seated_npc_nodes: Array[Node3D] = []
var _patrons: Array[Node3D] = []
var _patron_timer: float = 0.0
var _peds_manager: Node = null
var _last_occupancy_hour: float = -99.0


func _ready() -> void:
	add_to_group("business_managers")
	_connect_time_manager()
	_build_all_venues()


func setup(player: Node3D) -> void:
	player_ref = player


func set_activity_period(period: String) -> void:
	activity_period = period


## Open venues feed real pedestrians into the shared population near the
## player, rather than a separate frozen crowd at each storefront.
func _process(delta: float) -> void:
	_patron_timer += delta
	if _patron_timer < 9.0:
		return
	_patron_timer = 0.0
	_update_patrons()


func _update_patrons() -> void:
	var i := _patrons.size() - 1
	while i >= 0:
		if not is_instance_valid(_patrons[i]):
			_patrons.remove_at(i)
		i -= 1
	if _patrons.size() >= 8 or player_ref == null:
		return
	if _peds_manager == null or not is_instance_valid(_peds_manager):
		var managers := get_tree().get_nodes_in_group("pedestrian_managers")
		_peds_manager = managers[0] if not managers.is_empty() else null
	if _peds_manager == null or not _peds_manager.has_method("spawn_patron_at"):
		return
	for venue in active_venues:
		if not is_venue_open(venue):
			continue
		if player_ref.global_position.distance_to(venue["pos"]) > 95.0:
			continue
		if randf() > 0.55:
			continue
		var archetype := "cafe"
		var vtype := int(venue.get("type", VenueType.CAFE))
		if vtype == VenueType.PUB_CLUB:
			archetype = "nightlife" if activity_period in ["evening", "night"] else "hospitality"
		elif vtype == VenueType.RESTAURANT:
			archetype = "hospitality"
		elif vtype == VenueType.BUS_STOP:
			archetype = "commuter"
		var ped: Node3D = _peds_manager.call("spawn_patron_at", venue["pos"], archetype)
		if ped != null:
			_patrons.append(ped)
			break


func _connect_time_manager() -> void:
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm = time_mgrs[0]
		current_time_hours = float(tm.get("current_time_hours"))
		if tm.has_signal("time_changed"):
			tm.time_changed.connect(_on_time_changed)


func _on_time_changed(hours: float, _formatted: String) -> void:
	current_time_hours = hours
	# time_changed fires every frame, but open/closed visibility can only change
	# at a schedule boundary. Re-walking 17 venue trees at 60 Hz was pure waste.
	if absf(hours - _last_occupancy_hour) >= 0.25:
		_last_occupancy_hour = hours
		_update_venue_occupancy()


func is_venue_open(venue: Dictionary) -> bool:
	var open_hr: float = venue["open"]
	var close_hr: float = venue["close"]
	if open_hr == 0.0 and close_hr == 24.0:
		return true
	if open_hr < close_hr:
		return current_time_hours >= open_hr and current_time_hours < close_hr
	else:
		# Crosses midnight (e.g. 16:00 to 03:00)
		return current_time_hours >= open_hr or current_time_hours < close_hr


func _build_all_venues() -> void:
	active_venues.clear()
	for v in AUTHORED_VENUES:
		var node := Node3D.new()
		node.name = "Venue_" + str(v["id"])
		node.position = v["pos"]
		add_child(node)
		
		var v_data: Dictionary = v.duplicate()
		v_data["node"] = node
		
		# Build visual structures based on type
		match int(v["type"]):
			VenueType.CAFE:
				_build_cafe_visuals(node, v_data)
			VenueType.RESTAURANT:
				_build_restaurant_visuals(node, v_data)
			VenueType.PUB_CLUB:
				_build_pub_visuals(node, v_data)
			VenueType.CONVENIENCE_TAKEAWAY:
				_build_takeaway_visuals(node, v_data)
			VenueType.BUS_STOP:
				_build_bus_stop_visuals(node, v_data)
			VenueType.LOADING_BAY:
				_build_loading_bay_visuals(node, v_data)

		active_venues.append(v_data)
		venue_nodes[str(v["id"])] = node

	_update_venue_occupancy()


func _build_cafe_visuals(parent: Node3D, data: Dictionary) -> void:
	# Awning / Canopy
	var awning := Art.box(parent, Vector3(0, 3.2, 0), Vector3(5.0, 0.18, 2.5), Color("2d5a43"))
	awning.rotation.x = -0.1
	# Fascia sign
	Art.box(parent, Vector3(0, 3.6, -1.2), Vector3(4.8, 0.7, 0.15), Color("1b3d2b"))
	var label := Art.label(parent, Vector3(0, 3.6, -1.1), str(data["name"]), 22)
	label.modulate = Color("ffd97d")
	
	# Outdoor dining: 2 cafe tables with chairs and parasols
	for side in [-1.6, 1.6]:
		var table_pos := Vector3(side, 0.0, 0.8)
		# Table pedestal & round top
		Art.cylinder(parent, table_pos + Vector3(0, 0.38, 0), 0.05, 0.76, Color("333333"))
		Art.cylinder(parent, table_pos + Vector3(0, 0.76, 0), 0.55, 0.04, Color("dedede"))
		# Coffee cup on table
		Art.cylinder(parent, table_pos + Vector3(0.12, 0.83, 0.08), 0.04, 0.10, Color("f0f0f0"))
		# Chairs (2 per table)
		for chair_z in [-0.55, 0.55]:
			var chair_pos := table_pos + Vector3(0, 0.0, chair_z)
			Art.box(parent, chair_pos + Vector3(0, 0.44, 0), Vector3(0.42, 0.05, 0.42), Color("6d4c41"))
			Art.box(parent, chair_pos + Vector3(0, 0.72, chair_z * 0.35), Vector3(0.42, 0.5, 0.05), Color("6d4c41"))
			# Seated customer NPC
			_spawn_seated_npc(parent, chair_pos + Vector3(0, 0.46, 0), chair_z < 0)
		# Parasol umbrella
		var umbrella_pole := Art.cylinder(parent, table_pos + Vector3(0, 1.3, 0), 0.03, 2.6, Color("8d6e63"))
		Art.cylinder(parent, table_pos + Vector3(0, 2.4, 0), 1.3, 0.6, Color("2d5a43"), 0.0)

	# A-frame chalkboard menu
	var board := Art.box(parent, Vector3(2.8, 0.55, -0.6), Vector3(0.5, 0.9, 0.6), Color("263238"))
	Art.label(parent, Vector3(2.8, 0.6, -0.3), "FLAT WHITE $4.50\nCOLD BREW $5.50\nCROISSANT $6", 14)


func _build_restaurant_visuals(parent: Node3D, data: Dictionary) -> void:
	# Elegant canopy
	Art.box(parent, Vector3(0, 3.4, -1.0), Vector3(5.5, 0.8, 0.2), Color("1a1a24"))
	var label := Art.label(parent, Vector3(0, 3.4, -0.85), str(data["name"]), 22)
	label.modulate = Color("f0e6d2")
	
	# Outdoor dining terrace tables
	for side in [-1.8, 1.8]:
		var t_pos := Vector3(side, 0.0, 0.9)
		Art.box(parent, t_pos + Vector3(0, 0.75, 0), Vector3(1.1, 0.05, 0.8), Color("f5f5f5")) # Tablecloth
		Art.cylinder(parent, t_pos + Vector3(-0.15, 0.88, 0), 0.035, 0.22, Color("2e7d32")) # Wine bottle
		Art.cylinder(parent, t_pos + Vector3(0.2, 0.84, 0.1), 0.025, 0.14, Color("e0e0e0")) # Glass
		for cz in [-0.55, 0.55]:
			var c_pos := t_pos + Vector3(0, 0.0, cz)
			Art.box(parent, c_pos + Vector3(0, 0.45, 0), Vector3(0.44, 0.05, 0.44), Color("3e2723"))
			_spawn_seated_npc(parent, c_pos + Vector3(0, 0.46, 0), cz < 0)


func _build_pub_visuals(parent: Node3D, data: Dictionary) -> void:
	# Traditional pub frontage
	Art.box(parent, Vector3(0, 3.6, -1.2), Vector3(5.6, 0.9, 0.3), Color("2b1810"))
	var label := Art.label(parent, Vector3(0, 3.6, -1.0), str(data["name"]), 24)
	label.modulate = Color("f1c40f")
	
	# Glowing beer neon sign
	var neon := Art.box(parent, Vector3(0, 2.7, -1.0), Vector3(1.6, 0.45, 0.08), Color("ffaa00"))
	var neon_mat := StandardMaterial3D.new()
	neon_mat.emission_enabled = true
	neon_mat.emission = Color("ffaa00")
	neon_mat.emission_energy_multiplier = 2.5
	neon.material_override = neon_mat
	Art.label(parent, Vector3(0, 2.7, -0.92), "COLD BEER", 16)

	# Beer garden wooden bench tables
	var bench_pos := Vector3(-1.8, 0.0, 0.8)
	Art.box(parent, bench_pos + Vector3(0, 0.74, 0), Vector3(1.5, 0.06, 0.7), Color("5d4037")) # Table
	Art.cylinder(parent, bench_pos + Vector3(0.2, 0.85, 0.1), 0.045, 0.16, Color("e67e22")) # Schooner of beer
	Art.box(parent, bench_pos + Vector3(0, 0.44, -0.55), Vector3(1.5, 0.06, 0.3), Color("4e342e")) # Bench 1
	Art.box(parent, bench_pos + Vector3(0, 0.44, 0.55), Vector3(1.5, 0.06, 0.3), Color("4e342e")) # Bench 2
	_spawn_seated_npc(parent, bench_pos + Vector3(-0.35, 0.44, -0.55), true)
	_spawn_seated_npc(parent, bench_pos + Vector3(0.35, 0.44, 0.55), false)

	# Bouncer NPC standing by door at night
	var bouncer := Art.person(parent, Color("111116"))
	bouncer.name = "BouncerNPC"
	bouncer.position = Vector3(2.0, 0.15, -0.8)
	# Sunglasses / earpiece on bouncer
	Art.box(bouncer, Vector3(0, 1.62, -0.15), Vector3(0.22, 0.06, 0.08), Color("050505"))


func _build_takeaway_visuals(parent: Node3D, data: Dictionary) -> void:
	# Bright illuminated convenience/takeaway fascia
	Art.box(parent, Vector3(0, 3.3, -1.0), Vector3(5.0, 0.8, 0.2), Color("c0392b"))
	var label := Art.label(parent, Vector3(0, 3.3, -0.85), str(data["name"]), 22)
	label.modulate = Color("ffffff")
	
	# Warm interior display counter visible from street
	Art.box(parent, Vector3(0, 0.9, -0.7), Vector3(3.2, 0.9, 0.6), Color("2c3e50"))
	Art.box(parent, Vector3(0, 1.45, -0.7), Vector3(3.0, 0.35, 0.5), Color("f39c12")) # Warmer pie display
	# Litter bin / cigarette bin outside
	Art.cylinder(parent, Vector3(-2.4, 0.45, 0.4), 0.22, 0.9, Color("7f8c8d"))


func _build_bus_stop_visuals(parent: Node3D, data: Dictionary) -> void:
	# Modern Sydney glass transit shelter
	# Rear glass panel
	var glass := Art.box(parent, Vector3(0, 1.4, -0.7), Vector3(3.6, 2.4, 0.06), Color("a0c4d8"))
	var g_mat := StandardMaterial3D.new()
	g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g_mat.albedo_color = Color(0.6, 0.8, 0.9, 0.45)
	g_mat.roughness = 0.1
	glass.material_override = g_mat
	
	# Steel roof canopy
	Art.box(parent, Vector3(0, 2.65, 0.2), Vector3(3.8, 0.12, 1.9), Color("34495e"))
	# Support pillars
	Art.cylinder(parent, Vector3(-1.7, 1.3, -0.7), 0.05, 2.6, Color("2c3e50"))
	Art.cylinder(parent, Vector3(1.7, 1.3, -0.7), 0.05, 2.6, Color("2c3e50"))
	# Wooden bench seat
	Art.box(parent, Vector3(0, 0.48, -0.45), Vector3(2.6, 0.06, 0.38), Color("d35400"))
	# Timetable display totem
	Art.box(parent, Vector3(-1.8, 1.2, 0.1), Vector3(0.35, 2.2, 0.15), Color("2980b9"))
	Art.label(parent, Vector3(-1.8, 1.5, 0.2), "SYDNEY BUSES\n333 · 380 · 392", 14)
	
	# Waiting commuter NPC sitting on bench
	_spawn_seated_npc(parent, Vector3(-0.4, 0.5, -0.45), false)


func _build_loading_bay_visuals(parent: Node3D, data: Dictionary) -> void:
	# Commercial roller door entrance
	Art.box(parent, Vector3(0, 2.2, -1.2), Vector3(4.8, 3.8, 0.1), Color("7f8c8d"))
	# Loading dock bumper
	Art.box(parent, Vector3(0, 0.6, -0.8), Vector3(4.5, 0.8, 0.6), Color("333333"))
	# Stacked wooden freight pallets
	for i in 4:
		Art.box(parent, Vector3(-1.8, 0.07 + i * 0.14, 0.6), Vector3(1.2, 0.12, 1.2), Color("c7a168"))
	# Cardboard freight boxes
	Art.box(parent, Vector3(-1.8, 0.9, 0.6), Vector3(0.8, 0.6, 0.8), Color("bcaaa4"))
	Art.box(parent, Vector3(1.6, 0.45, 0.4), Vector3(0.9, 0.8, 0.9), Color("bcaaa4"))
	Art.box(parent, Vector3(1.6, 1.05, 0.4), Vector3(0.7, 0.5, 0.7), Color("a1887f"))
	# Worker in high-vis vest
	var worker := Art.person(parent, Color("e65100")) # High-vis orange
	worker.position = Vector3(0.5, 0.15, 0.2)
	Art.box(worker, Vector3(0, 1.72, 0), Vector3(0.32, 0.16, 0.32), Color("ffd600")) # Hard hat


func _spawn_seated_npc(parent: Node3D, pos: Vector3, facing_north: bool) -> void:
	var skin_tones := [Color("f1d0b5"), Color("d9a079"), Color("8d5524"), Color("5a3524")]
	var clothes := [Color("2c3e50"), Color("2980b9"), Color("27ae60"), Color("8e44ad"), Color("d35400")]
	var skin: Color = skin_tones[randi() % skin_tones.size()]
	var cloth: Color = clothes[randi() % clothes.size()]

	var npc := Node3D.new()
	npc.name = "SeatedNPC"
	npc.position = pos
	if facing_north:
		npc.rotation.y = PI
	
	# Seated pose geometry: torso upright, thighs forward horizontal, calves down vertical
	# Hips & Torso
	Art.box(npc, Vector3(0, 0.32, 0), Vector3(0.38, 0.45, 0.24), cloth)
	# Head
	Art.box(npc, Vector3(0, 0.72, 0), Vector3(0.24, 0.26, 0.24), skin)
	# Thighs extending horizontally
	Art.box(npc, Vector3(-0.1, 0.08, 0.22), Vector3(0.14, 0.14, 0.38), cloth.darkened(0.15))
	Art.box(npc, Vector3(0.1, 0.08, 0.22), Vector3(0.14, 0.14, 0.38), cloth.darkened(0.15))
	# Lower legs extending vertically down
	Art.box(npc, Vector3(-0.1, -0.22, 0.38), Vector3(0.13, 0.42, 0.13), cloth.darkened(0.2))
	Art.box(npc, Vector3(0.1, -0.22, 0.38), Vector3(0.13, 0.42, 0.13), cloth.darkened(0.2))
	
	parent.add_child(npc)
	_seated_npc_nodes.append(npc)


func _update_venue_occupancy() -> void:
	# Show/hide seated NPCs based on whether venues are currently operating
	for v in active_venues:
		var is_open: bool = is_venue_open(v)
		var v_node: Node3D = v["node"]
		for child: Node in v_node.get_children():
			if child.name == "SeatedNPC":
				(child as Node3D).visible = is_open
			elif child.name == "BouncerNPC":
				# Bouncers only on duty during evening/night
				(child as Node3D).visible = current_time_hours >= 19.0 or current_time_hours < 4.0


func find_nearest_interactive_venue(player_pos: Vector3, max_dist: float = 4.2) -> Dictionary:
	var closest: Dictionary = {}
	var closest_dist := max_dist
	for v in active_venues:
		var v_pos: Vector3 = v["pos"]
		var d := player_pos.distance_to(v_pos)
		if d < closest_dist:
			closest = v
			closest_dist = d
	return closest


func interact_with_venue(venue: Dictionary, player: Node3D) -> void:
	if venue.is_empty() or player == null:
		return
	var v_name: String = venue["name"]
	var is_open: bool = is_venue_open(venue)
	var world = player.get("world")
	
	if not is_open:
		var open_hr: float = venue["open"]
		if world != null:
			world.set("message", "%s · CLOSED (Opens at %02d:00)" % [v_name, int(open_hr)])
		return
	
	var item_name: String = venue["item"]
	var heal_amt: float = float(venue.get("heal", 0.0))
	var rep_amt: int = int(venue.get("rep", 0))
	
	# Apply benefits to player
	if heal_amt > 0.0 and player.has_method("take_damage"):
		var cur_hp: float = float(player.get("health"))
		player.set("health", clampf(cur_hp + heal_amt, 0.0, 100.0))
	if rep_amt > 0:
		var cur_rep: int = int(player.get("bonus_reputation"))
		player.set("bonus_reputation", cur_rep + rep_amt)

	if world != null:
		world.set("message", "%s · %s (+%d HP, +%d REP)" % [v_name, item_name, int(heal_amt), rep_amt])
		if world.has_method("sound"):
			world.call("sound", 480.0, 0.15)
	
	business_interacted.emit(v_name, item_name)
