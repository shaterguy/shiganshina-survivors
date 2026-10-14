class_name MobilityAnchorQuery
extends RefCounted
# Bounded deterministic paired-side proposals. Every path uses normal collision.
const Address = preload("res://game/world/world_address.gd")
const MAX_DISTANCE := 320.0
const SIDE_REACH := 256.0
const EDGE_MARGIN := 4.0
static func candidates(state: Dictionary, direction: Vector2, helper) -> Dictionary:
	if helper == null or not state.get("world") is Dictionary or state.world.get("stage") != "city" or not state.get("player") is Dictionary: return _failure("no_mobility_path")
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.length_squared() < 0.000001: return _failure("no_mobility_path")
	var from := Vector2(state.player.position[0],state.player.position[1])
	var forward := direction.normalized()
	var end := from+forward*MAX_DISTANCE
	var rectangle := Rect2(from.min(end)-Vector2.ONE*SIDE_REACH,(end-from).abs()+Vector2.ONE*SIDE_REACH*2)
	var queried: Dictionary = helper.mobility_geometry(state,rectangle)
	if not queried.get("ok",false): return queried
	var ranked := []
	for anchor in queried.anchors:
		var relative := Address.relative(anchor.chunk,Vector2(anchor.local[0],anchor.local[1]),state.world.origin_chunk)
		if not relative.ok: continue
		var offset: Vector2 = relative.local-from
		var along := offset.dot(forward)
		var side := forward.cross(offset)
		if along < 0.0 or along > MAX_DISTANCE or absf(side) <= 8.0 or absf(side) > SIDE_REACH or offset.length() > MAX_DISTANCE: continue
		ranked.append({"anchor":anchor,"along":along,"side":side,"distance":offset.length_squared()})
	ranked.sort_custom(func(a,b):
		if a.distance != b.distance: return a.distance < b.distance
		return a.anchor.prop_id < b.anchor.prop_id)
	var anchors := []
	for item in ranked: anchors.append(item.anchor)
	return {"ok":true,"anchors":anchors,"ranked":ranked}
static func plan(state: Dictionary, direction: Vector2, helper) -> Dictionary:
	var offered := candidates(state,direction,helper)
	if not offered.get("ok",false): return offered
	var from := Vector2(state.player.position[0],state.player.position[1])
	var forward := direction.normalized()
	var grounded: Dictionary = helper.walkable(from,8.0)
	if not grounded.get("ok",false): return grounded
	if not grounded.get("walkable",false): return _failure("no_mobility_path")
	var pair := []
	for left in offered.ranked:
		if left.side >= 0: continue
		for right in offered.ranked:
			if right.side <= 0 or absf(left.along-right.along) > 128.0: continue
			pair = [left.anchor.duplicate(true),right.anchor.duplicate(true)]
			break
		if not pair.is_empty(): break
	if pair.is_empty(): return _failure("no_mobility_path")
	var checked: Dictionary = helper.sweep(from,forward*MAX_DISTANCE,8.0)
	if not checked.get("ok",false): return checked
	var distance := MAX_DISTANCE
	if checked.fraction < 1.0: distance = maxf(0.0,from.distance_to(checked.position)-EDGE_MARGIN)
	# A wall before both hooks cannot turn a frontage into a corridor.
	for anchor in pair:
		var relative := Address.relative(anchor.chunk,Vector2(anchor.local[0],anchor.local[1]),state.world.origin_chunk)
		if (relative.local-from).dot(forward) > distance: return _failure("no_mobility_path")
	if distance < 16.0: return _failure("no_mobility_path")
	var landing := from+forward*distance
	var safe: Dictionary = helper.walkable(landing,8.0)
	if not safe.get("ok",false): return safe
	if not safe.get("walkable",false): return _failure("no_mobility_path")
	var revision := pair_revision(pair)
	var path := [_point(state.world.origin_chunk,from,revision),_point(state.world.origin_chunk,landing,revision)]
	if path.any(func(point): return point.is_empty()): return _failure("no_mobility_path")
	return {"ok":true,"path":path,"anchors":pair,"landing":path[1].duplicate(true),"direction":[forward.x,forward.y]}
static func pair_revision(anchors: Array) -> String:
	return (str(anchors[0].geometry_revision)+"|"+str(anchors[1].geometry_revision)).sha256_text()
static func _point(origin: Array, position: Vector2, revision: String) -> Dictionary:
	var normalized := Address.normalize(origin,position)
	if not normalized.ok: return {}
	return {"chunk":normalized.chunk.duplicate(),"local":[normalized.local.x,normalized.local.y],"height":0.0,"geometry_revision":revision}
static func _failure(code: String) -> Dictionary:
	return {"ok":false,"error_code":code,"path":[],"anchors":[],"landing":{}}
