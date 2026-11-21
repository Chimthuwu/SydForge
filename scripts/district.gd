extends Node3D

class MiniMap extends Control:
	var player_ref: BoomPlayer
	var camera_rig: BoomCamera
	var roads: Array = []
	var redraw_timer: float = 0.0
	## Per-road world-space bounds, rebuilt only when the road array changes.
	## Drawing used to transform every point of all 5,154 roads (28,589 points)
	## at ~8 Hz; culling to the 340 m map window first makes that a few hundred.
	var _road_bounds: Array[Rect2] = []
	var _road_bounds_count: int = -1
	const MAP_RADIUS_M := 170.0

	func _process(delta: float) -> void:
		redraw_timer += delta
		if redraw_timer >= 0.12:
			redraw_timer = 0.0
			queue_redraw()

	func _ensure_road_bounds() -> void:
		if _road_bounds_count == roads.size():
			return
		_road_bounds.clear()
		_road_bounds.resize(roads.size())
		for road_index in roads.size():
			var road: Dictionary = roads[road_index]
			var points: Array = road.get("points", [])
			var min_point := Vector2(INF, INF)
			var max_point := Vector2(-INF, -INF)
			var found := false
			for point in points:
				if typeof(point) != TYPE_ARRAY or point.size() < 2:
					continue
				var p := Vector2(float(point[0]), float(point[1]))
				min_point = min_point.min(p)
				max_point = max_point.max(p)
				found = true
			_road_bounds[road_index] = Rect2(min_point, max_point - min_point) if found else Rect2()
		_road_bounds_count = roads.size()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x,size.y) * 0.48
		draw_circle(center,radius,Color(0.015,0.025,0.035,0.91))
		draw_arc(center,radius,0.0,TAU,64,Color(0.77,0.84,0.82,0.72),2.0,true)
		if player_ref != null and is_instance_valid(player_ref):
			var player_xz := Vector2(player_ref.global_position.x,player_ref.global_position.z)
			var scale := radius / 170.0
			_ensure_road_bounds()
			# The map shows MAP_RADIUS_M around the player; skip roads whose
			# bounding box cannot reach that window before touching their points.
			var view_extent := MAP_RADIUS_M + 12.0
			var view := Rect2(
				player_xz - Vector2(view_extent, view_extent),
				Vector2.ONE * view_extent * 2.0
			)
			for road_index in roads.size():
				if not _road_bounds[road_index].intersects(view):
					continue
				var road: Dictionary = roads[road_index]
				var points: Array = road.get("points",[])
				var road_kind := str(road.get("highway",""))
				var line_color := Color(0.44,0.55,0.57,0.8)
				var line_width := 1.2
				if road_kind in ["primary","trunk","motorway","primary_link","trunk_link"]:
					line_color = Color("d3a94f")
					line_width = 2.2
				for index in range(points.size()-1):
					var a := _screen_point(points[index],player_xz,center,scale)
					var b := _screen_point(points[index+1],player_xz,center,scale)
					if a.distance_to(center) <= radius - 3.0 and b.distance_to(center) <= radius - 3.0:
						draw_line(a,b,line_color,line_width,true)
			var yaw := camera_rig.yaw if camera_rig != null else 0.0
			var forward := Vector2(-sin(yaw),-cos(yaw))
			var side := Vector2(-forward.y,forward.x)
			var marker := PackedVector2Array([
				center + forward * 10.0,
				center - forward * 6.0 + side * 5.5,
				center - forward * 6.0 - side * 5.5
			])
			draw_colored_polygon(marker,Color("ffe08a"))
			draw_circle(center,2.0,Color.WHITE)

	func _screen_point(point: Variant, player_xz: Vector2, center: Vector2, map_scale: float) -> Vector2:
		if typeof(point) != TYPE_ARRAY or point.size() < 2:
			return center + Vector2.ONE * 100000.0
		var delta := Vector2(float(point[0]),float(point[1])) - player_xz
		return center + delta * map_scale


