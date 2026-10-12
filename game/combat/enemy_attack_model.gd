class_name EnemyAttackModel
extends RefCounted
const Catalog := preload("res://game/combat/enemy_role_catalog.gd")
const World := preload("res://game/combat/world_geometry.gd")
const Query := preload("res://game/combat/enemy_world_query.gd")
const BODY_RADII := Catalog.BODY_RADII
const FIELDS := ["attack_id","source_id","role_id","kind","started_tick","active_from_tick","attack_ends_tick","recover_ends_tick","locked_origin","locked_direction","locked_target","profile","hit_target_ids"]
static func begin(actor: Dictionary, player: Dictionary, tick: int, profile: Dictionary, world_geometry: Dictionary, attack_id: String) -> Dictionary:
	if not World.valid(world_geometry): return _error("invalid_candidate")
	return _begin(actor,player,tick,profile,Query.for_finite(world_geometry),attack_id)
static func begin_query(actor: Dictionary, player: Dictionary, tick: int, profile: Dictionary, query: Query, attack_id: String) -> Dictionary:
	if query == null: return _error("world_not_ready")
	var status := query.status()
	if not status.ok: return status
	var begun := _begin(actor,player,tick,profile,query,attack_id,true)
	if not begun.ok: return begun
	if begun.attack.role_id in ["grabber","quadruped","stone_thrower"]:
		var origin := _vec(begun.attack.locked_origin)
		var direction := _vec(begun.attack.locked_direction)
		var clipped := query.sweep(origin,direction*float(profile.length),float(profile.width)*0.5)
		if not clipped.ok: return clipped
		begun.grab_reach_cap = clampf((clipped.position-origin).dot(direction),0.0,float(profile.length))
	return begun
static func _begin(actor: Dictionary, player: Dictionary, tick: int, profile: Dictionary, query: Query, attack_id: String, checked: bool = false) -> Dictionary:
	var role_id: String = str(actor.get("enemy_id",""))
	if not role_id in Catalog.ROLE_IDS or not _point(actor.get("position")) or not _point(player.get("position")) or not _integer(tick): return _error("invalid_candidate")
	var errors: Array[String] = []
	Catalog._profile_errors(profile,role_id,errors)
	if not errors.is_empty(): return _error("invalid_profile")
	var actor_radius: Variant = actor.get("radius",BODY_RADII[role_id])
	if not Catalog._number(actor_radius,true) or float(actor_radius) != float(BODY_RADII[role_id]): return _error("invalid_body_radius")
	var source: Variant = actor.get("id")
	if source is int or source is float:
		if not _integer(source) or float(source) <= 0.0: return _error("invalid_source")
	elif not source is String or (source.is_empty() if checked else source.strip_edges().is_empty()) or (not checked and ":" in source): return _error("invalid_source")
	var source_id := str(int(source)) if source is int or source is float else str(source)
	if not (_id_valid_checked(attack_id,source_id) if checked else _id_valid(attack_id,source_id)): return _error("invalid_attack_id")
	var origin := _vec(actor.position)
	var target := _vec(player.position)
	var legal := query.walkable(origin,maxf(BODY_RADII[role_id],float(profile.width)*0.5))
	if not legal.ok: return legal
	if not legal.walkable: return _error("invalid_origin")
	if origin.distance_to(target) > float(profile.trigger_range): return _error("out_of_range")
	var direction := origin.direction_to(target)
	if direction.is_zero_approx():
		direction = _vec(actor.facing).normalized() if _point(actor.get("facing")) else Vector2.RIGHT
		if direction.is_zero_approx(): direction = Vector2.RIGHT
	# The body cannot leap through a building. Lock the clipped endpoint now,
	# so every future warning and landing shares the same legal destination.
	if profile.kind == "leap": target = _sweep_point(origin,target-origin,BODY_RADII[role_id],query)
	if not query.status().ok: return query.status()
	var active := tick+int(profile.warning_ticks)+int(profile.airborne_ticks)
	var attack := {"attack_id":attack_id,"source_id":source_id,"role_id":role_id,"kind":profile.kind,"started_tick":tick,"active_from_tick":active,"attack_ends_tick":active+int(profile.active_ticks),"recover_ends_tick":active+int(profile.active_ticks)+int(profile.recovery_ticks),"locked_origin":_array(origin),"locked_direction":_array(direction),"locked_target":_array(target),"profile":profile.duplicate(true),"hit_target_ids":[]}
	return {"ok":true,"attack":attack,"grab_reach_cap":-1.0}
