class_name WorldInteractions
extends RefCounted
static func structure_candidate(actor: Dictionary, prop: Dictionary, rules: Dictionary, tick: int, reservations: Dictionary) -> Dictionary:
	if not actor.get("structure_capable",false) or actor.get("source_team","") != "titan" or actor.get("cancelled",false): return _reject("source_policy")
	if not prop.get("destructible",false) or prop.get("destroyed",true) or prop.get("hp",0) <= 0: return _reject("not_destructible")
	for field in ["structure_admission_interval_ticks","max_structure_attacks","warning_ticks","recovery_ticks","structure_damage","structure_reach"]:
		if not rules.has(field) or not (rules[field] is int or rules[field] is float) or not is_finite(float(rules[field])) or rules[field] <= 0 or rules[field] != floor(float(rules[field])): return _reject("invalid_structure_rules")
	if reservations.get("remaining_strong_slots",0) < 1 or reservations.get("in_flight",0) >= rules.max_structure_attacks or tick < reservations.get("next_admit_tick",0): return _reject("structure_budget")
	var point := _point(actor.get("position",Vector2(INF,INF)))
	var rect: Rect2 = prop.ground_footprint
	if not is_finite(point.x) or not is_finite(point.y) or point.distance_to(point.clamp(rect.position,rect.end)) > rules.structure_reach: return _reject("out_of_reach")
	return {"ok":true,"kind":"structure_strike","target_prop_id":prop.prop_id,"warning_ticks":int(rules.warning_ticks),"active_tick":tick+int(rules.warning_ticks),"recovery_until":tick+int(rules.warning_ticks)+int(rules.recovery_ticks),"next_admit_tick":tick+int(rules.structure_admission_interval_ticks),"structure_damage":int(rules.structure_damage),"strong_slots":1}
static func resolve_structure_hit(attack: Dictionary, prop: Dictionary, contact: Dictionary) -> Dictionary:
	if attack.get("kind","") != "structure_strike" or attack.get("source_team","") != "titan" or attack.get("cancelled",false): return _reject("source_policy")
	if str(attack.get("attack_instance_id","")).is_empty() or not attack.get("hit_target_ids") is Array: return _reject("invalid_attack")
	if not prop.get("destructible",false) or prop.get("destroyed",true) or prop.get("hp",0) <= 0: return _reject("not_destructible")
	if attack.get("target_prop_id","") != prop.prop_id or contact.get("prop_id","") != prop.prop_id or not contact.get("reached",false): return _reject("locked_target_missed")
	var tick: int = contact.get("tick",-1)
	if tick < attack.get("active_from_tick",0) or tick > attack.get("expires_tick",-1): return _reject("inactive_attack")
	if prop.prop_id in attack.hit_target_ids: return _reject("already_hit")
	var fraction: float = contact.get("fraction",-1)
	var damage = attack.get("structure_damage",1)
	if not is_finite(fraction) or fraction < 0 or fraction > 1 or not (damage is int or damage is float) or not is_finite(float(damage)) or damage <= 0 or damage != floor(float(damage)): return _reject("invalid_contact")
	var hp := maxi(0,int(prop.hp)-int(damage))
	var delta := {"slot_id":prop.slot_id,"hp":hp,"destroyed":hp == 0}
	return {"ok":true,"delta":delta,"hit_target_id":prop.prop_id,"event":{"type":"structure_destroyed" if hp == 0 else "structure_damaged","prop_id":prop.prop_id,"attack_instance_id":attack.attack_instance_id,"tick":tick,"hp":hp}}
static func cover_contact(origin: Vector2, target: Vector2, radius: float, mask: int, world) -> Dictionary:
	return world.cover_sweep(origin,target-origin,radius,mask)
static func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(value[0],value[1])
	return Vector2(INF,INF)
static func _reject(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