var player: BoomPlayer
var rig: BoomCamera
var enemy: BoomEnemy
var hud: Label
var status: Label
var hint: Label
var flash: ColorRect
var message: String = "WELCOME TO DISTRICT ZERO · Find a ride. Make some noise."
var hurt_flash: float = 0
var vehicles: Array[ArcadeCar] = []
var nearest: Node3D
var _nearest_timer: float = 0.0
var cross: Label
var hit_time: float = 0.0
var reload_bar: ProgressBar
var health_bar: ProgressBar
var minimap: MiniMap
var wanted_label: Label
var sydney_world: SydneyWorld
var using_sydney: bool = false

func _ready() -> void:
	configure_input()
	build_city()
	player = preload("res://scenes/player.tscn").instantiate()
	add_child(player)
	if using_sydney:
		player.spawn = sydney_world.player_spawn
		message = "SYDNEY · %s" % sydney_world.district_name
	player.position = player.spawn
	rig = BoomCamera.new()
	rig.target = player
	if using_sydney:
		rig.yaw = sydney_world.player_yaw
	add_child(rig)
	var resources := ["comet","viper","hauler","taxi","motorbike"]
	for i in resources.size():
		var car: ArcadeCar = load("res://scenes/vehicles/%s.tscn" % resources[i]).instantiate()
		if using_sydney and i < sydney_world.vehicle_spawns.size():
			car.position = sydney_world.vehicle_spawns[i]
			car.rotation.y = sydney_world.vehicle_yaws[i]
		else:
			car.position = Vector3(-5.5,0.1,11-i*7)
		add_child(car)
		vehicles.append(car)
	enemy = preload("res://scenes/enemy.tscn").instantiate()
	enemy.player = player
	if using_sydney:
		enemy.home = sydney_world.enemy_spawn
	add_child(enemy)
	enemy.position = enemy.home
	build_hud()
	var nos := preload("res://scripts/nos_overlay.gd").new()
	nos.name = "NOSOverlay"
	add_child(nos)
	nos.setup(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func configure_input() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"reload":KEY_R,"flashlight":KEY_F,"reset":KEY_F5,"weapon_pistol":KEY_1,"weapon_shotgun":KEY_2,"weapon_smg":KEY_3,"weapon_next":KEY_Q,"audio_up":KEY_BRACKETRIGHT,"audio_down":KEY_BRACKETLEFT,"horn":KEY_H,"sniff_petrol":KEY_G,"wheelie":KEY_B,"skate_boost":KEY_N,"skate_trick":KEY_T}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action,event)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire",mouse)
	if not InputMap.has_action("skateboard"):
		InputMap.add_action("skateboard")
	var right_alt := InputEventKey.new()
	right_alt.physical_keycode = KEY_ALT
	# Key location constants live in @GlobalScope in Godot 4
	# (`InputEventKey.LOCATION_*` does not exist and fails to parse).
	right_alt.location = KEY_LOCATION_RIGHT
	InputMap.action_add_event("skateboard", right_alt)
	if not InputMap.has_action("aim"):
		InputMap.add_action("aim")
	var aim_mouse := InputEventMouseButton.new()
	aim_mouse.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("aim",aim_mouse)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		interact()
	if event.is_action_pressed("reload"):
		player.reload()
	if event.is_action_pressed("weapon_pistol"):
		player.equip_weapon(BoomPlayer.WEAPON_PISTOL)
	if event.is_action_pressed("weapon_shotgun"):
		player.equip_weapon(BoomPlayer.WEAPON_SHOTGUN)
	if event.is_action_pressed("weapon_smg"):
		player.equip_weapon(BoomPlayer.WEAPON_SMG)
	if event.is_action_pressed("weapon_next"):
		player.cycle_weapon()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.cycle_weapon()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.cycle_weapon(-1)
	if event.is_action_pressed("flashlight"):
		player.toggle_flashlight()
	var audio := get_node_or_null("/root/AudioDirector")
	if event.is_action_pressed("audio_up") and audio != null:
		message = "MASTER %+d dB" % int(audio.adjust_master_volume(2.0))
	if event.is_action_pressed("audio_down") and audio != null:
		message = "MASTER %+d dB" % int(audio.adjust_master_volume(-2.0))
	if event.is_action_pressed("reset"):
		player.respawn()

