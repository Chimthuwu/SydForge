class_name NetworkManager
extends Node

## Minimal ENet session management for deathmatch. Deliberately thin: no
## matchmaking/relay yet (see SkyJump3D's WebSocket relay for where that goes
## later) — host_game()/join_game() are direct-IP/LAN/Tailscale for now.

signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal network_ready(peer_id: int)
signal connection_failed_signal

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

var active: bool = false


func host_game(port: int = DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Failed to host on port %d (error %d)" % [port, err]
	multiplayer.multiplayer_peer = peer
	active = true
	_connect_signals()
	player_joined.emit(multiplayer.get_unique_id())
	return "Hosting on port %d · your id %d" % [port, multiplayer.get_unique_id()]


func join_game(address: String, port: int = DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Failed to connect to %s:%d (error %d)" % [address, port, err]
	multiplayer.multiplayer_peer = peer
	active = true
	_connect_signals()
	return "Connecting to %s:%d..." % [address, port]


func stop() -> void:
	if active:
		_disconnect_signals()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false


func is_host() -> bool:
	return active and multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)


func _on_peer_connected(id: int) -> void:
	player_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)


func _on_connected_to_server() -> void:
	network_ready.emit(multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	active = false
	connection_failed_signal.emit()
