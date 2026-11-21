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
##   4. A richer Sydney-specific environment (atmosphere, fog, sun/shadow tuning)
##      layered on top of the shared District Zero defaults.

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


## Sydney-specific presentation: clearer daylight, softer ambient fill, longer
## shadows and light distance haze for depth. This only affects this playtest
## entry point (and subclasses that call super); the canonical CBD scene keeps
## its own environment setup in its modified district script.
func build_environment() -> void:
	super()
	for node in find_children("*", "WorldEnvironment", true, false):
		var world_env := node as WorldEnvironment
		if world_env == null or world_env.environment == null:
			continue
		var env := world_env.environment
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 0.94
		env.tonemap_white = 1.04
		env.ambient_light_energy = 0.5
		env.ambient_light_color = Color("d7e6f2")
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
			sky_mat.sky_top_color = Color("4ea8d8")
			sky_mat.sky_horizon_color = Color("cfe9e2")
			sky_mat.ground_horizon_color = Color("d7e0d2")
			sky_mat.sun_angle_max = 0.8
			sky_mat.sun_curve = 0.12
		env.fog_enabled = true
		env.fog_light_color = Color("8ea0aa")
		env.fog_light_energy = 0.75
		env.fog_density = 0.0009
		env.fog_aerial_perspective = 0.3
		env.fog_sky_affect = 0.12
		env.glow_enabled = true
		env.glow_intensity = 0.22
		env.glow_strength = 0.7
		env.glow_bloom = 0.02
		env.ssao_enabled = false
		env.ssr_enabled = false
	for node in find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sun.light_energy = 1.05
		sun.light_color = Color("ffe8be")
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 260.0
		sun.shadow_bias = 0.03
		break


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
