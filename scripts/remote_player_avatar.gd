class_name RemotePlayerAvatar
extends CharacterBody3D

## Lightweight stand-in shown for every OTHER connected peer in a deathmatch.
## It never reads local input and is never the multiplayer authority for
## anything — it is pure client-side visual (driven by state broadcast from
## the owning peer's real BoomPlayer) plus a hit target for the local
## player's own shoot()/melee raycasts.

var owner_peer_id: int = -1
var manager: Node
var health: float = 100.0
var _target_pos: Vector3
var _target_yaw: float = 0.0
var _has_target: bool = false


func _ready() -> void:
	add_to_group("remote_players")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	Art.box(self, Vector3(0, 0.55, 0), Vector3(0.6, 1.1, 0.35), Color("3a7bd5"))
	Art.box(self, Vector3(0, 1.3, 0), Vector3(0.4, 0.4, 0.4), Color("c68642"))
	_target_pos = global_position


func apply_state(pos: Vector3, yaw: float, new_health: float, _in_vehicle: bool) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_has_target = true
	health = new_health
	visible = health > 0.0
	collision_layer = 1 if health > 0.0 else 0


func _physics_process(dt: float) -> void:
	if not _has_target:
		return
	global_position = global_position.lerp(_target_pos, clampf(dt * 12.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(dt * 12.0, 0.0, 1.0))


## Matches the duck-typed contract BoomPlayer.shoot()/melee() call on any hit
## collider (see scripts/player.gd::_apply_weapon_hit).
func take_damage(amount: float) -> void:
	if manager == null or health <= 0.0:
		return
	manager.request_damage(owner_peer_id, amount, manager.network.local_id())


func take_damage_at(amount: float, _impact_position: Vector3, _impact_intensity: float, _shot_direction: Vector3) -> void:
	take_damage(amount)
