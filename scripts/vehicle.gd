class_name ArcadeCar
extends CharacterBody3D

const VehicleCombatScript := preload("res://scripts/vehicle_combat.gd")

## Arcade vehicle overhaul — arcade handling, NOS boost, powerslide drift,
## rollovers and recovery.
##
## Integration contracts (preserved from the pre-overhaul system):
##   * Public API: speed, health, max_health, driver, vehicle_name, paint,
##     home, wheels, body_art, style, enter(), exit_vehicle(), take_damage(),
##     repair_time, collision visibility, group "vehicles", CharacterBody3D
##     drivetrain with move_and_slide(), floor_snap_length = 0.7.
##   * Controls: forward/back/left/right input axes (WASD); jump = handbrake
##     (SPACE — brakes and powerslides); sprint = NOS boost (SHIFT); enter/
##     exit (E) and the camera rig are untouched.
##   * Behaviour gates: integration.gd passes — forward reaches > 10 in 90
##     frames, handbrake from ~16 m/s stops in 90 frames, the car turns right
##     within 15 frames, reverse drives backward, impacts damage health,
##     destroyed cars respawn drivers, District Zero integration passes.

@export var vehicle_name: String = "COMET"
@export var paint := Color("ef5b4b")
@export var top_speed: float = 32.0
@export var acceleration: float = 20.0
@export var steering: float = 2.2
@export var max_health: float = 120.0
@export var style: int = 0
@export var is_motorbike: bool = false

## Arcade tuning — one place, overridden per vehicle scene.
@export var mass: float = 1450.0
@export var front_grip: float = 1.0
@export var rear_grip: float = 0.35
@export var handbrake_rear_grip: float = 0.06
@export var handbrake_decel: float = 40.0
@export var drift_yaw_gain: float = 0.008
@export var sus_pitch_rate: float = 7.0
@export var boost_capacity: float = 8.0
@export var boost_drain_rate: float = 2.0
@export var boost_recharge_rate: float = 1.3
@export var boost_speed_factor: float = 0.35
@export var boost_accel_factor: float = 0.25
@export var crash_lateral_threshold: float = 14.0
@export var roll_max: float = 0.7
@export var unroll_rate: float = 2.2
@export var unroll_natural_rate: float = 1.1

var health: float = 120.0
var speed: float = 0.0
var driver: BoomPlayer
var home: Vector3
var wheels: Array[MeshInstance3D]
var wheel_visuals: Array[MeshInstance3D]
var body_art: Node3D
var engine_audio: AudioStreamPlayer3D
var engine_audio_system: EngineAudio
var engine_rpm: float = 0.0
var boost_audio: AudioStreamPlayer3D
var brake_lights: Array[MeshInstance3D]
var skid_marks: SkidMarks
var effects: VehicleEffects
var combat: RefCounted
var repair_time := 0.0
var boost_amount := 0.0
var boost_on := false
var boost_factor := 0.0
var handbrake := false
var rear_grip_effective: float = 0.35
var lateral_speed := 0.0
var slide_time := 0.0
var roll := 0.0
var airborne := false
var sus_pitch := 0.0
var impact_cooldown := 0.0
var velocity_before := Vector3.ZERO
var _blocked_msg_shown := false
var destroyed: bool = false
## Real dynamic headlights for every enterable car, not just emissive lamp
## meshes. Beams are off by default and switched on by the driver (F), with an
## automatic on at night when entering so a fresh car is immediately usable.
var headlights_on := false
var headlight_spots: Array[SpotLight3D] = []
var headlight_lenses: Array[MeshInstance3D] = []
var _headlight_lens_material: StandardMaterial3D

const SLIDE_MIN := 3.0


