class_name StreamedNavigationView
extends RefCounted
# NEW derived navigation-only view. Exact CityNavigation reads these immutable
# geometry records; collision decisions still come from the real StreamedWorld.
# Own one view per prepared world. Never reuse it for a different world/run.
var _world
var _coverage_revision := -1
var _world_revision := -1
var _by_id: Dictionary = {}
var _by_origin: Dictionary = {}
var _keys: Array = []
var _view: Dictionary = {}
var _empty: Dictionary = {}
# NEW distinguish an obstructed route from a failed real geometry query.
var _query_failure: Dictionary = {}
func _init(world) -> void:
	_world = world
	_empty.make_read_only()
func begin_navigation_queries() -> void: _query_failure.clear()
func navigation_query_status() -> Dictionary:
	return {"ok":true} if _query_failure.is_empty() else _query_failure.duplicate(true)
func walkable(position: Vector2, radius: float) -> bool:
	if not _world.covered(Rect2(position-Vector2.ONE*radius,Vector2.ONE*radius*2.0)):
		_observe_query({"ok":false,"error_code":"world_not_ready"})
		return false
	return _world.walkable(position,radius)
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	return _observe_query(_world.sweep(position,delta,radius))
func visibility_query(position: Vector2, target: Vector2, radius: float) -> Dictionary:
	var delta := target-position
	if get_script() != StreamedNavigationView or (_world.get_script() != ExactSmoothingStream and _world.get_script() != CachedSmoothingStream) or not _query_failure.is_empty() or not _world._last_error.is_empty() or not ExactSmoothingStream._valid_query(position,delta,radius):
		return _visibility_full_sweep(position,delta,radius)
	var bounds: Rect2 = ExactSmoothingStream._swept_rect(position,delta,radius)
	if not _visibility_domain_ready(bounds,position,delta,radius): return _visibility_full_sweep(position,delta,radius)
	# Exact World/CachedWorld borrow these same immutable collision records.
	# Navigation needs only fraction==1, not nearest hit identity, corrected
	# position or endpoint walkability. Mask4/8/16 alone must remain invisible
	# to this mask3 reader even when the original final position is corrected.
	for prop in _world._collision_query_props(bounds):
		if (int(prop.collision_mask) & 3) != 0 and ExactSmoothingStream.slab_fraction(position,delta,prop.ground_footprint.grow(radius)) < 1.0:
			return {"ok":true,"visible":false}
	return {"ok":true,"visible":true}
func _visibility_full_sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	var hit: Dictionary = sweep(position,delta,radius)
	return {"ok":hit.ok,"visible":hit.ok and hit.fraction == 1.0}
func _visibility_domain_ready(bounds: Rect2, position: Vector2, delta: Vector2, radius: float) -> bool:
	if _coverage_revision != _world._coverage_revision or _world_revision != _world._world_revision: _refresh(_world.diagnostics())
	# Keep the original half-open/point span and its >8 refusal. Every native
	# result/backoff point lies between position and position+delta. Using the
	# same Vector2 operation order as walkable bounds its rounded upper edge;
	# the original swept lower edge already bounds all those lower edges.
	# Do not regroup the radius products or replace the reconstructed endpoint
	# with target: float32 rounding and zero-size branches are part of the proof.
	# This check is read-only; refusal falls back without latching last_error.
	var low_x := int(floor(bounds.position.x/768))
	var high_x := int(floor((bounds.end.x-0.0001 if bounds.size.x > 0 else bounds.end.x)/768))
	var low_y := int(floor(bounds.position.y/768))
	var high_y := int(floor((bounds.end.y-0.0001 if bounds.size.y > 0 else bounds.end.y)/768))
	if high_x-low_x > 8 or high_y-low_y > 8: return false
	var upper: Vector2 = position.max(position+delta)
	var endpoint: Rect2 = Rect2(upper-Vector2.ONE*radius,Vector2.ONE*radius*2)
	var endpoint_high_x := int(floor((endpoint.end.x-0.0001 if endpoint.size.x > 0 else endpoint.end.x)/768))
	var endpoint_high_y := int(floor((endpoint.end.y-0.0001 if endpoint.size.y > 0 else endpoint.end.y)/768))
	high_x = maxi(high_x,endpoint_high_x)
	high_y = maxi(high_y,endpoint_high_y)
	for y in range(low_y,high_y+1):
		for x in range(low_x,high_x+1):
			if not _by_origin.has(Vector2(x*768,y*768)): return false
	return true
