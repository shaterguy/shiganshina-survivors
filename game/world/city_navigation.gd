class_name CityNavigation
extends RefCounted
const SafeSmoothingView = preload("res://game/world/streamed_navigation_view.gd")
const CLASSES := [8,16,18,20,24,28,30,32]
const CELL := 32
const SIDE := 24
var _world
var _grids: Dictionary = {}
var _grid_builds := 0
var _route_builds := 0
var _coverage_revision := -1
var _direction_los: Dictionary = {}
var _tick_los: Dictionary = {}
const MAX_TICK_LOS := 4096
func _init(world) -> void:
	_world = world
static func clearance_class(radius: float) -> int:
	if not is_finite(radius) or radius < 0: return -1
	for value in CLASSES:
		if value >= radius: return value
	return -1
func direction(position: Vector2, target: Vector2, radius: float, tick: int) -> Dictionary:
	# Exact immutable geometry may share successful LOS observations between
	# actors in one tick. Unknown callbacks still use the authoritative path.
	_direction_los = _direction_reuse_scope()
	if not _direction_los.is_empty():
		if not _tick_los.is_empty() and _tick_los.tick == tick and _tick_los.view == _direction_los.view and _tick_los.source == _direction_los.source and _tick_los.coverage == _direction_los.coverage and _tick_los.revision == _direction_los.revision and _tick_los.origin == _direction_los.origin:
			_direction_los.queries = _tick_los.queries
		_direction_los.tick = tick
	_tick_los = _direction_los
	var result: Dictionary = _direction_impl(position,target,radius,tick)
	# Private queries outside direction must never use this memo. Failed real
	# sweeps clear the shared scope, retiring the tick memo at the same time.
	_direction_los = {}
	return result
func _direction_reuse_scope() -> Dictionary:
	# Derived navigation/view/world callbacks can mutate geometry or add failures.
	# Load the known derived script at runtime to avoid a cyclic base preload.
	if get_script() != CityNavigation and get_script() != load("res://game/world/precise_city_navigation.gd"): return {}
	if _world.get_script() != SafeSmoothingView: return {}
	var source = _world._world
	if source.get_script() != SafeSmoothingView.ExactSmoothingStream and source.get_script() != SafeSmoothingView.CachedSmoothingStream: return {}
	if not _world._query_failure.is_empty() or not source._last_error.is_empty(): return {}
	return {"view":_world,"source":source,"coverage":source._coverage_revision,"revision":source._world_revision,"origin":source._origin.duplicate(),"queries":{}}
func _direction_impl(position: Vector2, target: Vector2, radius: float, tick: int) -> Dictionary:
	var clearance := clearance_class(radius)
	if clearance < 0: return _failure("unsupported_radius")
	_prune()
	if not _world.walkable(position,radius) or not _world.walkable(target,radius): return _failure("blocked")
	if _visible(position,target,radius): return _success(position,[target])
	var start_chunk: Dictionary = _world.chunk_at(position)
	var target_chunk: Dictionary = _world.chunk_at(target)
	if start_chunk.is_empty() or target_chunk.is_empty(): return _failure("world_not_ready")
	var chunks: Array = _chunk_path(start_chunk,target_chunk)
	if chunks.is_empty(): return _failure("world_not_ready")
	var points: Array = []
	var current := position
	for i in chunks.size():
		var chunk: Dictionary = chunks[i]
		var goal := target
		if i+1 < chunks.size():
			var change: Vector2 = chunks[i+1].local_origin-chunk.local_origin
			goal = chunk.local_origin+Vector2(384,384)+change.normalized()*384
		var local: Dictionary = _local_route(chunk,current,goal,clearance,radius,tick)
		if not local.ok: return local
		points.append_array(local.waypoints)
		current = goal
	return _success(position,_smooth(position,points,radius))
func invalidate(chunk_ids: Array) -> void:
	for key in _grids.keys():
		if _grids[key].chunk_id in chunk_ids: _grids.erase(key)
func diagnostics() -> Dictionary:
	return {"grid_count":_grids.size(),"grid_builds":_grid_builds,"route_builds":_route_builds}