func _ready() -> void:
	home = position
	health = max_health
	destroyed = false
	floor_snap_length = 0.7
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0,1.3,4.2)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	body_art = Node3D.new()
	body_art.name = "BodyArt"
	add_child(body_art)
	Art.tapered_box(body_art,Vector3(0,0.75,0),Vector3(2,0.65,4.1),Vector2(1.85,3.85),paint)
	var cabin_height := 1.3 if style == 2 else (0.55 if style == 1 else 0.8)
	var cabin_length := 2.7 if style == 2 else 2.0
	var cabin_z := 0.35 if style != 1 else 0.6
	Art.tapered_box(body_art,Vector3(0,1.05+cabin_height/2,cabin_z),Vector3(1.75,cabin_height,cabin_length),Vector2(1.45,cabin_length-0.65),Color("315c70"))
	Art.box(body_art,Vector3(0,1.08+cabin_height,cabin_z),Vector3(1.5,0.12,cabin_length-0.6),paint.lightened(0.12))
	if style == 2:
		Art.box(body_art,Vector3(0,1.65,1.15),Vector3(2.2,0.12,0.5),paint)
		Art.box(body_art,Vector3(0,1.65,1.72),Vector3(0.04,1.1,0.04),Color("263444"))
		Art.label(body_art,Vector3(0,1.65,1.75),"BOOM\nDELIVERY",15)
		for side in [-1,1]:
			brake_lights.append(Art.box(body_art,Vector3(side*0.7,0.85,2.07),Vector3(0.42,0.2,0.06),Color("981f35")))
			for z in [-1.3,1.3]:
				var wheel := Art.cylinder(body_art,Vector3(side*1.02,0.46,z),0.46,0.28,Color("202735"))
				wheel.rotation.z = PI/2
				wheels.append(wheel)
				wheel_visuals.append(wheel)
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
				wheel_visuals.append(wheel)
				var hub := Art.cylinder(body_art,Vector3(side*1.18,0.46,z),0.23,0.03,Color("d9e5dc"))
				hub.rotation.z = PI/2
				wheel_visuals.append(hub)
		Art.box(body_art,Vector3(0,0.52,-2.1),Vector3(1.9,0.16,0.15),Color("d5e1dc"))
		if style == 1:
			Art.box(body_art,Vector3(0,1.35,1.8),Vector3(2.2,0.12,0.5),paint)
		Art.box(body_art,Vector3(0,0.66,2.09),Vector3(0.55,0.17,0.04),Color("f0e4ca"))
	if is_motorbike:
		for part in body_art.get_children():
			if part is MeshInstance3D:
				(part as MeshInstance3D).visible = false
		_build_bike_visual()
	# Painted metal rather than flat plastic: the Art cache shares one rough
	# material per colour, so duplicate before polishing the car body.
	for part in body_art.get_children():
		var mesh_part := part as MeshInstance3D
		if mesh_part != null and mesh_part.material_override is StandardMaterial3D:
			var paint_material: StandardMaterial3D = mesh_part.material_override.duplicate()
			paint_material.metallic = maxf(paint_material.metallic, 0.38)
			paint_material.roughness = minf(paint_material.roughness, 0.42)
			mesh_part.material_override = paint_material
	# Keep the running gear attached to the chassis, not the pitching body
	# presentation. Otherwise a 0.3 rad nose-up body animation visibly lifts the
	# front axle off the road during acceleration.
	for wheel_visual: MeshInstance3D in wheel_visuals:
		wheel_visual.reparent(self, true)
	skid_marks = SkidMarks.new(self)
	effects = VehicleEffects.new(self)
	combat = VehicleCombatScript.new(self)
	setup_engine_audio()
	setup_boost_audio()
	add_to_group("vehicles")
	_build_headlights()


func _build_headlights() -> void:
	_headlight_lens_material = StandardMaterial3D.new()
	_headlight_lens_material.albedo_color = Color("fff2b2")
	_headlight_lens_material.emission_enabled = true
	_headlight_lens_material.emission = Color("fff1c8")
	_headlight_lens_material.emission_energy_multiplier = 0.0
	var offsets: Array[float] = []
	if is_motorbike:
		offsets.append(0.0)
	else:
		offsets.append(-0.62)
		offsets.append(0.62)
	for x: float in offsets:
		var spot := SpotLight3D.new()
		spot.name = "HeadlightBeam" if absf(x) < 0.01 else ("HeadlightBeamL" if x < 0.0 else "HeadlightBeamR")
		spot.position = Vector3(x, 0.82, -2.02)
		spot.light_color = Color("fff1cf")
		spot.light_energy = 4.2
		spot.spot_range = 38.0
		spot.spot_angle = 31.0
		spot.spot_attenuation = 1.1
		# Headlights are a gameplay readability aid, never a second shadow
		# pass; five parked cars would otherwise add ten shadow casters.
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		headlight_spots.append(spot)
		var lens := Art.box(self, Vector3(x, 0.85, -2.13), Vector3(0.34, 0.16, 0.05), Color("fff2b2"))
		lens.material_override = _headlight_lens_material
		lens.name = "HeadlightLens"
		headlight_lenses.append(lens)
	_apply_headlights()


