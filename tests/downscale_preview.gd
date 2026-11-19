extends SceneTree


func _initialize() -> void:
	for name in ["overhaul_day_aerial", "overhaul_night_aerial"]:
		var source := "res://tests/%s.png" % name
		var target := "res://tests/preview_%s.png" % name
		var image := Image.load_from_file(ProjectSettings.globalize_path(source))
		if image == null:
			push_error("Could not load " + source)
			continue
		image.resize(1024, 576, Image.INTERPOLATE_BILINEAR)
		image.save_png(ProjectSettings.globalize_path(target))
		print("PREVIEW: ", target)
	quit()