func _prune() -> void:
	var coverage: int = _world.diagnostics().coverage_revision
	if coverage != _coverage_revision:
		# Grids contain local positions, so coverage/origin changes retire derived data.
		var live: Array = _world.chunk_keys()
		for key in _grids.keys():
			var chunk: Dictionary = _world.localized_chunk(_grids[key].chunk_id)
			if not _grids[key].chunk_id in live or chunk.get("local_origin") != _grids[key].local_origin: _grids.erase(key)
		_coverage_revision = coverage
func _chunk_path(start: Dictionary, goal: Dictionary) -> Array:
	if start.chunk_id == goal.chunk_id: return [start]
	var chunks: Array = _world.render_view().chunks
	var indexed := {}
	for chunk in chunks: indexed[chunk.local_origin] = chunk
	var queue: Array = [start.local_origin]
	var previous := {start.local_origin:start.local_origin}
	var head := 0
	while head < queue.size():
		var point: Vector2 = queue[head]
		head += 1
		if point == goal.local_origin: break
		for step in [Vector2(0,-768),Vector2(-768,0),Vector2(768,0),Vector2(0,768)]:
			var next: Vector2 = point+step
			if indexed.has(next) and not previous.has(next):
				previous[next] = point
				queue.append(next)
	if not previous.has(goal.local_origin): return []
	var result: Array = []
	var cursor: Vector2 = goal.local_origin
	while cursor != start.local_origin:
		result.push_front(indexed[cursor])
		cursor = previous[cursor]
	result.push_front(start)
	return result
func _local_route(chunk: Dictionary, start: Vector2, goal: Vector2, clearance: int, radius: float, tick: int) -> Dictionary:
	if _visible(start,goal,radius): return {"ok":true,"waypoints":[goal]}
	var key: String = "%s:%d" % [chunk.chunk_id,clearance]
	if not _grids.has(key) or _grids[key].revision != chunk.geometry_revision:
		_grids[key] = _build_grid(chunk,clearance)
	var grid: Dictionary = _grids[key]
	var local_goal: Vector2 = goal-chunk.local_origin
	var gx := clampi(int(floor(local_goal.x/CELL)),0,23)
	var gy := clampi(int(floor(local_goal.y/CELL)),0,23)
	var target_cell := gy*SIDE+gx
	if not grid.has("target") or grid.target != target_cell or tick-grid.tick >= 12 or tick < grid.tick:
		_distances(grid,target_cell,goal,radius,tick)
	var best := -1
	var best_cost := INF
	var local_start: Vector2 = start-chunk.local_origin
	var sx := clampi(int(floor(local_start.x/CELL)),0,23)
	var sy := clampi(int(floor(local_start.y/CELL)),0,23)
	for y in range(maxi(0,sy-1),mini(24,sy+2)):
		for x in range(maxi(0,sx-1),mini(24,sx+2)):
			var id := y*24+x
			if grid.distances[id] < 0: continue
			var point: Vector2 = _center(id,grid.local_origin)
			var cost: float = start.distance_to(point)+grid.distances[id]
			if cost < best_cost and _visible(start,point,radius):
				best = id
				best_cost = cost
	if best < 0: return _failure("blocked")
	var points: Array = [_center(best,grid.local_origin)]
	var cursor := best
	var guard := 0
	while grid.distances[cursor] > 0:
		guard += 1
		if guard > 576: return _failure("blocked")
		var next := -1
		for neighbor in _neighbors(cursor):
			if grid.distances[neighbor] >= 0 and grid.distances[neighbor] < grid.distances[cursor] and (next < 0 or grid.distances[neighbor] < grid.distances[next] or (grid.distances[neighbor] == grid.distances[next] and neighbor < next)): next = neighbor
		if next < 0: return _failure("blocked")
		points.append(_center(next,grid.local_origin))
		cursor = next
	if not _visible(points.back(),goal,radius): return _failure("blocked")
	points.append(goal)
	return {"ok":true,"waypoints":_smooth(start,points,radius)}
