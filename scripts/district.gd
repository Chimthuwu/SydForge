extends Node3D

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
var nearest: ArcadeCar
var cross: Label
var hit_time: float = 0.0
var reload_bar: ProgressBar

func _ready() -> void:
	configure_input()
	build_city()
	player = preload("res://scenes/player.tscn").instantiate()
	add_child(player)
	player.position = player.spawn
	rig = BoomCamera.new()
	rig.target = player
	add_child(rig)
	var resources := ["comet","viper","hauler","taxi"]
	for i in 4:
		var car: ArcadeCar = load("res://scenes/vehicles/%s.tscn" % resources[i]).instantiate()
		car.position = Vector3(-5.5,0.1,11-i*7)
		add_child(car)
		vehicles.append(car)
	enemy = preload("res://scenes/enemy.tscn").instantiate()
	enemy.player = player
	add_child(enemy)
	enemy.position = enemy.home
	build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func configure_input() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"reload":KEY_R,"melee":KEY_F,"reset":KEY_F5}
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
	if event.is_action_pressed("melee"):
		player.melee()
	if event.is_action_pressed("reset"):
		player.respawn()

func interact() -> void:
	if player.vehicle != null:
		player.vehicle.exit_vehicle()
	else:
		find_nearest_vehicle()
		if nearest != null:
			nearest.enter(player)

func find_nearest_vehicle() -> void:
	nearest = null
	var distance := 4.0
	for car in vehicles:
		var d := player.global_position.distance_to(car.global_position)
		if d < distance and car.health > 0:
			nearest = car
			distance = d

func _process(dt: float) -> void:
	find_nearest_vehicle()
	hurt_flash = maxf(0,hurt_flash-dt)
	hit_time = maxf(0,hit_time-dt)
	cross.text = "×" if hit_time > 0 else "+"
	cross.modulate = Color("ffcb52") if hit_time > 0 else Color.WHITE
	cross.visible = player.vehicle == null
	reload_bar.visible = player.reload_time > 0 and player.vehicle == null
	reload_bar.value = (1.0-player.reload_time/1.25)*100
	flash.color.a = hurt_flash*0.8
	hud.text = "HEALTH  %03d     /     REP  %03d\nPISTOL  %02d / ∞   %s" % [player.health,player.kills*100,player.ammo,"RELOADING…" if player.reload_time > 0 else ""]
	if player.vehicle != null:
		var car := player.vehicle
		status.text = "%s   /   %03d KM/H   /   HULL %d%%" % [car.vehicle_name,absf(car.speed)*3.6,car.health/car.max_health*100]
		hint.text = "W S  accelerate / reverse     A D  steer     SPACE  brake     E  exit"
	else:
		status.text = message
		hint.text = "[ E ]  DRIVE %s" % nearest.vehicle_name if nearest != null else "WASD move   SHIFT sprint   SPACE jump   RMB aim   LMB fire   R reload   F melee"
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		hint.text = "MOUSE RELEASED · Click to resume     F5  respawn"

func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var top := ColorRect.new()
	top.color = Color(0.035,0.075,0.12,0.88)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 83
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var title := Label.new()
	title.text = "BOOMTOWN"
	title.position = Vector2(30,12)
	title.add_theme_font_size_override("font_size",32)
	title.add_theme_color_override("font_color",Color("ffcb52"))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "DISTRICT ZERO   /   FREE ROAM"
	sub.position = Vector2(32,51)
	sub.add_theme_font_size_override("font_size",14)
	root.add_child(sub)
	hud = Label.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud.position = Vector2(-365,18)
	hud.add_theme_font_size_override("font_size",19)
	root.add_child(hud)
	var bottom := ColorRect.new()
	bottom.color = Color(0.035,0.075,0.12,0.88)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -88
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -76
	status.offset_bottom = -47
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color",Color("ffcb52"))
	status.add_theme_font_size_override("font_size",20)
	root.add_child(status)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -41
	hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	cross = Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size",28)
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
