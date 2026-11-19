class_name BoomCamera
extends Node3D

var yaw: float = 0.0
var pitch: float = -0.18
var camera: Camera3D
var arm: SpringArm3D
var target: BoomPlayer
var manual_look_time: float = 0.0
var recoil: float = 0.0
var weapon_mount: Node3D
var shotgun_mount: Node3D
var muzzle_flash: MeshInstance3D
var muzzle_light: OmniLight3D
var shotgun_muzzle_flash: MeshInstance3D
var shotgun_muzzle_light: OmniLight3D
var muzzle_time: float = 0.0

func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 0.0
	arm.margin = 0.08
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	arm.shape = shape
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 68
	# The unified scene spans several kilometres. Keep a useful skyline view
	# while avoiding the worst far-depth precision/shimmer at the horizon.
	camera.near = 0.2
	camera.far = 2800.0
	arm.add_child(camera)
	camera.current = true
	arm.add_excluded_object(target.get_rid())
	global_position = target.global_position+Vector3(0,1.62,0)
	_build_first_person_weapon()
	_build_first_person_shotgun()


func _build_first_person_weapon() -> void:
	weapon_mount = Node3D.new()
	weapon_mount.name = "FirstPersonPistol"
	weapon_mount.position = Vector3(0.0, 0.0, 0.0)
	camera.add_child(weapon_mount)

	# Procedural service-pistol silhouette: separate steel slide, polymer frame,
	# angled textured grip, iron sights, controls, trigger guard and exposed barrel.
	_weapon_box(Vector3(0.28, -0.235, -0.79), Vector3(0.145, 0.105, 0.43), Color("343d45"))
	_weapon_box(Vector3(0.28, -0.296, -0.70), Vector3(0.13, 0.045, 0.31), Color("20272e"))
	_weapon_box(Vector3(0.28, -0.338, -0.69), Vector3(0.105, 0.028, 0.22), Color("151a20"))
	var grip := _weapon_box(Vector3(0.28, -0.405, -0.59), Vector3(0.112, 0.235, 0.155), Color("20262b"))
	grip.rotation.x = -0.19
	var grip_panel := _weapon_box(Vector3(0.354, -0.408, -0.59), Vector3(0.018, 0.17, 0.135), Color("30373b"))
	grip_panel.rotation.x = -0.19
	for groove in 7:
		_weapon_box(Vector3(0.365, -0.35 - groove * 0.018, -0.645), Vector3(0.009, 0.006, 0.105), Color("171c20"))
	_weapon_box(Vector3(0.28, -0.527, -0.57), Vector3(0.135, 0.025, 0.17), Color("3b4348"))

	# Slide bevels, ejection port, serrations and controls.
	_weapon_box(Vector3(0.28, -0.178, -0.79), Vector3(0.12, 0.012, 0.36), Color("58636b"))
	_weapon_box(Vector3(0.357, -0.218, -0.72), Vector3(0.009, 0.045, 0.105), Color("11171c"))
	_weapon_box(Vector3(0.363, -0.216, -0.72), Vector3(0.004, 0.025, 0.064), Color("758087"))
	for groove in 8:
		_weapon_box(Vector3(0.357, -0.235, -0.955 + groove * 0.022), Vector3(0.012, 0.058, 0.008), Color("171d22"))
	_weapon_box(Vector3(0.365, -0.274, -0.62), Vector3(0.018, 0.018, 0.075), Color("8a969c"))
	_weapon_box(Vector3(0.358, -0.324, -0.77), Vector3(0.02, 0.032, 0.055), Color("525b60"))
	_weapon_box(Vector3(0.28, -0.253, -0.565), Vector3(0.11, 0.032, 0.02), Color("343b40"))

	# Barrel opening and the two simple iron sights.
	_weapon_cylinder(Vector3(0.28, -0.23, -1.018), 0.035, 0.105, Color("12171b"))
	_weapon_cylinder(Vector3(0.28, -0.23, -1.075), 0.019, 0.018, Color("080b0e"))
	_weapon_box(Vector3(0.28, -0.167, -0.973), Vector3(0.052, 0.022, 0.04), Color("171d22"))
	_weapon_box(Vector3(0.28, -0.161, -0.973), Vector3(0.012, 0.006, 0.018), Color("e5e7dd"))
	_weapon_box(Vector3(0.28, -0.162, -0.59), Vector3(0.07, 0.026, 0.045), Color("171d22"))
	_weapon_box(Vector3(0.255, -0.147, -0.59), Vector3(0.012, 0.006, 0.014), Color("11161a"))
	_weapon_box(Vector3(0.305, -0.147, -0.59), Vector3(0.012, 0.006, 0.014), Color("11161a"))

	# Trigger bow and trigger sit below the frame, clear of the grip.
	var guard_top := _weapon_box(Vector3(0.28, -0.327, -0.675), Vector3(0.018, 0.018, 0.14), Color("858e92"))
	guard_top.rotation.x = 0.1
	_weapon_box(Vector3(0.28, -0.392, -0.70), Vector3(0.018, 0.015, 0.12), Color("858e92"))
	var guard_front := _weapon_box(Vector3(0.28, -0.36, -0.755), Vector3(0.018, 0.06, 0.015), Color("858e92"))
	guard_front.rotation.x = -0.12
	_weapon_box(Vector3(0.28, -0.36, -0.695), Vector3(0.012, 0.045, 0.018), Color("b6bdbe"))

	muzzle_flash = MeshInstance3D.new()
	muzzle_flash.name = "MuzzleFlash"
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.09
	flash_mesh.height = 0.18
	muzzle_flash.mesh = flash_mesh
	muzzle_flash.position = Vector3(0.28, -0.18, -1.11)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color("fff0a0")
	flash_material.emission_enabled = true
	flash_material.emission = Color("ffb32e")
	flash_material.emission_energy_multiplier = 3.0
	muzzle_flash.material_override = flash_material
	muzzle_flash.visible = false
	weapon_mount.add_child(muzzle_flash)

	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleLight"
	muzzle_light.position = muzzle_flash.position
	muzzle_light.light_color = Color("ffb65c")
	muzzle_light.light_energy = 1.4
	muzzle_light.omni_range = 3.0
	muzzle_light.visible = false
	weapon_mount.add_child(muzzle_light)

