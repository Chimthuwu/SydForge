extends SceneTree

## Owner bug: "when I kill a cop another spawns immediately". A backup request
## must not create anyone at once, must not stack, and must arrive well away from
## the scene and the player.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/police_backup_test.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var mgr := EmergencyIncidentManager.new()
	root.add_child(mgr)
	mgr.player_ref = player
	mgr.set_process(false)  # the test drives the clock itself
	var scene_pos := Vector3(2.0, 0.2, 0.0)

	for i in 5:
		mgr.request_police_response(scene_pos, 1.2)
	_check(mgr.foot_patrol_officers.is_empty(), "no officer appears the instant backup is called")
	mgr._tick_backup(10.0)
	_check(mgr.foot_patrol_officers.is_empty(), "still nobody after 10 s")
	mgr._tick_backup(20.0)
	_check(mgr.foot_patrol_officers.size() == 1, "repeated calls bring one officer, not five (%d)" % mgr.foot_patrol_officers.size())
	if not mgr.foot_patrol_officers.is_empty():
		var cop: Node3D = mgr.foot_patrol_officers[0]
		var from_scene := cop.global_position.distance_to(scene_pos)
		var from_player := cop.global_position.distance_to(player.global_position)
		_check(from_scene > 40.0 and from_player > 40.0, "backup arrives away from the scene (%.0f m) and player (%.0f m)" % [from_scene, from_player])

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
