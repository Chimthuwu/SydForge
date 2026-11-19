class_name BoomPlayer
extends CharacterBody3D

const WEAPON_PISTOL := 0
const WEAPON_SHOTGUN := 1

var health: float = 100.0
var ammo: int = 12
var shotgun_ammo: int = 6
var reload_time: float = 0.0
var shotgun_reload_time: float = 0.0
var fire_time: float = 0.0
var melee_time: float = 0.0
var vehicle: CharacterBody3D
var model: Node3D
var world: Node3D
var spawn := Vector3(-9,1,15)
var invulnerable: float = 0.0
var kills: int = 0
var bonus_reputation: int = 0
var stride: float = 0
var coyote_time: float = 0
var jump_buffer: float = 0
var aiming: bool = false
var current_weapon: int = WEAPON_PISTOL

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

func _physics_process(dt: float) -> void:
	invulnerable = maxf(0,invulnerable-dt)
	fire_time = maxf(0,fire_time-dt)
	melee_time = maxf(0,melee_time-dt)
	if shotgun_reload_time > 0.0:
		shotgun_reload_time = maxf(0.0,shotgun_reload_time-dt)
		if shotgun_reload_time <= 0.0:
			shotgun_ammo = 6
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
	var speed := 3.5 if aiming else (10.0 if Input.is_action_pressed("sprint") else 6.0)
	velocity.x = move_toward(velocity.x,direction.x*speed,30*dt)
	velocity.z = move_toward(velocity.z,direction.z*speed,30*dt)
	coyote_time = 0.12 if is_on_floor() else maxf(0,coyote_time-dt)
	jump_buffer = 0.12 if Input.is_action_just_pressed("jump") else maxf(0,jump_buffer-dt)
	if jump_buffer > 0 and coyote_time > 0:
		velocity.y = 8.0
		jump_buffer = 0
		coyote_time = 0
	elif not is_on_floor():
		velocity.y -= 24*dt
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
	if global_position.y < -10:
		respawn()

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
	if fire_time > 0 or reload_time > 0 or vehicle != null:
		return
	if ammo == 0:
		reload()
		return
	ammo -= 1
	fire_time = 0.23
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
	if not hit.is_empty() and (
		hit.collider.has_method("take_damage_at") or hit.collider.has_method("take_damage")
	):
		_apply_weapon_hit(hit.collider,25.0,end,1.0,-camera.global_basis.z)
		world.hit_time = 0.18
	if not hit.is_empty():
		world.impact(end)
	world.rig.recoil = 0.018
	world.rig.show_muzzle_flash()
	world.impact(muzzle,Color("fff2a1"),0.13)
	world.tracer(muzzle,end,Color("fff2a1"))
	world.gunshot(false)

func shoot_shotgun() -> void:
	if fire_time > 0.0 or shotgun_reload_time > 0.0 or vehicle != null:
		return
	if shotgun_ammo <= 0:
		reload()
		return
	shotgun_ammo -= 1
	fire_time = 0.72
	var camera: Camera3D = world.rig.camera
	var muzzle: Vector3 = world.rig.muzzle_position()
	var base_direction: Vector3 = -camera.global_basis.z
	var pellet_hits: Dictionary = {}
	for pellet_index in 9:
		var direction := (
			base_direction
			+ camera.global_basis.x * randf_range(-0.055,0.055)
			+ camera.global_basis.y * randf_range(-0.055,0.055)
		).normalized()
		var query := PhysicsRayQueryParameters3D.create(
			muzzle,muzzle + direction * 55.0,1,[get_rid()]
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider: Object = hit.collider
		if collider.has_method("take_damage_at") or collider.has_method("take_damage"):
			var id: int = collider.get_instance_id()
			if not pellet_hits.has(id):
				pellet_hits[id] = {
					"target": collider,
					"position": hit.position,
					"count": 0,
					"direction": direction
				}
			pellet_hits[id]["count"] += 1
			pellet_hits[id]["position"] = hit.position
		elif pellet_index == 0:
			world.impact(hit.position,Color("d6b99b"),0.12)
		if pellet_index in [0,4,8]:
			world.tracer(muzzle,hit.position,Color("ffe1a6"))
	for result: Dictionary in pellet_hits.values():
		var pellet_count: int = int(result["count"])
		var damage := float(pellet_count) * 16.0
		_apply_weapon_hit(
			result["target"],damage,result["position"],
			1.2 + float(pellet_count) * 0.18,result["direction"]
		)
		world.hit_time = 0.18
	world.rig.recoil = 0.085
	world.rig.show_muzzle_flash()
	world.gunshot(true)

func _apply_weapon_hit(
	target: Object,
	damage: float,
	impact_position: Vector3,
	impact_intensity: float,
	shot_direction: Vector3
) -> void:
	if target.has_method("take_damage_at"):
		target.call("take_damage_at",damage,impact_position,impact_intensity,shot_direction)
	elif target.has_method("take_damage"):
		target.call("take_damage",damage)

func equip_weapon(weapon: int) -> void:
	if vehicle != null:
		return
	current_weapon = WEAPON_SHOTGUN if weapon == WEAPON_SHOTGUN else WEAPON_PISTOL

func is_shotgun_equipped() -> bool:
	return current_weapon == WEAPON_SHOTGUN

func weapon_status_text() -> String:
	if is_shotgun_equipped():
		return "12-GAUGE  %02d / 06" % shotgun_ammo
	return "9MM  %02d / ∞" % ammo

func current_reload_time() -> float:
	return shotgun_reload_time if is_shotgun_equipped() else reload_time

func current_reload_duration() -> float:
	return 2.2 if is_shotgun_equipped() else 1.25

func reload() -> void:
	if is_shotgun_equipped():
		if shotgun_ammo < 6 and shotgun_reload_time <= 0.0:
			shotgun_reload_time = 2.2
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
	reload_time = 0
	invulnerable = 3.0
	world.message = "BACK IN BUSINESS · health restored"
