class_name BoomCamera
extends Node3D

var yaw: float = 0.0
var pitch: float = -0.18
var camera: Camera3D
var arm: SpringArm3D
var target: BoomPlayer
var manual_look_time: float = 0.0
var recoil: float = 0.0

func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 6
	arm.margin = 0.25
	arm.position.x = 0.8
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	arm.shape = shape
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 72
	arm.add_child(camera)
	camera.current = true
	arm.add_excluded_object(target.get_rid())
	global_position = target.global_position+Vector3(0,1.7,0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)

func apply_look(relative: Vector2) -> void:
	manual_look_time = 1.8
	yaw -= relative.x*0.003
	pitch = clampf(pitch-relative.y*0.003,-1.05,0.45)

func _process(dt: float) -> void:
	var driving := target.vehicle != null
	manual_look_time = maxf(0,manual_look_time-dt)
	recoil = move_toward(recoil,0,dt*0.18)
	if driving and manual_look_time <= 0 and target.vehicle.speed > 4:
		yaw = lerp_angle(yaw,target.vehicle.rotation.y,1-exp(-2*dt))
		pitch = lerpf(pitch,-0.18,1-exp(-1.5*dt))
	var aiming := not driving and Input.is_action_pressed("aim")
	var desired := target.global_position+Vector3(0,2.1 if driving else 1.65,0)
	global_position = global_position.lerp(desired,1.0-exp(-12*dt))
	rotation = Vector3(pitch+recoil,yaw,0)
	var distance := 9.0 if driving else (3.2 if aiming else 5.5)
	arm.spring_length = lerpf(arm.spring_length,distance,1-exp(-6*dt))
	var fov := 55.0 if aiming else 72.0
	if driving:
		fov = 72+clampf(absf(target.vehicle.speed)/40,0,1)*10
	camera.fov = lerpf(camera.fov,fov,1-exp(-6*dt))
