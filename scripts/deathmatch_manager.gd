class_name DeathmatchManager
extends Node

## Peer-authoritative deathmatch: each peer's own BoomPlayer is the only
## authority over its own health/position. Other peers see it only through a
## RemotePlayerAvatar, driven by broadcast state. A hit on a remote avatar is
## relayed with rpc_id() to the *victim's* machine, which applies the damage
## to its own real BoomPlayer and reports the death back to everyone — so no
## peer can be killed except by its own client's take_damage() call.

const AvatarScene := preload("res://scripts/remote_player_avatar.gd")
const BROADCAST_HZ := 15.0

var world: Node
var local_player: BoomPlayer
var network: NetworkManager
var avatars: Dictionary = {}
var scores: Dictionary = {}
var active: bool = false
var _broadcast_timer: float = 0.0
var _last_health: float = 100.0


func setup(world_node: Node, player_node: BoomPlayer, net: NetworkManager) -> void:
	world = world_node
	local_player = player_node
	network = net
	network.player_joined.connect(_on_player_joined)
	network.player_left.connect(_on_player_left)


func host(port: int = NetworkManager.DEFAULT_PORT) -> String:
	var result := network.host_game(port)
	active = network.active
	scores[multiplayer.get_unique_id()] = 0
	return result


func join(address: String, port: int = NetworkManager.DEFAULT_PORT) -> String:
	var result := network.join_game(address, port)
	active = network.active
	return result


func leave() -> void:
	for id in avatars.keys():
		_despawn_avatar(id)
	network.stop()
	active = false
	scores.clear()


func scoreboard_text() -> String:
	if not active:
		return ""
	var ids := scores.keys()
	ids.sort_custom(func(a, b): return int(scores.get(a, 0)) > int(scores.get(b, 0)))
	var lines: Array[String] = ["SCOREBOARD"]
	for id in ids:
		var tag := "YOU" if id == multiplayer.get_unique_id() else "P%d" % id
		lines.append("%s · %d" % [tag, int(scores.get(id, 0))])
	return "\n".join(lines)


func _on_player_joined(id: int) -> void:
	if not scores.has(id):
		scores[id] = 0
	if id == multiplayer.get_unique_id() or avatars.has(id):
		return
	var avatar: RemotePlayerAvatar = AvatarScene.new()
	avatar.owner_peer_id = id
	avatar.manager = self
	world.add_child(avatar)
	avatars[id] = avatar


func _on_player_left(id: int) -> void:
	_despawn_avatar(id)
	scores.erase(id)


func _despawn_avatar(id: int) -> void:
	if avatars.has(id):
		var avatar: Node = avatars[id]
		if is_instance_valid(avatar):
			avatar.queue_free()
		avatars.erase(id)


func _physics_process(dt: float) -> void:
	if not active or local_player == null:
		return
	_broadcast_timer += dt
	if _broadcast_timer < 1.0 / BROADCAST_HZ:
		return
	_broadcast_timer = 0.0
	var in_vehicle := local_player.vehicle != null
	rpc("_net_player_state", local_player.global_position, local_player.rotation.y, local_player.health, in_vehicle)
	if local_player.health <= 0.0 and _last_health > 0.0:
		world.message = "YOU WERE ELIMINATED"
	_last_health = local_player.health


## Called by a RemotePlayerAvatar's take_damage() on the SHOOTER's machine —
## relays the hit to the victim's own machine so it lands on the real,
## authoritative BoomPlayer instead of the proxy.
func request_damage(target_peer_id: int, amount: float, from_peer_id: int) -> void:
	rpc_id(target_peer_id, "_take_pvp_damage", amount, from_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _net_player_state(pos: Vector3, yaw: float, health: float, in_vehicle: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == multiplayer.get_unique_id():
		return
	if avatars.has(sender):
		avatars[sender].apply_state(pos, yaw, health, in_vehicle)


@rpc("any_peer", "reliable")
func _take_pvp_damage(amount: float, from_peer_id: int) -> void:
	if local_player == null or local_player.health <= 0.0:
		return
	var was_alive := local_player.health > 0.0
	if was_alive and amount >= local_player.health:
		_randomize_respawn()
	local_player.take_damage(amount)
	if was_alive and local_player.health <= 0.0:
		rpc("_report_death", from_peer_id, multiplayer.get_unique_id())


## Scatters deathmatch respawns instead of everyone dying back onto the same
## spawn point. Picked before take_damage() so it's already in place when
## BoomPlayer.respawn() reads player.spawn on the fatal hit.
func _randomize_respawn() -> void:
	var spots: Array = world.get("sydney_world").vehicle_spawns if world.get("sydney_world") != null else []
	if spots.is_empty():
		return
	local_player.spawn = spots[randi() % spots.size()] + Vector3.UP * 1.0


@rpc("any_peer", "call_local", "reliable")
func _report_death(killer_id: int, victim_id: int) -> void:
	scores[killer_id] = int(scores.get(killer_id, 0)) + 1
	if not scores.has(victim_id):
		scores[victim_id] = 0
	var killer_tag := "YOU" if killer_id == multiplayer.get_unique_id() else "P%d" % killer_id
	var victim_tag := "YOU" if victim_id == multiplayer.get_unique_id() else "P%d" % victim_id
	world.message = "%s ELIMINATED %s" % [killer_tag, victim_tag]
