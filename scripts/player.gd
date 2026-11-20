class_name BoomPlayer
extends CharacterBody3D

const WEAPON_PISTOL := 0
const WEAPON_SHOTGUN := 1
const WEAPON_SMG := 2
const TRIP_SHADER := preload("res://shaders/petrol_trip.gdshader")

var health: float = 100.0
var ammo: int = 12
var shotgun_ammo: int = 6
var smg_ammo: int = 30
var reload_time: float = 0.0
var shotgun_reload_time: float = 0.0
var smg_reload_time: float = 0.0
var weapon_switch_time: float = 0.0
var fire_time: float = 0.0
var melee_time: float = 0.0
var vehicle: CharacterBody3D
var model: Node3D
var world: Node3D
var spawn := Vector3(-9,1,15)
var invulnerable: float = 0.0
var kills: int = 0
var bonus_reputation: int = 0
var quad_jump_time: float = 0.0
var stride: float = 0
var coyote_time: float = 0
var jump_buffer: float = 0
var air_jumps_left: int = 1
var aiming: bool = false
var current_weapon: int = WEAPON_PISTOL
var flashlight: SpotLight3D
var flashlight_on: bool = false
var damage_boost: float = 1.0
var trip_time: float = 0.0
var shoplift_total: int = 0
var wanted_heat: int = 0
var in_supermarket: Node = null
var _trip_overlay: ColorRect
var _trip_material: ShaderMaterial

## Tallest obstacle the controller climbs without jumping. The Opera House
## podium risers are 0.5 m, so 0.6 m clears them with margin while a 0.7 m curb
## or a wall stays impassable.
const STEP_HEIGHT := 0.6
## Downward snap while walking. Long enough to follow a 0.5 m riser downhill
## instead of free-falling off every step.
const GROUND_SNAP := 0.6


func _ready() -> void:
	world = get_parent()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.9
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.95
	add_child(collider)
	model = Art.person(self,Color("ffb52e"))
	# The on-foot view is first person; the gameplay body stays available for
	# collision, health and animation logic without filling the camera.
	model.visible = false
	floor_snap_length = GROUND_SNAP
	add_to_group("player")
	_build_trip_overlay()

func _physics_process(dt: float) -> void:
	quad_jump_time = maxf(0.0, quad_jump_time - dt)
	invulnerable = maxf(0,invulnerable-dt)
	_update_trip(dt)
	fire_time = maxf(0,fire_time-dt)
	melee_time = maxf(0,melee_time-dt)
	weapon_switch_time = maxf(0.0,weapon_switch_time-dt)
	if shotgun_reload_time > 0.0:
		shotgun_reload_time = maxf(0.0,shotgun_reload_time-dt)
		if shotgun_reload_time <= 0.0:
			shotgun_ammo = 6
	if smg_reload_time > 0.0:
		smg_reload_time = maxf(0.0,smg_reload_time-dt)
		if smg_reload_time <= 0.0:
			smg_ammo = 30
	if reload_time > 0:
		reload_time -= dt
		if reload_time <= 0:
			ammo = 12
	if vehicle != null:
		coyote_time = 0
		jump_buffer = 0
		global_position = vehicle.global_position
		return
	var input := Input.get_vector("left","right","forward","back")
	var direction := Vector3(input.x,0,input.y).rotated(Vector3.UP,world.rig.yaw)
	aiming = Input.is_action_pressed("aim")
	# Fast, immediate movement with a little retained air momentum.
	var speed := 4.2 if aiming else (11.2 if Input.is_action_pressed("sprint") else 6.4)
	var accel := 46.0 if is_on_floor() else 22.0
	velocity.x = move_toward(velocity.x,direction.x*speed,accel*dt)
	velocity.z = move_toward(velocity.z,direction.z*speed,accel*dt)
	if is_on_floor():
		air_jumps_left = 3 if quad_jump_time > 0.0 else 1
	coyote_time = 0.12 if is_on_floor() else maxf(0,coyote_time-dt)
	jump_buffer = 0.12 if Input.is_action_just_pressed("jump") else maxf(0,jump_buffer-dt)
	if jump_buffer > 0 and coyote_time > 0:
		velocity.y = 9.4
		jump_buffer = 0
		coyote_time = 0
	elif jump_buffer > 0 and (air_jumps_left > 0 or quad_jump_time > 0.0):
		velocity.y = 8.8
		if quad_jump_time <= 0.0:
			air_jumps_left -= 1
		jump_buffer = 0
	elif not is_on_floor():
		velocity.y -= 26*dt
	var grounded := is_on_floor()
	# Snapping is effectively off while rising so a jump is never pulled back to
	# the floor, and long while walking so stairs are followed downhill.
	floor_snap_length = 0.05 if velocity.y > 0.01 else GROUND_SNAP
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	move_and_slide()
	if grounded and is_on_wall() and velocity.y <= 0.01:
		_try_step_up(motion)
	stride += dt*velocity.length()*1.6
	var swing := sin(stride)*0.55 if direction.length() > 0.1 and is_on_floor() else 0.0
	model.get_node("LegLeft").rotation.x = swing
	model.get_node("LegRight").rotation.x = -swing
	if aiming or fire_time > 0:
		model.rotation.y = lerp_angle(model.rotation.y,world.rig.yaw,1-exp(-18*dt))
	elif direction.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y,atan2(-direction.x,-direction.z),dt*12)
	if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		shoot()
	if Input.is_action_just_pressed("sniff_petrol") and vehicle == null and in_supermarket == null:
		for station: Node in get_tree().get_nodes_in_group("petrol_station"):
			if global_position.distance_to((station as Node3D).global_position) < 8.0:
				station.call("sniff", self)
				break
	if global_position.y < -10:
		respawn()

