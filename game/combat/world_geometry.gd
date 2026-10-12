class_name WorldGeometry
extends RefCounted
# Ground footprints are conservative axis-aligned boxes. Expanding them by the
# actor radius prevents body penetration, including at sprite/roof corners.
const NAV_CLEARANCE := 0.125
const MAX_OBSTACLES := 32
var _nav_world: Dictionary = {}
var _graphs: Dictionary = {}
static func valid(world: Variant) -> bool:
	if not world is Dictionary: return false
	if world.is_empty(): return true # Legacy pure-core fixtures have no map.
	if world.size() != 2 or not _rect_valid(world.get("bounds")) or not world.get("obstacles") is Array or world.obstacles.size() > MAX_OBSTACLES: return false
	var bounds := _rect(world.bounds)
	if bounds.size.x < 64.0 or bounds.size.y < 64.0: return false
	for value in world.obstacles:
		if not _rect_valid(value): return false
		var obstacle := _rect(value)
		if obstacle.position.x < bounds.position.x or obstacle.position.y < bounds.position.y or obstacle.end.x > bounds.end.x or obstacle.end.y > bounds.end.y: return false
	return true
static func canonical(world: Dictionary) -> Dictionary:
	if world.is_empty(): return {}
	var result := {"bounds":[],"obstacles":[]}
	for number in world.bounds: result.bounds.append(float(number))
	for obstacle in world.obstacles:
		var values: Array = []
		for number in obstacle: values.append(float(number))
		result.obstacles.append(values)
	return result
static func walkable(position: Vector2, radius: float, world: Dictionary) -> bool:
	if not is_finite(position.x) or not is_finite(position.y) or not is_finite(radius) or radius < 0: return false
	if world.is_empty(): return true
	var shapes := _prepared(radius,world)
	var bounds: Rect2 = shapes.bounds
	if bounds.size.x < 0 or bounds.size.y < 0 or position.x < bounds.position.x or position.y < bounds.position.y or position.x > bounds.end.x or position.y > bounds.end.y: return false
	for solid: Rect2 in shapes.obstacles:
		if position.x > solid.position.x and position.x < solid.end.x and position.y > solid.position.y and position.y < solid.end.y: return false
	return true
static func move(position: Vector2, delta: Vector2, radius: float, world: Dictionary) -> Vector2:
	if world.is_empty(): return position+delta
	# Swept axes cannot tunnel, even for maximum upgrades or large caller steps.
	# The axis-specific path avoids general ray casts for every walking actor.
	var shapes := _prepared(radius,world)
	var bounds: Rect2 = shapes.bounds
	var next := position
	for axis in 2:
		var other := 1-axis
		var end := clampf(next[axis]+delta[axis],bounds.position[axis],bounds.end[axis])
		for solid: Rect2 in shapes.obstacles:
			if next[other] <= solid.position[other] or next[other] >= solid.end[other]: continue
			if delta[axis] > 0 and next[axis] <= solid.position[axis]: end = minf(end,solid.position[axis])
			elif delta[axis] < 0 and next[axis] >= solid.end[axis]: end = maxf(end,solid.end[axis])
		next[axis] = end
	return next
static func sweep(position: Vector2, delta: Vector2, radius: float, world: Dictionary) -> Vector2:
	if world.is_empty(): return position+delta
	var fraction := _travel_fraction(position,delta,radius,world)
	var result := position+delta*fraction
	# Vector2 is float32: multiplying an exact slab fraction can round inward.
	# Back off by a subpixel only if needed, with no broad walkability epsilon.
	if not walkable(result,radius,world):
		result = position+delta*maxf(0.0,fraction-0.0001/maxf(delta.length(),1.0))
	return result if walkable(result,radius,world) else position
static func nearest_walkable(position: Vector2, radius: float, world: Dictionary) -> Vector2:
	if world.is_empty(): return position
	var bounds := _rect(world.bounds).grow(-radius)
	var point := position.clamp(bounds.position,bounds.end)
	if walkable(point,radius,world): return point
	var best := point
	var distance := INF
	# Project onto every expanded edge and corner. Authored footprints are
	# separated; deterministic tie order is part of spawn/landing replay.
	for value in world.obstacles:
		var solid := _rect(value).grow(radius+NAV_CLEARANCE)
		var candidates := [Vector2(solid.position.x,point.y),Vector2(solid.end.x,point.y),Vector2(point.x,solid.position.y),Vector2(point.x,solid.end.y),solid.position,Vector2(solid.end.x,solid.position.y),solid.end,Vector2(solid.position.x,solid.end.y)]
		for candidate in candidates:
			var test: Vector2 = candidate.clamp(bounds.position,bounds.end)
			var squared := position.distance_squared_to(test)
			if walkable(test,radius,world) and squared < distance:
				best = test
				distance = squared
	return best
