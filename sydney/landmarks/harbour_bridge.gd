extends Node3D
## Sydney Harbour Bridge. Plan from OSM; elevations and member sections are
## authored against official dimensions. No runtime simulation or frame work.
const DATA := "res://sydney/landmarks/harbour_bridge.json"
const SPAN := 503.0
const DECK := 52.0
const PANELS := 28
var reference: Dictionary
var centre := Vector3.ZERO
var north := Vector3.ZERO
var east := Vector3.ZERO
var route: Array[Vector3] = []
var route_east: Array[Vector3] = []
var stats: Dictionary = {}
var surfaces: Dictionary = {}
var collision := PackedVector3Array()
var members: Array = []
var _box := BoxMesh.new()

const StationInteriorsScript := preload("res://sydney/railway/station_interiors.gd")

func point(s: float, x: float, y: float) -> Vector3:
	return centre + north*s + east*x + Vector3.UP*y

func lower(s: float) -> float:
	return 12.0 + 104.0*(1.0-pow(s/251.5,2))

func upper(s: float) -> float:
	return lower(s) + 18.0 + 39.0*pow(s/251.5,2)

func build() -> void:
	var begin := Time.get_ticks_usec()
	reference = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	centre = Vector3(reference.centre[0],0,reference.centre[1])
	north = Vector3(reference.axis[0],0,reference.axis[1])
	east = Vector3(-north.z,0,north.x)
	for key in ["Steel", "Stone", "Road", "Walk", "Paint", "Rail"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[key] = st
	_build_route()
	_build_arch()
	_build_pylons()
	_build_site()
	var colors := {"Steel":"4c565a", "Stone":"b5ab92", "Road":"33383c", "Walk":"b0aba0", "Paint":"eee7d2", "Rail":"655b50"}
	var triangles := 0
	for key in surfaces:
		var mesh: ArrayMesh = surfaces[key].commit()
		if mesh == null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(colors[key])
		material.roughness = 0.85
		mesh.surface_set_material(0,material)
		var node := MeshInstance3D.new()
		node.name = key
		node.mesh = mesh
		add_child(node)
		triangles += mesh.get_faces().size()/3
	var body := StaticBody3D.new()
	body.name = "BridgeCollision"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	# A single convex slab carries the long, flat central roadway. This avoids
	# concave triangle-edge contacts against the car's box at coplanar seams.
	var roadway := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(24,0.5,560)
	roadway.shape = slab
	roadway.transform = Transform3D(Basis(east,Vector3.UP,-north),point(0,0,51.75))
	body.add_child(roadway)
	add_child(body)
	stats = {"triangles":triangles,"collisionTriangles":collision.size()/3,"members":members.size(),"buildMs":(Time.get_ticks_usec()-begin)/1000.0}

func _box_at(key: String, pos: Vector3, size: Vector3, solid := false, frame := Basis.IDENTITY) -> void:
	_box.size = size
	var transform := Transform3D(frame,pos)
	# Keep the entire batch unindexed. append_from(BoxMesh) introduces an index
	# buffer that would leave subsequently emitted strip vertices unreferenced.
	var arrays := _box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st: SurfaceTool = surfaces[key]
	for i in ids:
		var v := transform*vertices[i]
		st.set_normal(frame*normals[i])
		st.add_vertex(v)
		if solid:
			collision.append(v)

func _beam(a: Vector3, b: Vector3, width: float, depth: float, key := "Steel", solid := false) -> void:
	var along := (b-a).normalized()
	var side := Vector3.UP.cross(along).normalized()
	if side.length() < 0.1:
		side = east
	var frame := Basis(side,along,side.cross(along))
	_box_at(key,(a+b)*0.5,Vector3(width,a.distance_to(b),depth),solid,frame)
	if key == "Steel":
		members.append([a,b])

func _local_box(key: String, s: float, x: float, y: float, size: Vector3, solid := false) -> void:
	_box_at(key,point(s,x,y),size,solid,Basis(east,Vector3.UP,-north))

func _tri(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, solid: bool) -> void:
	var n := (c-a).cross(b-a).normalized()
	if n.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		n = -n
	var st: SurfaceTool = surfaces[key]
	st.set_normal(n)
	for v in [a,b,c]:
		st.add_vertex(v)
		if solid:
			collision.append(v)

func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, solid := false) -> void:
	_tri(key,a,b,c,outward,solid)
	_tri(key,a,c,d,outward,solid)

