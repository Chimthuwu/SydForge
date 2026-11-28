extends SceneTree
var checks := 0
var failures := 0
var world: Node3D
var bridge: Node3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ")+label)

func _initialize() -> void:
	call_deferred("run")

func settle(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	world = load("res://sydney/sydney_bridge_test.tscn").instantiate()
	root.add_child(world)
	bridge = world.sydney_world.get_node("HarbourBridge")
	await settle(150)
	check(world.player is BoomPlayer and world.vehicles[0] is ArcadeCar,"real player and vehicle in dedicated scene")
	check(world.player.is_on_floor(),"southern spawn rests on approach")
	check(bridge.north.x>0.45 and bridge.north.x<0.47 and bridge.north.z< -0.88,"OSM alignment 27.5 degrees east of north")
	check(bridge.point(-251.5,0,0).distance_to(Vector3(131.236,0,-2076.450))<0.02,"Dawes Point bearing")
	check(bridge.point(251.5,0,0).distance_to(Vector3(363.370,0,-2522.682))<0.02,"Milsons Point bearing")
	check(is_equal_approx(bridge.upper(0),134) and is_equal_approx(bridge.lower(0),116),"134 m summit and 18 m crown depth")
	check(is_equal_approx(bridge.upper(251.5)-bridge.lower(251.5),57),"57 m end depth")
	check(bridge.reference.pylonCenters.size()==4,"four OSM pylons")
	check(bridge.get_node("ApproachLand")!=null and bridge.get_node("MilsonsStreets")!=null,"bounded shore extension and sourced local streets exist")
	var valid := true
	var winding := true
	var degenerates := 0
	var checksum := 0.0
	for child in bridge.get_children():
		if not child is MeshInstance3D or child.name in ["ApproachLand","HarbourExtension","MilsonsStreets"]:
			continue
		var mesh: ArrayMesh = child.mesh
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ids := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			ids = arrays[Mesh.ARRAY_INDEX]
		for v in verts:
			valid = valid and v.is_finite()
			checksum += v.x+v.y+v.z
		var count := ids.size() if ids.size()>0 else verts.size()
		for i in range(0,count,3):
			var a := ids[i] if ids.size()>0 else i
			var b := ids[i+1] if ids.size()>0 else i+1
			var c := ids[i+2] if ids.size()>0 else i+2
			var cross := (verts[c]-verts[a]).cross(verts[b]-verts[a])
			if cross.length()<0.000001:
				degenerates += 1
			if winding and cross.dot(normals[a])<=0:
				print("WINDING OFFENDER ",child.name," tri ",i," ids.size=",ids.size()," verts=",verts.size())
			winding = winding and cross.dot(normals[a])>0
			valid = valid and absf(normals[a].length()-1)<0.002
	check(valid,"all vertices finite and normals unit length")
	check(degenerates==0,"no degenerate triangles: %d"%degenerates)
	check(winding,"clockwise Godot winding agrees with outward normals")
	var duplicate_bridge = load("res://sydney/landmarks/harbour_bridge.gd").new()
	duplicate_bridge.build()
	check(duplicate_bridge.get_node("Steel").mesh.get_faces()==bridge.get_node("Steel").mesh.get_faces(),"deterministic steel geometry")
	duplicate_bridge.free()
	check(bridge.get_node("BridgeCollision").get_child_count()==2,"one bridge body: batched geometry and convex central roadway")
	var space := world.get_world_3d().direct_space_state
	var road_hits := 0
	var walk_hits := 0
	var blocked := 0
	var exclude: Array[RID] = [world.player.get_rid()]
	for car in world.vehicles:
		exclude.append(car.get_rid())
	for i in bridge.route.size():
		for x in [-7.5,21.0]:
			var p: Vector3 = bridge.route[i]+bridge.route_east[i]*x
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*3,p+Vector3.DOWN*0.3,1,exclude))
			if not hit.is_empty() and absf(hit.position.y-p.y)<0.2:
				if x<0: road_hits += 1
				else: walk_hits += 1
			else:
				print("BAD SURFACE ",i," x=",x," expected=",p," hit=",hit.get("position"))
	check(road_hits==bridge.route.size(),"road supported at all %d route sections (%d hits)"%[bridge.route.size(),road_hits])
	check(walk_hits==bridge.route.size(),"walkway supported at all route sections (%d hits)"%walk_hits)
	check(bridge.point(0,24,52).distance_to(Vector3(658.72,12,-1763.81))>500,"bridge clear of Opera House")
	check(world.sydney_world.has_node("OperaHouse"),"Opera House retained")
	for end in [0,bridge.route.size()-1]:
		var p: Vector3 = bridge.route[end]+bridge.route_east[end]*21
		var out: Vector3 = (bridge.route[end]-bridge.route[1 if end==0 else end-1]).normalized()
		out.y=0
		p += out*4
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*3,p+Vector3.DOWN*3,1,exclude))
		check(not hit.is_empty() and absf(hit.position.y)<0.15,"approach ends on grounded shore: "+str(end))
	# Real controller, real input, complete route in both directions. No teleport
	# between sections: the path follower changes heading only.
	world._intro = 10.0
	world.rig.set_process(false)
	world.player.global_position = bridge.route[0]+bridge.route_east[0]*21+Vector3.UP*0.4
	world.player.velocity = Vector3.ZERO
	await settle(20)
	Input.action_press("sprint")
	Input.action_press("forward")
	for reverse in [false,true]:
		var reached := 0
		for step in bridge.route.size():
			var i: int = bridge.route.size()-1-step if reverse else step
			var target: Vector3 = bridge.route[i]+bridge.route_east[i]*21
			var frames := 0
			while Vector2(world.player.position.x-target.x,world.player.position.z-target.z).length()>1.0 and frames<160:
				var direction: Vector3 = target-world.player.position
				world.rig.yaw = atan2(-direction.x,-direction.z)
				await physics_frame
				frames += 1
			if frames>=160 or absf(world.player.position.y-target.y)>2:
				print("WALK STOP section ",i," position ",world.player.position," target ",target)
				break
			reached += 1
		check(reached==bridge.route.size(),"player complete crossing "+("southbound" if reverse else "northbound")+" sections=%d"%reached)
	Input.action_release("forward")
	Input.action_release("sprint")
	# Existing ArcadeCar physics and throttle. Steering is an automated test
	# driver following the route, not a replacement movement implementation.
	var car: ArcadeCar = world.vehicles[0]
	car.health = car.max_health
	car.global_position = bridge.route[0]-bridge.route_east[0]*7.5+Vector3.UP*0.5
	car.velocity = Vector3.ZERO
	car.speed = 0
	car.enter(world.player)
	await settle(30)
	Input.action_press("forward",0.45)
	var reached := 0
	var previous_health := car.health
	for i in range(1,bridge.route.size()):
		var target: Vector3 = bridge.route[i]-bridge.route_east[i]*7.5
		var frames := 0
		while Vector2(car.position.x-target.x,car.position.z-target.z).length()>2 and frames<200:
			var direction := target-car.position
			car.rotation.y = atan2(-direction.x,-direction.z)
			await physics_frame
			frames += 1
			if car.health<previous_health:
				for k in car.get_slide_collision_count():
					var contact := car.get_slide_collision(k)
					print("IMPACT CONTACT ",contact.get_collider().name," ",contact.get_normal()," at ",contact.get_position())
				print("CAR IMPACT section ",i," health ",car.health," at ",car.position)
				previous_health = car.health
		if frames>=200 or absf(car.position.y-target.y)>2:
			print("CAR STOP section ",i," position ",car.position," target ",target)
			break
		reached += 1
		if car.health<previous_health:
			print("CAR IMPACT section ",i," health ",car.health," at ",car.position)
			previous_health = car.health
	check(reached==bridge.route.size()-1,"vehicle drives entire southern to northern route sections=%d"%reached)
	check(car.health>119,"vehicle crosses without structure impacts")
	# Continue off the elevated route onto the OSM Lavender Street exit. This
	# proves the last deck section connects to the local land collision.
	var local_points: Array = []
	for id in ["way/29174822","way/1484195095","way/1484195094","way/279682336","way/245334220"]:
		for street in bridge.reference.localStreets:
			if street.id==id:
				for xy in street.points:
					local_points.append(Vector3(xy[0],0,xy[1]))
	var local_reached := 0
	for target: Vector3 in local_points:
		var frames := 0
		while Vector2(car.position.x-target.x,car.position.z-target.z).length()>3 and frames<1000:
			var direction := target-car.position
			car.rotation.y = atan2(-direction.x,-direction.z)
			await physics_frame
			frames += 1
		if frames>=1000 or absf(car.position.y)>1:
			print("LOCAL STOP ",car.position," target ",target)
			print("LOCAL CAR health=",car.health," speed=",car.speed)
			for k in car.get_slide_collision_count():
				var contact := car.get_slide_collision(k)
				print("LOCAL CONTACT ",contact.get_collider().name," ",contact.get_normal()," at ",contact.get_position())
			break
		local_reached += 1
	check(local_reached==local_points.size(),"vehicle leaves bridge via Lavender exit to Alfred Street")
	Input.action_release("forward")
	print("BRIDGE STATS ",bridge.stats)
	print("WORLD TIMINGS ",world.sydney_world.build_times_ms)
	print("RESULT: %d checks, %d failures"%[checks,failures])
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
