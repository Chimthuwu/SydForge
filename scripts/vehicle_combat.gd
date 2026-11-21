extends RefCounted

## Weapon damage, escalating visual feedback, wrecks and area damage for ArcadeCar.
## Pure presentation + damage dispatch; no traffic or driving logic is changed.

const MAX_EXPLOSION_RADIUS := 14.0
const MAX_EXPLOSION_DAMAGE := 110.0
const CHAIN_DAMAGE_SCALE := 0.35

var car: ArcadeCar
var stage: int = 0  # 0 clean, 1 sparks, 2 smoke, 3 fire
var wreck: Node3D
var wreck_light: OmniLight3D
var _smoke: Array[MeshInstance3D] = []
var _fire: Array[MeshInstance3D] = []
var _time := 0.0
var _exploding := false

static var _recent_explosions: Dictionary = {}


func _init(owner: ArcadeCar) -> void:
	car = owner


func apply_damage(amount: float, impact_position: Vector3 = Vector3.INF) -> void:
	if car.destroyed or car.health <= 0.0 or _exploding:
		return
	car.health = maxf(0.0, car.health - amount)
	_update_stage()
	if impact_position != Vector3.INF and stage >= 1:
		_spawn_sparks(impact_position)
	if car.health <= 0.0:
		explode()


func _update_stage() -> void:
	var ratio := car.health / maxf(car.max_health, 1.0)
	var next := 0
	if ratio < 0.30:
		next = 3
	elif ratio < 0.60:
		next = 2
	elif ratio < 0.85:
		next = 1
	if next <= stage:
		return
	stage = next
	if stage == 1:
		car.vehicle_name = car.vehicle_name  # keep identity; no visual change yet
	elif stage == 2:
		_add_smoke()
	elif stage == 3:
		_add_smoke()
		_add_fire()