func interact() -> void:
	if player.in_supermarket != null:
		player.in_supermarket.call("interact", player)
		return
	var market := _nearest_supermarket()
	if market != null:
		market.call("interact", player)
		return
	if player.vehicle != null:
		player.vehicle.call("exit_vehicle")
		return
	# Vehicles keep priority: a cafe can be authored right beside a parked car,
	# and E must never be stolen by a storefront when the player is reaching for
	# a door handle.
	find_nearest_vehicle()
	if nearest != null:
		var wanted := get_node_or_null("WantedSystem")
		if nearest.is_in_group("traffic_vehicles") and wanted != null:
			wanted.add_crime(8.0, "GRAND THEFT AUTO · police alerted")
		nearest.call("enter", player)
		return
	# Lightweight venue entrances (cafes, pubs, takeaways, bus stops). The
	# BusinessManager owns schedules and benefits; E just forwards the intent.
	for manager: Node in get_tree().get_nodes_in_group("business_managers"):
		if not manager.has_method("find_nearest_interactive_venue"):
			continue
		var venue: Dictionary = manager.call("find_nearest_interactive_venue", player.global_position, 4.5)
		if not venue.is_empty():
			manager.call("interact_with_venue", venue, player)
			return


func _nearest_supermarket() -> Node3D:
	var closest: Node3D = null
	var closest_distance := 8.0
	for market: Node3D in get_tree().get_nodes_in_group("supermarket"):
		var distance := player.global_position.distance_to(market.global_position)
		if distance < closest_distance:
			closest = market
			closest_distance = distance
	return closest

func find_nearest_vehicle() -> void:
	nearest = null
	var distance := 7.0
	for car in vehicles:
		var d := player.global_position.distance_to(car.global_position)
		if d < distance and car.health > 0:
			nearest = car
			distance = d
	for traffic: Node3D in get_tree().get_nodes_in_group("traffic_vehicles"):
		if not traffic.has_method("enter") or traffic.get("driver") != null:
			continue
		var d := player.global_position.distance_to(traffic.global_position)
		if d < distance and d < 7.0:
			nearest = traffic
			distance = d

func _set_label_text(label: Label, text: String) -> void:
	# Assigning Label.text every frame re-shapes the label even when nothing
	# changed; the HUD has three of them, so guard the assignment.
	if label != null and label.text != text:
		label.text = text

func _process(dt: float) -> void:
	_nearest_timer += dt
	if _nearest_timer >= 0.1:
		_nearest_timer = 0.0
		find_nearest_vehicle()
	hurt_flash = maxf(0,hurt_flash-dt)
	hit_time = maxf(0,hit_time-dt)
	_set_label_text(cross, "×" if hit_time > 0 else "+")
	cross.modulate = Color("ffcb52") if hit_time > 0 else Color.WHITE
	cross.visible = player.vehicle == null
	var current_reload := player.current_reload_time()
	var reload_duration := player.current_reload_duration()
	reload_bar.visible = current_reload > 0.0 and player.vehicle == null
	reload_bar.value = (1.0-current_reload/reload_duration)*100.0
	flash.color.a = hurt_flash*0.8
	_set_label_text(hud, "HEALTH  %03d     /     REP  %03d\n%s   %s" % [
		player.health,player.kills*100+player.bonus_reputation,
		player.weapon_status_text(),"RELOADING…" if current_reload > 0.0 else ""])
	health_bar.value = clampf(player.health,0.0,100.0)
	health_bar.modulate = Color("e65a54") if player.health < 30 else Color("d5b45e")
	var hint_text := ""
	if player.vehicle != null:
		var car := player.vehicle
		var max_health := maxf(float(car.get("max_health")),1.0)
		_set_label_text(status, "%s   /   %03d KM/H   /   HULL %d%%" % [
			car.get("vehicle_name"),absf(float(car.get("speed")))*3.6,
			float(car.get("health"))/max_health*100])
		hint_text = "W S accelerate/reverse · A D steer · SPACE brake · SHIFT NOS boost · E exit"
	else:
		_set_label_text(status, message)
		if player.in_supermarket != null:
			hint_text = "E near shelf: SHOPLIFT · E at the marked door: LEAVE · G near a pump: HUFF PETROL"
		elif nearest != null:
			var action := "STEAL" if nearest.is_in_group("traffic_vehicles") else "DRIVE"
			hint_text = "[ E ]  %s %s" % [action,nearest.get("vehicle_name")]
		else:
			hint_text = "WASD move · SPACE double jump · SHIFT sprint · F torch · RMB aim · LMB fire · wheel/1-3 weapons · R reload · G sniff petrol · B wheelie (bike) · RIGHT ALT skateboard · N board boost · T trick"
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		hint_text = "MOUSE RELEASED · Click to resume     F5  respawn"
	_set_label_text(hint, hint_text)
	var wanted := get_node_or_null("WantedSystem")
	_set_label_text(wanted_label, wanted.stars_text() if wanted != null else "")

