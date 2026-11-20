class_name EshayController
extends "res://sydney/ecosystem/pedestrian_controller.gd"

## Sydney "Eshay" local character. Uses the pedestrian navigation, collision and
## gore implementation from PedestrianController, but dresses like a stereotypical
## eshay and aggressively demands durries from the player, then attacks.

const HOSTILE_LINES := [
	"Give us a durry brah!",
	"Give us a durry ya dog cunt!",
	"Hand over the durries cunt!",
	"Oi cunt, got a durry or what?",
	"Gimme a smoke ya grub!",
	"Fork over the durries brah!",
]

const ATTACK_LINES := [
	"Take that ya dog!",
	"Fark off cunt!",
	"Get wrecked brah!",
	"Stay down ya grub!",
]

var is_hostile: bool = false
var hostile_timer: float = 0.0
var attack_cooldown: float = 0.0
var hostile_label: Label3D
var _hostile_cooldown: float = 8.0
var _player_ref: Node3D

func _ready() -> void:
	super()
	walk_speed = randf_range(1.3, 1.9)  # Slightly faster, more aggressive
	hostile_label = Art.label(self, Vector3(0.0, 2.15, 0.0), "", 28)
	hostile_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hostile_label.modulate = Color("ff4444")  # Red for hostility
	hostile_label.visible = false
	_player_ref = get_tree().get_first_node_in_group("player") as Node3D

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
	
	# Update cooldowns
	_hostile_cooldown = maxf(0.0, _hostile_cooldown - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	
	if _player_ref == null:
		_player_ref = get_tree().get_first_node_in_group("player") as Node3D
	
	if is_hostile:
		hostile_timer -= delta
		# Chase and attack the player
		if _player_ref != null:
			var to_player := _player_ref.global_position - global_position
			var dist := to_player.length()
			to_player.y = 0.0
			
			if to_player.length_squared() > 0.01:
				rotation.y = atan2(-to_player.x, -to_player.z)
			
			# Melee attack when close
			if dist < 2.0 and attack_cooldown <= 0.0:
				_attack_player()
				attack_cooldown = 1.2
				return
			
			# Chase player
			if dist < 15.0:
				var fwd := to_player.normalized()
				velocity.x = fwd.x * walk_speed * 1.5
				velocity.z = fwd.z * walk_speed * 1.5
				velocity.y -= 9.8 * delta
				move_and_slide()
				_animate_walking(walk_speed * 1.5, delta)
			else:
				# Lost the player, calm down
				is_hostile = false
				hostile_label.visible = false
				_hostile_cooldown = randf_range(20.0, 35.0)
				_pick_next_target()
		else:
			is_hostile = false
			hostile_label.visible = false
		return
	
	# Not hostile - look for player to harass
	if _player_ref != null and _hostile_cooldown <= 0.0:
		var distance := global_position.distance_to(_player_ref.global_position)
		if distance < 8.0 and distance > 1.5:
			_begin_hostile()
			return
	
	super(delta)

func _begin_hostile() -> void:
	is_hostile = true
	hostile_timer = randf_range(8.0, 15.0)
	is_waiting = true
	hostile_label.text = HOSTILE_LINES[randi() % HOSTILE_LINES.size()]
	hostile_label.visible = true
	if _player_ref != null:
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			rotation.y = atan2(-to_player.x, -to_player.z)

func _attack_player() -> void:
	if _player_ref == null or not _player_ref.has_method("take_damage"):
		return
	
	# Show attack line
	hostile_label.text = ATTACK_LINES[randi() % ATTACK_LINES.size()]
	
	# Deal melee damage to player (12 damage like the enemy melee)
	_player_ref.call("take_damage", 12.0)
	
	# Visual feedback - brief screen flash or knockback could be added here
	# For now, just the damage call
	
	# Play a sound if audio director exists
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null:
		audio.play_impact("flesh", global_position + Vector3.UP * 1.5)