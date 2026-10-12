class_name EnemyThreatBudget
extends RefCounted
const Model := preload("res://game/combat/enemy_attack_model.gd")
const Query := preload("res://game/combat/enemy_world_query.gd")
const Geometry := preload("res://game/combat/attack_geometry.gd")
const MAX_HORIZON := 180
const DIRECTION_COUNT := 16
const PATH_COUNT := DIRECTION_COUNT+DIRECTION_COUNT*DIRECTION_COUNT
# Cost counts one static sweep and one swept danger-geometry/visibility test.
# It is deterministic logical work, not a claim about milliseconds on Android.
static func evaluate(candidate: Dictionary, active_attacks: Array[Dictionary], player: Dictionary, world_geometry: Dictionary, context: Dictionary) -> Dictionary:
	return _evaluate(candidate,active_attacks,player,Query.for_finite(world_geometry),context,false)
static func evaluate_query(candidate: Dictionary, active_attacks: Array[Dictionary], player: Dictionary, query: Query, context: Dictionary) -> Dictionary:
	var result := _evaluate(candidate,active_attacks,player,query,context,true)
	if query != null: result.diagnostics.world_queries = query.status().queries
	return result
static func _evaluate(candidate: Dictionary, active_attacks: Array[Dictionary], player: Dictionary, query: Query, context: Dictionary, checked: bool) -> Dictionary:
	var diagnostics := {"role_id":str(candidate.get("role_id","unknown")),"attack_id":str(candidate.get("attack_id","")),"source_id":str(candidate.get("source_id","")),"candidate_wait_since":context.get("candidate_wait_since",0),"wait_ticks":0,"work_units":0,"paths_tested":0,"sample_calls":0,"cache_hits":0,"path_prefix_reuses":0,"static_queries":0,"geometry_queries":0,"actual_query_units":0,"visibility_blocked":0,"max_work_units":context.get("max_work_units",8192),"horizon_ticks":0,"strong_slots_used":0,"strong_slot_limit":2,"melee_slots_used":0,"melee_slot_limit":2,"deferral_reason":"","detail":""}
	if not _context_valid(context) or not Model._point(player.get("position")):
		return _result(false,"invalid_candidate",[],diagnostics,"invalid_context_or_player")
	var tick := int(context.tick)
	diagnostics.wait_ticks = tick-int(context.candidate_wait_since)
	diagnostics.strong_slot_limit = 2 if int(context.survival_tick) < 10800 else 3
	var observation_error := ""
	if checked:
		observation_error = _observation_inputs(context)
		if observation_error.is_empty():
			# Collection already ran in Core, even when this world is unavailable.
			# Record only validated metadata; keep the existing failure precedence.
			diagnostics.observation_counts = context.get("observation_counts",{}).duplicate()
			diagnostics.observation_work_units = int(context.get("observation_work_units",0))
			diagnostics.observed_body_tests = 0
			diagnostics.current_contact_rejections = 0
			diagnostics.bounded_pressure_rejections = 0
			diagnostics.work_units = mini(diagnostics.observation_work_units,int(diagnostics.max_work_units))
	if not context.geometry_fully_loaded:
		if checked and query != null:
			var prior := query.status()
			if not prior.ok: return _world_failure(diagnostics,prior)
		return _result(false,"world_unavailable",[],diagnostics)
	if query == null: return _world_failure(diagnostics,{"ok":false,"error_code":"world_not_ready"})
	if not query.status().ok:
		return _world_failure(diagnostics,query.status()) if checked else _result(false,"world_unavailable",[],diagnostics,"invalid_world_geometry")
	if not _attack_valid(candidate,checked) or candidate.get("legacy_projection",false) or int(candidate.started_tick) != tick:
		return _result(false,"invalid_candidate",[],diagnostics,"invalid_new_attack")
	var origin := Model._vec(player.position)
	var body_radius := float(context.player_radius)
	var clearance := body_radius+float(context.margin)
	var legal := query.walkable(origin,body_radius)
	if not legal.ok: return _world_failure(diagnostics,legal)
	if not legal.walkable: return _result(false,"no_safe_path",[],diagnostics,"player_body_blocked")
	var attacks: Array[Dictionary] = [candidate]
	var seen := {str(candidate.attack_id):true}
	for attack in active_attacks:
		if not _attack_valid(attack,checked) or seen.has(str(attack.get("attack_id",""))): return _result(false,"invalid_candidate",[],diagnostics,"invalid_or_duplicate_reservation")
		seen[str(attack.attack_id)] = true
		if not attack.get("legacy_projection",false) and int(attack.started_tick) > tick: return _result(false,"invalid_candidate",[],diagnostics,"future_start_reservation")
		if int(attack.attack_ends_tick) > tick: attacks.append(attack)
	attacks.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.attack_id) < str(b.attack_id))
	var horizon := 0
	for attack in attacks:
		horizon = maxi(horizon,int(attack.attack_ends_tick)-1-tick)
		if attack.get("legacy_projection",false): diagnostics.strong_slots_used += 2
		elif attack.role_id == "walker": diagnostics.melee_slots_used += 1
		else: diagnostics.strong_slots_used += int(attack.profile.threat_cost)
	diagnostics.horizon_ticks = horizon
	if checked:
		var detail := _checked_inputs(active_attacks,attacks,context,horizon,observation_error)
		if not detail.is_empty(): return _result(false,"invalid_candidate",[],diagnostics,detail)
	if diagnostics.strong_slots_used > diagnostics.strong_slot_limit or diagnostics.melee_slots_used > 2:
		return _result(false,"budget_full",[],diagnostics)
	if horizon > MAX_HORIZON: return _result(false,"invalid_candidate",[],diagnostics,"horizon_exceeds_limit")
	if checked:
		if diagnostics.observation_work_units > diagnostics.max_work_units:
			diagnostics.work_units = int(diagnostics.max_work_units)
			return _result(false,"work_budget_exhausted",[],diagnostics)
		for body in context.get("observed_bodies",[]):
			if not _spend(diagnostics): return _result(false,"work_budget_exhausted",[],diagnostics)
			diagnostics.observed_body_tests += 1
			var distance := origin.distance_to(Model._vec(body.origin))
			var current := float(body.body_radius)+clearance
			var expanded := current+float(body.move_speed)*float(int(body.observed_until_tick)-tick)/60.0
			if distance <= expanded:
				if distance <= float(body.body_radius)+body_radius: diagnostics.current_contact_rejections += 1
				else: diagnostics.bounded_pressure_rejections += 1
				return _result(false,"no_safe_path",[],diagnostics,"observed_body_pressure")
	var danger_cache: Dictionary = {}
	var transition_cache: Dictionary = {}
	var prefix_cache: Dictionary = {}
	var reaction := int(context.reaction_ticks)
	var turn_at := reaction+int(floor(float(horizon-reaction)/2.0))
	var step_length := float(context.move_speed)/60.0
	for path_index in PATH_COUNT:
		diagnostics.paths_tested += 1
		var first: int = path_index if path_index < DIRECTION_COUNT else int((path_index-DIRECTION_COUNT)/DIRECTION_COUNT)
		var second: int = first if path_index < DIRECTION_COUNT else (path_index-DIRECTION_COUNT)%DIRECTION_COUNT
		var first_direction := Vector2.RIGHT.rotated(TAU*float(first)/float(DIRECTION_COUNT))
		var second_direction := Vector2.RIGHT.rotated(TAU*float(second)/float(DIRECTION_COUNT))
		var position := origin
		var safe := true
		var from_offset := 0
		var path_start_work := int(diagnostics.work_units)
		var path_start_blocked := int(diagnostics.visibility_blocked)
		if path_index >= DIRECTION_COUNT:
			# Every bend shares an already checked prefix with one of the 16
			# straight paths. Reuse that entire prefix, including a known failure.
			var prefix: Dictionary = prefix_cache[first]
			diagnostics.path_prefix_reuses += 1
			if int(diagnostics.work_units)+int(prefix.work_units) > int(diagnostics.max_work_units):
				diagnostics.work_units = int(diagnostics.max_work_units)
				return _result(false,"work_budget_exhausted",[],diagnostics)
			diagnostics.work_units += int(prefix.work_units)
			diagnostics.visibility_blocked += int(prefix.visibility_blocked)
			if not prefix.safe: continue
			position = prefix.position
			from_offset = turn_at+1
		for offset in range(from_offset,horizon+1):
			var previous := position
			var delta := Vector2.ZERO
			if offset > reaction:
				delta = (first_direction if offset <= turn_at or path_index < DIRECTION_COUNT else second_direction)*step_length
			position = previous+delta
			var now := tick+offset
			var transition := _transition(previous,position,now,body_radius,clearance,query,attacks,danger_cache,transition_cache,diagnostics,context if checked else {})
			if transition == -2: return _world_failure(diagnostics,diagnostics.query_error)
			if transition < 0: return _result(false,"work_budget_exhausted",[],diagnostics)
			if path_index < DIRECTION_COUNT and (offset == turn_at or (transition == 0 and offset <= turn_at)):
				prefix_cache[first] = {"safe":transition > 0,"position":position,"work_units":int(diagnostics.work_units)-path_start_work,"visibility_blocked":int(diagnostics.visibility_blocked)-path_start_blocked}
			if transition == 0:
				safe = false
				break
		if safe: return _result(true,"accepted",_path(origin,first_direction,second_direction,path_index < DIRECTION_COUNT,reaction,turn_at,horizon,tick,step_length),diagnostics)
	return _result(false,"no_safe_path",[],diagnostics)
