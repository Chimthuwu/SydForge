extends CanvasLayer

## Full-screen NOS perception distortion. Follows the player's boost state and
## fades in/out smoothly; the pass is skipped entirely when idle.

const SHADER := preload("res://shaders/nos_distortion.gdshader")

var material: ShaderMaterial
var rect: ColorRect
var player: Node3D
var target := 0.0
var current := 0.0
var pulse := 0.0
var _was_boosting := false


func _ready() -> void:
	layer = 20
	material = ShaderMaterial.new()
	material.shader = SHADER
	rect = ColorRect.new()
	rect.name = "NOSOverlay"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.visible = false


func setup(actor: Node3D) -> void:
	player = actor


func _process(dt: float) -> void:
	var boosting := false
	var fast := false
	if player != null and is_instance_valid(player):
		var car = player.get("vehicle")
		if car != null and is_instance_valid(car):
			boosting = car.get("boost_on") == true
			fast = absf(float(car.get("speed"))) > 18.0
		var board = null
		if player.has_meta("skateboard"):
			board = player.get_meta("skateboard")
		if board != null and is_instance_valid(board):
			boosting = boosting or board.get("boosting") == true
	if boosting:
		if not _was_boosting:
			pulse = 1.0
		target = 1.0
	else:
		target = 0.30 if fast else 0.0
	_was_boosting = boosting
	current = lerpf(current, target, 1.0 - exp(-(6.0 if boosting else 3.0) * dt))
	pulse = maxf(0.0, pulse - dt * 2.6)
	rect.visible = current > 0.01
	if rect.visible:
		material.set_shader_parameter("intensity", current)
		material.set_shader_parameter("pulse", pulse)