static func sample(attack: Dictionary, tick: int, world_geometry: Dictionary) -> Dictionary:
	if not World.valid(world_geometry): return _empty()
	var result := _sample(attack,tick,Query.for_finite(world_geometry))
	return result.get("sample",_empty())
static func sample_query(attack: Dictionary, tick: int, query: Query, grab_reach_cap: float = -1.0) -> Dictionary:
	if query == null: return _error("world_not_ready")
	return _sample(attack,tick,query,grab_reach_cap,true)
static func _sample(attack: Dictionary, tick: int, query: Query, grab_reach_cap: float = -1.0, checked: bool = false) -> Dictionary:
	if not attack.get("profile") is Dictionary or not (validate_checked(attack,attack.profile) if checked else validate(attack,attack.profile)).is_empty(): return _error("invalid_attack")
	if not query.status().ok: return query.status()
	if checked and attack.role_id in ["grabber","quadruped","stone_thrower"] and (not is_finite(grab_reach_cap) or grab_reach_cap < 0.0 or grab_reach_cap > float(attack.profile.length)): return _error("invalid_grab_reach_cap")
	if checked:
		var legal := query.walkable(_vec(attack.locked_origin),maxf(BODY_RADII[attack.role_id],float(attack.profile.width)*0.5))
		if not legal.ok: return legal
		if not legal.walkable: return _error("invalid_origin")
	var p: Dictionary = attack.profile
	var origin := _vec(attack.locked_origin)
	var direction := _vec(attack.locked_direction)
	var active := int(attack.active_from_tick)
	var ends := int(attack.attack_ends_tick)
	var phase := "windup"
	if tick >= int(attack.recover_ends_tick): phase = "finished"
	elif tick >= ends: phase = "recover"
	elif tick >= active: phase = "attack"
	elif tick >= active-int(p.airborne_ticks) and int(p.airborne_ticks) > 0: phase = "airborne"
	var position := origin
	var velocity := Vector2.ZERO
	var damage: Array[Dictionary] = []
	var warning: Array[Dictionary] = []
	var hand_pose: Dictionary = {}
	var projectile_pose: Dictionary = {}
	var show_warning := phase in ["windup","airborne"] and tick >= int(attack.started_tick)
	match str(attack.kind):
		"charge":
			var steps := clampi(tick-active+1,0,int(p.active_ticks))
			var cap := grab_reach_cap if checked and attack.role_id == "quadruped" else -1.0
			position = _charge_point(origin,direction,p,steps,query,cap)
			var previous := _charge_point(origin,direction,p,maxi(0,steps-1),query,cap)
			if phase == "attack":
				velocity = (position-previous)*60.0
				damage.append(_line(previous,position,float(p.width)))
			if show_warning:
				var end := _charge_point(origin,direction,p,int(p.active_ticks),query,cap)
				warning.append(_line(origin,end,float(p.width)+8.0))
		"throw":
			# Derive the rock from its locked ray. Sweep actual solid geometry;
			# once the previous step was clipped, the projectile stays expired.
			var steps := clampi(tick-active+1,0,int(p.active_ticks))
			var previous_distance := float(maxi(0,steps-1))*float(p.rush_speed)/60.0
			var distance := float(steps)*float(p.rush_speed)/60.0
			var cap := grab_reach_cap if checked else float(p.length)
			var previous := _sweep_point(origin,direction*minf(cap,previous_distance),float(p.width)*0.5,query)
			var current := _sweep_point(origin,direction*minf(cap,distance),float(p.width)*0.5,query)
			var blocked := current.distance_to(origin+direction*distance) > 0.001
			var expired := previous.distance_to(origin+direction*previous_distance) > 0.001
			if phase == "attack" and not expired: damage.append(_line(previous,current,float(p.width)))
			if show_warning:
				var endpoint := _sweep_point(origin,direction*cap,float(p.width)*0.5,query)
				warning.append(_line(origin,endpoint,float(p.width)+8.0))
			projectile_pose = {"previous":_array(previous),"current":_array(current),"radius":float(p.width)*0.5,"visible":phase == "attack" and not blocked,"blocked":phase == "attack" and blocked}
		"grab":
			var step := clampi(tick-active+1,0,int(p.active_ticks))
			var cap := grab_reach_cap if checked else float(p.length)
			var radius := float(p.width)*0.5
			var previous := _hand_point(origin,direction,minf(cap,lerpf(40.0,float(p.length),float(maxi(0,step-1))/float(p.active_ticks))),radius,query)
			var hand := _hand_point(origin,direction,minf(cap,lerpf(40.0,float(p.length),float(step)/float(p.active_ticks))),radius,query)
			hand = _sweep_point(previous,hand-previous,radius,query)
			var rest := _hand_point(origin,direction,minf(40.0,cap),radius,query) if checked or show_warning else Vector2.ZERO
			var endpoint := _hand_point(origin,direction,cap,radius,query) if checked or show_warning else Vector2.ZERO
			if phase == "attack": damage.append(_line(previous,hand,float(p.width)))
			if show_warning: warning.append(_line(rest,endpoint,float(p.width)))
			if checked:
				if phase in ["recover","finished"]:
					var elapsed := clampi(tick-ends+1,0,int(p.recovery_ticks))
					previous = endpoint.lerp(rest,float(maxi(0,elapsed-1))/float(p.recovery_ticks))
					hand = endpoint.lerp(rest,float(elapsed)/float(p.recovery_ticks))
					if phase == "finished": previous = rest; hand = rest
				hand_pose = {"rest":_array(rest),"previous":_array(previous),"current":_array(hand),"warning_start":_array(rest),"warning_end":_array(endpoint)}
		"sweep":
			var step := clampi(tick-active+1,0,int(p.active_ticks))
			if phase == "attack": damage = _arm_sweep(origin,direction,p,maxi(0,step-1),step,query)
			# The warning is the same union of planned swept arms, never a thin ring.
			if show_warning:
				for index in int(p.active_ticks): warning.append_array(_arm_sweep(origin,direction,p,index,index+1,query))
		"bite":
			var sector := {"shape":"sector","origin":_array(origin),"direction":_array(direction),"radius":float(p.radius),"arc_degrees":float(p.arc_degrees)}
			if show_warning: warning.append(sector)
			if phase == "attack": damage.append(sector.duplicate(true))
		"slam":
			var circle := _circle(origin,float(p.radius))
			if show_warning: warning.append(circle)
			if phase == "attack": damage.append(circle.duplicate(true))
		"leap":
			var landing := _sweep_point(origin,_vec(attack.locked_target)-origin,BODY_RADII[attack.role_id],query)
			if phase == "airborne":
				var elapsed := tick-(active-int(p.airborne_ticks))+1
				position = origin.lerp(landing,float(elapsed)/float(p.airborne_ticks))
				velocity = (landing-origin)*60.0/float(p.airborne_ticks)
			elif tick >= active: position = landing
			if show_warning: warning.append(_circle(landing,float(p.radius)))
			if phase == "attack": damage.append(_circle(landing,float(p.radius)))
	if not phase in ["windup","airborne"] or tick < int(attack.started_tick): warning.clear()
	if not query.status().ok: return query.status()
	var result := {"phase":phase,"position":_array(position),"velocity":_array(velocity),"telegraph_geometry":warning,"damage_geometry":damage,"finished":phase == "finished","requires_visibility":attack.kind in ["bite","slam","leap"],"visibility_origin":_array(position)}
	if checked and attack.kind == "grab": result.hand_pose = hand_pose
	if checked and attack.kind == "throw": result.projectile_pose = projectile_pose
	return {"ok":true,"sample":result}
