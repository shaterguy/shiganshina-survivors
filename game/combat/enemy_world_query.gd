class_name EnemyWorldQuery
extends RefCounted
# One synchronous, immutable world boundary. Core owns prepare/batch reset.
# No terrain copies, obstacle extraction, navigation, or hidden re-preparation.
const World = preload("res://game/combat/world_geometry.gd")
const Streamed = preload("res://game/core/streamed_run_world.gd")
var _geometry: Dictionary = {}
var _helper: Streamed
var _state: Dictionary = {}
var _prepared_identity: Dictionary = {}
var _identity: Array = []
var _failure: Dictionary = {}
var _counts := {"walkable_calls":0,"sweep_calls":0,"visibility_calls":0,"cover_calls":0}
var _admitted_tick := -1
var _expired_status: Dictionary = {}
static func for_finite(geometry: Dictionary) -> EnemyWorldQuery:
	var query := EnemyWorldQuery.new()
	query._geometry = geometry
	if not World.valid(geometry): query._fail({"ok":false,"error_code":"invalid_world_geometry"})
	return query
static func for_streamed(helper: Streamed, state: Dictionary) -> EnemyWorldQuery:
	var query := EnemyWorldQuery.new()
	query._helper = helper
	query._state = state
	if helper == null or not Streamed.enabled(state) or not state.world.get("stage") is String or not state.world.get("scene_id") is String or state.world.stage != "city" or state.world.scene_id != "city":
		query._fail({"ok":false,"error_code":"world_not_ready"})
		return query
	# Preserve a failure already owned by this Core tick. Never begin a batch.
	var prior := helper.query_status()
	if not prior.ok: query._fail(prior); return query
	var ready := helper.readiness(state)
	if not ready.ok: query._fail(ready); return query
	query._prepared_identity = helper._prepared_identity
	query._identity = query._current_identity()
	return query
static func _for_admitted_tick(helper: Streamed, state: Dictionary, tick: int) -> EnemyWorldQuery:
	# Core alone calls this after a successful native begin_query_batch, with no
	# spatial writer before the pre-move bind. Public callers retain readiness.
	var query := EnemyWorldQuery.new()
	query._helper = helper
	query._state = state
	query._admitted_tick = tick
	if helper == null or helper.get_script() != Streamed or helper._world == null or helper._world.get_script() != Streamed.Stream or helper._generator == null or helper._generator.get_script() != Streamed.Generator or not Streamed.enabled(state) or not state.world.get("stage") is String or not state.world.get("scene_id") is String or state.world.stage != "city" or state.world.scene_id != "city" or not state.get("active_tick") is int or state.active_tick != tick or tick < 1 or tick > Streamed.Mobility.MAX_COUNTER:
		query._fail({"ok":false,"error_code":"world_not_ready"})
		return query
	var prior := helper.query_status()
	if not prior.ok: query._fail(prior); return query
	if not helper.matches(state): query._fail({"ok":false,"error_code":"world_not_ready"}); return query
	query._prepared_identity = helper._prepared_identity
	query._identity = query._current_identity()
	return query
func _expire_admitted_tick() -> void:
	if _admitted_tick >= 0 and _expired_status.is_empty(): _expired_status = _guard().duplicate(true)
func _current_identity() -> Array:
	var world: Dictionary = _state.get("world",{})
	return [_state.get("run_id"),_state.get("seed"),world.get("mode"),world.get("stage"),world.get("scene_id"),world.get("origin_revision"),world.get("world_revision"),world.get("origin_chunk",[]).duplicate()]
func _guard() -> Dictionary:
	if not _failure.is_empty(): return _failure
	# Expiry blocks operations without overwriting the completed tick's status.
	if not _expired_status.is_empty(): return {"ok":false,"error_code":"world_not_ready"}
	if _helper != null:
		var prior := _helper.query_status()
		if not prior.ok: return _fail(prior)
		if _admitted_tick >= 0 and (not _state.get("active_tick") is int or _state.active_tick != _admitted_tick): return _fail({"ok":false,"error_code":"world_not_ready"})
		if not is_same(_prepared_identity,_helper._prepared_identity) or _identity != _current_identity(): return _fail({"ok":false,"error_code":"world_not_ready"})
	return {"ok":true}