func _strip(index: int, left: float, right: float, height: float, depth: float, key: String, solid := true) -> void:
	var a := route[index]+route_east[index]*left+Vector3.UP*height
	var b := route[index]+route_east[index]*right+Vector3.UP*height
	var c := route[index+1]+route_east[index+1]*right+Vector3.UP*height
	var d := route[index+1]+route_east[index+1]*left+Vector3.UP*height
	_quad(key,a,b,c,d,Vector3.UP,solid)
	if depth <= 0:
		return
	var down := Vector3.DOWN*depth
	_quad(key,a,d,d+down,a+down,-route_east[index],solid)
	_quad(key,b,c,c+down,b+down,route_east[index],solid)
	_quad(key,a+down,b+down,c+down,d+down,Vector3.DOWN,solid)
	# Only the outer ends are capped: shared sections remain seamless.
	if index == 0:
		_quad(key,a,b,b+down,a+down,route[0]-route[1],solid)
	if index == route.size()-2:
		_quad(key,d,c,c+down,d+down,route[-1]-route[-2],solid)

func _build_route() -> void:
	var raw: Array = reference.roadPoints
	for i in raw.size()-1:
		var a := Vector3(raw[i][0],0,raw[i][1])
		var b := Vector3(raw[i+1][0],0,raw[i+1][1])
		var count := maxi(1,ceili(a.distance_to(b)/8.0))
		for j in count:
			route.append(a.lerp(b,float(j)/count))
	route.append(Vector3(raw[-1][0],0,raw[-1][1]))
	var start_s := (route[0]-centre).dot(north)
	var end_s := (route[-1]-centre).dot(north)
	for i in route.size():
		var s := (route[i]-centre).dot(north)
		# Flatten at the tie-ins; 52 m across the harbour. Cubic easing makes
		# slope transitions smooth for the existing CharacterBody car.
		var t := 1.0
		if s < -290:
			t = clampf((s-start_s)/(-290-start_s),0,1)
		elif s > 290:
			t = clampf((end_s-s)/(end_s-290),0,1)
		route[i].y = lerpf(0.12,DECK,t*t*(3-2*t))
		var tangent := route[mini(i+1,route.size()-1)]-route[maxi(0,i-1)]
		tangent.y = 0
		route_east.append(Vector3(-tangent.z,0,tangent.x).normalized())
	for i in route.size()-1:
		_strip(i,-24.5,24.5,-0.08,2.92,"Steel")
		var core := absf((route[i]-centre).dot(north))<275 and absf((route[i+1]-centre).dot(north))<275
		_strip(i,-12,12,0,0,"Road",not core)
		_strip(i,18,24.5,0.12,0.2,"Walk")
		_strip(i,-24.5,-22.5,0.12,0.2,"Walk")
		_strip(i,-22,-16,0.03,0,"Rail",false)
		for x in [-21.7175,-20.2825,-17.7175,-16.2825]:
			_strip(i,x-0.035,x+0.035,0.18,0.12,"Steel",false)
		# Road/pedestrian separator and outer parapets: one shared physics mesh.
		for x in [-24.3,-12.5,12.5,17.7,24.3]:
			_strip(i,x-0.12,x+0.12,1.4,1.45,"Steel")
		for x in [18.0,24.3]:
			for y in [1.85,2.35]:
				_beam(route[i]+route_east[i]*x+Vector3.UP*y,route[i+1]+route_east[i+1]*x+Vector3.UP*y,0.08,0.08)
		for x in [-9,-6,-3,0,3,6,9]:
			if i%2 == 0 or x == 0:
				_strip(i,x-0.06,x+0.06,0.015,0,"Paint",false)
		# Pickets on the walkway, open above a low parapet visually.
		if i%1 == 0:
			for x in [18.0,24.3]:
				_beam(route[i]+route_east[i]*x,route[i]+route_east[i]*x+Vector3.UP*2.4,0.08,0.08)
		if i%4 == 0:
			# Railway sleepers and catenary stay entirely in the rail corridor.
			for x in [-21,-17]:
				_box_at("Rail",route[i]+route_east[i]*x+Vector3.UP*0.06,Vector3(2.5,0.12,0.22),false,Basis(route_east[i],Vector3.UP,route_east[i].cross(Vector3.UP)))
		if i%8 == 0:
			var p := route[i]-route_east[i]*22
			_beam(p,p+Vector3.UP*6,0.15,0.15)
			_beam(p+Vector3.UP*6,p+route_east[i]*6+Vector3.UP*6,0.12,0.12)
		var s := (route[i]-centre).dot(north)
		if absf(s)>290 and route[i].y>14 and route[i+1].y>14:
			for x in [-15.0,15.0]:
				var a: Vector3 = route[i]+route_east[i]*x
				var b: Vector3 = route[i+1]+route_east[i+1]*x
				_beam(a+Vector3.DOWN*3,b+Vector3.DOWN*3,0.65,0.7)
				_beam(a+Vector3.DOWN*9,b+Vector3.DOWN*9,0.65,0.7)
				_beam(a+Vector3.DOWN*3,a+Vector3.DOWN*9,0.35,0.4)
				_beam(a+Vector3.DOWN*(3 if i%2==0 else 9),b+Vector3.DOWN*(9 if i%2==0 else 3),0.35,0.4)
		if absf(s)>300 and i%8 == 0 and route[i].y>4:
			for x in [-15,15]:
				var p: Vector3 = route[i]+route_east[i]*x
				_box_at("Stone",Vector3(p.x,(p.y-3)*0.5,p.z),Vector3(5,p.y-3,7),true,Basis(east,Vector3.UP,-north))
			_beam(route[i]-route_east[i]*24+Vector3.DOWN*2,route[i]+route_east[i]*24+Vector3.DOWN*2,1.6,2.4)
	# Direction arrows: fixed 4+4 left-hand arrangement; no reversible traffic.
	for i in range(8,route.size()-8,18):
		var dir := (route[i+1]-route[i]).normalized()
		for lane in 8:
			var x := -10.5+lane*3.0
			var p := route[i]+route_east[i]*x+Vector3.UP*0.025
			var heading := dir if lane<4 else -dir
			_beam(p-heading*2,p+heading*2,0.12,0.025,"Paint")
			_beam(p+heading*2,p+heading*0.6+route_east[i]*0.65,0.14,0.025,"Paint")
			_beam(p+heading*2,p+heading*0.6-route_east[i]*0.65,0.14,0.025,"Paint")

