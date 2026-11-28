extends SceneTree

## Owner bug: ferries sailed over land. Every leg of every boat route, sampled
## every 4 m with room for the hull, must be on harbour water.

const Water := preload("res://sydney/harbour/harbour_water.gd")
const Boats := preload("res://sydney/harbour/harbour_boats.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var water = Water.new()
	root.add_child(water)
	water.build()
	var fleet = Boats.new()
	root.add_child(fleet)
	fleet.setup(null)
	fleet.set_process(false)
	var dry := 0
	var samples := 0
	for boat: Dictionary in fleet.boats:
		var points: Array = boat.points
		for i in points.size() - 1:
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var side := Vector3.UP.cross((b - a).normalized()).normalized()
			var steps := maxi(1, ceili(a.distance_to(b) / 4.0))
			for s in steps + 1:
				for offset in [-4.0, 0.0, 4.0]:
					var p: Vector3 = a.lerp(b, float(s) / steps) + side * offset
					samples += 1
					if not water.is_water(p.x, p.z):
						dry += 1
	var ok: bool = dry == 0 and samples > 200
	print(("PASS: " if ok else "FAIL: ") + "boat routes stay on water (%d dry of %d samples)" % [dry, samples])
	print("RESULT: 1 checks, %d failures" % (0 if ok else 1))
	quit(0 if ok else 1)