func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var brand_panel := ColorRect.new()
	brand_panel.color = Color(0.012,0.024,0.035,0.86)
	brand_panel.position = Vector2(22,18)
	brand_panel.size = Vector2(260,62)
	brand_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(brand_panel)
	var title := Label.new()
	title.text = "SPLOOGE"
	title.position = Vector2(36,18)
	title.add_theme_font_size_override("font_size",27)
	title.add_theme_color_override("font_color",Color("ffcb52"))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "SYDNEY  /  FREE ROAM" if using_sydney else "DISTRICT ZERO  /  FREE ROAM"
	sub.position = Vector2(38,51)
	sub.add_theme_font_size_override("font_size",12)
	sub.add_theme_color_override("font_color",Color("c2cbd0"))
	root.add_child(sub)
	var stats_panel := ColorRect.new()
	stats_panel.color = Color(0.012,0.024,0.035,0.86)
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stats_panel.offset_left = -318
	stats_panel.offset_right = -22
	stats_panel.offset_top = 18
	stats_panel.offset_bottom = 91
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_panel)
	hud = Label.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left = -300
	hud.offset_right = -34
	hud.offset_top = 24
	hud.offset_bottom = 66
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_theme_font_size_override("font_size",15)
	hud.add_theme_color_override("font_color",Color("f1f1e9"))
	root.add_child(hud)
	health_bar = ProgressBar.new()
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	health_bar.offset_left = -292
	health_bar.offset_right = -34
	health_bar.offset_top = 73
	health_bar.offset_bottom = 81
	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color("d5b45e")
	health_bar.add_theme_stylebox_override("fill",health_fill)
	var health_track := StyleBoxFlat.new()
	health_track.bg_color = Color("30383a")
	health_bar.add_theme_stylebox_override("background",health_track)
	root.add_child(health_bar)
	var bottom := ColorRect.new()
	bottom.color = Color(0.012,0.024,0.035,0.82)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -72
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -64
	status.offset_bottom = -38
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color",Color("ffcb52"))
	status.add_theme_font_size_override("font_size",18)
	root.add_child(status)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -8
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color",Color("d3d9d8"))
	hint.add_theme_font_size_override("font_size",13)
	root.add_child(hint)
	if using_sydney:
		minimap = MiniMap.new()
		minimap.name = "WorldMiniMap"
		minimap.player_ref = player
		minimap.camera_rig = rig
		minimap.roads = sydney_world.data.get("roads",[])
		minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		minimap.offset_left = 22
		minimap.offset_top = -198
		minimap.offset_right = 190
		minimap.offset_bottom = -22
		minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(minimap)
	wanted_label = Label.new()
	wanted_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wanted_label.offset_left = -330
	wanted_label.offset_right = -340
	wanted_label.offset_top = 96
	wanted_label.offset_bottom = 128
	wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wanted_label.add_theme_font_size_override("font_size", 18)
	wanted_label.add_theme_color_override("font_color", Color("ff5a4d"))
	root.add_child(wanted_label)
	cross = Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size",24)
	cross.add_theme_color_override("font_color",Color("f4f2e9"))
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-10,-20)
	root.add_child(cross)
	reload_bar = ProgressBar.new()
	reload_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reload_bar.offset_left = -45
	reload_bar.offset_right = 45
	reload_bar.offset_top = 28
	reload_bar.offset_bottom = 34
	reload_bar.show_percentage = false
	reload_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reload_bar)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1,0.1,0.1,0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

func build_city() -> void:
	build_environment()
	if _sydney_requested():
		var world := SydneyWorld.new()
		if world.load_world():
			sydney_world = world
			using_sydney = true
			add_child(world)
		else:
			push_warning("Sydney world failed to load (%s); using District Zero" % world.load_error)
	if not using_sydney:
		build_district_zero()

