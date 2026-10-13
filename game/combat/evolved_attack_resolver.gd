class_name EvolvedAttackResolver
extends RefCounted
# NEW pure cast proposal and persisted-stage validation. Core owns admission/hits.
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const FINAL_PATTERNS := {"evo_whirlwind":"circle","evo_sky_lance":"line","evo_echo_assault":"sector","evo_wing_squad":"line"}
const FIELDS := ["attack_id","cast_id","base_item_id","evolution_id","attack_started_tick","execute_tick","stage_index","stage_count","origin_binding","origin","direction","shape","radius","arc_degrees","damage","hit_entity_ids","pose_tag"]
var _catalog
func _init(upgrade_catalog = null) -> void:
	_catalog = Upgrades.new() if upgrade_catalog == null else upgrade_catalog
func reserve(state: Dictionary, base_item_id: String, target: Vector2, direction: Vector2, cast_id: String) -> Dictionary:
	if not _context_valid(state): return {"ok":false,"error_code":"invalid_core_state"}
	var id: String = state.evolutions.get(base_item_id,"")
	var detail: Dictionary = _catalog.evolutions.evaluate(state,id)
	if detail.get("status") != "evolved" or not _point(target) or not _point(direction) or direction.is_zero_approx(): return {"ok":false,"error_code":"invalid_option"}
	if not _catalog.integer_valid(state.get("active_tick")) or not _catalog.integer_valid(state.get("attack_seq")) or cast_id != state.run_id+":attack:"+str(int(state.attack_seq)+1): return {"ok":false,"error_code":"invalid_core_state"}
	if FINAL_PATTERNS.has(id): return _reserve_final(state,base_item_id,id,detail.effect_delta,target,direction,cast_id)
	var effective: Dictionary = detail.effect_delta
	var origin := Vector2(state.player.position[0],state.player.position[1])
	var aim := direction.normalized()
	var perpendicular := Vector2(-aim.y,aim.x)
	var records: Array[Dictionary] = []
	for index in 2:
		var execute := int(state.active_tick)+int(effective.stage_delays[index])
		if execute > 2147483647: return {"ok":false,"error_code":"counter_exhausted"}
		var point := origin if id == "evo_wing_cut" else target+perpendicular*float(effective.point_offset)*(-1.0 if index == 0 else 1.0)
		records.append({"attack_id":cast_id+":"+str(index),"cast_id":cast_id,"base_item_id":base_item_id,"evolution_id":id,"attack_started_tick":int(state.active_tick),"execute_tick":execute,"stage_index":index,"stage_count":2,"origin_binding":"player" if id == "evo_wing_cut" and index == 1 else "fixed","origin":[point.x,point.y],"direction":[aim.x,aim.y],"shape":"sector" if id == "evo_wing_cut" else "circle","radius":float(effective.radius),"arc_degrees":float(effective.get("arc_degrees",360.0)),"damage":float(effective.stage_damage[index]),"hit_entity_ids":[],"pose_tag":"blade_slash" if id == "evo_wing_cut" else "artillery_command"})
	return {"ok":true,"records":records,"cooldown_ticks":int(effective.cooldown_ticks)}
func validate_records(state: Dictionary) -> bool:
	if not _context_valid(state): return false
	if not state.get("player_attack_instances") is Array or state.player_attack_instances.size() > 64: return false
	var ids := {}
	var casts := {}
	for record in state.player_attack_instances:
		if not _record_valid(state,record) or ids.has(record.attack_id): return false
		ids[record.attack_id] = true
		if not casts.has(record.cast_id): casts[record.cast_id] = []
		casts[record.cast_id].append(record)
	for records in casts.values():
		if not _cast_records_valid(state,records): return false
	return true