func _add_smoke() -> void:
	if body() == null:
		return
	for i in 2:
		var puff := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		s.radial_segments = 6
		s.rings = 3
		puff.mesh = s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("383838", 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = m
		body().add_child(puff)
		puff.position = Vector3(randf_range(-0.4, 0.4), 1.2, -1.0 + randf_range(-0.3, 0.3))
		_smoke.append(puff)


func _add_fire() -> void:
	if body() == null:
		return
	for i in 3:
		var flame := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.22
		s.height = 0.5
		s.radial_segments = 6
		s.rings = 3
		flame.mesh = s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("ff7a18")
		m.emission_enabled = true
		m.emission = Color("ff5510")
		m.emission_energy_multiplier = 2.5
		flame.material_override = m
		body().add_child(flame)
		flame.position = Vector3(randf_range(-0.5, 0.5), 1.0 + randf_range(0.0, 0.5), randf_range(-1.5, 0.5))
		_fire.append(flame)


func _spawn_sparks(pos: Vector3) -> void:
	if body() == null:
		return
	var spark := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.08
	s.height = 0.16
	spark.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ffd86b")
	m.emission_enabled = true
	m.emission = Color("ffae32")
	m.emission_energy_multiplier = 3.0
	spark.material_override = m
	car.get_parent().add_child(spark)
	spark.global_position = pos
	var t := spark.create_tween()
	t.parallel().tween_property(spark, "global_position", pos + Vector3(randf_range(-1, 1), randf_range(1, 2), randf_range(-1, 1)), 0.35)
	t.parallel().tween_property(spark, "scale", Vector3.ZERO, 0.4)
	t.tween_callback(spark.queue_free)


func explode() -> void:
	if _exploding or car.destroyed:
		return
	_exploding = true
	_recent_explosions[car.get_instance_id()] = Time.get_ticks_msec()
	var pos: Vector3 = car.global_position + Vector3.UP * 1.0
	if car.effects != null:
		car.effects.play_explosion()
	_play_sound(pos)
	_area_damage(pos)
	_make_wreck()
	car.destroyed = true
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.collision_layer = 0
	car.collision_mask = 0
	if car.driver != null:
		car.driver.respawn()


func _make_wreck() -> void:
	if body() == null:
		return
	wreck = Node3D.new()
	wreck.name = "Wreck"
	car.add_child(wreck)
	# The existing body art stays as the scorched shell.
	body().rotation.z = randf_range(-0.25, 0.25)
	body().position.y -= 0.15
	for mesh in body().find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var src := mi.material_override as StandardMaterial3D
			var burnt := StandardMaterial3D.new()
			burnt.albedo_color = src.albedo_color.darkened(0.72)
			burnt.roughness = 0.95
			mi.material_override = burnt
	# Persistent smoke column from the wreck.
	for i in 3:
		var puff := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.3 + float(i) * 0.1
		s.height = 0.7
		puff.mesh = s
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("2c2c2c", 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = m
		wreck.add_child(puff)
		puff.position = Vector3(randf_range(-0.4, 0.4), 1.0 + float(i) * 0.5, randf_range(-0.4, 0.4))
		_smoke.append(puff)
	wreck_light = OmniLight3D.new()
	wreck_light.light_color = Color("ff5a18")
	wreck_light.light_energy = 2.0
	wreck_light.omni_range = 7.0
	wreck_light.shadow_enabled = false
	wreck.add_child(wreck_light)
	wreck_light.position = Vector3(0, 1.0, 0)


func _area_damage(center: Vector3) -> void:
	var tree := car.get_tree()
	if tree == null:
		return
	var now := Time.get_ticks_msec()
	for other in tree.get_nodes_in_group("vehicles"):
		if not is_instance_valid(other) or other == car:
			continue
		if _recent_explosions.has(other.get_instance_id()):
			var t: int = int(_recent_explosions[other.get_instance_id()])
			if now - t < 1500:
				continue
		var oc := other as ArcadeCar
		if oc == null or oc.destroyed:
			continue
		var d := oc.global_position.distance_to(center)
		if d > MAX_EXPLOSION_RADIUS:
			continue
		var dmg := MAX_EXPLOSION_DAMAGE * (1.0 - d / MAX_EXPLOSION_RADIUS) * CHAIN_DAMAGE_SCALE
		if oc.has_method("take_explosion_damage"):
			oc.call("take_explosion_damage", dmg)
	for target in tree.get_nodes_in_group("pedestrians"):
		if not is_instance_valid(target):
			continue
		var npc := target as Node3D
		var d := npc.global_position.distance_to(center)
		if d > MAX_EXPLOSION_RADIUS:
			continue
		var dmg := MAX_EXPLOSION_DAMAGE * (1.0 - d / MAX_EXPLOSION_RADIUS)
		if npc.has_method("take_damage_at"):
			npc.call("take_damage_at", dmg, center, 1.5, (npc.global_position - center).normalized())
		elif npc.has_method("take_damage"):
			npc.call("take_damage", dmg)
	var player := tree.get_first_node_in_group("player") as Node3D
	if player != null and player.has_method("take_damage"):
		var d := player.global_position.distance_to(center)
		if d < MAX_EXPLOSION_RADIUS:
			player.call("take_damage", MAX_EXPLOSION_DAMAGE * (1.0 - d / MAX_EXPLOSION_RADIUS) * 0.6)


func _play_sound(pos: Vector3) -> void:
	var tree := car.get_tree()
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioDirector")
	if audio == null:
		return
	if audio != null and audio.has_method("play_explosion"):
		audio.call("play_explosion", pos)


func reset() -> void:
	stage = 0
	_exploding = false
	if wreck != null and is_instance_valid(wreck):
		wreck.queue_free()
	wreck = null
	wreck_light = null
	_smoke.clear()
	_fire.clear()
	body().rotation.z = 0.0
	body().position.y = 0.0


func update(dt: float) -> void:
	_time += dt
	for puff in _smoke:
		if is_instance_valid(puff):
			puff.position.y += dt * 0.8
			var m := puff.material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = maxf(0.0, m.albedo_color.a - dt * 0.12)
	for flame in _fire:
		if is_instance_valid(flame):
			var s := 0.9 + 0.3 * sin(_time * 12.0 + flame.position.x * 5.0)
			flame.scale = Vector3(s, s * 1.4, s)
	if wreck_light != null and is_instance_valid(wreck_light):
		wreck_light.light_energy = 1.6 + 0.6 * sin(_time * 9.0)


func body() -> Node3D:
	return car.body_art
