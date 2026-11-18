class_name ArcadeCar
extends CharacterBody3D

@export var vehicle_name: String = "COMET"
@export var paint := Color("ef5b4b")
@export var top_speed: float = 32.0
@export var acceleration: float = 15.0
@export var steering: float = 1.8
@export var max_health: float = 120.0
@export var style: int = 0
var health: float = 120.0
var speed: float = 0.0
var driver: BoomPlayer
var wheels: Array[MeshInstance3D] = []
var home: Vector3
var repair_time: float = 0.0
var impact_cooldown: float = 0.0
var body_art: Node3D
var engine_audio: AudioStreamPlayer3D
var brake_lights: Array[MeshInstance3D] = []

func _ready() -> void:
	home = position
	health = max_health
	floor_snap_length = 0.7
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0,1.3,4.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	body_art = Node3D.new()
	add_child(body_art)
	Art.tapered_box(body_art,Vector3(0,0.75,0),Vector3(2,0.65,4.1),Vector2(1.85,3.85),paint)
	var cabin_height := 1.3 if style == 2 else (0.55 if style == 1 else 0.8)
	var cabin_length := 2.7 if style == 2 else 2.0
	var cabin_z := 0.35 if style != 1 else 0.6
	Art.tapered_box(body_art,Vector3(0,1.05+cabin_height/2,cabin_z),Vector3(1.75,cabin_height,cabin_length),Vector2(1.45,cabin_length-0.65),Color("315c70"))
	Art.box(body_art,Vector3(0,1.08+cabin_height,cabin_z),Vector3(1.5,0.12,cabin_length-0.6),paint.lightened(0.12))
	if style == 2:
		Art.box(body_art,Vector3(0,1.65,1.15),Vector3(1.78,1.25,1.1),paint)
		Art.box(body_art,Vector3(0,1.65,1.72),Vector3(0.04,1.1,0.04),Color("263444"))
		Art.label(body_art,Vector3(0,1.65,1.75),"BOOM\nDELIVERY",15)
	else:
		for stripe_x in [-0.2,0.2]:
			if style == 1:
				Art.box(body_art,Vector3(stripe_x,1.084,-1.1),Vector3(0.16,0.02,1.3),Color("f4e3b1"))
	for side in [-1,1]:
		Art.box(body_art,Vector3(side*0.81,1.05+cabin_height/2,cabin_z),Vector3(0.1,cabin_height,0.1),paint)
		Art.box(body_art,Vector3(side*0.94,1.0,0.3),Vector3(0.06,0.06,0.28),Color("e5e3cf"))
		Art.box(body_art,Vector3(side*1.02,1.2,-0.5),Vector3(0.24,0.16,0.24),paint)
		Art.box(body_art,Vector3(side*0.7,0.85,-2.07),Vector3(0.42,0.23,0.06),Color("fff2b2"))
		brake_lights.append(Art.box(body_art,Vector3(side*0.7,0.85,2.07),Vector3(0.42,0.2,0.06),Color("981f35")))
		for z in [-1.3,1.3]:
			var wheel := Art.cylinder(body_art,Vector3(side*1.02,0.46,z),0.46,0.28,Color("202735"))
			wheel.rotation.z = PI/2
			wheels.append(wheel)
			var hub := Art.cylinder(body_art,Vector3(side*1.18,0.46,z),0.23,0.03,Color("d9e5dc"))
			hub.rotation.z = PI/2
	Art.box(body_art,Vector3(0,0.52,-2.1),Vector3(1.9,0.16,0.15),Color("d5e1dc"))
	if style == 1:
		Art.box(body_art,Vector3(0,1.35,1.8),Vector3(2.2,0.12,0.5),paint)
	if style == 2:
		Art.box(body_art,Vector3(0,2.5,0.3),Vector3(1.65,0.12,2.3),Color("f3d975"))
	if style == 3:
		Art.box(body_art,Vector3(0,2.04,0.3),Vector3(0.75,0.22,0.35),Color("ffe778"))
		Art.label(body_art,Vector3(0,2.04,0.49),"TAXI",10)
	Art.box(body_art,Vector3(0,0.66,2.09),Vector3(0.55,0.17,0.04),Color("f0e4ca"))
	setup_engine_audio()
	add_to_group("vehicles")