# Materialize DTO points only for the successful path. Failed candidates need
# no thousands of throwaway point dictionaries; reconstruction repeats exactly
# the already-validated fixed-step additions, not an analytical approximation.
static func _path(origin: Vector2, first: Vector2, second: Vector2, straight: bool, reaction: int, turn_at: int, horizon: int, tick: int, step_length: float) -> Array:
	var result: Array = []
	var position := origin
	for offset in range(horizon+1):
		if offset > reaction: position += (first if straight or offset <= turn_at else second)*step_length
		result.append({"tick":tick+offset,"position":[position.x,position.y]})
	return result
# Cache lifetime is ONE evaluation against ONE immutable geometry/reservation
# snapshot. The 272 candidate order and original logical work charges stay exact;
# diagnostics distinguish cached logical work from actual collision queries.
static func _transition(previous: Vector2, position: Vector2, now: int, body_radius: float, clearance: float, world: Query, attacks: Array[Dictionary], danger_cache: Dictionary, transition_cache: Dictionary, d: Dictionary, checked_context: Dictionary) -> int:
	if not transition_cache.has(now): transition_cache[now] = {}
	var cache: Dictionary = transition_cache[now]
	var key := Vector4(previous.x,previous.y,position.x,position.y)
	if cache.has(key):
		var reused: Array = cache[key]
		d.cache_hits += 1
		if int(d.work_units)+int(reused[1]) > int(d.max_work_units):
			d.work_units = int(d.max_work_units)
			return -1
		d.work_units += int(reused[1])
		d.visibility_blocked += int(reused[2])
		return 1 if reused[0] else 0
	var before := int(d.work_units)
	var blocked_before := int(d.visibility_blocked)
	if not _spend(d): return -1
	d.static_queries += 1
	d.actual_query_units += 1
	var swept := world.sweep(previous,position-previous,body_radius)
	if not swept.ok: d.query_error = swept; return -2
	var safe: bool = swept.position.distance_squared_to(position) <= 0.00000001
	if safe:
		if not danger_cache.has(now): danger_cache[now] = _danger_at(attacks,now,world,d,checked_context)
		if d.has("query_error"): return -2
		for danger in danger_cache[now]:
			if not _spend(d): return -1
			d.geometry_queries += 1
			d.actual_query_units += 1
			if _swept_hits(danger.geometry,previous,position,clearance):
				var sight: Dictionary = Model.visibility_query(danger,position,world,previous)
				if not sight.ok: d.query_error = sight; return -2
				if sight.blocked_by_solid: d.visibility_blocked += 1
				else:
					safe = false
					break
	cache[key] = [safe,int(d.work_units)-before,int(d.visibility_blocked)-blocked_before]
	return 1 if safe else 0
