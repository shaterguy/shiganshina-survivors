extends RefCounted
const Cases = preload("res://tests/movement_axis_equivalence/axis_cases.gd")
func run(t) -> void:
	Cases.new().run(t)