func _build_trip_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PetrolTripLayer"
	layer.layer = 0
	add_child(layer)
	_trip_overlay = ColorRect.new()
	_trip_overlay.name = "PetrolTripOverlay"
	_trip_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trip_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trip_overlay.color = Color.WHITE
	layer.add_child(_trip_overlay)
	_trip_material = ShaderMaterial.new()
	_trip_material.shader = TRIP_SHADER
	_trip_material.set_shader_parameter("intensity", 0.0)
	_trip_overlay.material = _trip_material
	_trip_overlay.visible = false


func sniff_petrol(duration: float = 18.0) -> void:
	trip_time = maxf(trip_time, duration)
	damage_boost = 1.35
	if _trip_overlay != null:
		_trip_overlay.visible = true
		if _trip_material != null:
			_trip_material.set_shader_parameter("intensity", 0.9)
	if world != null:
		world.message = "PETROL TRIP · +35%% DAMAGE · %ds · GET TO WORK" % int(trip_time)


func _update_trip(dt: float) -> void:
	if trip_time <= 0.0:
		return
	trip_time = maxf(0.0, trip_time - dt)
	if _trip_overlay != null and _trip_material != null:
		var fade_in := clampf((18.0 - trip_time) / 0.8, 0.0, 1.0)
		var fade_out := clampf(trip_time / 2.0, 0.0, 1.0)
		_trip_material.set_shader_parameter("intensity", minf(fade_in, fade_out) * 0.9)
		_trip_overlay.visible = true
	if trip_time <= 0.0:
		damage_boost = 1.0
		if _trip_overlay != null:
			_trip_overlay.visible = false
		if world != null:
			world.message = "THE PETROL TRIP FADES · DAMAGE BACK TO NORMAL"


func add_shoplift(value: int) -> void:
	shoplift_total += maxi(0, value)
	wanted_heat += 1


## Standard step assist: when the walk is stopped by a vertical face, lift by
## STEP_HEIGHT, retry the horizontal move, and drop back onto the surface. The
## whole attempt is reverted if there is no headroom, the move stays blocked, or
## the landing is higher than STEP_HEIGHT, so walls and ledges cannot be climbed.
func _try_step_up(motion: Vector3) -> bool:
	if motion.length() < 0.001:
		return false
	var before := global_position
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return false
	global_position = before + up
	# Push past the riser by the capsule radius, otherwise the body lands on the
	# nose of the step (a ~46 degree normal) and wedges there instead of settling
	# on the tread.
	var horizontal := Vector3(motion.x, 0.0, motion.z)
	var clear := horizontal + horizontal.normalized() * 0.36
	if move_and_collide(clear) != null:
		global_position = before
		return false
	var drop := move_and_collide(Vector3.DOWN * (STEP_HEIGHT + 0.1))
	if drop == null:
		global_position = before
		return false
	var climbed := global_position.y - before.y
	# A nose landing gives a diagonal normal, so only reject surfaces steeper
	# than 60 degrees; the height check is what keeps walls out of reach.
	if drop.get_normal().dot(up_direction) < 0.5 or climbed < 0.02 or climbed > STEP_HEIGHT + 0.02:
		global_position = before
		return false
	velocity.y = 0.0
	return true