func _build_arch() -> void:
	for rib in [-15.0,15.0]:
		for i in PANELS:
			var s := -251.5+SPAN*i/PANELS
			var t := -251.5+SPAN*(i+1)/PANELS
			var a := point(s,rib,lower(s))
			var b := point(t,rib,lower(t))
			var c := point(s,rib,upper(s))
			var d := point(t,rib,upper(t))
			_beam(a,b,1.5,1.8)
			_beam(c,d,1.5,1.8)
			_beam(a,c,0.8,0.9)
			_beam(a,d,0.85,0.95) if i<PANELS/2 else _beam(c,b,0.85,0.95)
			# Double flange bands give deep steel members, not thin wire lines.
			for offset in [-0.8,0.8]:
				_beam(a+east*offset,b+east*offset,0.16,2.1)
				_beam(c+east*offset,d+east*offset,0.16,2.1)
			if lower(s)>DECK+5:
				_beam(point(s,rib,DECK-2),a,0.48,0.65)
				_beam(point(s,-24,DECK-2),point(s,24,DECK-2),1.2,2.0)
		_beam(point(251.5,rib,lower(251.5)),point(251.5,rib,upper(251.5)),0.8,0.9)
		for s in [-251.5,251.5]:
			_local_box("Stone",s,rib,5.5,Vector3(9,11,12),true)
			_local_box("Steel",s,rib,11.5,Vector3(4,1,4))
	for i in PANELS:
		var s := -251.5+SPAN*i/PANELS
		var t := -251.5+SPAN*(i+1)/PANELS
		_beam(point(s,-15,upper(s)),point(s,15,upper(s)),0.65,0.7)
		_beam(point(s,-15,upper(s)),point(t,15,upper(t)),0.4,0.45)
		_beam(point(s,15,upper(s)),point(t,-15,upper(t)),0.4,0.45)
		# Lower lateral bracing only above the vehicle clearance envelope.
		if minf(lower(s),lower(t))>DECK+7:
			_beam(point(s,-15,lower(s)),point(t,15,lower(t)),0.35,0.4)
			_beam(point(s,15,lower(s)),point(t,-15,lower(t)),0.35,0.4)

func _build_pylons() -> void:
	for xy in reference.pylonCenters:
		var p := Vector3(xy[0],0,xy[1])
		var s := (p-centre).dot(north)
		var x := (p-centre).dot(east)
		# Granite-faced concrete shafts. Footway/rail portals at deck height.
		_local_box("Stone",s,x,23.5,Vector3(14,47,30),true)
		_local_box("Stone",s,x,48.5,Vector3(12,3,28),true)
		for side in [-1,1]:
			_local_box("Stone",s,x+side*5.2,54,Vector3(1.6,8,26),true)
		_local_box("Stone",s,x,68,Vector3(10.5,20,25),true)
		_local_box("Stone",s,x,82,Vector3(10,8,24),true)
		_local_box("Stone",s,x,87.5,Vector3(11.4,3,25.5),true)
		for y in [8,18,28,38,47,59,69,78]:
			_local_box("Stone",s,x,y,Vector3(14.15 if y<47 else 10.7,0.32,30.15 if y<47 else 25.15))
		# Recessed window strips on all faces near the observation level.
		for j in [-1,0,1]:
			for side in [-1,1]:
				_local_box("Steel",s+j*6,x+side*5.03,82,Vector3(0.08,3.8,1.5))
				_local_box("Steel",s+side*12.03,x+j*2.7,82,Vector3(1.2,3.8,0.08))

