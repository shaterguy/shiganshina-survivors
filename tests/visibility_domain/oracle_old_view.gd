extends RefCounted
# Exact original functions, mechanically adapted to a real native View.
# Neither function calls the candidate proof. Static reconstruction is checked.
const View = preload("res://game/world/streamed_navigation_view.gd")
const ExactSmoothingStream = preload("res://game/world/streamed_world.gd")
const CachedSmoothingStream = preload("res://game/world/cached_streamed_world.gd")
static func visibility_query(view, position: Vector2, target: Vector2, radius: float) -> Dictionary:
	var delta := target-position
	if view.get_script() != View or (view._world.get_script() != ExactSmoothingStream and view._world.get_script() != CachedSmoothingStream) or not view._query_failure.is_empty() or not view._world._last_error.is_empty() or not ExactSmoothingStream._valid_query(position,delta,radius):
		return view._visibility_full_sweep(position,delta,radius)
	var bounds: Rect2 = ExactSmoothingStream._swept_rect(position,delta,radius)
	if not domain_ready(view,bounds): return view._visibility_full_sweep(position,delta,radius)
	# Exact World/CachedWorld borrow these same immutable collision records.
	# Navigation needs only fraction==1, not nearest hit identity, corrected
	# position or endpoint walkability. Mask4/8/16 alone must remain invisible
	# to this mask3 reader even when the original final position is corrected.
	for prop in view._world._collision_query_props(bounds):
		if (int(prop.collision_mask) & 3) != 0 and ExactSmoothingStream.slab_fraction(position,delta,prop.ground_footprint.grow(radius)) < 1.0:
			return {"ok":true,"visible":false}
	return {"ok":true,"visible":true}
static func domain_ready(view, bounds: Rect2) -> bool:
	if view._coverage_revision != view._world._coverage_revision or view._world_revision != view._world._world_revision: view._refresh(view._world.diagnostics())
	# Keep the original half-open/point span and its >8 refusal. A whole extra
	# resident cell on every side conservatively contains every separately
	# rounded endpoint/backoff walkable rectangle of the full sweep. The
	# original valid-query limits bound coordinates below 100000 and radius32;
	# float32 reconstruction error cannot approach a 768px padding cell.
	# This proof is read-only: a failed proof must not itself latch last_error.
	var low_x := int(floor(bounds.position.x/768))
	var high_x := int(floor((bounds.end.x-0.0001 if bounds.size.x > 0 else bounds.end.x)/768))
	var low_y := int(floor(bounds.position.y/768))
	var high_y := int(floor((bounds.end.y-0.0001 if bounds.size.y > 0 else bounds.end.y)/768))
	if high_x-low_x > 8 or high_y-low_y > 8: return false
	for y in range(low_y-1,high_y+2):
		for x in range(low_x-1,high_x+2):
			if not view._by_origin.has(Vector2(x*768,y*768)): return false
	return true