func _build_grid(chunk: Dictionary, clearance: int) -> Dictionary:
	_grid_builds += 1
	var flags := PackedByteArray()
	flags.resize(576)
	for id in 576:
		var point: Vector2 = _center(id,chunk.local_origin)
		flags[id] = 1
		for prop in chunk.props:
			if prop.collision_mask == 0: continue
			var box: Rect2 = prop.ground_footprint.grow(clearance)
			if point.x > box.position.x and point.x < box.end.x and point.y > box.position.y and point.y < box.end.y: flags[id] = 0; break
	return {"chunk_id":chunk.chunk_id,"revision":chunk.geometry_revision,"local_origin":chunk.local_origin,"flags":flags}
func _distances(grid: Dictionary, target: int, goal: Vector2, radius: float, tick: int) -> void:
	_route_builds += 1
	var distances := PackedInt32Array()
	distances.resize(576)
	distances.fill(-1)
	var queue: Array[int] = []
	# A cached reverse shortest-path field is the unit-cost cardinal-grid form
	# of Dijkstra. Packed arrays avoid per-cell dictionaries and repeated A*.
	if grid.flags[target] and _visible(_center(target,grid.local_origin),goal,radius):
		distances[target] = 0
		queue.append(target)
	else:
		for id in _neighbors(target):
			if grid.flags[id] and _visible(_center(id,grid.local_origin),goal,radius):
				distances[id] = 0
				queue.append(id)
	var head := 0
	while head < queue.size():
		var id := queue[head]
		head += 1
		for next in _neighbors(id):
			if grid.flags[next] and distances[next] < 0:
				distances[next] = distances[id]+CELL
				queue.append(next)
	grid.distances = distances
	grid.target = target
	grid.tick = tick
func _smooth(start: Vector2, points: Array, radius: float) -> Array:
	var result: Array = []
	var current := start
	var index := 0
	while index < points.size():
		var best := index
		# The exact stream can prove these queries cannot fail before reordering.
		# Unknown worlds or unsafe query domains retain original error observation.
		if _world.get_script() == SafeSmoothingView and _world.smoothing_queries_safe(current,points,index,radius):
			for next in range(points.size()-1,index-1,-1):
				if _visible(current,points[next],radius):
					best = next
					break
		else:
			for next in range(index,points.size()):
				if _visible(current,points[next],radius): best = next
		result.append(points[best])
		current = points[best]
		index = best+1
	return result
func _visible(a: Vector2, b: Vector2, radius: float) -> bool:
	var key: Array = []
	if not _direction_los.is_empty():
		var source = _direction_los.source
		if _world != _direction_los.view or _world._world != source or source._coverage_revision != _direction_los.coverage or source._world_revision != _direction_los.revision or source._origin != _direction_los.origin or not _world._query_failure.is_empty() or not source._last_error.is_empty():
			_direction_los.clear()
		else:
			# Variant Array keys keep exact Vector2 endpoints and float radius.
			# Do not round, reconstruct the endpoint, or equate reverse segments.
			key = [a,b,radius]
			if _direction_los.queries.has(key): return _direction_los.queries[key]
	var hit: Dictionary = _world.sweep(a,b-a,radius)
	var visible: bool = hit.ok and hit.fraction == 1.0
	if not _direction_los.is_empty():
		# A blocked successful sweep is reusable; a failed query never is.
		if hit.ok:
			if _direction_los.queries.size() < MAX_TICK_LOS: _direction_los.queries[key] = visible
		else: _direction_los.clear()
	return visible
static func _neighbors(id: int) -> Array[int]:
	var result: Array[int] = []
	if id >= SIDE: result.append(id-SIDE)
	if id%SIDE > 0: result.append(id-1)
	if id%SIDE < SIDE-1: result.append(id+1)
	if id < SIDE*(SIDE-1): result.append(id+SIDE)
	return result
static func _center(id: int, offset: Vector2) -> Vector2:
	return offset+Vector2((id%SIDE)*CELL+16,(id/SIDE)*CELL+16)
static func _failure(code: String) -> Dictionary:
	return {"ok":false,"direction":Vector2.ZERO,"waypoints":[],"length":0.0,"error_code":code}
static func _success(start: Vector2, points: Array) -> Dictionary:
	var length := 0.0
	var current := start
	for point in points:
		length += current.distance_to(point)
		current = point
	return {"ok":true,"direction":start.direction_to(points[0]) if not points.is_empty() else Vector2.ZERO,"waypoints":points,"length":length,"error_code":""}
