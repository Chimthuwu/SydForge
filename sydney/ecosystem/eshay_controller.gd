class_name EshayController
extends "res://sydney/ecosystem/pedestrian_controller.gd"

## Sydney "Eshay" local character. Uses the pedestrian navigation, collision and
## gore implementation from PedestrianController, but dresses like a stereotypical
## eshay and periodically stops to ask the player for a cigarette.

const BEG_LINES := [
	"got a ciggie bro?",
	"got a smoke?",
	"spare a ciggie?",
	"got a durry?",
]

var is_begging: bool = false
var beg_timer: float = 0.0
var beg_label: Label3D
var _beg_cooldown: float = 8.0


func _ready() -> void:
	super()
	walk_speed = randf_range(1.1, 1.7)
	beg_label = Art.label(self, Vector3(0.0, 2.15, 0.0), "", 26)
	beg_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	beg_label.modulate = Color("ffe7a8")
	beg_label.visible = false


func _build_visuals() -> void:
	super()
	if body_root == null:
		return
	# Distinct eshay silhouette: loud cap, oversized jacket and track pants.
	var cap_colors := [Color("c0392b"), Color("2c3e50"), Color("8e44ad"), Color("d35400")]
	var cap_col: Color = cap_colors[randi() % cap_colors.size()]
	Art.box(body_root, Vector3(0.0, 1.72, 0.0), Vector3(0.3, 0.12, 0.3), cap_col)
	Art.box(body_root, Vector3(0.0, 1.68, -0.2), Vector3(0.26, 0.04, 0.18), cap_col)
	Art.box(body_root, Vector3(0.0, 1.12, -0.13), Vector3(0.5, 0.42, 0.06), Color("c8c8c0"))
	var chain := Art.cylinder(body_root, Vector3(0.0, 1.02, -0.17), 0.02, 0.3, Color("d4af37"))
	chain.rotation.z = PI * 0.5


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_beg_cooldown = maxf(0.0, _beg_cooldown - delta)
	if is_begging:
		beg_timer -= delta
		if beg_timer <= 0.0:
			is_begging = false
			beg_label.visible = false
			_beg_cooldown = randf_range(14.0, 26.0)
			is_waiting = false
			_pick_next_target()
		_animate_walking(0.0, delta)
		return
	if _player != null and _beg_cooldown <= 0.0:
		var distance := global_position.distance_to(_player.global_position)
		if distance < 7.0 and distance > 1.5:
			_begin_beg()
			return
	super(delta)


func _begin_beg() -> void:
	is_begging = true
	beg_timer = randf_range(3.5, 6.0)
	is_waiting = true
	beg_label.text = BEG_LINES[randi() % BEG_LINES.size()]
	beg_label.visible = true
	if _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			rotation.y = atan2(-to_player.x, -to_player.z)
