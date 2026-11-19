extends "res://scripts/sydney_district.gd"

## INNER WEST PLAYTEST ENTRY POINT — open res://sydney/sydney_inner_west_test.tscn
## and press F6.
##
## This scene keeps the full existing game: the Stage A CBD world, the Opera
## House and the Harbour Bridge load exactly as Phase 3–5 built them (the
## parent class forces the Sydney branch on). This script then ADDS the Phase
## 6C Inner West district beside it — same origin, same projection, terrain
## blending to 0 at the shared seam — and moves the player, the four ArcadeCars
## and the enemy to the Inner West spawn so the district is playable on foot
## and by car.
##
## Nothing in scripts/district.gd, sydney/sydney_world.gd, the Opera House or
## the Harbour Bridge is modified.

## King Street, Newtown, near the station: the Phase 6C default entry point.
const NEWTOWN_LOOK := Vector3(-1314.0, 8.0, 239.0)


var inner_west: InnerWestWorld


func _playtest_message() -> String:
	return "INNER WEST · King Street, Newtown — Glebe, Balmain, Marrickville beyond"


func _ready() -> void:
	super()
	if not using_sydney or player == null:
		return
	inner_west = InnerWestWorld.new()
	inner_west.name = "InnerWestWorld"
	if not inner_west.load_world():
		push_warning("Inner West failed to load (%s); staying in Stage A" % inner_west.load_error)
		inner_west.free()
		return
	add_child(inner_west)
	var spawn := inner_west.player_spawn
	# drop onto terrain: the world file stores x/z; y comes from the height grid
	spawn.y = InnerWestMesh.height_at(inner_west.height_grid, spawn.x, spawn.z) + 0.3
	player.spawn = spawn
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	if rig != null:
		rig.yaw = inner_west.player_yaw
		rig.pitch = -0.04
		_opening_yaw = rig.yaw
		_intro = 0.0
	for index in mini(vehicles.size(), inner_west.vehicle_spawns.size()):
		var car := vehicles[index]
		var vehicle_spawn := inner_west.vehicle_spawns[index]
		car.position = Vector3(
			vehicle_spawn.x,
			InnerWestMesh.height_at(inner_west.height_grid, vehicle_spawn.x, vehicle_spawn.z) + 0.5,
			vehicle_spawn.z
		)
		car.rotation.y = inner_west.vehicle_yaws[index]
	enemy.home = Vector3(
		inner_west.enemy_spawn.x,
		InnerWestMesh.height_at(inner_west.height_grid, inner_west.enemy_spawn.x, inner_west.enemy_spawn.z) + 0.3,
		inner_west.enemy_spawn.z
	)
	enemy.position = enemy.home
	message = _playtest_message()


## What the opening heading aims at while the intro hold lasts.
func _playtest_look_target() -> Vector3:
	if inner_west != null:
		var look := inner_west.player_spawn + Vector3(-sin(inner_west.player_yaw), 0.0, -cos(inner_west.player_yaw)) * 60.0
		look.y = InnerWestMesh.height_at(inner_west.height_grid, look.x, look.z) + 6.0
		return look
	return NEWTOWN_LOOK