func shoot() -> void:
	if current_weapon == WEAPON_SHOTGUN:
		shoot_shotgun()
		return
	if current_weapon == WEAPON_SMG:
		shoot_smg()
		return
	if fire_time > 0 or reload_time > 0 or vehicle != null or weapon_switch_time > 0:
		return
	if ammo == 0:
		reload()
		return
	ammo -= 1
	fire_time = 0.11
	var camera: Camera3D = world.rig.camera
	var origin := camera.global_position
	var end := origin - camera.global_basis.z*150
	var query := PhysicsRayQueryParameters3D.create(origin,end,1,[get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	var muzzle: Vector3 = world.rig.muzzle_position()
	# Trace from the visible barrel so nearby cover cannot be shot through.
	query = PhysicsRayQueryParameters3D.create(muzzle,end,1,[get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		hit = obstruction
		end = hit.position
	var hit_actor := false
	if not hit.is_empty() and (
		hit.collider.has_method("take_damage_at") or hit.collider.has_method("take_damage")
	):
		_apply_weapon_hit(hit.collider,25.0,end,1.0,-camera.global_basis.z)
		world.hit_time = 0.18
		hit_actor = true
	if not hit.is_empty():
		world.impact(end)
		var audio := get_node_or_null("/root/AudioDirector")
		if audio != null:
			audio.play_impact("flesh" if hit_actor else "concrete",end)
	world.rig.recoil = 0.020
	world.rig.show_muzzle_flash()
	world.impact(muzzle,Color("fff2a1"),0.10)
	world.tracer(muzzle,end,Color("fff2a1"))
	world.gunshot("pistol")

func shoot_shotgun() -> void:
	if fire_time > 0.0 or shotgun_reload_time > 0.0 or vehicle != null or weapon_switch_time > 0.0:
		return
	if shotgun_ammo <= 0:
		reload()
		return
	shotgun_ammo -= 1
	fire_time = 0.44
	var camera: Camera3D = world.rig.camera
	var muzzle: Vector3 = world.rig.muzzle_position()
	var base_direction: Vector3 = -camera.global_basis.z
	var pellet_hits: Dictionary = {}
	var pellet_count_total := 14
	for pellet_index in pellet_count_total:
		var spread_x := randf_range(-0.085, 0.085)
		var spread_y := randf_range(-0.075, 0.075)
		if pellet_index == 0:
			spread_x *= 0.25
			spread_y *= 0.25
		var direction := (
			base_direction
			+ camera.global_basis.x * spread_x
			+ camera.global_basis.y * spread_y
		).normalized()
		var origin := muzzle
		var remaining_range := 45.0
		var exclude: Array = [get_rid()]
		# Penetrating blast: pellets can tear through multiple bodies in a line,
		# letting one shot blow apart several people at close range.
		for penetration in 3:
			if remaining_range <= 0.5:
				break
			var query := PhysicsRayQueryParameters3D.create(
				origin, origin + direction * remaining_range, 1, exclude
			)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var collider: Object = hit.collider
			var hit_pos: Vector3 = hit.position
			if collider.has_method("take_damage_at") or collider.has_method("take_damage"):
				var id: int = collider.get_instance_id()
				if not pellet_hits.has(id):
					pellet_hits[id] = {
						"target": collider,
						"position": hit_pos,
						"count": 0,
						"direction": direction
					}
				pellet_hits[id]["count"] += 1
				pellet_hits[id]["position"] = hit_pos
				exclude.append(collider.get_rid())
				# Push through bodies with reduced energy; stop on hard surfaces.
				origin = hit_pos + direction * 0.35
				remaining_range -= (hit_pos.distance_to(origin - direction * 0.35) + 0.35)
				if penetration >= 1 and pellet_hits[id]["count"] >= 4:
					break
			else:
				if pellet_index == 0:
					world.impact(hit_pos, Color("d6b99b"), 0.14)
				break
		if pellet_index in [0, 4, 8, 13]:
			var trace_end := muzzle + direction * 35.0
			var trace_query := PhysicsRayQueryParameters3D.create(muzzle, trace_end, 1, [get_rid()])
			var trace_hit := get_world_3d().direct_space_state.intersect_ray(trace_query)
			if not trace_hit.is_empty():
				trace_end = trace_hit.position
			world.tracer(muzzle, trace_end, Color("ffe1a6"))
	for result: Dictionary in pellet_hits.values():
		var target_pellets: int = int(result["count"])
		var damage := float(target_pellets) * 22.0
		if target_pellets >= 6:
			damage += 35.0
		if target_pellets >= 10:
			damage += 40.0
		_apply_weapon_hit(
			result["target"], damage, result["position"],
			1.8 + float(target_pellets) * 0.28, result["direction"]
		)
		# Extra close-range gore splatter for brutal impact feedback.
		if target_pellets >= 4:
			var GoreFx := preload("res://scripts/gore_effects.gd")
			GoreFx.spawn_hit_spray(get_parent(), result["position"], 2.5 + float(target_pellets) * 0.25, result["direction"])
			if target_pellets >= 6:
				GoreFx.spawn_hit_spray(get_parent(), result["position"] + Vector3.UP * 0.15, 1.8 + float(target_pellets) * 0.15, result["direction"])
			if target_pellets >= 8:
				GoreFx.spawn_death_splatter(get_parent(), result["position"], 1.6 + float(target_pellets) * 0.1, false)
		world.hit_time = 0.22
	world.rig.recoil = 0.12
	world.rig.show_muzzle_flash()
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null:
		audio.play_impact("flesh" if not pellet_hits.is_empty() else "concrete", muzzle + base_direction * 2.0)
	world.gunshot("shotgun")

## Compact SMG: fast automatic fire, low per-shot recoil, clear short-range
## identity. Nine-millimetre supplier from the shared asset index is represented
## through silhouette and behaviour; no external audio is required.
func shoot_smg() -> void:
	if fire_time > 0.0 or smg_reload_time > 0.0 or vehicle != null or weapon_switch_time > 0.0:
		return
	if smg_ammo <= 0:
		reload()
		return
	smg_ammo -= 1
	fire_time = 0.055
	var camera: Camera3D = world.rig.camera
	var muzzle: Vector3 = world.rig.muzzle_position()
	var direction := (
		-camera.global_basis.z
		+ camera.global_basis.x * randf_range(-0.012,0.012)
		+ camera.global_basis.y * randf_range(-0.010,0.010)
	).normalized()
	var end := muzzle + direction * 130.0
	var query := PhysicsRayQueryParameters3D.create(muzzle,end,1,[get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_actor := false
	if not hit.is_empty():
		end = hit.position
		if hit.collider.has_method("take_damage_at") or hit.collider.has_method("take_damage"):
			_apply_weapon_hit(hit.collider,15.0,end,0.8,direction)
			world.hit_time = 0.14
			hit_actor = true
		world.impact(end,Color("ffd58a"),0.07)
		var audio := get_node_or_null("/root/AudioDirector")
		if audio != null:
			audio.play_impact("flesh" if hit_actor else "concrete",end)
	world.rig.recoil = 0.008
	world.rig.show_muzzle_flash()
	if smg_ammo % 3 == 0:
		world.tracer(muzzle,end,Color("ffe6a8"))
	world.gunshot("smg")

func _apply_weapon_hit(
	target: Object,
	damage: float,
	impact_position: Vector3,
	impact_intensity: float,
	shot_direction: Vector3
) -> void:
	damage *= damage_boost
	if target is ArcadeCar and target.has_method("take_weapon_damage"):
		target.call("take_weapon_damage",damage)
	elif target.has_method("take_damage_at"):
		target.call("take_damage_at",damage,impact_position,impact_intensity,shot_direction)
	elif target.has_method("take_damage"):
		target.call("take_damage",damage)

func equip_weapon(weapon: int) -> void:
	if vehicle != null:
		return
	var next := WEAPON_PISTOL
	if weapon == WEAPON_SHOTGUN:
		next = WEAPON_SHOTGUN
	elif weapon == WEAPON_SMG:
		next = WEAPON_SMG
	if next != current_weapon:
		current_weapon = next
		fire_time = 0.0
		weapon_switch_time = 0.18

func cycle_weapon(direction: int = 1) -> void:
	equip_weapon((current_weapon + direction + 3) % 3)


func toggle_flashlight() -> void:
	if flashlight == null:
		flashlight = SpotLight3D.new()
		flashlight.name = "PlayerFlashlight"
		flashlight.spot_range = 34.0
		flashlight.spot_angle = 34.0
		flashlight.light_color = Color("fff3dd")
		flashlight.light_energy = 0.0
		flashlight.shadow_enabled = false
		world.rig.camera.add_child(flashlight)
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	flashlight.light_energy = 3.2 if flashlight_on else 0.0

func is_shotgun_equipped() -> bool:
	return current_weapon == WEAPON_SHOTGUN

func is_smg_equipped() -> bool:
	return current_weapon == WEAPON_SMG

func weapon_status_text() -> String:
	if is_shotgun_equipped():
		return "12-GAUGE  %02d / 06" % shotgun_ammo
	if is_smg_equipped():
		return "SMG  %02d / 30" % smg_ammo
	return "9MM  %02d / ∞" % ammo

func current_reload_time() -> float:
	if is_shotgun_equipped():
		return shotgun_reload_time
	if is_smg_equipped():
		return smg_reload_time
	return reload_time

func current_reload_duration() -> float:
	if is_shotgun_equipped():
		return 2.2
	if is_smg_equipped():
		return 1.55
	return 1.25

func reload() -> void:
	if is_shotgun_equipped():
		if shotgun_ammo < 6 and shotgun_reload_time <= 0.0:
			shotgun_reload_time = 2.2
	elif is_smg_equipped():
		if smg_ammo < 30 and smg_reload_time <= 0.0:
			smg_reload_time = 1.55
	elif ammo < 12 and reload_time <= 0:
		reload_time = 1.25

func melee() -> void:
	if melee_time > 0 or vehicle != null:
		return
	melee_time = 0.55
	world.sound(180,0.12)
	var facing: Vector3 = -world.rig.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var offset := enemy.global_position-global_position
		offset.y = 0.0
		if offset.length() >= 2.8 or facing.dot(offset.normalized()) < 0.25:
			continue
		var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP,enemy.global_position+Vector3.UP,1,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider == enemy:
			enemy.take_damage(40.0)
			world.hit_time = 0.18
	var tween := create_tween()
	tween.tween_property(model,"rotation:z",-0.22,0.08)
	tween.tween_property(model,"rotation:z",0.0,0.18)

func take_damage(amount: float) -> void:
	if invulnerable > 0 or vehicle != null:
		return
	health -= amount
	world.hurt_flash = 0.3
	if health <= 0:
		respawn()

func award_bin_chicken_bonus() -> void:
	bonus_reputation += 500
	world.message = "BIN CHICKEN BINNED! · +500 REP"
	world.sound(520,0.16)

func respawn() -> void:
	if vehicle != null:
		world.rig.arm.remove_excluded_object(vehicle.get_rid())
		if vehicle.has_method("force_release_driver"):
			vehicle.call("force_release_driver", self)
		else:
			vehicle.set("driver", null)
		vehicle = null
	collision_layer = 1
	collision_mask = 1
	visible = true
	global_position = spawn
	velocity = Vector3.ZERO
	coyote_time = 0
	jump_buffer = 0
	health = 100
	ammo = 12
	shotgun_ammo = 6
	smg_ammo = 30
	reload_time = 0
	shotgun_reload_time = 0
	smg_reload_time = 0
	invulnerable = 3.0
	world.message = "BACK IN BUSINESS · health restored"