func _build_first_person_shotgun() -> void:
	shotgun_mount = Node3D.new()
	shotgun_mount.name = "FirstPersonPumpShotgun"
	camera.add_child(shotgun_mount)
	_shotgun_box(Vector3(0.30,-0.30,-0.64),Vector3(0.13,0.14,0.31),Color("30383e"))
	_shotgun_box(Vector3(0.30,-0.38,-0.47),Vector3(0.12,0.23,0.16),Color("242a2e"))
	_shotgun_box(Vector3(0.30,-0.50,-0.45),Vector3(0.145,0.035,0.18),Color("42494d"))
	_shotgun_box(Vector3(0.30,-0.32,-0.43),Vector3(0.12,0.10,0.20),Color("11171b"))
	# Long blued-steel barrel and magazine tube.
	_shotgun_cylinder(Vector3(0.30,-0.235,-1.02),0.034,0.83,Color("171d22"))
	_shotgun_cylinder(Vector3(0.235,-0.305,-0.98),0.026,0.69,Color("283139"))
	_shotgun_cylinder(Vector3(0.30,-0.235,-1.445),0.022,0.02,Color("080b0e"))
	# Ribbed pump fore-end, receiver controls, and top sight rib.
	_shotgun_box(Vector3(0.30,-0.32,-1.00),Vector3(0.16,0.105,0.28),Color("262b2d"))
	for rib in 6:
		_shotgun_box(Vector3(0.385,-0.32,-1.105 + rib * 0.043),Vector3(0.012,0.012,0.014),Color("0f1316"))
	_shotgun_box(Vector3(0.30,-0.168,-1.00),Vector3(0.045,0.018,0.77),Color("303940"))
	_shotgun_box(Vector3(0.38,-0.29,-0.67),Vector3(0.018,0.04,0.09),Color("68747a"))
	_shotgun_box(Vector3(0.388,-0.295,-0.65),Vector3(0.012,0.018,0.038),Color("10161a"))
	# Bead sight, trigger guard and a textured recoil pad.
	_shotgun_box(Vector3(0.30,-0.15,-1.42),Vector3(0.035,0.025,0.035),Color("e6dfc3"))
	_shotgun_box(Vector3(0.30,-0.39,-0.68),Vector3(0.018,0.018,0.13),Color("858e92"))
	_shotgun_box(Vector3(0.30,-0.45,-0.68),Vector3(0.018,0.015,0.12),Color("858e92"))
	_shotgun_box(Vector3(0.30,-0.42,-0.735),Vector3(0.018,0.055,0.015),Color("858e92"))
	_shotgun_box(Vector3(0.30,-0.38,-0.30),Vector3(0.14,0.18,0.035),Color("15191c"))
	for line in 5:
		_shotgun_box(Vector3(0.30,-0.45 + line * 0.035,-0.278),Vector3(0.11,0.008,0.008),Color("4c555a"))

	shotgun_muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.13
	flash_mesh.height = 0.24
	shotgun_muzzle_flash.mesh = flash_mesh
	shotgun_muzzle_flash.position = Vector3(0.30,-0.235,-1.49)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color("fff0a0")
	flash_material.emission_enabled = true
	flash_material.emission = Color("ff8f32")
	flash_material.emission_energy_multiplier = 4.0
	shotgun_muzzle_flash.material_override = flash_material
	shotgun_muzzle_flash.visible = false
	shotgun_mount.add_child(shotgun_muzzle_flash)
	shotgun_muzzle_light = OmniLight3D.new()
	shotgun_muzzle_light.position = shotgun_muzzle_flash.position
	shotgun_muzzle_light.light_color = Color("ff9e43")
	shotgun_muzzle_light.light_energy = 2.0
	shotgun_muzzle_light.omni_range = 4.0
	shotgun_muzzle_light.visible = false
	shotgun_mount.add_child(shotgun_muzzle_light)

