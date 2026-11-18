class_name BoomPlayer
extends CharacterBody3D

var health: float = 100.0
var ammo: int = 12
var reload_time: float = 0.0
var fire_time: float = 0.0
var melee_time: float = 0.0
var vehicle: ArcadeCar
var model: Node3D
var world: Node3D
var spawn := Vector3(-9,1,15)
var invulnerable: float = 0.0
var kills: int = 0
var stride: float = 0
var coyote_time: float = 0
var jump_buffer: float = 0
var aiming: bool = false

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
	floor_snap_length = 0.35
	add_to_group("player")

func _physics_process(dt: float) -> void:
	invulnerable = maxf(0,invulnerable-dt)
	fire_time = maxf(0,fire_time-dt)
	melee_time = maxf(0,melee_time-dt)
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
	move_and_slide()
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

func shoot() -> void:
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
	var muzzle := global_position+Vector3(0,1.35,0)
	# A second ray prevents firing through a wall between the player and reticle.
	query = PhysicsRayQueryParameters3D.create(muzzle,end,1,[get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		hit = obstruction
		end = hit.position
	if not hit.is_empty() and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(25.0)
		world.hit_time = 0.18
	if not hit.is_empty():
		world.impact(end)
	world.rig.recoil = 0.018
	world.impact(muzzle,Color("fff2a1"),0.13)
	world.tracer(muzzle,end,Color("fff2a1"))
	world.sound(650,0.07)

func reload() -> void:
	if ammo < 12 and reload_time <= 0:
		reload_time = 1.25

func melee() -> void:
	if melee_time > 0 or vehicle != null:
		return
	melee_time = 0.55
	world.sound(180,0.12)
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var offset := enemy.global_position-global_position
		if offset.length() >= 2.8 or (-model.global_basis.z).dot(offset.normalized()) < 0.25:
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

func respawn() -> void:
	if vehicle != null:
		world.rig.arm.remove_excluded_object(vehicle.get_rid())
		vehicle.driver = null
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