func _cast_records_valid(state: Dictionary, records: Array) -> bool:
	var first: Dictionary = records[0]
	if FINAL_PATTERNS.has(first.evolution_id): return _final_cast_valid(state,records)
	var recipe: Dictionary = _catalog.evolutions.definition(first.evolution_id)
	var expected: Array[int] = []
	for index in 2:
		if int(first.attack_started_tick)+int(recipe.effect_params.stage_delays[index]) > int(state.active_tick): expected.append(index)
	if records.size() != expected.size(): return false
	var indexed := {}
	for record in records:
		if not int(record.stage_index) in expected or indexed.has(int(record.stage_index)): return false
		for field in ["base_item_id","evolution_id","attack_started_tick","direction","radius"]:
			if record[field] != first[field]: return false
		var first_base: float = first.damage/recipe.effect_params.damage_multipliers[int(first.stage_index)]
		var record_base: float = record.damage/recipe.effect_params.damage_multipliers[int(record.stage_index)]
		if absf(first_base-record_base) > 0.000001: return false
		indexed[int(record.stage_index)] = record
	if records.size() == 2 and first.evolution_id == "evo_crossfire":
		var aim := Vector2(first.direction[0],first.direction[1])
		var range_scale: float = first.radius/float(recipe.effect_params.radius)
		var offset: Vector2 = Vector2(-aim.y,aim.x)*float(recipe.effect_params.point_offset)*range_scale*2.0
		var actual: Vector2 = Vector2(indexed[1].origin[0],indexed[1].origin[1])-Vector2(indexed[0].origin[0],indexed[0].origin[1])
		if actual.distance_to(offset) > 0.001: return false
	return true
func _context_valid(state: Dictionary) -> bool:
	if not _catalog.validate().is_empty() or not _catalog.presentation_state_valid(state): return false
	if not state.get("player") is Dictionary or not _position(state.player.get("position")): return false
	if not state.get("evolutions") is Dictionary or not state.get("run_id") is String: return false
	if not Upgrades.integer_valid(state.get("active_tick")) or not Upgrades.integer_valid(state.get("attack_seq")): return false
	return preload("res://game/progression/growth_offer_service.gd")._run_id_valid(state.run_id)
func _record_valid(state: Dictionary, record: Variant) -> bool:
	if record is Dictionary and record.get("evolution_id") is String and FINAL_PATTERNS.has(record.evolution_id): return _final_record_valid(state,record)
	if not record is Dictionary or record.size() != FIELDS.size() or not record.has_all(FIELDS) or not Upgrades.json_data_valid(record): return false
	for field in ["attack_id","cast_id","base_item_id","evolution_id","origin_binding","shape","pose_tag"]:
		if not record[field] is String: return false
	var recipe: Dictionary = _catalog.evolutions.definition(record.evolution_id)
	if recipe.is_empty() or recipe.base_item_id != record.base_item_id or state.evolutions.get(record.base_item_id) != record.evolution_id: return false
	if not _cast_id_valid(state,record.cast_id) or not Upgrades.integer_valid(record.stage_index,0,1) or not Upgrades.integer_valid(record.stage_count,2,2) or record.attack_id != record.cast_id+":"+str(int(record.stage_index)): return false
	for field in ["attack_started_tick","execute_tick"]:
		if not Upgrades.integer_valid(record[field]): return false
	var index := int(record.stage_index)
	if record.attack_started_tick > state.active_tick or record.execute_tick <= state.active_tick or record.execute_tick != record.attack_started_tick+recipe.effect_params.stage_delays[index]: return false
	if not _position(record.origin) or not _position(record.direction) or not is_equal_approx(Vector2(record.direction[0],record.direction[1]).length_squared(),1.0): return false
	if not record.hit_entity_ids is Array or not record.hit_entity_ids.is_empty(): return false
	var wing: bool = record.evolution_id == "evo_wing_cut"
	if record.origin_binding != ("player" if wing and index == 1 else "fixed") or record.shape != ("sector" if wing else "circle") or record.pose_tag != ("blade_slash" if wing else "artillery_command"): return false
	if not Upgrades.number_valid(record.arc_degrees,1,360) or record.arc_degrees != (recipe.effect_params.arc_degrees if wing else 360): return false
	var definition: Dictionary = _catalog.equipment[record.base_item_id]
	var base_damage := (float(definition.damage)+4*float(definition.damage_per_level))*float(recipe.effect_params.damage_multipliers[index])
	if not _past_modifier_matches(state,record.damage,base_damage,"damage"): return false
	if not _past_modifier_matches(state,record.radius,float(recipe.effect_params.radius),"attack_range"): return false
	return true
# Restore only: recover the exact cast-time operation order after JSON decimal
# parsing. Never select an arbitrary first near-match from ambiguous tuning.
func canonicalize_damage(state: Dictionary) -> bool:
	var values: Array[float] = []
	for record in state.player_attack_instances:
		var recipe: Dictionary = _catalog.evolutions.definition(record.evolution_id)
		var definition: Dictionary = _catalog.equipment[record.base_item_id]
		var base := float(definition.damage)+4.0*float(definition.damage_per_level)
		var multiplier := float(recipe.effect_params.damage_multipliers[int(record.stage_index)])
		var permanent := float(state.rules.get("permanent_damage_bonus",0.0))
		var matches: Array[float] = []
		for level in range(int(state.passives.get("damage",0))+1):
			var expected := base*(1.0+permanent+float(_catalog.passives.damage.increment)*level)*multiplier
			if absf(float(record.damage)-expected) <= 0.000001 and not expected in matches: matches.append(expected)
		if matches.size() != 1: return false
		values.append(matches[0])
	for index in values.size(): state.player_attack_instances[index].damage = values[index]
	return true