func _apply_headlights() -> void:
	for spot: SpotLight3D in headlight_spots:
		spot.visible = headlights_on
	if _headlight_lens_material != null:
		_headlight_lens_material.emission_energy_multiplier = 2.8 if headlights_on else 0.0


func toggle_headlights() -> void:
	set_headlights(not headlights_on)


func set_headlights(on: bool) -> void:
	headlights_on = on
	_apply_headlights()


func is_headlights_on() -> bool:
	return headlights_on


## Night is owned by the district's WorldTimeManager. Reading it through the
## player's world avoids a second clock and keeps the auto-on rule in one place.
func _is_night() -> bool:
	if driver == null or driver.world == null:
		return false
	var clock: Node = driver.world.get_node_or_null("WorldTimeManager")
	return clock != null and bool(clock.get("is_night"))


var rider: Node3D
var front_wheel_visual: MeshInstance3D
var wheelie := 0.0
var wheelie_active := false


func _build_bike_visual() -> void:
	# Single-track silhouette: narrow chassis, exposed engine, two wheels,
	# handlebars and a seat. Wheels are stored separately for wheelie pose.
	Art.box(body_art, Vector3(0, 0.62, 0), Vector3(0.42, 0.34, 1.85), paint)
	Art.box(body_art, Vector3(0, 0.74, -0.15), Vector3(0.5, 0.18, 0.85), Color("2b3138"))
	Art.box(body_art, Vector3(0, 0.92, -0.9), Vector3(0.62, 0.12, 0.28), Color("20262b"))
	Art.box(body_art, Vector3(0, 0.62, -1.0), Vector3(0.5, 0.5, 0.2), Color("1c2126"))
	for side in [-1, 1]:
		Art.box(body_art, Vector3(side * 0.34, 0.92, -0.9), Vector3(0.06, 0.06, 0.5), Color("30383d"))
		var wheel := Art.cylinder(body_art, Vector3(0, 0.42, side * 1.0), 0.42, 0.16, Color("171a1d"))
		wheel.rotation.z = PI / 2
		wheel_visuals.append(wheel)
		wheels.append(wheel)
		if side < 0:
			front_wheel_visual = wheel
	brake_lights.append(Art.box(body_art, Vector3(0, 0.72, 1.0), Vector3(0.22, 0.12, 0.06), Color("c11f26")))


func _build_rider() -> void:
	if rider != null and is_instance_valid(rider):
		return
	rider = Node3D.new()
	rider.name = "Rider"
	body_art.add_child(rider)
	# Seated, leaning-forward human pose with articulated arms and bent legs.
	var skin := Color("c68642")
	var jacket := Color("1f2c3a")
	var pants := Color("2a2e37")
	Art.box(rider, Vector3(0, 1.22, 0.05), Vector3(0.44, 0.5, 0.3), jacket)
	Art.box(rider, Vector3(0, 1.48, -0.28), Vector3(0.24, 0.12, 0.3), skin)
	Art.box(rider, Vector3(0, 1.62, -0.3), Vector3(0.25, 0.26, 0.25), skin)
	Art.box(rider, Vector3(0, 1.75, -0.3), Vector3(0.27, 0.1, 0.27), Color("121417"))
	for side in [-1, 1]:
		var arm := Art.box(rider, Vector3(side * 0.24, 1.22, -0.46), Vector3(0.11, 0.11, 0.55), jacket)
		arm.rotation.x = -0.45
		Art.box(rider, Vector3(side * 0.28, 1.02, -0.7), Vector3(0.09, 0.1, 0.12), skin)
		var thigh := Art.box(rider, Vector3(side * 0.26, 0.92, 0.12), Vector3(0.16, 0.16, 0.5), pants)
		thigh.rotation.x = 0.35
		var shin := Art.box(rider, Vector3(side * 0.28, 0.68, 0.38), Vector3(0.13, 0.36, 0.13), pants)
		shin.rotation.x = -0.2
		Art.box(rider, Vector3(side * 0.3, 0.5, 0.4), Vector3(0.14, 0.1, 0.25), Color("111418"))


func setup_engine_audio() -> void:
	# The engine is a reusable, state-driven system with per-class profiles and
	# separate tyre/road layers (scripts/engine_audio.gd).
	var system := EngineAudio.new()
	system.name = "EngineAudioSystem"
	system.profile_id = _engine_profile()
	add_child(system)
	engine_audio_system = system


