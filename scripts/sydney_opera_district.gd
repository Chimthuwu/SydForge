extends "res://scripts/sydney_district.gd"

## SYDNEY OPERA HOUSE PLAYTEST — open res://sydney/sydney_opera_test.tscn, F6.
##
## Same world, player, camera, HUD and gameplay as sydney_test.tscn; only the
## start point differs. The player starts on the paved forecourt south of the
## stepped podium, facing the shells, with the 24 risers directly ahead.

## Look target height: the podium deck, so the shells sit in frame.
const PODIUM_LOOK_HEIGHT := 14.0

## On the forecourt plaza (y = 0.12), about 7 m south of the lowest riser and
## 116 m down the podium's long axis from its centroid. Derived from the
## landmark: the podium ring spans u = -85..+85, the 24 steps occupy
## u = -86..-109, so this point is the first clear ground in front of them.
## It is 67 m from the water and 850 m from the nearest building.
const FORECOURT_SPAWN := Vector3(632.1, 0.3, -1650.9)


func _playtest_spawn() -> Vector3:
	return FORECOURT_SPAWN


func _playtest_look_target() -> Vector3:
	return Vector3(OPERA_HOUSE_XZ.x, PODIUM_LOOK_HEIGHT, OPERA_HOUSE_XZ.y)


func _playtest_message() -> String:
	return "SYDNEY PLAYTEST · Opera House forecourt · steps ahead"
