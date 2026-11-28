class_name DeathmatchManager
extends Node

## Peer-authoritative deathmatch: each peer's own BoomPlayer is the only
## authority over its own health/position. Other peers see it only through a
## RemotePlayerAvatar, driven by broadcast state. A hit on a remote avatar is
## relayed through the room server to the *victim's* machine, which applies the damage
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
	network.network_ready.connect(_on_ready_in_room)
	network.player_joined.connect(_on_player_joined)
	network.player_left.connect(_on_player_left)
	network.message_received.connect(_on_message)
	network.connection_failed_signal.connect(_on_disconnected)


## Hosting and joining are the same thing with a relay: enter the room.
func join(room: String) -> String:
	leave()
	var result := network.join_room(room)
	active = network.active
	return result


func host(room: String = "lobby") -> String:
	return join(room)


func leave() -> void:
	for id in avatars.keys():
		_despawn_avatar(id)
	network.stop()
	active = false
	scores.clear()


func _on_ready_in_room(id: int) -> void:
	scores[id] = 0
	world.message = "DEATHMATCH · in room '%s' — friends join with the same code" % network.room


func _on_disconnected() -> void:
	for id in avatars.keys():
		_despawn_avatar(id)
	active = false
	scores.clear()
	world.message = "DEATHMATCH · connection lost or room full"


func scoreboard_text() -> String:
	if not active:
		return ""
	var ids := scores.keys()
	ids.sort_custom(func(a, b): return int(scores.get(a, 0)) > int(scores.get(b, 0)))
	var lines: Array[String] = ["SCOREBOARD"]
	for id in ids:
		var tag := "YOU" if id == network.local_id() else "P%d" % id
		lines.append("%s · %d" % [tag, int(scores.get(id, 0))])
	return "\n".join(lines)


func _on_player_joined(id: int) -> void:
	if not scores.has(id):
		scores[id] = 0
	if id == network.local_id() or avatars.has(id):
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
	var at := local_player.global_position
	network.send({
		"t": "state", "p": [at.x, at.y, at.z], "y": local_player.rotation.y,
		"h": local_player.health, "v": local_player.vehicle != null,
	})
	if local_player.health <= 0.0 and _last_health > 0.0:
		world.message = "YOU WERE ELIMINATED"
	_last_health = local_player.health


## Called by a RemotePlayerAvatar's take_damage() on the SHOOTER's machine —
## relays the hit to the victim's own machine so it lands on the real,
## authoritative BoomPlayer instead of the proxy.
func request_damage(target_peer_id: int, amount: float, _from_peer_id: int) -> void:
	network.send({"t": "damage", "to": target_peer_id, "a": amount})


## `from` is stamped by the relay, so a player cannot speak for someone else.
func _on_message(message: Dictionary) -> void:
	var sender := int(message.get("from", 0))
	if sender <= 0 or sender == network.local_id():
		return
	match str(message.get("t", "")):
		"state":
			var at: Array = message.get("p", [])
			if at.size() != 3:
				return
			if not avatars.has(sender):
				_on_player_joined(sender)
			avatars[sender].apply_state(
				Vector3(float(at[0]), float(at[1]), float(at[2])), float(message.get("y", 0.0)),
				float(message.get("h", 0.0)), bool(message.get("v", false)))
		"damage":
			_take_pvp_damage(clampf(float(message.get("a", 0.0)), 0.0, 100.0), sender)
		"death":
			_report_death(int(message.get("k", 0)), sender)


func _take_pvp_damage(amount: float, from_peer_id: int) -> void:
	if local_player == null or local_player.health <= 0.0:
		return
	var was_alive := local_player.health > 0.0
	if was_alive and amount >= local_player.health:
		_randomize_respawn()
	var lethal := amount >= local_player.health
	local_player.take_damage(amount)
	if lethal:
		network.send({"t": "death", "k": from_peer_id})
		_report_death(from_peer_id, network.local_id())


## Scatters deathmatch respawns instead of everyone dying back onto the same
## spawn point. Picked before take_damage() so it's already in place when
## BoomPlayer.respawn() reads player.spawn on the fatal hit.
func _randomize_respawn() -> void:
	var spots: Array = world.get("sydney_world").vehicle_spawns if world.get("sydney_world") != null else []
	if spots.is_empty():
		return
	local_player.spawn = spots[randi() % spots.size()] + Vector3.UP * 1.0


func _report_death(killer_id: int, victim_id: int) -> void:
	scores[killer_id] = int(scores.get(killer_id, 0)) + 1
	if not scores.has(victim_id):
		scores[victim_id] = 0
	var killer_tag := "YOU" if killer_id == network.local_id() else "P%d" % killer_id
	var victim_tag := "YOU" if victim_id == network.local_id() else "P%d" % victim_id
	world.message = "%s ELIMINATED %s" % [killer_tag, victim_tag]