func _sydney_requested() -> bool:
	return "--sydney" in OS.get_cmdline_user_args() or OS.get_environment("SPLOOGE_SYDNEY") == "1"

func build_environment() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("4296bf")
	atmosphere.sky_horizon_color = Color("c1e7df")
	atmosphere.ground_horizon_color = Color("c1e7df")
	sky.sky_material = atmosphere
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c1dcf2")
	settings.ambient_light_energy = 0.32
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("ffe1ac")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160
	add_child(sun)

func build_district_zero() -> void:
	Art.box(self,Vector3(0,-0.55,0),Vector3(240,1,240),Color("487665"),true)
	# Three generous 18 m avenues each way, enclosing four walkable blocks.
	for axis in 2:
		for street in [-70,0,70]:
			var pos := Vector3(street,0,0) if axis == 0 else Vector3(0,0.01,street)
			var size := Vector3(18,0.1,218) if axis == 0 else Vector3(218,0.1,18)
			Art.box(self,pos,size,Color("344858"))
			for dash in range(-104,105,7):
				if abs(dash) < 12 or abs(abs(dash)-70) < 12:
					continue
				var mark := Vector3(street,0.07,dash) if axis == 0 else Vector3(dash,0.08,street)
				Art.box(self,mark,Vector3(0.18,0.02,3) if axis == 0 else Vector3(3,0.02,0.18),Color("f5cf69"))
	for x in [-70,0,70]:
		for z in [-70,0,70]:
			for side in [-1,1]:
				for stripe in range(-7,8,2):
					Art.box(self,Vector3(x+stripe,0.08,z+side*11),Vector3(1.1,0.02,3),Color("e8e5cf"))
					Art.box(self,Vector3(x+side*11,0.08,z+stripe),Vector3(3,0.02,1.1),Color("e8e5cf"))
	for bx in [-35,35]:
		for bz in [-35,35]:
			Art.box(self,Vector3(bx,0.1,bz),Vector3(51,0.3,51),Color("c9c3ac"),true)
	# Southwest is a landscaped public park, not another building plot.
	Art.box(self,Vector3(-35,0.28,35),Vector3(43,0.08,43),Color("78a657"))
	Art.box(self,Vector3(-35,0.34,35),Vector3(6,0.08,44),Color("e1c999"))
	Art.box(self,Vector3(-35,0.35,35),Vector3(44,0.08,6),Color("e1c999"))
	Art.cylinder(self,Vector3(-35,0.45,35),7,0.3,Color("edd5a6"))
	Art.cylinder(self,Vector3(-35,0.7,35),4.5,0.45,Color("b4d1ca"))
	Art.cylinder(self,Vector3(-35,0.96,35),3.9,0.08,Color("48bfd0"))
	Art.cylinder(self,Vector3(-35,3.0,35),0.6,4.1,Color("f5c756"))
	Art.cylinder(self,Vector3(-35,5.6,35),1.5,2.1,Color("f5c756"),0)
	for x in [-51,-19]:
		for z in [19,35,51]:
			tree(Vector3(x,0.3,z))
	for z in [24,46]:
		for x in [-40,-30]:
			Art.box(self,Vector3(x,0.85,z),Vector3(3.2,0.22,0.8),Color("985b41"),true)
			Art.box(self,Vector3(x,1.4,z+0.4),Vector3(3.2,0.8,0.16),Color("985b41"))
	building(Vector3(24,0.25,-24),Vector3(20,10,20),Color("f0a044"),"SUNSET DINER",0)
	building(Vector3(47,0.25,-25),Vector3(19,22,23),Color("59a9ab"),"PALM HOTEL",1)
	building(Vector3(35,0.25,-49),Vector3(42,14,17),Color("e78270"),"BOOM BOX RECORDS",2)
	building(Vector3(-25,0.25,-24),Vector3(21,15,20),Color("8c9fc5"),"ARCADE / 24H",2)
	building(Vector3(-49,0.25,-27),Vector3(17,28,25),Color("dfb3a0"),"ZERO LOFTS",1)
	building(Vector3(-35,0.25,-50),Vector3(41,9,16),Color("e6c65e"),"CUSTOMS & AUTO",0)
	building(Vector3(48,0.25,34),Vector3(18,18,41),Color("e89e91"),"CIVIC HALL",1)
	# Rocket monument and generous civic plaza.
	Art.cylinder(self,Vector3(24,0.6,35),7,0.6,Color("eee1b6"))
	Art.cylinder(self,Vector3(24,1.4,35),3.5,1.4,Color("526e80"))
	Art.cylinder(self,Vector3(24,6,35),1.8,8,Color("f9d763"),1.2)
	Art.cylinder(self,Vector3(24,11,35),1.2,2,Color("ec6757"),0)
	for a in 4:
		var fin := Art.box(self,Vector3(24,3,35)+Vector3(2.1,0,0).rotated(Vector3.UP,a*PI/2),Vector3(0.3,3.2,2.2),Color("e85f51"))
		fin.rotation.y = a*PI/2
	Art.label(self,Vector3(24,3.5,39),"DISTRICT\nZERO",65)
	for street in [-70,0,70]:
		for z in range(-94,100,24):
			lamp(Vector3(street+10.2,0.2,z))
			if abs(z)>14:
				tree(Vector3(street-11.5,0.2,z))
	# Perimeter silhouettes, collision boundaries, and a coastal backdrop.
	for i in 12:
		var x := -99+i*18
		building(Vector3(x,0,-96),Vector3(14,12+(i%4)*7,16),Color("7d9caa").lightened((i%3)*0.08),"",i%3)
		building(Vector3(96,0,x),Vector3(16,13+(i%3)*8,14),Color("c6a69b"),"",i%3)
	for side in [-1,1]:
		Art.box(self,Vector3(side*110,1.2,0),Vector3(1,2.5,220),Color("7faaa7"),true)
		Art.box(self,Vector3(0,1.2,side*110),Vector3(220,2.5,1),Color("7faaa7"),true)
	Art.box(self,Vector3(-150,-0.8,0),Vector3(60,0.2,400),Color("419eae"))