func _past_modifier_matches(state: Dictionary, value: Variant, base: float, passive: String) -> bool:
	if not Upgrades.number_valid(value,0,10000000): return false
	var definition: Dictionary = _catalog.passives[passive]
	for level in range(int(state.passives.get(passive,0))+1):
		var permanent: float = float(state.rules.get("permanent_damage_bonus",0.0)) if passive == "damage" else 0.0
		var expected := base*(1.0+permanent+float(definition.increment)*level)
		if absf(float(value)-expected) <= 0.000001: return true
	return false
static func _cast_id_valid(state: Dictionary, value: String) -> bool:
	var prefix: String = state.run_id+":attack:"
	if not value.begins_with(prefix): return false
	var suffix := value.substr(prefix.length())
	return suffix.is_valid_int() and str(suffix.to_int()) == suffix and Upgrades.integer_valid(suffix.to_int(),1,int(state.attack_seq))
static func _point(value: Vector2) -> bool: return is_finite(value.x) and is_finite(value.y) and absf(value.x) <= 10000000 and absf(value.y) <= 10000000
static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Upgrades.number_valid(value[0],-10000000,10000000) and Upgrades.number_valid(value[1],-10000000,10000000)

# Final-stage patterns reuse the existing persisted record/event geometry.
# No character movement, signature-skill state or new save fields are introduced.
func _reserve_final(state: Dictionary, base: String, id: String, stats: Dictionary, target: Vector2, direction: Vector2, cast: String) -> Dictionary:
	var origin := Vector2(state.player.position[0],state.player.position[1])
	var aim := direction.normalized()
	var anchor := target if id == "evo_echo_assault" else origin
	var records: Array[Dictionary] = []
	for index in 3:
		var execute := int(state.active_tick)+int(stats.stage_delays[index])
		if execute > Upgrades.MAX_COUNTER: return {"ok":false,"error_code":"counter_exhausted"}
		var point := anchor+_final_offset(id,index,aim,stats)
		var rotated := aim.rotated(deg_to_rad(_final_turn(id,index)))
		var radius := float(stats.radius)+float(stats.get("radius_step",0.0))*index
		var record := {"attack_id":cast+":"+str(index),"cast_id":cast,"base_item_id":base,"evolution_id":id,"attack_started_tick":int(state.active_tick),"execute_tick":execute,"stage_index":index,"stage_count":3,"origin_binding":"player" if id == "evo_whirlwind" else "fixed","origin":[point.x,point.y],"direction":[rotated.x,rotated.y],"shape":FINAL_PATTERNS[id],"radius":radius,"arc_degrees":float(stats.get("arc_degrees",360.0)),"damage":float(stats.stage_damage[index]),"hit_entity_ids":[],"pose_tag":base}
		if record.shape == "line": record.merge({"length":float(stats.length),"width":float(stats.width)})
		records.append(record)
	return {"ok":true,"records":records,"cooldown_ticks":int(stats.cooldown_ticks)}
