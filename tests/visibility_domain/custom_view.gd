extends "res://game/world/streamed_navigation_view.gd"
var sweep_calls: Array = []
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	sweep_calls.append([position,delta,radius])
	if sweep_calls.size() == 2: return _observe_query({"ok":false,"error_code":"custom_view_second_failure","position":position,"fraction":0.0,"hit_prop_id":""})
	return super.sweep(position,delta,radius)