func direction(position: Vector2, target: Vector2, radius: float, world: Dictionary) -> Vector2:
	if world.is_empty(): return position.direction_to(target)
	var goal := nearest_walkable(target,radius,world)
	if _visible(position,goal,radius,world): return position.direction_to(goal)
	if _nav_world != world:
		_nav_world = world.duplicate(true)
		_graphs.clear()
	if not _graphs.has(radius): _graphs[radius] = _build_graph(radius,world)
	var graph: Dictionary = _graphs[radius]
	if not graph.has("target") or graph.target != goal: _route_to_goal(graph,goal,radius,world)
	var best := INF
	var waypoint := position
	for index in graph.nodes.size():
		if not is_finite(graph.distances[index]): continue
		var node: Vector2 = graph.nodes[index]
		var cost: float = position.distance_to(node)+graph.distances[index]
		if cost < best and _visible(position,node,radius,world):
			best = cost
			waypoint = node
	return position.direction_to(waypoint)
static func _visible(start: Vector2, end: Vector2, radius: float, world: Dictionary) -> bool:
	return _travel_fraction(start,end-start,radius,world) >= 1.0
static func _build_graph(radius: float, world: Dictionary) -> Dictionary:
	var nodes: Array[Vector2] = []
	for value in world.obstacles:
		var solid := _rect(value).grow(radius+NAV_CLEARANCE)
		for point in [solid.position,Vector2(solid.end.x,solid.position.y),solid.end,Vector2(solid.position.x,solid.end.y)]:
			if walkable(point,radius,world): nodes.append(point)
	var edges: Array = []
	for index in nodes.size():
		var adjacent: Array = []
		for other in nodes.size():
			if other != index and _visible(nodes[index],nodes[other],radius,world): adjacent.append([other,nodes[index].distance_to(nodes[other])])
		edges.append(adjacent)
	return {"nodes":nodes,"edges":edges}
static func _route_to_goal(graph: Dictionary, target: Vector2, radius: float, world: Dictionary) -> void:
	var distances: Array[float] = []
	var visited: Array[bool] = []
	for point in graph.nodes:
		distances.append(point.distance_to(target) if _visible(point,target,radius,world) else INF)
		visited.append(false)
	for iteration in graph.nodes.size():
		var best := INF
		var next := -1
		for index in graph.nodes.size():
			if not visited[index] and distances[index] < best:
				best = distances[index]
				next = index
		if next < 0: break
		visited[next] = true
		for edge in graph.edges[next]: distances[edge[0]] = minf(distances[edge[0]],best+edge[1])
	graph.target = target
	graph.distances = distances
static func _travel_fraction(position: Vector2, delta: Vector2, radius: float, world: Dictionary) -> float:
	if world.is_empty(): return 1.0
	var shapes := _prepared(radius,world)
	var bounds: Rect2 = shapes.bounds
	var fraction := 1.0
	for axis in 2:
		if delta[axis] > 0: fraction = minf(fraction,(bounds.end[axis]-position[axis])/delta[axis])
		elif delta[axis] < 0: fraction = minf(fraction,(bounds.position[axis]-position[axis])/delta[axis])
	for solid: Rect2 in shapes.obstacles:
		var enter := -INF
		var leave := INF
		var crosses := true
		for axis in 2:
			if delta[axis] == 0:
				if position[axis] <= solid.position[axis] or position[axis] >= solid.end[axis]:
					crosses = false
					break
			else:
				var first: float = (solid.position[axis]-position[axis])/delta[axis]
				var last: float = (solid.end[axis]-position[axis])/delta[axis]
				enter = maxf(enter,minf(first,last))
				leave = minf(leave,maxf(first,last))
		if crosses and leave > maxf(0.0,enter) and enter < fraction: fraction = maxf(0.0,enter)
	return clampf(fraction,0.0,1.0)
static func _prepared(radius: float, world: Dictionary) -> Dictionary:
	# Pure local shapes: no cross-thread mutable static collision cache.
	var obstacles: Array[Rect2] = []
	for value in world.obstacles: obstacles.append(_rect(value).grow(radius))
	return {"bounds":_rect(world.bounds).grow(-radius),"obstacles":obstacles}
static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
static func _rect_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 4: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 100000: return false
	return float(value[2]) > 0 and float(value[3]) > 0