func building(pos: Vector3, size: Vector3, color: Color, sign_text: String, style: int) -> void:
	var group := Node3D.new()
	add_child(group)
	group.position = pos
	Art.box(group,Vector3(0,size.y/2,0),size,color,true)
	Art.box(group,Vector3(0,0.5,0),Vector3(size.x+0.4,1,size.z+0.4),Color("e4d8bd"))
	Art.box(group,Vector3(0,size.y+0.1,0),Vector3(size.x+0.8,0.5,size.z+0.8),Color("f0dfba"))
	Art.box(group,Vector3(0,size.y+0.5,0),Vector3(size.x-1,0.6,size.z-1),Color("455e6a"))
	if style == 1:
		Art.box(group,Vector3(size.x*0.2,size.y+2,0),Vector3(size.x*0.45,3,size.z*0.5),color)
		Art.cylinder(group,Vector3(-size.x*0.23,size.y+2.5,0),2,4,Color("936a52"))
		Art.cylinder(group,Vector3(-size.x*0.23,size.y+5,0),2.3,1,Color("405360"),0)
		for level in range(5,int(size.y),6):
			Art.box(group,Vector3(0,level,size.z/2+0.5),Vector3(size.x+0.5,0.25,1.1),Color("f0dfba"))
	elif style == 2:
		for side in [-1,1]:
			Art.cylinder(group,Vector3(side*(size.x/2-0.6),size.y/2,size.z/2),0.7,size.y+1,color.lightened(0.15))
		Art.box(group,Vector3(0,size.y+1,0),Vector3(size.x*0.6,2,size.z*0.85),color)
	else:
		Art.prism(group,Vector3(0,size.y+1.3,0),Vector3(size.x+1,2.6,size.z+1),Color("cf6955"))
	for floor_index in range(2,int(size.y)-1,3):
		for column in range(int(-size.x/2)+2,int(size.x/2)-1,3):
			for side in [-1,1]:
				Art.box(group,Vector3(column,floor_index,side*(size.z/2+0.04)),Vector3(1.5,1.7,0.1),Color("294c65"))
				Art.box(group,Vector3(column,floor_index-0.9,side*(size.z/2+0.14)),Vector3(1.8,0.14,0.3),Color("f3dcad"))
		for column in range(int(-size.z/2)+2,int(size.z/2)-1,4):
			for side in [-1,1]:
				Art.box(group,Vector3(side*(size.x/2+0.04),floor_index,column),Vector3(0.1,1.7,2),Color("315c74"))
	if not sign_text.is_empty():
		Art.box(group,Vector3(0,3.8,size.z/2+0.4),Vector3(size.x*0.9,1.65,0.6),Color("263c51"))
		var sign_label := Art.label(group,Vector3(0,3.8,size.z/2+0.74),sign_text,40)
		sign_label.modulate = Color("ffde86")
		for x in range(int(-size.x/2)+2,int(size.x/2)-1,4):
			Art.box(group,Vector3(x,1.6,size.z/2+0.1),Vector3(2.8,2.6,0.1),Color("49869b"))
		var awning := Art.box(group,Vector3(0,2.8,size.z/2+1),Vector3(size.x+0.5,0.18,2),Color("fff0c9"))
		awning.rotation.x = -0.12
		for stripe in range(int(-size.x/2),int(size.x/2),2):
			var strip := Art.box(group,Vector3(stripe,2.84,size.z/2+1),Vector3(0.7,0.06,2.02),color.darkened(0.12))
			strip.rotation.x = -0.12