static func _context_valid(c: Dictionary) -> bool:
	for key in ["tick","survival_tick","reaction_ticks","candidate_wait_since"]:
		if not Model._integer(c.get(key)): return false
	if c.candidate_wait_since > c.tick or not c.get("geometry_fully_loaded") is bool: return false
	for key in ["move_speed","player_radius","margin"]:
		var v: Variant = c.get(key)
		if not (v is float or v is int) or not is_finite(float(v)) or float(v) < 0 or float(v) > 1000000: return false
	return Model._integer(c.get("max_work_units",8192)) and int(c.reaction_ticks) <= MAX_HORIZON
static func _attack_valid(a: Dictionary, checked: bool = false) -> bool:
	if a.has("legacy_projection"):
		if not a.legacy_projection is bool or not a.legacy_projection: return false
		var fields := ["legacy_projection","attack_id","source_id","active_from_tick","attack_ends_tick","threat_cost","damage_geometry"]
		if a.size() != fields.size(): return false
		for field in fields:
			if not a.has(field): return false
		if not a.attack_id is String or a.attack_id.is_empty() or not (a.source_id is String or a.source_id is int) or str(a.source_id).is_empty(): return false
		if not Model._integer(a.active_from_tick) or not Model._integer(a.attack_ends_tick) or a.attack_ends_tick <= a.active_from_tick or not Model._integer(a.threat_cost) or a.threat_cost != 2: return false
		if not a.damage_geometry is Array or a.damage_geometry.is_empty() or not Model._json_safe(a): return false
		for record in a.damage_geometry:
			if not _geometry_valid(record): return false
		return true
	return a.get("profile") is Dictionary and (Model.validate_checked(a,a.profile) if checked else Model.validate(a,a.profile)).is_empty()
