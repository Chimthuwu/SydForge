extends SceneTree

## Project-wide script parse/load check.
##
## Loads every `.gd` file under res:// and reports the ones that fail to compile.
## A single broken script stops `scripts/district.gd` from loading, which takes
## the whole game down, so this is the cheapest useful gate before any suite.
##
##   Godot --headless --path . --script res://tests/parse_check.gd

var failures := 0
var checked := 0


func _initialize() -> void:
	_scan("res://")
	print("parse_check: %d scripts checked, %d failed" % [checked, failures])
	quit(1 if failures > 0 else 0)


func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_scan(full)
		elif entry.ends_with(".gd"):
			# The running script cannot be validated from inside itself.
			if full == "res://tests/parse_check.gd":
				entry = dir.get_next()
				continue
			checked += 1
			# `load()` still hands back a script object for a file that failed to
			# compile; `can_instantiate()` is false in that case.
			var script := ResourceLoader.load(full) as GDScript
			if script == null or not script.can_instantiate():
				print("PARSE FAILED: " + full)
				failures += 1
		entry = dir.get_next()
	dir.list_dir_end()
