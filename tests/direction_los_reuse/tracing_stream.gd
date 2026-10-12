extends "res://game/world/streamed_world.gd"
var calls: Array = []
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
 calls.append([position,delta,radius])
 if calls.size() == 2:
  return {"ok":false,"error_code":"custom_second_failure","position":position,"fraction":0.0,"hit_prop_id":""}
 return super.sweep(position,delta,radius)