static func _geometry_valid(value: Variant) -> bool:
	if not value is Dictionary or not Model._point(value.get("origin")): return false
	if not value.get("shape") in ["circle","line","sector"]: return false
	var fields: Array = {"circle":["shape","origin","radius"],"line":["shape","origin","direction","length","width"],"sector":["shape","origin","direction","radius","arc_degrees"]}[value.shape]
	if value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	if value.shape == "circle": return _positive(value.get("radius"))
	if not Model._point(value.get("direction")) or absf(Model._vec(value.direction).length()-1.0) > 0.00001: return false
	if value.shape == "line": return _nonnegative(value.get("length")) and _positive(value.get("width"))
	return _positive(value.get("radius")) and _positive(value.get("arc_degrees")) and float(value.arc_degrees) <= 360.0
static func _positive(v: Variant) -> bool:
	return _nonnegative(v) and float(v) > 0.0
static func _nonnegative(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= 0.0 and float(v) <= 1000000.0
static func _spend(d: Dictionary) -> bool:
	if int(d.work_units) >= int(d.max_work_units): return false
	d.work_units += 1
	return true
static func _danger_at(attacks: Array[Dictionary], tick: int, world: Query, diagnostics: Dictionary, checked_context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for a in attacks:
		if tick < int(a.active_from_tick) or tick >= int(a.attack_ends_tick): continue
		var records: Array
		# Legacy actual damage uses its fixed geometry without a visibility gate.
		# Preserve that conservative contract; shape type cannot grant an exemption.
		var requires_visibility := false
		if a.get("legacy_projection",false): records = a.damage_geometry
		else:
			diagnostics.sample_calls += 1
			var checked := not checked_context.is_empty()
			var sampled: Dictionary = Model._sample(a,tick,world,float(checked_context.get("grab_reach_caps",{}).get(a.attack_id,-1.0)),checked)
			if not sampled.ok: diagnostics.query_error = sampled; return []
			records = sampled.sample.damage_geometry
			requires_visibility = sampled.sample.requires_visibility
		for index in records.size():
			var record: Dictionary = records[index]
			if a.get("legacy_projection",false) and not checked_context.is_empty():
				requires_visibility = checked_context.legacy_cover_modes[a.attack_id][index] == "legacy_mask4"
			result.append({"geometry":record,"requires_visibility":requires_visibility,"visibility_origin":record.origin})
	return result
const OBSERVATION_COUNT_KEYS := ["entity_count","telegraph_count","time_filtered","bounds_filtered","hash_cells","hash_candidates","body_exact_tests","reservation_count","primitive_count"]
static func _observation_inputs(context: Dictionary) -> String:
	var counts: Variant = context.get("observation_counts",{})
	if not counts is Dictionary or not Model._integer(context.get("observation_work_units",0)): return "invalid_checked_context"
	var count_sum := 0
	for key in counts:
		if not key is String or not key in OBSERVATION_COUNT_KEYS or not Model._integer(counts[key]): return "invalid_observation_counts"
		count_sum += int(counts[key])
		if count_sum > 9007199254740991: return "invalid_observation_counts"
	if int(context.get("observation_work_units",0)) < count_sum: return "uncharged_observation_work"
	return ""
static func _checked_inputs(reservations: Array[Dictionary], attacks: Array[Dictionary], context: Dictionary, horizon: int, observation_error: String) -> String:
	var caps: Variant = context.get("grab_reach_caps",{})
	var modes: Variant = context.get("legacy_cover_modes",{})
	var bodies: Variant = context.get("observed_bodies",[])
	if not caps is Dictionary or not modes is Dictionary or not bodies is Array: return "invalid_checked_context"
	if not observation_error.is_empty(): return observation_error
	var sources := {}
	for a in attacks:
		var source := str(a.source_id)
		if sources.has(source): return "duplicate_reservation_source"
		sources[source] = true
		if not a.get("legacy_projection",false) and a.role_id in ["grabber","quadruped","stone_thrower"]:
			if not _nonnegative(caps.get(a.attack_id)) or float(caps[a.attack_id]) > float(a.profile.length): return "invalid_grab_reach_cap"
	for a in reservations:
		if not a.get("legacy_projection",false):
			if a.role_id in ["grabber","quadruped","stone_thrower"] and (not _nonnegative(caps.get(a.attack_id)) or float(caps[a.attack_id]) > float(a.profile.length)): return "invalid_grab_reach_cap"
			continue
		if not modes.get(a.attack_id) is Array or modes[a.attack_id].size() != a.damage_geometry.size(): return "invalid_legacy_cover_modes"
		for mode in modes[a.attack_id]:
			if not mode is String or not mode in ["legacy_mask4","none"]: return "invalid_legacy_cover_modes"
	for body in bodies:
		if not body is Dictionary or body.size() != 5 or not body.has_all(["source_id","origin","body_radius","move_speed","observed_until_tick"]): return "invalid_observed_body"
		var source: Variant = body.source_id
		if not ((source is int and source > 0) or (source is String and not source.is_empty())): return "invalid_observed_body"
		if sources.has(str(source)): return "duplicate_observed_source"
		sources[str(source)] = true
		if not Model._point(body.origin) or not _nonnegative(body.body_radius) or not _nonnegative(body.move_speed) or not Model._integer(body.observed_until_tick): return "invalid_observed_body"
		if body.observed_until_tick < context.tick or body.observed_until_tick > int(context.tick)+mini(int(context.reaction_ticks),horizon): return "invalid_observed_interval"
	return ""
static func _world_failure(diagnostics: Dictionary, error: Dictionary) -> Dictionary:
	diagnostics.query_error = error.duplicate(true)
	return _result(false,"world_unavailable",[],diagnostics,str(error.get("error_code","world_not_ready")))
static func _swept_hits(record: Dictionary, start: Vector2, end: Vector2, radius: float) -> bool:
	var origin := Model._vec(record.origin)
	if record.shape == "circle": return _point_segment_distance(origin,start,end) <= float(record.radius)+radius
	var direction := Model._vec(record.direction)
	if record.shape == "line": return _segment_distance(start,end,origin,origin+direction*float(record.length)) <= float(record.width)*0.5+radius
	# Sector expanded by target radius: endpoints, its two radial edges, and
	# the swept segment's intersection with the expanded circular arc.
	if Geometry.overlaps(record,start,radius) or Geometry.overlaps(record,end,radius): return true
	var half := deg_to_rad(float(record.arc_degrees))*0.5
	for sign_value in [-1.0,1.0]:
		var edge := origin+direction.rotated(half*sign_value)*float(record.radius)
		if _segment_distance(start,end,origin,edge) <= radius: return true
	var delta := end-start
	var squared := delta.length_squared()
	if squared < 0.00000001: return false
	var offset := start-origin
	var projection := offset.dot(delta)
	var expanded := float(record.radius)+radius
	var discriminant := projection*projection-squared*(offset.length_squared()-expanded*expanded)
	if discriminant < 0: return false
	for distance in [(-projection-sqrt(discriminant))/squared,(-projection+sqrt(discriminant))/squared]:
		if distance >= 0 and distance <= 1 and absf(direction.angle_to(start+delta*distance-origin)) <= half: return true
	return false
static func _point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta := end-start
	if delta.is_zero_approx(): return point.distance_to(start)
	return point.distance_to(start+delta*clampf((point-start).dot(delta)/delta.length_squared(),0.0,1.0))
static func _segment_distance(a: Vector2,b: Vector2,c: Vector2,d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a,b,c,d) != null: return 0.0
	return minf(minf(_point_segment_distance(a,c,d),_point_segment_distance(b,c,d)),minf(_point_segment_distance(c,a,b),_point_segment_distance(d,a,b)))
static func _result(accepted: bool, reason: String, path: Array, diagnostics: Dictionary, detail: String = "") -> Dictionary:
	diagnostics.deferral_reason = "" if accepted else reason
	diagnostics.detail = detail
	return {"accepted":accepted,"reason":reason,"safe_path":path,"diagnostics":diagnostics}