func _observe_query(result: Dictionary) -> Dictionary:
	if not result.get("ok",false) and _query_failure.is_empty(): _query_failure = result.duplicate(true)
	return result
func diagnostics() -> Dictionary:
	var current: Dictionary = _world.diagnostics()
	_refresh(current)
	return current
func chunk_keys() -> Array:
	_refresh(_world.diagnostics())
	return _keys
func localized_chunk(key: String) -> Dictionary:
	_refresh(_world.diagnostics())
	return _by_id.get(key,_empty)
func chunk_at(position: Vector2) -> Dictionary:
	_refresh(_world.diagnostics())
	if not is_finite(position.x) or not is_finite(position.y) or absf(position.x) > 49152 or absf(position.y) > 49152: return _empty
	var origin := Vector2(floor(position.x/768)*768,floor(position.y/768)*768)
	return _by_origin.get(origin,_empty)
func render_view() -> Dictionary:
	# Navigation's existing duck-typed API requires this method name. This is
	# deliberately not a presentation view: it contains no sprites or art data.
	_refresh(_world.diagnostics())
	return _view
func _refresh(current: Dictionary) -> void:
	if current.coverage_revision == _coverage_revision and current.world_revision == _world_revision: return
	# StreamedWorld's public mutations advance coverage on origin/residency
	# changes and world_revision on damage (also advancing geometry_revision).
	# Rebuild privately, one localized chunk at a time. Unchanged warm queries
	# allocate no chunk/prop snapshots and never call the world's render_view.
	var by_id := {}
	var by_origin := {}
	var chunks: Array = []
	for key in _world.chunk_keys():
		var source: Dictionary = _world.localized_chunk(key)
		var props: Array = []
		for original in source.props:
			var prop := {"collision_mask":original.collision_mask,"ground_footprint":original.ground_footprint}
			prop.make_read_only()
			props.append(prop)
		props.make_read_only()
		var chunk := {"chunk_id":source.chunk_id,"geometry_revision":source.geometry_revision,"local_origin":source.local_origin,"props":props}
		chunk.make_read_only()
		by_id[key] = chunk
		by_origin[chunk.local_origin] = chunk
		chunks.append(chunk)
	# Same ordering as the exact render view: absolute y then x, expressed
	# locally without lossy conversion of potentially int64 chunk addresses.
	chunks.sort_custom(func(a,b): return a.local_origin.y < b.local_origin.y or (a.local_origin.y == b.local_origin.y and a.local_origin.x < b.local_origin.x))
	chunks.make_read_only()
	var keys: Array = by_id.keys()
	keys.make_read_only()
	var view := {"chunks":chunks}
	view.make_read_only()
	by_id.make_read_only()
	by_origin.make_read_only()
	_by_id = by_id; _by_origin = by_origin; _keys = keys; _view = view
	_coverage_revision = current.coverage_revision
	_world_revision = current.world_revision

