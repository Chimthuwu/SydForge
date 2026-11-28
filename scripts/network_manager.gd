class_name NetworkManager
extends Node

## Room-based multiplayer through a WebSocket relay (cloudflare/worker.js), the
## same method SKYJUMP3D uses. Everyone who connects with the same room code is
## in the same game: no IP addresses or port forwarding, and it works in a
## browser. The relay only passes JSON between players.

signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal network_ready(peer_id: int)
signal connection_failed_signal
signal message_received(message: Dictionary)

const RELAY_URL := "wss://syd-forge-relay.nyan-anonymous-d45.workers.dev"

var active: bool = false
var room := ""
var _socket: WebSocketPeer
var _id := 0


func _ready() -> void:
	# The connection must stay serviced while the pause menu is open.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Room codes keep only the characters the relay accepts.
static func clean_room(code: String) -> String:
	var result := ""
	for character in code.strip_edges().to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			result += character
	return result.left(24) if not result.is_empty() else "lobby"


func join_room(code: String) -> String:
	stop()
	room = clean_room(code)
	var base := OS.get_environment("SYDFORGE_RELAY")
	if base.is_empty():
		base = RELAY_URL
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url("%s/ws?room=%s" % [base, room])
	if error != OK:
		_socket = null
		return "Could not connect (error %d)" % error
	active = true
	return "Joining room '%s'..." % room


func stop() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	active = false
	_id = 0


func local_id() -> int:
	return _id


func send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	while _socket != null and _socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			_handle(parsed)
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		stop()
		connection_failed_signal.emit()


func _handle(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"hi":
			_id = int(message.get("id", 0))
			network_ready.emit(_id)
			for peer in message.get("peers", []):
				player_joined.emit(int(peer))
		"join":
			player_joined.emit(int(message.get("id", 0)))
		"leave":
			player_left.emit(int(message.get("id", 0)))
		"full":
			stop()
			connection_failed_signal.emit()
		_:
			message_received.emit(message)
