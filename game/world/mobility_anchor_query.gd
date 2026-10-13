class_name MobilityAnchorQuery
extends RefCounted
# Bounded deterministic proposals, without RNG, damage or mutable physics.
const Address = preload("res://game/world/world_address.gd")
const Props = preload("res://game/world/world_prop_catalog.gd")
const MAX_DISTANCE := 320.0
const EDGE_MARGIN := 4.0
const LANDING_DISTANCE := 24.0
static func candidates(state: Dictionary, direction: Vector2, helper) -> Dictionary:
	if helper == null or not state.get("world") is Dictionary or state.world.get("stage") != "city" or not state.get("player") is Dictionary: return _failure("no_mobility_path")
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.length_squared() < 0.000001: return _failure("no_mobility_path")
	var from := Vector2(state.player.position[0],state.player.position[1])
	var forward := direction.normalized()
	var end := from+forward*MAX_DISTANCE
	var radius := float(state.player.radius)
	var rectangle := Rect2(from.min(end)-Vector2.ONE*(radius+96), (end-from).abs()+Vector2.ONE*(radius+96)*2)
	var queried: Dictionary = helper.mobility_geometry(state,rectangle)
	if not queried.get("ok",false): return queried
	var ranked := []
	for anchor in queried.anchors:
		var relative := Address.relative(anchor.chunk,Vector2(anchor.local[0],anchor.local[1]),state.world.origin_chunk)
		if not relative.ok: continue
		var offset: Vector2 = relative.local-from
		var distance := offset.length_squared()
		if distance <= 0.0 or distance > MAX_DISTANCE*MAX_DISTANCE or offset.dot(forward) <= 0.0: continue
		ranked.append({"anchor":anchor,"distance":distance,"direction":offset.normalized().dot(forward)})
	ranked.sort_custom(func(a,b):
		if a.distance != b.distance: return a.distance < b.distance
		if a.direction != b.direction: return a.direction > b.direction
		return a.anchor.prop_id < b.anchor.prop_id)
	var anchors := []
	for item in ranked: anchors.append(item.anchor)
	return {"ok":true,"anchors":anchors}
static func plan(state: Dictionary, direction: Vector2, helper) -> Dictionary:
	var offered := candidates(state,direction,helper)
	if not offered.get("ok",false): return offered
	var from := Vector2(state.player.position[0],state.player.position[1])
	var forward := direction.normalized()
	var radius := float(state.player.radius)
	var grounded: Dictionary = helper.walkable(from,radius)
	if not grounded.get("ok",false): return grounded
	if not grounded.get("walkable",false): return _failure("no_mobility_path")
	for offered_anchor in offered.anchors:
		var anchor: Dictionary = offered_anchor.duplicate(true)
		var connected := Address.relative(anchor.chunk,Vector2(anchor.local[0],anchor.local[1]),state.world.origin_chunk)
		if not connected.ok: continue
		var box := Props.rect(anchor.pass_range)
		box.position += connected.local-Vector2(anchor.connection[0],anchor.connection[1])
		box = box.grow(radius)
		var interval := _ray_interval(from,forward,box)
		if interval.is_empty() or interval[0] < 16.0: continue
		var entry := float(interval[0])-EDGE_MARGIN
		var exit := float(interval[1])+EDGE_MARGIN
		var distance := exit+LANDING_DISTANCE
		if distance > MAX_DISTANCE: continue
		var rise := from+forward*entry
		var over := from+forward*exit
		var landing := from+forward*distance
		var path := [_point(state.world.origin_chunk,from,0.0,anchor.geometry_revision),_point(state.world.origin_chunk,rise,float(anchor.roof_height),anchor.geometry_revision),_point(state.world.origin_chunk,over,float(anchor.roof_height),anchor.geometry_revision),_point(state.world.origin_chunk,landing,0.0,anchor.geometry_revision)]
		if path.any(func(value): return value.is_empty()): continue
		anchor.pass_start = path[1].duplicate(true)
		anchor.pass_end = path[2].duplicate(true)
		var approached: Dictionary = helper.sweep(from,rise-from,radius)
		if not approached.get("ok",false): return approached
		if approached.get("fraction",0.0) < 1.0: continue
		var crossed: Dictionary = helper.mobility_sweep(state,rise,over-rise,radius,anchor,float(anchor.roof_height))
		if not crossed.get("ok",false):
			if crossed.get("error_code") == "world_not_ready": return crossed
			continue
		if crossed.get("fraction",0.0) < 1.0: continue
		var descended: Dictionary = helper.sweep(over,landing-over,radius)
		if not descended.get("ok",false): return descended
		if descended.get("fraction",0.0) < 1.0:
			# Dense alleys can be shorter than the nominal descent. Use the
			# actual normal sweep, retaining clearance before the next solid.
			var safe_distance := LANDING_DISTANCE*float(descended.fraction)-EDGE_MARGIN
			if safe_distance < EDGE_MARGIN: continue
			landing = over+forward*safe_distance
			path[3] = _point(state.world.origin_chunk,landing,0.0,anchor.geometry_revision)
			if path[3].is_empty(): continue
		var safe: Dictionary = helper.walkable(landing,radius)
		if not safe.get("ok",false): return safe
		if not safe.get("walkable",false): continue
		return {"ok":true,"path":path,"anchor":anchor,"landing":path[3].duplicate(true),"direction":[forward.x,forward.y]}
	return _failure("no_mobility_path")
static func _ray_interval(from: Vector2, direction: Vector2, rectangle: Rect2) -> Array:
	var entering := -INF
	var leaving := INF
	for axis in 2:
		if absf(direction[axis]) < 0.000001:
			if from[axis] <= rectangle.position[axis] or from[axis] >= rectangle.end[axis]: return []
			continue
		var a: float = (rectangle.position[axis]-from[axis])/direction[axis]
		var b: float = (rectangle.end[axis]-from[axis])/direction[axis]
		entering = maxf(entering,minf(a,b))
		leaving = minf(leaving,maxf(a,b))
	if leaving <= maxf(0.0,entering): return []
	return [entering,leaving]
static func _point(origin: Array, position: Vector2, height: float, revision: String) -> Dictionary:
	var normalized := Address.normalize(origin,position)
	if not normalized.ok: return {}
	return {"chunk":normalized.chunk.duplicate(),"local":[normalized.local.x,normalized.local.y],"height":height,"geometry_revision":revision}
static func _failure(code: String) -> Dictionary:
	return {"ok":false,"error_code":code,"path":[],"anchor":{},"landing":{}}
