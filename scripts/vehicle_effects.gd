class_name VehicleEffects
extends RefCounted

## Visual effects for ArcadeCars, built from primitives so no new textures or
## assets are needed. Covers: NOS exhaust glow, drifting smoke, brake flash.

var car: ArcadeCar
var parent: Node3D
var exhaust: Array[MeshInstance3D]        # 3 orange flame boxes at the tail
var tail_glow: OmniLight3D               # soft glow near the tail
var drift_smoke: MeshInstance3D           # puff behind the rear axle
var brake_flash: OmniLight3D             # bright amber when braking


func _init(owner: ArcadeCar) -> void:
	car = owner
	parent = owner.body_art
	## Exhaust flare at the car's rear (-Z of the body).
	exhaust = []
	for i in 3:
		var flame := Art.box(parent, Vector3(0.0, 0.0, 2.1+0.05*i), Vector3(0.3, 0.12, 0.12), Color("ffe578"))
		flame.visible = false
		exhaust.append(flame)
	## Tail glow.
	tail_glow = OmniLight3D.new()
	tail_glow.name = "BoostTailGlow"
	tail_glow.position = Vector3(0.0, 0.0, 2.15)
	tail_glow.light_color = Color("fff0d0")
	tail_glow.light_energy = 3.0
	tail_glow.omni_range = 14.0
	tail_glow.visible = false
	parent.add_child(tail_glow)
	## Drift smoke puff behind the rear axle.
	drift_smoke = Art.box(parent, Vector3(0.0, -0.3, 1.9), Vector3(0.9, 0.5, 0.35), Color("b0a090"))
	drift_smoke.material_override = _smoke_material()
	drift_smoke.visible = false
	## Brake flash: amber light near the cabin.
	brake_flash = OmniLight3D.new()
	brake_flash.name = "BrakeFlash"
	brake_flash.light_color = Color("ffd06e")
	brake_flash.omni_range = 6.0
	brake_flash.position = Vector3(0.0, 0.2, -1.35)
	parent.add_child(brake_flash)
	brake_flash.visible = false


func update(dt: float, car: ArcadeCar) -> void:
	## Exhaust: brightened pulse during boost, dim when off.
	var on := car.boost_on and car.driver != null
	for flame in exhaust:
		flame.visible = on
	if on:
		var now := Time.get_ticks_msec()
		for flame in exhaust:
			flame.scale = Vector3(0.92+0.3*sin(now*0.0008), 1.0, 1.0)
	else:
		for flame in exhaust:
			flame.scale = Vector3.ONE
	tail_glow.visible = on
	if on:
		tail_glow.light_energy = lerpf(tail_glow.light_energy, 6.5, 0.18)
	else:
		tail_glow.light_energy = move_toward(tail_glow.light_energy, 0.0, dt*10.0)
	## Drift smoke during handbrake slides.
	var slide := car.handbrake and absf(car.lateral_speed) > 6.0
	drift_smoke.visible = slide
	if slide:
		var dense := clampf(absf(car.lateral_speed)/10.0, 0.0, 1.0)
		drift_smoke.material_override.albedo_color.a = 0.25+0.6*dense


func _smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c8b8a2", 0.25)
	material.roughness = 0.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func play_brake_flash(braking: bool, dt: float) -> void:
	if braking:
		brake_flash.visible = true
		brake_flash.light_energy = move_toward(brake_flash.light_energy, 5.0, dt*18.0)
	else:
		brake_flash.light_energy = move_toward(brake_flash.light_energy, 0.0, dt*8.0)
		if brake_flash.light_energy <= 0.03:
			brake_flash.visible = false
