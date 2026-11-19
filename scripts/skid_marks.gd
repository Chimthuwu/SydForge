class_name SkidMarks
extends RefCounted

## Dedicated, pooled tyre-mark system attached to every ArcadeCar.
##
## * Marks are placed at the car's rear axle (both sides), so the trail
##   matches the actual tyre path of the vehicle.
## * Bounded: exactly `POOL_SIZE` meshes per vehicle; marks recycle when the
##   pool is busy, so a long powerslide can't grow the node count.
## * Marks fade out over FADE_SECONDS while the car keeps sliding; alpha
##   scales with slip intensity.
## * Marks are placed slightly behind the axle relative to the car's
##   velocity so the trail reads like a continuous path.
## * Invisible marks are hidden (not deleted) — zero draw cost when not
##   sliding.

const POOL_SIZE := 12
const SPAN := 2.8          # mark length, along the axle
const WIDTH := 0.55        # mark width (tyre contact patch)
const FADE_SECONDS := 0.9
const SLIDE_SPAWN_MIN := 3.0

var car: ArcadeCar
var parent: Node3D
var pool: Array[MeshInstance3D]


func _init(owner: ArcadeCar) -> void:
	car = owner
	parent = owner.body_art
	for _i in POOL_SIZE:
		var mark := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(SPAN, WIDTH)
		mark.mesh = plane
		mark.material_override = _material()
		mark.rotation = Vector3(-PI/2, 0.0, 0.0)
		parent.add_child(mark)
		mark.visible = false
		_set_alpha(mark, 0.0)
		pool.append(mark)


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = car.paint.darkened(0.42)
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## MeshInstance3D has no CanvasItem modulate, so skid fade lives in the
## per-mark material's alpha instead.
func _alpha_of(mark: MeshInstance3D) -> float:
	var material := mark.material_override as StandardMaterial3D
	return material.albedo_color.a if material != null else 1.0


func _set_alpha(mark: MeshInstance3D, alpha: float) -> void:
	var material := mark.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = alpha


func update(dt: float, car: ArcadeCar) -> void:
	var lat := car.lateral_speed
	if absf(lat) > SLIDE_SPAWN_MIN:
		var alpha := clampf(0.8+absf(lat)/14.0, 0.85, 1.0)
		var back := car.global_position + car.global_basis*Vector3(0.0, 0.46, -2.06)
		var drift := car.velocity*0.22
		place(back + car.global_basis.x*(-0.95) - drift, alpha)
		place(back + car.global_basis.x*(0.95) - drift, alpha)
	for mark in pool:
		if mark.visible:
			var faded := _alpha_of(mark) - dt/FADE_SECONDS
			if faded <= 0.0:
				mark.visible = false
				_set_alpha(mark, 0.0)
			else:
				_set_alpha(mark, faded)


func place(origin: Vector3, alpha: float) -> void:
	var target: MeshInstance3D = null
	for mark in pool:
		if not mark.visible:
			target = mark
			break
	if target == null:
		var lowest: float = _alpha_of(pool[0])
		target = pool[0]
		for mark in pool:
			if _alpha_of(mark) < lowest:
				target = mark
				lowest = _alpha_of(mark)
	target.position = origin
	_set_alpha(target, maxf(alpha, 0.12))
	target.visible = true


func is_any_visible() -> bool:
	for mark in pool:
		if mark.visible:
			return true
	return false