func _engine_profile() -> String:
	var upper := vehicle_name.to_upper()
	if style == 1 or upper.contains("VIPER"):
		return "sports"
	if style == 2 or upper.contains("HAULER") or upper.contains("DELIVERY"):
		return "ute"
	return "car"


func setup_boost_audio() -> void:
	## Procedural NOS burst: rising chirp plus broadband noise, so boost has
	## audible feedback even though the project ships no audio assets.
	var n := 11025
	var samples := PackedByteArray()
	samples.resize(n*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100003
	for i in n:
		var t := float(i)/44100.0
		var pos := maxf(t-0.02, 0.0)
		var freq := 380.0+pos*520.0
		var envelope := (1.0 if pos < 0.5 else (2.2-pos)*1.4)*clampf(pos*3.0,0.0,1.0)
		var wave := sin(TAU*freq*pos*1.2)+sin(TAU*freq*pos*2.9)*0.4
		for j in 4:
			wave += rng.randf()*2.2-1.1
		samples.encode_s16(i*2, int(clampf(wave*envelope*9000.0,-32000,32000)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.data = samples
	boost_audio = AudioStreamPlayer3D.new()
	boost_audio.stream = stream
	boost_audio.bus = "Vehicles"
	boost_audio.volume_db = -80
	boost_audio.unit_size = 8
	boost_audio.max_distance = 30
	add_child(boost_audio)


func _process(dt: float) -> void:
	if destroyed:
		effects.update(dt, self)
		if combat != null:
			combat.update(dt)
		return
	var occupied := driver != null and health > 0
	var throttle := maxf(0.0, Input.get_axis("back","forward")) if occupied else 0.0
	engine_rpm = EngineAudio.gear_rpm(speed, top_speed)
	if is_motorbike and wheelie_active:
		engine_rpm = minf(1.0, engine_rpm + 0.18)
	if engine_audio_system != null:
		engine_audio_system.set_audible(occupied)
		engine_audio_system.update_audio(dt, speed, engine_rpm, throttle, absf(lateral_speed), airborne)
	if boost_on:
		boost_audio.volume_db = lerpf(boost_audio.volume_db, -24.0, 1-exp(-7*dt))
		boost_audio.pitch_scale = lerpf(boost_audio.pitch_scale, 1.3, 0.35*dt)
		if not boost_audio.is_playing():
			boost_audio.play()
	else:
		boost_audio.volume_db = lerpf(boost_audio.volume_db, -70.0, 1-exp(-6*dt))
		boost_audio.pitch_scale = lerpf(boost_audio.pitch_scale, 0.95, 0.35*dt)
		if boost_audio.is_playing() and boost_factor < 0.08:
			boost_audio.stop()
	effects.update(dt, self)
	if combat != null:
		combat.update(dt)
	if is_motorbike:
		_update_wheelie(dt)


func _update_wheelie(dt: float) -> void:
	var wants := driver != null and Input.is_action_pressed("wheelie") \
		and speed > 9.0 and absf(roll) < 0.35 and not destroyed
	if wants:
		wheelie = move_toward(wheelie, 1.0, dt * 1.6)
	else:
		wheelie = move_toward(wheelie, 0.0, dt * 2.4)
	wheelie_active = wheelie > 0.15
	if rider != null and is_instance_valid(rider):
		# Leaning back with the bike during a wheelie.
		rider.rotation.x = -wheelie * 0.22
	if front_wheel_visual != null and is_instance_valid(front_wheel_visual):
		front_wheel_visual.position.y = 0.42 + wheelie * 0.45
	# Handled after suspension in _apply_suspension to avoid being overwritten.


func _exit_tree() -> void:
	if is_instance_valid(engine_audio):
		engine_audio.stop()
	if is_instance_valid(boost_audio):
		boost_audio.stop()


## ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if destroyed and repair_time <= 0.0:
		return
	impact_cooldown = maxf(0,impact_cooldown-dt)
	if repair_time > 0:
		repair_time -= dt
		if repair_time <= 0:
			repair_now()
			return
	_input_and_boost_state(dt)
	if driver != null and Input.is_action_just_pressed("horn") and engine_audio_system != null:
		engine_audio_system.honk()
	_speed_control(dt)
	_steering(dt)
	_suspension(dt)
	_grip_and_drift(dt)
	_motion(dt)


## ---- input interpretation ----
func _input_and_boost_state(dt: float) -> void:
	handbrake = Input.is_action_pressed("jump") and driver != null
	boost_on = Input.is_action_pressed("sprint") and driver != null and not handbrake \
		and boost_amount > 0.0001
	if handbrake:
		boost_factor = move_toward(boost_factor, 0.0, 10.0*dt)
	else:
		boost_factor = move_toward(boost_factor,
			clampf(boost_amount/boost_capacity, 0.0, 1.0) if boost_on else 0.0, 2.0*dt)
		if boost_on:
			boost_amount = maxf(0.0, boost_amount - boost_drain_rate*dt)
		else:
			boost_amount = minf(boost_amount + boost_recharge_rate*dt, boost_capacity)


func _speed_control(dt: float) -> void:
	var axis := Input.get_axis("back","forward") if driver != null else 0.0
	var top := top_speed
	if boost_on:
		top += top_speed*boost_speed_factor*clampf(boost_factor, 0.05, 1.0)
	var target := 0.0
	if axis > 0.0:
		target = top*axis
	elif axis < 0.0:
		target = -11.0
	if handbrake:
		## SPACE is the handbrake — it decelerates the car strongly so a
		## straight stop is quick (the integration suites expect a full stop
		## within 90 frames). When the player is not steering into the slide
		## we scrub the forward velocity coast so the car doesn't sail backward
		## into geometry; when steering into the slide, the slide is the point
		## and the lateral momentum is preserved.
		speed = move_toward(speed, 0.0, handbrake_decel*dt)
		var turn_in := Input.get_axis("left","right") if driver != null else 0.0
		var coast_scrub := 0.9 if absf(turn_in) <= 0.2 else 0.0
		var fwd_v := velocity.dot(_forward())
		if coast_scrub != 0.0 and fwd_v != 0.0:
			velocity -= _forward()*clampf(fwd_v,-handbrake_decel*dt*coast_scrub,handbrake_decel*dt*coast_scrub)
	elif absf(axis) > 0.0:
		var rate := acceleration
		if boost_on:
			rate = rate*(1.0+boost_accel_factor*boost_factor)
		speed = move_toward(speed, target, rate*dt)
	else:
		## Coasting: decay toward zero without a constant brake push.
		speed = move_toward(speed, 0.0, 5.0*dt)


func _steering(dt: float) -> void:
	var speed_a := speed
	var turn_input := Input.get_axis("left","right") if driver != null else 0.0
	var turn_rate := 0.0
	if handbrake:
		## During the handbrake the player steers through the slide.
		turn_rate = turn_input*steering*0.7*clampf(absf(speed_a)/15.0,0.0,1.0)
	elif not tipping_now():
		turn_rate = -turn_input*steering*clampf(absf(speed_a)/10.0,0.0,1.6)
	rotation.y = lerpf(rotation.y, rotation.y+turn_rate*dt, 1.0)
	## Suspension bank: the car leans into turns while moving.
	var bank := clampf(turn_input*0.35*clampf(speed_a/12.0,-1.0,1.0),-0.55,0.55)
	rotation.z = lerpf(rotation.z, bank, 2.5*dt)
	effects.play_brake_flash(braking(), dt)


func tipping_now() -> bool:
	return absf(roll) > 0.4 or absf(rotation.z) > 0.6 or airborne


func braking() -> bool:
	return handbrake or Input.is_action_pressed("back") and speed != 0.0


func _suspension(dt: float) -> void:
	## Visual weight transfer: the body pitches as acceleration/braking load
	## shifts.
	var axis := Input.get_axis("back","forward") if driver != null else 0.0
	var sus_target := 0.0
	if handbrake:
		sus_target = 0.04
	elif axis < 0.0:
		sus_target = -0.08
	elif axis > 0.0:
		sus_target = 0.08
	elif speed < -0.01:
		sus_target = -0.04
	sus_pitch = lerpf(sus_pitch, sus_target, 1.0-exp(-sus_pitch_rate*dt))
	sus_pitch = clampf(sus_pitch, -0.12, 0.12)
	body_art.rotation.x = sus_pitch - wheelie * 0.5


func _grip_and_drift(dt: float) -> void:
	var fwd := _forward()
	var right := _right()
	var lat := velocity.dot(right)
	lateral_speed = lat
	var speed_abs := absf(speed)

	var front_eff := minf(front_grip - clampf(speed_abs/22.0,0.0,0.5), 1.0)
	if handbrake:
		## In a handbrake drift the front gives up almost entirely so the car
		## slides forward while preserving momentum.
		front_eff = minf(front_eff, 0.05+speed_abs*0.005)
	rear_grip_effective = handbrake_rear_grip if handbrake else rear_grip
	## Front pull restores alignment; rear slip adds lateral push.
	if absf(lat) > 1.0 and speed_abs > 2.0:
		velocity -= fwd*clampf(lat,-6.0,6.0)*front_eff*2.2*dt
		velocity -= right*clampf(lat,-6.0,6.0)*rear_grip_effective*2.6*dt
	## During handbrake the car is steered by the user through _steering and
	## keeps lateral momentum; nothing forces lateral back to zero here so a
	## slide can be held.


func _forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func _right() -> Vector3:
	return Vector3(cos(rotation.y), 0.0, -sin(rotation.y))


## ---- physical motion ----
func _motion(dt: float) -> void:
	velocity_before = velocity
	var incoming := velocity
	velocity.y -= 24*dt
	move_and_slide()
	## Drive alignment: pull the velocity toward the car's forward at the
	## grip rate — the car's engine pull. Zero during handbrake so the slide
	## keeps its momentum; the scalar target comes from _speed_control.
	var forward := _forward()
	var grip := 0.0 if handbrake else 10.0
	velocity.x = lerpf(velocity.x, forward.x*speed, minf(1.0, grip*dt))
	velocity.z = lerpf(velocity.z, forward.z*speed, minf(1.0, grip*dt))
	lateral_speed = velocity.dot(_right())
	slide_time += dt if absf(lateral_speed) > SLIDE_MIN*0.7 else 0.0
	for wheel in wheels:
		wheel.rotate_object_local(Vector3.UP,speed*dt/0.46)
	if not is_on_floor():
		airborne = true
		velocity.y = maxf(velocity.y, -35.0)
		if position.y < -10:
			take_damage(max_health)
	else:
		airborne = false
	skid_marks.update(dt, self)
	_rollover_and_recovery_collisions(incoming, dt)


## ---- rollover & recovery ----
func _rollover_and_recovery_collisions(incoming: Vector3, dt: float) -> void:
	var contact_details: Array[Dictionary] = []
	for i in get_slide_collision_count():
		var contact := get_slide_collision(i)
		contact_details.append({
			"collider": contact.get_collider(),
			"normal": contact.get_normal(),
			"impact": maxf(0.0,-incoming.dot(contact.get_normal())),
		})
	_drag_tips(dt)
	_auto_unroll(dt)
	_apply_crash_tips(contact_details)
	_exit_blocked_hint()
	if absf(roll) > roll_max*2.2 and health > 0:
		health = maxf(0.0, health-3.0)


## `roll` is the flip angle on rotation.x (upside down past ±roll_max).
## Sideways instability lives on rotation.z (lane tips, wall catches);
## recovery returns both axes toward upright.
func _drag_tips(dt: float) -> void:
	if absf(roll) > 0.01:
		var rate := unroll_natural_rate if not handbrake else unroll_rate
		if not handbrake and absf(roll) > PI/2:
			rate = 2.8
		if absf(speed) > 6.0:
			rate = minf(rate, 0.8)   # a moving car recovers tips slower
		roll = move_toward(roll, 0.0, rate*dt)
	else:
		roll = 0.0
	if absf(rotation.z) > 0.02:
		rotation.z = move_toward(rotation.z, 0.0,
			(unroll_rate if handbrake else unroll_natural_rate)*dt)


func _auto_unroll(dt: float) -> void:
	## A driver-less car whose flip is fully upside down pops back up after
	## auto_unroll_delay so a crash never strands the vehicle permanently.
	if driver != null:
		return
	if absf(roll) > roll_max*1.35 and speed == 0.0:
		roll = move_toward(roll, 0.0, 2.5*dt)


func _apply_crash_tips(contact_details: Array[Dictionary]) -> void:
	for info in contact_details:
		var normal: Vector3 = info["normal"]
		var impact: float = info["impact"]
		var other: Object = info["collider"]
		if other is Node and other.is_in_group("wildlife"):
			if other.has_method("hit_by_vehicle"):
				other.call("hit_by_vehicle",absf(speed),self)
			continue
		if other is Node and other.is_in_group("pedestrians"):
			if other.has_method("hit_by_vehicle"):
				other.call("hit_by_vehicle",absf(speed),self)
			continue
		if absf(normal.y) < 0.5 and impact > 5 and impact_cooldown <= 0:
			if other != null and other.has_method("take_damage"):
				other.take_damage(speed*4.0)
			take_damage(impact*1.3)
			_tip_from_impact(velocity_before, impact)
			if engine_audio_system != null:
				engine_audio_system.impact(impact)
			## The speed reversal models a bounce-back from a crash, but not
			## while the handbrake is held — the handbrake's own decay takes
			## the car to rest and negative speed breaks the stop contract.
			if not handbrake:
				speed = speed*-0.15
			impact_cooldown = 0.5


func _tip_from_impact(incoming: Vector3, impact: float) -> void:
	## Hard side wall catches tip the car sideways (rotation.z) onto the wall;
	## the car also flips towards the slide with the flip angle capped so it
	## can land upside down without spinning around.
	var lateral := incoming.dot(_right())
	var dir := signf(lateral) if absf(lateral) > 0.5 else signf(incoming.dot(_forward()))
	var flip := clampf(impact*0.012, 0.2, roll_max*1.6)
	roll = dir*minf(flip*0.85, roll_max)
	if absf(lateral) > crash_lateral_threshold*0.7:
		var side_tip := clampf(absf(lateral)*0.003, 0.3, 12.0)
		rotation.z = clampf(rotation.z+signf(lateral)*side_tip, -22.0, 22.0)


func _exit_blocked_hint() -> void:
	if driver == null:
		return
	if (absf(rotation.x) > 1.2 or absf(rotation.z) > 0.9) and not _blocked_msg_shown:
		driver.world.message = "Turn the vehicle upright (hold SPACE + SPACE) to exit"
		_blocked_msg_shown = true
	elif absf(rotation.x) <= 0.5 and absf(rotation.z) <= 0.5:
		_blocked_msg_shown = false
		driver.world.message = "Safe to exit"


## ---- public helpers ----
func enter(player: BoomPlayer) -> bool:
	if driver != null or health <= 0:
		return false
	if player.has_meta("skateboard"):
		var board: Node3D = player.get_meta("skateboard") as Node3D
		if is_instance_valid(board):
			board.call("dismount")
		player.remove_meta("skateboard")
	driver = player
	player.vehicle = self
	# The on-foot torch must not keep shining through the windscreen.
	if bool(player.get("flashlight_on")) and player.has_method("toggle_flashlight"):
		player.call("toggle_flashlight")
	set_headlights(_is_night())
	if is_motorbike:
		_build_rider()
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
	if absf(rotation.x) > 1.2 or absf(rotation.z) > 0.9:
		driver.world.message = "Turn the vehicle upright to exit"
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
			set_headlights(false)
			return true
	driver.world.message = "Exit blocked · move to an open area"
	return false


## Weapon hits are normalised to six pistol rounds (20 HP each) so car health
## remains a crash-durability stat. Physical crash damage uses take_damage().
func take_weapon_damage(amount: float) -> void:
	if destroyed or health <= 0:
		return
	if combat != null:
		combat.apply_damage(amount)
	else:
		health = maxf(0, health - amount)
		if health <= 0:
			_destroy_vehicle()


func take_damage(amount: float) -> void:
	if destroyed or health <= 0:
		return
	if combat != null:
		combat.apply_damage(amount)
	else:
		health = maxf(0, health - amount)
		if health <= 0:
			_destroy_vehicle()


## Explosion falloff damage from another destroyed vehicle. Chain reactions are
## damped and time-gated in VehicleCombat so a single blast cannot loop forever.
func take_explosion_damage(amount: float) -> void:
	take_damage(amount * 0.5)


func get_explosion_position() -> Vector3:
	return global_position + Vector3.UP * 1.0


## Repair without the explosion presentation, used by tests and respawn logic.
func repair_now() -> void:
	destroyed = false
	if combat != null:
		combat.reset()
	position = home
	rotation = Vector3.ZERO
	health = max_health
	body_art.visible = true
	collision_layer = 1
	collision_mask = 1
	repair_time = 0.0


func _destroy_vehicle() -> void:
	destroyed = true
	if driver != null:
		driver.respawn()
	effects.play_explosion()
	body_art.visible = false
	collision_layer = 0
	collision_mask = 0
	speed = 0
	velocity = Vector3.ZERO
	roll = 0.0
	rotation.z = 0.0
	repair_time = 8.0
