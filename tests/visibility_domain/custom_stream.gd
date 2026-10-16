extends "res://game/world/streamed_world.gd"
var sweep_calls: Array = []
var public_calls: Array = []
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	sweep_calls.append([position,delta,radius])
	if sweep_calls.size() == 2: return {"ok":false,"error_code":"custom_stream_second_failure","position":position,"fraction":0.0,"hit_prop_id":""}
	return super.sweep(position,delta,radius)
func query_props(bounds: Rect2) -> Array:
	public_calls.append(bounds)
	return super.query_props(bounds)