func _final_record_valid(state: Dictionary, record: Dictionary) -> bool:
	var id: String = record.evolution_id
	var fields: Array = FIELDS.duplicate()
	if FINAL_PATTERNS[id] == "line": fields.append_array(["length","width"])
	if record.size() != fields.size() or not record.has_all(fields) or not Upgrades.json_data_valid(record): return false
	var recipe: Dictionary = _catalog.evolutions.definition(id)
	if recipe.is_empty() or recipe.base_item_id != record.base_item_id or state.evolutions.get(record.base_item_id) != id: return false
	for field in ["attack_id","cast_id","base_item_id","origin_binding","shape","pose_tag"]:
		if not record[field] is String: return false
	if not _cast_id_valid(state,record.cast_id) or not Upgrades.integer_valid(record.stage_index,0,2) or record.stage_count != 3 or record.attack_id != record.cast_id+":"+str(int(record.stage_index)): return false
	var index := int(record.stage_index)
	var params: Dictionary = recipe.effect_params
	if not Upgrades.integer_valid(record.attack_started_tick,0,int(state.active_tick)) or not Upgrades.integer_valid(record.execute_tick,int(state.active_tick)+1): return false
	if record.execute_tick != record.attack_started_tick+params.stage_delays[index]: return false
	if not _position(record.origin) or not _position(record.direction) or not is_equal_approx(Vector2(record.direction[0],record.direction[1]).length_squared(),1.0): return false
	if not record.hit_entity_ids is Array or not record.hit_entity_ids.is_empty(): return false
	if record.shape != FINAL_PATTERNS[id] or record.origin_binding != ("player" if id == "evo_whirlwind" else "fixed") or record.pose_tag != recipe.base_item_id: return false
	if not Upgrades.number_valid(record.arc_degrees,1,360) or record.arc_degrees != params.get("arc_degrees",360.0): return false
	var weapon: Dictionary = _catalog.equipment[recipe.base_item_id]
	var base_damage := (float(weapon.damage)+4.0*float(weapon.damage_per_level))*float(params.damage_multipliers[index])
	if not _past_modifier_matches(state,record.damage,base_damage,"damage"): return false
	var radius := float(params.get("radius",0.0))+float(params.get("radius_step",0.0))*index
	if not _past_modifier_matches(state,record.radius,radius,"attack_range"): return false
	if record.shape == "line":
		for field in ["length","width"]:
			if not _past_modifier_matches(state,record[field],float(params[field]),"attack_range"): return false
		# A single cast snapshots one range multiplier for every distance,
		# including when only its last pending stage remains after restore.
		if absf(float(record.length)/float(params.length)-float(record.width)/float(params.width)) > 0.000001: return false
	return true
func _final_cast_valid(state: Dictionary, records: Array) -> bool:
	var first: Dictionary = records[0]
	var id: String = first.evolution_id
	var params: Dictionary = _catalog.evolutions.definition(id).effect_params
	var expected := []
	for index in 3:
		if int(first.attack_started_tick)+int(params.stage_delays[index]) > int(state.active_tick): expected.append(index)
	if records.size() != expected.size(): return false
	var first_aim := Vector2(first.direction[0],first.direction[1]).rotated(-deg_to_rad(_final_turn(id,int(first.stage_index))))
	var scale := _final_scale(first,params)
	var distances := _final_distances(params,scale)
	var anchor := Vector2(first.origin[0],first.origin[1])-_final_offset(id,int(first.stage_index),first_aim,distances)
	var seen := {}
	for record in records:
		var index := int(record.stage_index)
		if not index in expected or seen.has(index): return false
		seen[index] = true
		for field in ["base_item_id","evolution_id","attack_started_tick","stage_count"]:
			if record[field] != first[field]: return false
		if absf(_final_scale(record,params)-scale) > 0.000001: return false
		var aim := Vector2(record.direction[0],record.direction[1]).rotated(-deg_to_rad(_final_turn(id,index)))
		if aim.distance_to(first_aim) > 0.000001: return false
		var actual_anchor := Vector2(record.origin[0],record.origin[1])-_final_offset(id,index,aim,distances)
		if actual_anchor.distance_to(anchor) > 0.001: return false
		var first_base := float(first.damage)/float(params.damage_multipliers[int(first.stage_index)])
		if absf(float(record.damage)/float(params.damage_multipliers[index])-first_base) > 0.000001: return false
	return true
static func _final_turn(id: String, index: int) -> float:
	if id == "evo_echo_assault": return [45.0,-45.0,0.0][index]
	if id == "evo_wing_squad": return [24.0,-24.0,0.0][index]
	return 0.0
static func _final_offset(id: String, index: int, aim: Vector2, stats: Dictionary) -> Vector2:
	var perpendicular := Vector2(-aim.y,aim.x)
	if id == "evo_sky_lance": return aim*float(stats.advance_step)*index
	if id == "evo_echo_assault": return perpendicular*float(stats.point_offset)*[-1.0,1.0,0.0][index]
	if id == "evo_wing_squad":
		return (aim if index == 2 else perpendicular*(-1.0 if index == 0 else 1.0))*float(stats.point_offset)
	return Vector2.ZERO
static func _final_scale(record: Dictionary, params: Dictionary) -> float:
	if record.shape == "line": return float(record.length)/float(params.length)
	return float(record.radius)/(float(params.radius)+float(params.get("radius_step",0.0))*int(record.stage_index))
static func _final_distances(params: Dictionary, scale: float) -> Dictionary:
	var result := {}
	for field in ["advance_step","point_offset"]:
		if params.has(field): result[field] = float(params[field])*scale
	return result