# Shared by Core hit application and the threat planner. A geometry overlap alone
# never authorizes a radial/sector hit. For a swept target, accept occlusion only
# when ONE convex solid shadows both endpoints (therefore the entire segment).
# Otherwise conservatively consider it visible; no gap is assumed safe.
static func visibility(sample_value: Dictionary, target: Vector2, world_geometry: Dictionary, previous_target: Variant = null) -> Dictionary:
	if sample_value.get("requires_visibility") is bool and not sample_value.requires_visibility:
		return {"required":false,"visible":true,"blocked_by_solid":false}
	var result := visibility_query(sample_value,target,Query.for_finite(world_geometry),previous_target)
	if not result.ok: return {"required":true,"visible":false,"blocked_by_solid":true,"error_code":"invalid_visibility_input"}
	result.erase("ok")
	return result
static func visibility_query(sample_value: Dictionary, target: Vector2, query: Query, previous_target: Variant = null) -> Dictionary:
	return _error("world_not_ready") if query == null else query.visibility(sample_value,target,previous_target)
static func validate_checked(attack: Variant, profile: Dictionary) -> Array[String]:
	return _validate(attack,profile,true)
static func validate(attack: Variant, profile: Dictionary) -> Array[String]:
	return _validate(attack,profile,false)
static func _validate(attack: Variant, profile: Dictionary, checked: bool) -> Array[String]:
	var errors: Array[String] = []
	if not attack is Dictionary or not _json_safe(attack): return ["attack must be JSON-safe dictionary"]
	Catalog._keys(attack,FIELDS,"attack",errors)
	var role := str(attack.get("role_id",""))
	if not role in Catalog.ROLE_IDS: return ["unapproved role"]
	Catalog._profile_errors(profile,role,errors)
	if not attack.get("profile") is Dictionary or attack.profile != profile: errors.append("profile mismatch")
	if not attack.get("kind") is String or attack.kind != Catalog.KINDS[role]: errors.append("kind/role mismatch")
	if not attack.get("source_id") is String or str(attack.get("source_id","")).is_empty(): errors.append("source_id must be nonempty string")
	if not attack.get("attack_id") is String or not (_id_valid_checked(str(attack.get("attack_id","")),str(attack.get("source_id",""))) if checked else _id_valid(str(attack.get("attack_id","")),str(attack.get("source_id","")))): errors.append("invalid attack identity")
	for field in ["started_tick","active_from_tick","attack_ends_tick","recover_ends_tick"]:
		if not _integer(attack.get(field)): errors.append("invalid integer tick: " + field)
	for field in ["locked_origin","locked_direction","locked_target"]:
		if not _point(attack.get(field)): errors.append("invalid vector: " + field)
	if _point(attack.get("locked_direction")) and absf(_vec(attack.locked_direction).length()-1.0) > 0.00001: errors.append("direction must be normalized")
	if not attack.get("hit_target_ids") is Array: errors.append("hit_target_ids must be array")
	else:
		var seen: Array[String] = []
		for target in attack.hit_target_ids:
			if not target is String or str(target).is_empty() or target in seen: errors.append("invalid or duplicate hit target")
			else: seen.append(target)
	if not errors.is_empty(): return errors
	var target_delta := _vec(attack.locked_target)-_vec(attack.locked_origin)
	if target_delta.length() > float(profile.trigger_range)+0.0001: errors.append("locked target exceeds trigger range")
	if not target_delta.is_zero_approx() and target_delta.normalized().dot(_vec(attack.locked_direction)) < 0.99999: errors.append("locked direction/target mismatch")
	if int(attack.active_from_tick) != int(attack.started_tick)+int(profile.warning_ticks)+int(profile.airborne_ticks): errors.append("active time mismatch")
	if int(attack.attack_ends_tick) != int(attack.active_from_tick)+int(profile.active_ticks): errors.append("attack end mismatch")
	if int(attack.recover_ends_tick) != int(attack.attack_ends_tick)+int(profile.recovery_ticks): errors.append("recovery end mismatch")
	return errors