func _build_site() -> void:
	# Only the bounded extension beyond Stage A; existing export is immutable.
	for item in [["ApproachLand",reference.landRings,0.0,Color("5d6258")],["HarbourExtension",reference.waterRings,0.02,Color("2b6f86")]]:
		var mesh := SydneyMesh.flat_polygons(item[1],item[2],item[3])
		if item[0] == "ApproachLand":
			mesh = SydneyMesh.engine_building_mesh(mesh)
		var node := MeshInstance3D.new()
		node.name = item[0]
		node.mesh = mesh
		add_child(node)
		if item[0] == "ApproachLand":
			collision.append_array(mesh.get_faces())
		else:
			for ring in item[1]:
				for i in ring.size()-1:
					var a := Vector3(ring[i][0],0,ring[i][1])
					var b := Vector3(ring[i+1][0],0,ring[i+1][1])
					# Do not wall off the artificial clipping seam at Stage A.
					if absf(a.z+1887.3)<0.01 and absf(b.z+1887.3)<0.01:
						continue
					for v in [a,b,b+Vector3.UP*2.4,a,b+Vector3.UP*2.4,a+Vector3.UP*2.4,b,a,a+Vector3.UP*2.4,b,a+Vector3.UP*2.4,b+Vector3.UP*2.4]:
						collision.append(v)
	# Source-aligned local roads provide a finite usable Milsons Point loop via
	# Lavender / Alfred / Fitzroy. Terrain is flat like Stage A; no suburb build.
	var paths: Array = []
	var widths: Array = []
	for street in reference.localStreets:
		var path: Array = []
		for xy in street.points:
			path.append(Vector2(xy[0],xy[1]))
		paths.append(path)
		widths.append(12.0)
	var local_mesh := SydneyMesh.engine_building_mesh(SydneyMesh.flat_paths(paths,widths,0.04,Color("33383c")))
	var local_node := MeshInstance3D.new()
	local_node.name = "MilsonsStreets"
	local_node.mesh = local_mesh
	add_child(local_node)
	_build_southern_city_connector()


## The bridge deck ends at the mapped Bradfield tie-in while the exported city
## road mesh begins slightly further south. Bridge that seam with a short,
## collision-backed asphalt ribbon so the carriageway never vanishes mid-drive.
func _build_southern_city_connector() -> void:
	if route.size() < 4:
		return
	var last: Vector3 = route[0]
	var before: Vector3 = route[1]
	var direction := (last - before).normalized()
	direction.y = 0.0
	if direction.length_squared() < 0.1:
		return
	var connector_length := 190.0
	var path: Array = []
	for index in 39:
		var point := last + direction * (connector_length * float(index) / 38.0)
		point.y = last.y
		path.append(Vector2(point.x, point.z))
	# Never lay the connector over the open rail ramp: trains punched straight
	# through it. Split it into the runs that stay clear of the cutting.
	var clearance: float = 12.0 + StationInteriorsScript.DESCENT_CUT_HALF_WIDTH
	var cut: Array = StationInteriorsScript.descent_cut_path()
	var segments: Array = []
	var paths: Array = []
	var widths: Array = []
	for index in range(path.size() - 1):
		var middle: Vector2 = (path[index] + path[index + 1]) * 0.5
		var blocked := false
		for j in range(cut.size() - 1):
			if Geometry2D.get_closest_point_to_segment(middle, cut[j], cut[j + 1]).distance_to(middle) < clearance:
				blocked = true
				break
		if not blocked:
			segments.append([path[index], path[index + 1]])
			paths.append([path[index], path[index + 1]])
			widths.append(24.0)
	if segments.is_empty():
		return
	var surface := SydneyMesh.flat_paths(paths, widths, 0.06, Color("34383c"))
	var instance := MeshInstance3D.new()
	instance.name = "SouthernCityConnector"
	instance.mesh = surface
	add_child(instance)
	# Flat collision pad matches the exported city's flat ground; the bridge's
	# own concave body carries the elevated section up to the tie-in.
	var body := StaticBody3D.new()
	body.name = "SouthernCityConnectorCollision"
	add_child(body)
	for pair: Array in segments:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var segment := b - a
		var segment_length := segment.length()
		if segment_length < 0.01:
			continue
		var center := (a + b) * 0.5
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(24.0, 0.12, segment_length)
		collider.shape = box
		collider.transform = Transform3D(
			Basis(Vector3(segment.x / segment_length, 0.0, segment.y / segment_length), Vector3.UP,
				Vector3(-segment.y / segment_length, 0.0, segment.x / segment_length)),
			Vector3(center.x, last.y - 0.06, center.y)
		)
		body.add_child(collider)
