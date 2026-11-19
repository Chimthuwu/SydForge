class_name WalkaboutController
extends "res://sydney/ecosystem/pedestrian_controller.gd"

## Aboriginal pedestrian walking "walkabout" through the city. Uses the shared
## pedestrian navigation and collision system and asks the player for a dollar
## for the bus when they come close.

const BEG_LINES := [
	"got a dollar for da bus?",
	"any change for the bus?",
	"can you spare a dollar for the bus?",
]

var is_asking: bool = false
var ask_timer: float = 0.0
var ask_label: Label3D
var _ask_cooldown: float = 10.0


func _ready() -> void:
	super()
	walk_speed = randf_range(0.9, 1.4)
	ask_label = Art.label(self, Vector3(0.0, 2.15, 0.0), "", 26)
	ask_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ask_label.modulate = Color("cfe9ff")
	ask_label.visible = false


func _build_visuals() -> void:
	super()
	if body_root == null:
		return
	# Distinguishing outfit: broad-brim hat, light shirt and a walking stick.
	Art.cylinder(body_root, Vector3(0.0, 1.76, 0.0), 0.24, 0.06, Color("6d5836"))
	Art.cylinder(body_root, Vector3(0.0, 1.71, 0.0), 0.13, 0.12, Color("6d5836"))
	Art.box(body_root, Vector3(0.0, 1.05, -0.14), Vector3(0.48, 0.5, 0.06), Color("d9c9a3"))
	var stick := Art.cylinder(body_root, Vector3(0.42, 0.72, 0.05), 0.025, 1.5, Color("6b4a2b"))
	stick.rotation.z = 0.08


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_ask_cooldown = maxf(0.0, _ask_cooldown - delta)
	if is_asking:
		ask_timer -= delta
		if ask_timer <= 0.0:
			is_asking = false
			ask_label.visible = false
			_ask_cooldown = randf_range(18.0, 30.0)
			is_waiting = false
			_pick_next_target()
		_animate_walking(0.0, delta)
		return
	if _player != null and _ask_cooldown <= 0.0:
		var distance := global_position.distance_to(_player.global_position)
		if distance < 8.0 and distance > 1.5:
			_begin_ask()
			return
	super(delta)


func _begin_ask() -> void:
	is_asking = true
	ask_timer = randf_range(4.0, 6.5)
	is_waiting = true
	ask_label.text = BEG_LINES[randi() % BEG_LINES.size()]
	ask_label.visible = true
	if _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			rotation.y = atan2(-to_player.x, -to_player.z)
