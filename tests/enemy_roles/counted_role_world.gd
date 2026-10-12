extends "res://game/world/cached_streamed_world.gd"
# QA instrumentation, inherited real collision and coverage algorithms.
var candidate_props := 0
var narrow_tests := 0
func _collision_query_props(aabb: Rect2) -> Array:
	var props := super._collision_query_props(aabb)
	candidate_props += props.size()
	return props
func _collision_box(prop: Dictionary, radius: float) -> Rect2:
	narrow_tests += 1
	return super._collision_box(prop,radius)