func _shotgun_box(at: Vector3, dimensions: Vector3, tint: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	part.mesh = box
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.42
	material.roughness = 0.48
	part.material_override = material
	shotgun_mount.add_child(part)
	return part

func _shotgun_cylinder(at: Vector3, radius: float, length: float, tint: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 16
	part.mesh = cylinder
	part.position = at
	part.rotation.x = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.75
	material.roughness = 0.28
	part.material_override = material
	shotgun_mount.add_child(part)
	return part


func _weapon_box(at: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	piece.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.55
	material.roughness = 0.42
	piece.material_override = material
	weapon_mount.add_child(piece)
	return piece


func _weapon_cylinder(at: Vector3, radius: float, length: float, tint: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var barrel := CylinderMesh.new()
	barrel.top_radius = radius
	barrel.bottom_radius = radius
	barrel.height = length
	barrel.radial_segments = 16
	piece.mesh = barrel
	piece.position = at
	piece.rotation.x = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.72
	material.roughness = 0.28
	piece.material_override = material
	weapon_mount.add_child(piece)
	return piece


func show_muzzle_flash() -> void:
	muzzle_time = 0.055
	if target.is_shotgun_equipped():
		muzzle_time = 0.08
		shotgun_muzzle_flash.visible = true
		shotgun_muzzle_light.visible = true
	else:
		muzzle_flash.visible = true
		muzzle_light.visible = true


func muzzle_position() -> Vector3:
	return shotgun_muzzle_flash.global_position if target.is_shotgun_equipped() else muzzle_flash.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)

func apply_look(relative: Vector2) -> void:
	manual_look_time = 1.8
	yaw -= relative.x*0.003
	pitch = clampf(pitch-relative.y*0.003,-1.05,0.45)

func _process(dt: float) -> void:
	var driving := target.vehicle != null
	var vehicle_speed := float(target.vehicle.get("speed")) if driving else 0.0
	manual_look_time = maxf(0,manual_look_time-dt)
	recoil = move_toward(recoil,0,dt*0.18)
	muzzle_time = maxf(0.0, muzzle_time - dt)
	if muzzle_time <= 0.0:
		muzzle_flash.visible = false
		muzzle_light.visible = false
		shotgun_muzzle_flash.visible = false
		shotgun_muzzle_light.visible = false
	if driving and manual_look_time <= 0 and vehicle_speed > 4:
		yaw = lerp_angle(yaw,target.vehicle.rotation.y,1-exp(-2*dt))
		pitch = lerpf(pitch,-0.18,1-exp(-1.5*dt))
	var aiming := not driving and Input.is_action_pressed("aim")
	var desired := target.global_position+Vector3(0,2.1 if driving else 1.62,0)
	if driving:
		global_position = global_position.lerp(desired,1.0-exp(-12*dt))
		arm.position = Vector3(0.8, 0.0, 0.0)
		weapon_mount.visible = false
		shotgun_mount.visible = false
	else:
		global_position = desired
		arm.position = Vector3.ZERO
		weapon_mount.visible = not target.is_shotgun_equipped()
		shotgun_mount.visible = target.is_shotgun_equipped()
	rotation = Vector3(pitch+recoil,yaw,0)
	var distance := 9.0 if driving else 0.0
	arm.spring_length = lerpf(arm.spring_length,distance,1-exp(-6*dt))
	var fov := 56.0 if aiming else 68.0
	if driving:
		var boost_factor := float(target.vehicle.get("boost_factor")) if target.vehicle.get("boost_factor") != null else 0.0
		fov = 68+clampf(absf(vehicle_speed)/40,0,1)*10+boost_factor*8
	camera.fov = lerpf(camera.fov,fov,1-exp(-6*dt))
