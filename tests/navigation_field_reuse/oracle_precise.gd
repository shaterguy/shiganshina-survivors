extends "res://tests/navigation_field_reuse/oracle_navigation.gd"
# NEW cache-key correction around the byte-preserved navigation algorithm.
# Reverse-field seeds depend on the exact goal and physical radius, not only
# their grid cell/clearance class. Keep immutable geometry flags when they vary.
func _local_route(chunk: Dictionary, start: Vector2, goal: Vector2, clearance: int, radius: float, tick: int) -> Dictionary:
	var key: String = "%s:%d"%[chunk.chunk_id,clearance]
	if _grids.has(key):
		var grid: Dictionary = _grids[key]
		if not grid.has("precise_goal") or grid.precise_goal != goal or not grid.has("precise_radius") or grid.precise_radius != radius:
			grid.erase("target")
	return super._local_route(chunk,start,goal,clearance,radius,tick)
func _distances(grid: Dictionary, target: int, goal: Vector2, radius: float, tick: int) -> void:
	super._distances(grid,target,goal,radius,tick)
	grid.precise_goal = goal
	grid.precise_radius = radius
