extends "res://game/world/precise_city_navigation.gd"
# Oracle adapter for the small helper integration group only. Main comparisons
# use exact native View._visibility_full_sweep directly, with no subclass.
func _visible(a: Vector2, b: Vector2, radius: float) -> bool:
	var result: Dictionary = _world._visibility_full_sweep(a,b-a,radius)
	return result.ok and result.visible
