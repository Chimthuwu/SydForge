extends "res://scripts/district.gd"

## SYDNEY PLAYTEST ENTRY POINT — open res://sydney/sydney_test.tscn and press F6.
##
## This scene is the normal game (scripts/district.gd) with the Sydney branch
## switched on, exactly like PLAY_SYDNEY.cmd does with `-- --sydney`. It does not
## replace the main scene, does not touch District Zero, and does not create a
## second player, camera, HUD or interaction system: every one of those is the
## existing BoomPlayer / BoomCamera / HUD built by the parent script.
##
## The additions are:
##   1. `_sydney_requested()` returns true, so F6 loads Sydney with no flags.
##   2. An overridable playtest spawn, look target and HUD line. This scene uses
##      Circular Quay; scripts/sydney_opera_district.gd overrides them for the
##      Opera House forecourt.
##   3. A two-second hold on the opening heading (see INTRO_HOLD).

## Opera House podium centroid in the world projection (Bennelong Point).
const OPERA_HOUSE_XZ := Vector2(658.72, -1763.81)

## Derived footpath vertex on the Circular Quay promenade: on land, more than 3 m
## clear of any building, 439 m west of the Opera House. Chosen from the Stage A
## export with tests/sydney_playtest_test.gd re-checking it at runtime.
const PLAYTEST_SPAWN := Vector3(219.9, 0.3, -1755.7)

## How long the opening heading is held. `district.gd` captures the mouse in
## `_ready`, and the OS cursor jump that follows is delivered as one large
## `InputEventMouseMotion` that `BoomCamera.apply_look` applies, spinning the
## camera away from the landmark. For a couple of seconds the playtest keeps the
## opening heading so the Opera House is framed when the scene starts; control
## is then handed over untouched.
const INTRO_HOLD := 2.0

var _opening_yaw := 0.0
var _opening_pitch := -0.05
var _intro := 0.0


func _sydney_requested() -> bool:
	return true


## Where this entry point starts the player.
func _playtest_spawn() -> Vector3:
	return PLAYTEST_SPAWN


## What the opening heading aims at.
func _playtest_look_target() -> Vector3:
	return Vector3(OPERA_HOUSE_XZ.x, 0.0, OPERA_HOUSE_XZ.y)


## The HUD line shown while walking.
func _playtest_message() -> String:
	return "SYDNEY PLAYTEST · Opera House east along the quay"


func _ready() -> void:
	super()
	if not using_sydney or player == null:
		# The parent already logs the reason and fell back to District Zero.
		return
	var spawn := _playtest_spawn()
	player.spawn = spawn
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	if rig != null:
		var look_target := _playtest_look_target()
		var forward := look_target - spawn
		forward.y = 0.0
		var horizontal_distance := forward.length()
		if horizontal_distance > 0.01:
			forward = forward.normalized()
			# The camera's forward vector for a yaw is (-sin(yaw), 0, -cos(yaw)).
			rig.yaw = atan2(-forward.x, -forward.z)
			rig.pitch = atan2(look_target.y - spawn.y, horizontal_distance)
			_opening_yaw = rig.yaw
			_opening_pitch = rig.pitch
			_intro = 0.0
	message = _playtest_message()


func _process(dt: float) -> void:
	super(dt)
	if rig == null or _intro >= INTRO_HOLD:
		return
	_intro += dt
	rig.yaw = _opening_yaw
	rig.pitch = _opening_pitch
	rig.manual_look_time = 0.0
