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
var explosion_root: Node3D
var explosion_light: OmniLight3D
var _explosion_time: float = 0.0
const EXPLOSION_DURATION := 2.6


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


func play_explosion() -> void:
	if explosion_root != null:
		return
	_explosion_time = EXPLOSION_DURATION
	explosion_root = Node3D.new()
	explosion_root.name = "VehicleExplosion"
	parent.add_child(explosion_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	var flame_colors := [Color("fff2a8"), Color("ffb02e"), Color("e0431a"), Color("8c1f12")]
	for index in 26:
		var fragment := MeshInstance3D.new()
		var flame := SphereMesh.new()
		flame.radius = rng.randf_range(0.18, 0.52)
		flame.height = flame.radius * 2.0
		flame.radial_segments = 8
		flame.rings = 4
		fragment.mesh = flame
		var mat := StandardMaterial3D.new()
		mat.albedo_color = flame_colors[index % flame_colors.size()]
		mat.emission_enabled = true
		mat.emission = flame_colors[index % flame_colors.size()]
		mat.emission_energy_multiplier = 2.4
		fragment.material_override = mat
		explosion_root.add_child(fragment)
		var direction := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.1, 1.4),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var distance := rng.randf_range(0.8, 3.4)
		var flight := rng.randf_range(0.4, 1.1)
		var start := fragment.position
		var finish := start + direction * distance + Vector3.DOWN * 0.4
		var tween := explosion_root.create_tween()
		tween.parallel().tween_property(fragment, "position", finish, flight)
		tween.parallel().tween_property(fragment, "scale", Vector3.ZERO, flight + 0.4)
		tween.tween_callback(fragment.queue_free)
	explosion_light = OmniLight3D.new()
	explosion_light.name = "ExplosionLight"
	explosion_light.light_color = Color("ff8a32")
	explosion_light.light_energy = 9.0
	explosion_light.omni_range = 22.0
	explosion_light.shadow_enabled = false
	explosion_root.add_child(explosion_light)


func update(dt: float, car: ArcadeCar) -> void:
	if _explosion_time > 0.0:
		_explosion_time = maxf(0.0, _explosion_time - dt)
		if explosion_light != null and is_instance_valid(explosion_light):
			explosion_light.light_energy = 9.0 * (_explosion_time / EXPLOSION_DURATION)
		if _explosion_time <= 0.0 and explosion_root != null and is_instance_valid(explosion_root):
			explosion_root.queue_free()
			explosion_root = null
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