func tree(pos: Vector3) -> void:
	Art.cylinder(self,pos+Vector3(0,1.8,0),0.24,3.6,Color("8e6850"))
	Art.sphere(self,pos+Vector3(0,4.6,0),2.1,Color("448969"))
	Art.sphere(self,pos+Vector3(1.1,5.5,0),1.5,Color("70ab66"))
	Art.sphere(self,pos+Vector3(-1.0,5.2,0.7),1.5,Color("5b9e61"))

func lamp(pos: Vector3) -> void:
	Art.cylinder(self,pos+Vector3(0,3,0),0.12,6,Color("304a5b"))
	Art.box(self,pos+Vector3(-0.65,5.9,0),Vector3(1.5,0.15,0.16),Color("304a5b"))
	Art.box(self,pos+Vector3(-1.2,5.8,0),Vector3(0.65,0.2,0.45),Color("fff1bb"))

func tracer(start: Vector3, end: Vector3, color: Color) -> void:
	var distance := start.distance_to(end)
	if distance < 0.01:
		return
	var line := Art.box(self,(start+end)*0.5,Vector3(0.035,0.035,distance),color)
	line.look_at(end)
	var tween := create_tween()
	tween.tween_interval(0.07)
	tween.tween_callback(line.queue_free)

func impact(point: Vector3, color: Color = Color("ffce68"), radius: float = 0.09) -> void:
	var spark := Art.sphere(self,point,radius,color)
	var tween := create_tween()
	tween.tween_property(spark,"scale",Vector3.ONE*0.05,0.12)
	tween.tween_callback(spark.queue_free)

func sound(frequency: float, duration: float) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(int(22050*duration)*2)
	for i in samples.size()/2:
		var envelope := 1.0-float(i)/(samples.size()/2)
		var value := int(sin(i*frequency*TAU/22050)*envelope*6500)
		samples.encode_s16(i*2,value)
	stream.data = samples
	var audio := AudioStreamPlayer.new()
	add_child(audio)
	audio.stream = stream
	audio.finished.connect(audio.queue_free)
	audio.play()

## Weapon reports are owned by AudioDirector: pooled, level-managed and
## compressed. Keeping this entry point means player combat code stays simple.
## Accepts the new string ids and the old boolean shotgun flag.
func gunshot(kind: Variant = "pistol") -> void:
	var weapon := str(kind) if typeof(kind) == TYPE_STRING else ("shotgun" if kind else "pistol")
	var audio := get_node_or_null("/root/AudioDirector")
	if audio == null:
		return
	# One report per shot. The old code created a new player per shot and the
	# 3D duplicate made every round read twice as loud.
	audio.play_weapon(weapon)
	# The living world hears gunfire: pedestrians scatter, ambient scenes break
	# up and, with a cooldown, police attend. No weapon volume change here.
	var sim := get_node_or_null("WorldSimulationDirector")
	if sim != null and sim.has_method("report_event") and player != null:
		sim.call("report_event", "gunfire", player.global_position, 1.0)