static func _arm_sweep(origin: Vector2, direction: Vector2, p: Dictionary, previous_step: int, step: int, world: Query) -> Array[Dictionary]:
	var half := deg_to_rad(float(p.arc_degrees))*0.5
	var old_axis := direction.rotated(lerpf(-half,half,float(previous_step)/float(p.active_ticks)))
	var axis := direction.rotated(lerpf(-half,half,float(step)/float(p.active_ticks)))
	var radius := float(p.width)*0.5
	var old_start := _hand_point(origin,old_axis,20.0,radius,world)
	var old_end := _hand_point(origin,old_axis,float(p.radius),radius,world)
	var start := _hand_point(origin,axis,20.0,radius,world)
	var end := _hand_point(origin,axis,float(p.radius),radius,world)
	# Clip both the shoulder ray and the movement from the previous hand tip.
	var swept_end := _sweep_point(old_end,end-old_end,radius,world)
	return [_line(old_start,old_end,float(p.width)),_line(start,end,float(p.width)),_line(old_end,swept_end,float(p.width))]
static func _hand_point(origin: Vector2, direction: Vector2, distance: float, radius: float, world: Query) -> Vector2:
	return _sweep_point(origin,direction*distance,radius,world)
static func _charge_point(origin: Vector2, direction: Vector2, p: Dictionary, steps: int, world: Query, cap: float = -1.0) -> Vector2:
	var distance := float(steps)*float(p.rush_speed)/60.0
	return _sweep_point(origin,direction*(minf(distance,cap) if cap >= 0.0 else distance),float(p.width)*0.5,world)