func setup_engine_audio() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 4410
	var samples := PackedByteArray()
	samples.resize(8820)
	for i in 4410:
		var phase := float(i)*TAU*55/22050
		var wave := sin(phase)*0.6+sin(phase*2)*0.25+sin(phase*4)*0.15
		samples.encode_s16(i*2,int(wave*12000))
	stream.data = samples
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.stream = stream
	engine_audio.volume_db = -60
	engine_audio.unit_size = 8
	engine_audio.max_distance = 45
	add_child(engine_audio)
	engine_audio.play()

func _process(dt: float) -> void:
	var occupied := driver != null and health > 0
	engine_audio.volume_db = lerpf(engine_audio.volume_db,-21.0 if occupied else -60.0,1-exp(-5*dt))
	engine_audio.pitch_scale = lerpf(engine_audio.pitch_scale,0.8+absf(speed)/top_speed*1.9,1-exp(-5*dt))

func _exit_tree() -> void:
	if is_instance_valid(engine_audio):
		engine_audio.stop()

func _physics_process(dt: float) -> void:
	impact_cooldown = maxf(0,impact_cooldown-dt)
	if repair_time > 0:
		repair_time -= dt
		if repair_time <= 0:
			position = home
			rotation = Vector3.ZERO
			health = max_health
			body_art.visible = true
			collision_layer = 1
			collision_mask = 1
		return
	var throttle := Input.get_axis("back","forward") if driver != null else 0.0
	var turn := Input.get_axis("left","right") if driver != null else 0.0
	var braking := Input.is_action_pressed("jump") and driver != null
	var target_speed := throttle*(top_speed if throttle >= 0 else 11.0)
	if braking:
		speed = move_toward(speed,0,28*dt)
	else:
		var rate := acceleration if throttle != 0 else 5.0
		if throttle*speed < 0:
			rate = 26.0
		speed = move_toward(speed,target_speed,rate*dt)
	for light in brake_lights:
		light.material_override = Art.mat(Color("ff5448") if braking or throttle*speed < 0 else Color("981f35"))
	rotation.y -= turn*steering*clampf(speed/9,-1,1)*dt*(0.65 if absf(speed)>23 else 1.0)
	var forward := -global_basis.z
	var grip := 3.0 if braking else 10.0
	velocity.x = lerpf(velocity.x,forward.x*speed,minf(1,grip*dt))
	velocity.z = lerpf(velocity.z,forward.z*speed,minf(1,grip*dt))
	velocity.y -= 24*dt
	var before := absf(speed)
	var incoming := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		var impact_speed := maxf(0,-incoming.dot(contact.get_normal()))
		if absf(contact.get_normal().y) < 0.5 and impact_speed > 5 and impact_cooldown <= 0:
			var other := contact.get_collider()
			if other.has_method("take_damage"):
				other.take_damage(before*4)
			take_damage(impact_speed*1.3)
			speed *= -0.15
			impact_cooldown = 0.5
	for wheel in wheels:
		wheel.rotate_object_local(Vector3.UP,speed*dt/0.46)
	if position.y < -10:
		take_damage(max_health)

func enter(player: BoomPlayer) -> bool:
	if driver != null or health <= 0:
		return false
	driver = player
	player.vehicle = self
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.world.rig.arm.add_excluded_object(get_rid())
	return true

func exit_vehicle() -> bool:
	if driver == null:
		return false
	if absf(speed) > 3:
		driver.world.message = "Slow down to exit"
		return false
	for offset in [Vector3(2.2,0.2,0),Vector3(-2.2,0.2,0),Vector3(0,0.2,3.3)]:
		var point: Vector3 = global_position+global_basis*offset
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.9
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY,point+Vector3(0,1,0))
		query.exclude = [get_rid(),driver.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			var player := driver
			driver = null
			player.vehicle = null
			player.global_position = point
			player.velocity = Vector3.ZERO
			player.visible = true
			player.collision_layer = 1
			player.collision_mask = 1
			player.world.rig.arm.remove_excluded_object(get_rid())
			return true
	driver.world.message = "Exit blocked · move to an open area"
	return false

func take_damage(amount: float) -> void:
	if health <= 0:
		return
	health = maxf(0,health-amount)
	if health <= 0:
		if driver != null:
			driver.respawn()
		body_art.visible = false
		collision_layer = 0
		collision_mask = 0
		speed = 0
		velocity = Vector3.ZERO
		repair_time = 8.0
