class_name HomelessController
extends "res://sydney/ecosystem/pedestrian_controller.gd"

## Homeless / street-person pedestrian found around the CBD. Reuses navigation,
## vehicle collision and gore from PedestrianController. Adds street behaviours:
## smoking a cigarette, public urination, and huffing petrol (with a dizzy
## wobble). All are harmless presentation animations, not interactions.

enum StreetBehaviour { WANDER, SMOKE, URINATE, PETROL }

var behaviour: int = StreetBehaviour.WANDER
var behaviour_timer: float = 0.0
var behaviour_label: Label3D
var cigarette: MeshInstance3D
var petrol_bag: MeshInstance3D


func _ready() -> void:
	super()
	walk_speed = randf_range(0.7, 1.2)
	behaviour_label = Art.label(self, Vector3(0.0, 2.15, 0.0), "", 24)
	behaviour_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	behaviour_label.modulate = Color("d8d2b8")
	behaviour_label.visible = false
	_pick_behaviour()


func _build_visuals() -> void:
	super()
	if body_root == null:
		return
	# Layered worn clothing, beanie and a sleeping roll on the back.
	Art.box(body_root, Vector3(0.0, 1.16, -0.13), Vector3(0.5, 0.38, 0.08), Color("6e6250"))
	Art.box(body_root, Vector3(0.0, 1.72, 0.0), Vector3(0.28, 0.12, 0.28), Color("4a4034"))
	Art.cylinder(body_root, Vector3(0.0, 1.82, 0.0), 0.11, 0.1, Color("7d705c"))
	Art.cylinder(body_root, Vector3(0.0, 0.65, 0.2), 0.14, 0.8, Color("8b7a5f")).rotation.z = PI * 0.5
	cigarette = Art.box(body_root, Vector3(0.18, 1.35, -0.16), Vector3(0.02, 0.02, 0.14), Color("e8d2a0"))
	cigarette.visible = false
	petrol_bag = Art.box(body_root, Vector3(0.2, 0.9, -0.18), Vector3(0.16, 0.22, 0.12), Color("c8c0a0"))
	petrol_bag.visible = false


func _pick_behaviour() -> void:
	var roll := randf()
	if roll < 0.22:
		behaviour = StreetBehaviour.SMOKE
	elif roll < 0.36:
		behaviour = StreetBehaviour.URINATE
	elif roll < 0.52:
		behaviour = StreetBehaviour.PETROL
	else:
		behaviour = StreetBehaviour.WANDER
	behaviour_timer = randf_range(5.0, 12.0)
	cigarette.visible = behaviour == StreetBehaviour.SMOKE
	petrol_bag.visible = behaviour == StreetBehaviour.PETROL
	behaviour_label.text = ["", "ciggie?", "…", "gonna have a huff…"][behaviour]
	behaviour_label.visible = behaviour in [StreetBehaviour.SMOKE, StreetBehaviour.PETROL]
	is_waiting = behaviour != StreetBehaviour.WANDER


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if behaviour != StreetBehaviour.WANDER:
		behaviour_timer -= delta
		if behaviour == StreetBehaviour.URINATE:
			body_root.rotation.x = lerpf(body_root.rotation.x, 0.12, delta * 4.0)
		elif behaviour == StreetBehaviour.PETROL:
			body_root.rotation.x = -0.35 + sin(Time.get_ticks_msec() * 0.004) * 0.05
		if behaviour_timer <= 0.0:
			body_root.rotation.x = 0.0
			behaviour = StreetBehaviour.WANDER
			is_waiting = false
			behaviour_label.visible = false
			cigarette.visible = false
			petrol_bag.visible = false
			_pick_next_target()
		_animate_walking(0.0, delta)
		return
	super(delta)
	if randf() < delta * 0.02:
		_pick_behaviour()