func status() -> Dictionary:
	var result := (_expired_status if not _expired_status.is_empty() else _guard()).duplicate(true)
	result.queries = _counts.duplicate()
	return result
func walkable(point: Vector2, radius: float) -> Dictionary:
	var checked := _guard()
	if not checked.ok: return checked.duplicate(true)
	_counts.walkable_calls += 1
	if _helper != null: return _record(_helper.walkable(point,radius))
	if not _vector(point) or not is_finite(radius) or radius < 0: return _fail({"ok":false,"error_code":"invalid_query"})
	return {"ok":true,"walkable":World.walkable(point,radius,_geometry)}
func sweep(origin: Vector2, delta: Vector2, radius: float) -> Dictionary:
	var checked := _guard()
	if not checked.ok: return checked.duplicate(true)
	_counts.sweep_calls += 1
	if _helper != null: return _record(_helper.sweep(origin,delta,radius))
	if not _vector(origin) or not _vector(delta) or not is_finite(radius) or radius < 0: return _fail({"ok":false,"error_code":"invalid_query"})
	var position := World.sweep(origin,delta,radius,_geometry)
	var fraction := 1.0 if delta.is_zero_approx() else clampf((position-origin).dot(delta)/delta.length_squared(),0.0,1.0)
	return {"ok":true,"position":position,"fraction":fraction,"hit_prop_id":""}
func visibility(sample: Dictionary, target: Vector2, previous_target: Variant = null) -> Dictionary:
	var checked := _guard()
	if not checked.ok: return checked.duplicate(true)
	_counts.visibility_calls += 1
	if not sample.get("requires_visibility") is bool: return _visibility_error()
	var result := {"ok":true,"required":sample.requires_visibility,"visible":true,"blocked_by_solid":false}
	if not result.required: return result
	if not _point(sample.get("visibility_origin")) or not _vector(target) or (previous_target != null and (not previous_target is Vector2 or not _vector(previous_target))): return _visibility_error()
	var origin := Vector2(sample.visibility_origin[0],sample.visibility_origin[1])
	if _helper != null:
		var last := _cover(origin,target)
		if not last.ok: return last
		if previous_target == null: result.visible = float(last.fraction) >= 1.0
		elif float(last.fraction) < 1.0 and not str(last.hit_prop_id).is_empty():
			var first := _cover(origin,previous_target)
			if not first.ok: return first
			# Prepared city footprints are convex boxes. Different/empty IDs
			# cannot prove the entire swept target segment is shadowed.
			result.visible = not (float(first.fraction) < 1.0 and first.hit_prop_id == last.hit_prop_id)
	else:
		if previous_target == null:
			result.visible = World.sweep(origin,target-origin,0.0,_geometry).distance_squared_to(target) < 0.00000001
		elif not _geometry.is_empty():
			for obstacle in _geometry.obstacles:
				var one := {"bounds":_geometry.bounds,"obstacles":[obstacle]}
				var first_blocked := World.sweep(origin,previous_target-origin,0.0,one).distance_squared_to(previous_target) >= 0.00000001
				var last_blocked := World.sweep(origin,target-origin,0.0,one).distance_squared_to(target) >= 0.00000001
				if first_blocked and last_blocked: result.visible = false; break
	result.blocked_by_solid = not result.visible
	return result
func _cover(origin: Vector2, target: Vector2) -> Dictionary:
	_counts.cover_calls += 1
	return _record(_helper.cover_query(origin,target,0.0,4))
func _record(result: Dictionary) -> Dictionary:
	return result if result.get("ok",false) else _fail(result)
func _fail(result: Dictionary) -> Dictionary:
	if _failure.is_empty(): _failure = result.duplicate(true)
	return _failure.duplicate(true)
func _visibility_error() -> Dictionary:
	return {"ok":false,"required":true,"visible":false,"blocked_by_solid":true,"error_code":"invalid_visibility_input"}
static func _vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for scalar in value:
		if not (scalar is int or scalar is float) or not is_finite(float(scalar)) or absf(float(scalar)) > 1000000: return false
	return true
