extends RefCounted
func run(t) -> void:
	var script = load("res://tools/qa/armored_raster_review.gd")
	t.check(script != null and script.can_instantiate(), "authored-only QA script parses")
	var scene = load("res://tools/qa/armored_raster_review.tscn")
	t.check(scene is PackedScene, "authored-only QA scene resource loads without instantiation")
