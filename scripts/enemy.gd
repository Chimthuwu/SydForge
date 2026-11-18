class_name BoomEnemy
extends CharacterBody3D

var health: float = 100
var cooldown: float = 0
var respawn_time: float = 0
var home := Vector3(6,0.3,-20)
var model: Node3D
var player: BoomPlayer
var health_label: Label3D

func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.95
	add_child(collision)
	model = Art.person(self,Color("de4561"))
	health_label = Art.label(self,Vector3(0,2.6,0),"GRUNT · 100",24)
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_to_group("enemies")
	floor_snap_length = 0.35

func _physics_process(dt: float) -> void:
	if respawn_time > 0:
		respawn_time -= dt
		if respawn_time <= 0:
			health = 100
			position = home
			visible = true
			collision_layer = 1
			health_label.text = "GRUNT · 100"
		return
	cooldown -= dt
	var delta := player.global_position-global_position
	delta.y = 0
	var dist := delta.length()
	var direction := delta.normalized()
	velocity.x = 0
	velocity.z = 0
	if dist < 28 and dist > 2:
		var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.4,player.global_position+Vector3.UP*1.2,1,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider == player:
			model.rotation.y = atan2(-direction.x,-direction.z)
			if dist > 12:
				velocity.x = direction.x*3
				velocity.z = direction.z*3
			if cooldown <= 0:
				player.take_damage(8)
				get_parent().tracer(global_position+Vector3.UP*1.4,player.global_position+Vector3.UP,Color("ff6473"))
				cooldown = 1.3
	elif dist <= 2 and cooldown <= 0:
		player.take_damage(12)
		cooldown = 1
	velocity.y -= 24*dt
	move_and_slide()

func take_damage(amount: float) -> void:
	if health <= 0:
		return
	health = maxf(0,health-amount)
	health_label.text = "GRUNT · %d" % health
	if health <= 0:
		player.kills += 1
		get_parent().message = "GRUNT DOWN · +100 reputation"
		visible = false
		collision_layer = 0
		respawn_time = 12