static func _sweep_point(origin: Vector2, delta: Vector2, radius: float, query: Query) -> Vector2:
	var result := query.sweep(origin,delta,radius)
	# Internal placeholder only. The shared caller must propagate sticky error.
	return result.position if result.ok else origin
static func _line(start: Vector2, end: Vector2, width: float) -> Dictionary:
	var delta := end-start
	return {"shape":"line","origin":_array(start),"direction":_array(delta.normalized() if not delta.is_zero_approx() else Vector2.RIGHT),"length":delta.length(),"width":width}
static func _circle(center: Vector2, radius: float) -> Dictionary:
	return {"shape":"circle","origin":_array(center),"radius":radius}
static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 9007199254740991.0 and float(value) == floor(float(value))
static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 1000000.0: return false
	return true
static func _id_valid(id: String, source: String) -> bool:
	var pieces := id.split(":enemy:")
	if pieces.size() != 2 or pieces[0].is_empty() or source.is_empty(): return false
	var tail := pieces[1].split(":")
	return tail.size() == 2 and tail[0] == source and tail[1].is_valid_int() and int(tail[1]) > 0
static func _id_valid_checked(id: String, source: String) -> bool:
	var split := id.rfind(":")
	if split < 0 or source.is_empty(): return false
	var serial := id.substr(split+1)
	if not serial.is_valid_int() or int(serial) <= 0 or serial != str(int(serial)): return false
	var suffix := ":enemy:"+source
	var prefix := id.substr(0,split)
	return prefix.ends_with(suffix) and prefix.length() > suffix.length()
static func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 20: return false
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		for child in value:
			if not _json_safe(child,depth+1): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _json_safe(value[key],depth+1): return false
		return true
	return false
static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))
static func _array(value: Vector2) -> Array:
	return [value.x,value.y]
static func _error(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
static func _empty() -> Dictionary:
	return {"phase":"finished","position":[0.0,0.0],"velocity":[0.0,0.0],"telegraph_geometry":[],"damage_geometry":[],"finished":true}
