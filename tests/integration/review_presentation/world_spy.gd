extends "res://game/presentation/world_view.gd"
var draw_calls: Array[Dictionary] = []
func _draw_city() -> void:
	pass
func _draw_props() -> void:
	pass
func _draw_telegraph(_hazard: Dictionary) -> void:
	pass
func _sprite(asset_id: String, world: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
	draw_calls.append({"id":asset_id,"world":world,"animation":animation,"scale":scale_value,"flip":flip,"seconds":seconds})
