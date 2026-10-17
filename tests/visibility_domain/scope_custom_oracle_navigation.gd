extends "res://tests/visibility_domain/oracle_city_navigation.gd"
var rays: Array = []
func _visible(a: Vector2, b: Vector2, radius: float) -> bool:
	rays.append([a,b,radius])
	if rays.size() == 2:
		_world.sweep(a,Vector2(100000,0),radius)
		return false
	return super._visible(a,b,radius)
var preparation_calls := 0
func _smoothing_scope_ready(_start: Vector2, _points: Array, _radius: float) -> bool:
	preparation_calls += 1
	return true
