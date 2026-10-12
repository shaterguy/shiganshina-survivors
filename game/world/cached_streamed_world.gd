class_name CachedStreamedWorld
extends "res://game/world/streamed_world.gd"
# NEW derived coverage cache. Collision/movement algorithms remain inherited.
# A successful exact single-cell query is the only source of a cached entry.
var _covered_cells: Dictionary = {}
var _covered_revision := -1
var _covered_origin: Array = []
var _coverage_cell_checks := 0
var _coverage_hits := 0
var _coverage_fallbacks := 0
func _collision_query_props(aabb: Rect2) -> Array:
	# Coverage alone differs here; inherited collision readers never mutate props.
	# Further subclasses may override callbacks and must keep owned snapshots.
	if get_script() != CachedStreamedWorld: return query_props(aabb)
	return _query_props(aabb,false)
func _collision_box(prop: Dictionary, radius: float) -> Rect2:
	# The exact coverage-only subtype has the same immutable collision geometry.
	if get_script() == CachedStreamedWorld: return prop.ground_footprint.grow(radius)
	return super._collision_box(prop,radius)
func covered(aabb: Rect2) -> bool:
	if not _cacheable_rectangle(aabb):
		_coverage_fallbacks += 1
		return super.covered(aabb)
	if _covered_revision != _coverage_revision or _covered_origin != _origin:
		_covered_cells.clear()
		_covered_revision = _coverage_revision
		_covered_origin = _origin.duplicate()
	# Identical half-open/point epsilon convention to the exact base method.
	var low_x := int(floor(aabb.position.x/768))
	var high_x := int(floor((aabb.end.x-0.0001 if aabb.size.x > 0 else aabb.end.x)/768))
	var low_y := int(floor(aabb.position.y/768))
	var high_y := int(floor((aabb.end.y-0.0001 if aabb.size.y > 0 else aabb.end.y)/768))
	if high_x-low_x > 8 or high_y-low_y > 8:
		_coverage_fallbacks += 1
		return super.covered(aabb)
	for y in range(low_y,high_y+1):
		for x in range(low_x,high_x+1):
			var cell := Vector2i(x,y)
			if _covered_cells.has(cell):
				_coverage_hits += 1
				continue
			_coverage_cell_checks += 1
			if not super.covered(Rect2(Vector2(x*768,y*768),Vector2.ZERO)): return false
			_covered_cells[cell] = true
	return true
func _cacheable_rectangle(value: Rect2) -> bool:
	if value.size.x < 0 or value.size.y < 0: return false
	for scalar in [value.position.x,value.position.y,value.end.x,value.end.y,value.size.x,value.size.y]:
		if not is_finite(scalar) or absf(scalar) > 49152.0: return false
	return true
func coverage_cache_stats() -> Dictionary:
	return {"cells":_covered_cells.size(),"cell_checks":_coverage_cell_checks,"hits":_coverage_hits,"fallbacks":_coverage_fallbacks,"coverage_revision":_covered_revision,"origin":_covered_origin.duplicate()}
