extends "res://scripts/sydney_district.gd"

@export var north_start := false

func _playtest_spawn() -> Vector3:
	var bridge = sydney_world.get_node("HarbourBridge")
	var i: int = bridge.route.size()-5 if north_start else 4
	return bridge.route[i]+bridge.route_east[i]*21+Vector3.UP*0.4

func _playtest_look_target() -> Vector3:
	return Vector3(247.3,52,-2299.6)

func _playtest_message() -> String:
	return "HARBOUR BRIDGE · Eastern walkway · N: switch shore · car at road entrance"

func _ready() -> void:
	super()
	if not using_sydney:
		return
	var bridge = sydney_world.get_node("HarbourBridge")
	for i in vehicles.size():
		# Five district vehicles share the 24 m-wide roadway; the lane array
		# must cover every index or line 24 raises an out-of-bounds error.
		var at: int = clampi(3+i*2 if i<2 else bridge.route.size()-4-(i-2)*2, 1, bridge.route.size()-2)
		var car: ArcadeCar = vehicles[i]
		var lane: float = [-7.5,-1.5,7.5,1.5,-4.5][i]
		car.global_position = bridge.route[at]+bridge.route_east[at]*lane+Vector3.UP*0.5
		var direction: Vector3 = bridge.route[at+1]-bridge.route[at] if i<2 else bridge.route[at-1]-bridge.route[at]
		car.rotation.y = atan2(-direction.x,-direction.z)
		car.home = car.global_position

func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N and player.vehicle == null:
		north_start = not north_start
		player.spawn = _playtest_spawn()
		player.respawn()
		var direction := _playtest_look_target()-player.spawn
		rig.yaw = atan2(-direction.x,-direction.z)
		_opening_yaw = rig.yaw
		_intro = 0.0
