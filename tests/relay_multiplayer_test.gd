extends SceneTree

## Two players through the relay: they find each other, exchange state, a hit is
## applied on the victim's own game, and leaving is noticed.
## Needs a relay: set SYDFORGE_RELAY (local `wrangler dev`) or it uses the live one.

const Net := preload("res://scripts/network_manager.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _run() -> void:
	var a = Net.new()
	var b = Net.new()
	var c = Net.new()
	var seen := {"a_joined": [], "a_left": [], "b_joined": [], "b_msgs": [], "c_msgs": []}
	for n in [a, b, c]:
		root.add_child(n)
	a.player_joined.connect(func(id): seen.a_joined.append(id))
	a.player_left.connect(func(id): seen.a_left.append(id))
	b.player_joined.connect(func(id): seen.b_joined.append(id))
	b.message_received.connect(func(m): seen.b_msgs.append(m))
	c.message_received.connect(func(m): seen.c_msgs.append(m))
	var room := "test-%d" % (randi() % 1000000)
	a.join_room(room)
	_check(await _until(func(): return a.local_id() > 0), "first player enters the room")
	b.join_room(room)
	c.join_room(room + "x")
	_check(await _until(func(): return b.local_id() > 0 and c.local_id() > 0 and seen.a_joined.size() > 0), "second player is announced to the first")
	_check(seen.b_joined == [a.local_id()], "the newcomer learns who is already there")
	a.send({"t": "state", "p": [1.0, 2.0, 3.0], "from": 999})
	_check(await _until(func(): return seen.b_msgs.size() > 0), "state reaches the other player")
	if not seen.b_msgs.is_empty():
		_check(int(seen.b_msgs[0].from) == a.local_id(), "the relay stamps the real sender")
	a.send({"t": "damage", "to": b.local_id(), "a": 20})
	_check(await _until(func(): return seen.b_msgs.size() > 1), "a hit is delivered to its target")
	_check(seen.c_msgs.is_empty(), "another room hears nothing")
	var b_id: int = b.local_id()
	b.stop()
	_check(await _until(func(): return b_id in seen.a_left), "leaving is announced")
	a.stop()
	c.stop()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