# Current exact StreamedWorld._sweep fails only on invalid arguments or absent
# coverage. This pure precheck uses the already-owned immutable chunk index;
# it never calls covered/query_props, changes last_error, or observes a query.
# Custom/derived sweep implementations can add failure modes, so stay forward.
const ExactSmoothingStream = preload("res://game/world/streamed_world.gd")
const CachedSmoothingStream = preload("res://game/world/cached_streamed_world.gd")
func smoothing_queries_safe(start: Vector2, points: Array, first: int, radius: float) -> bool:
	if _world.get_script() != ExactSmoothingStream and _world.get_script() != CachedSmoothingStream: return false
	if not _query_failure.is_empty(): return false
	_refresh(_world.diagnostics())
	if first < 0 or first >= points.size(): return false
	var low_x := 0
	var high_x := 0
	var low_y := 0
	var high_y := 0
	for next in range(first,points.size()):
		if not points[next] is Vector2: return false
		var delta: Vector2 = points[next]-start
		if not ExactSmoothingStream._valid_query(start,delta,radius): return false
		var bounds: Rect2 = ExactSmoothingStream._swept_rect(start,delta,radius)
		# Match covered() on each actual segment before combining integers.
		# Rect2.merge can round an endpoint inward across a chunk boundary.
		var segment_low_x := int(floor(bounds.position.x/768))
		var segment_high_x := int(floor((bounds.end.x-0.0001 if bounds.size.x > 0 else bounds.end.x)/768))
		var segment_low_y := int(floor(bounds.position.y/768))
		var segment_high_y := int(floor((bounds.end.y-0.0001 if bounds.size.y > 0 else bounds.end.y)/768))
		low_x = segment_low_x if next == first else mini(low_x,segment_low_x)
		high_x = segment_high_x if next == first else maxi(high_x,segment_high_x)
		low_y = segment_low_y if next == first else mini(low_y,segment_low_y)
		high_y = segment_high_y if next == first else maxi(high_y,segment_high_y)
	# This integer superset may reject a safe batch conservatively, but cannot
	# omit any actual segment cell. Fallback leaves all diagnostics untouched.
	if high_x-low_x > 8 or high_y-low_y > 8: return false
	for y in range(low_y,high_y+1):
		for x in range(low_x,high_x+1):
			if not _by_origin.has(Vector2(x*768,y*768)): return false
	return true

func _smoothing_scope_ready(start: Vector2, points: Array, radius: float) -> bool:
	# Scalar hull padding is proof slack only, never collision geometry.
	# At |endpoint| <= 8192 each ray is valid; one pixel exceeds every
	# native swept/reconstructed-endpoint roundoff bound in this domain.
	if points.is_empty(): return false
	if get_script() != StreamedNavigationView or (_world.get_script() != ExactSmoothingStream and _world.get_script() != CachedSmoothingStream): return false
	if not _query_failure.is_empty() or not _world._last_error.is_empty(): return false
	_refresh(_world.diagnostics())
	if not is_finite(radius) or radius < 0 or radius > 32: return false
	if not is_finite(start.x) or not is_finite(start.y) or absf(start.x) > 8192 or absf(start.y) > 8192: return false
	var min_x: float = start.x
	var max_x: float = start.x
	var min_y: float = start.y
	var max_y: float = start.y
	for point in points:
		if not point is Vector2: return false
		if not is_finite(point.x) or not is_finite(point.y) or absf(point.x) > 8192 or absf(point.y) > 8192: return false
		min_x = minf(min_x,point.x); max_x = maxf(max_x,point.x)
		min_y = minf(min_y,point.y); max_y = maxf(max_y,point.y)
	var pad: float = radius+1.0
	var low_x := int(floor((min_x-pad)/768))
	var high_x := int(floor((max_x+pad)/768))
	var low_y := int(floor((min_y-pad)/768))
	var high_y := int(floor((max_y+pad)/768))
	if high_x-low_x > 8 or high_y-low_y > 8: return false
	for y in range(low_y,high_y+1):
		for x in range(low_x,high_x+1):
			if not _by_origin.has(Vector2(x*768,y*768)): return false
	return true
func _visibility_prepared(position: Vector2, target: Vector2, radius: float) -> Dictionary:
	# Called only inside the admitted synchronous smoothing scope. Keep the
	# original scalar bounds, query/cache warming and collision order intact.
	var delta := target-position
	var bounds: Rect2 = ExactSmoothingStream._swept_rect(position,delta,radius)
	for prop in _world._collision_query_props(bounds):
		if (int(prop.collision_mask) & 3) != 0 and ExactSmoothingStream.slab_fraction(position,delta,prop.ground_footprint.grow(radius)) < 1.0:
			return {"ok":true,"visible":false}
	return {"ok":true,"visible":true}
