class_name EvolvedAttackResolver
extends RefCounted
# NEW pure cast proposal and persisted-stage validation. Core owns admission/hits.
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
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
func _past_modifier_matches(state: Dictionary, value: Variant, base: float, passive: String) -> bool:
	if not Upgrades.number_valid(value,0,10000000): return false
	var definition: Dictionary = _catalog.passives[passive]
	for level in range(int(state.passives.get(passive,0))+1):
		var expected := base*(1.0+float(definition.increment)*level)
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
