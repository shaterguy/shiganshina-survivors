class_name UpgradeCatalog
extends RefCounted
# NEW implementation. Catalog rows and presentation results are private copies.
const Evolutions = preload("res://game/progression/evolution_catalog.gd")
const MAX_LEVEL := 5
const SLOT_LIMIT := 4
const MAX_COUNTER := 2147483647
const EQUIPMENT_IDS := ["ally_cover","blade_slash","odm_dash","reentry_combo","spin_slash","wall_cannon"]
const OPTIONAL_EQUIPMENT_IDS := ["chain_lightning","fire_zone"]
const PASSIVE_STATS := {"damage":"damage_multiplier","fire_interval":"cooldown_multiplier","movement":"move_multiplier","max_health":"max_hp","recovery":"regen_per_second","pickup_radius":"pickup_radius","attack_range":"range_multiplier","armor":"armor"}
var _equipment: Dictionary = {}
var _passives: Dictionary = {}
var _progression: Dictionary = {}
var _base_errors: Array[String] = []
var evolutions
var equipment: Dictionary:
	get: return _equipment.duplicate(true) if _base_errors.is_empty() else {}
var passives: Dictionary:
	get: return _passives.duplicate(true) if _base_errors.is_empty() else {}
var progression: Dictionary:
	get: return _progression.duplicate(true) if _base_errors.is_empty() else {}
func _init(equipment_override = null, passives_override = null, evolution_override = null) -> void:
	var equipment_data = _read("res://data/equipment.json") if equipment_override == null else equipment_override
	var passive_data = _read("res://data/passives.json") if passives_override == null else passives_override
	_load_base(equipment_data,passive_data)
	evolutions = Evolutions.new(self,evolution_override)
func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 131072: return null
	return JSON.parse_string(file.get_as_text())
func _load_base(equipment_data: Variant, passive_data: Variant) -> void:
	for data in [equipment_data,passive_data]:
		if not json_data_valid(data) or not data is Dictionary or data.get("schema_version") != 1 or not data.get("items") is Dictionary:
			_base_errors.append("invalid_item")
			return
	_equipment = equipment_data.items.duplicate(true)
	_passives = passive_data.items.duplicate(true)
	if not passive_data.get("progression") is Dictionary:
		_base_errors.append("invalid_item")
	else:
		_progression = passive_data.progression.duplicate(true)
		for field in ["base_xp","xp_per_level"]:
			if not integer_valid(_progression.get(field),1,MAX_COUNTER): _base_errors.append("invalid_item")
	var equipment_ids := _equipment.keys()
	equipment_ids.sort()
	var passive_ids := _passives.keys()
	passive_ids.sort()
	var expected_passives := PASSIVE_STATS.keys()
	expected_passives.sort()
	var required_equipment: Array = equipment_ids.filter(func(id): return not id in OPTIONAL_EQUIPMENT_IDS)
	if required_equipment != EQUIPMENT_IDS or passive_ids != expected_passives: _base_errors.append("invalid_item")
	for id in _equipment:
		var row = _equipment[id]
		if not _row_valid(row) or not row.get("mode") in ["sector","circle","line","combo","projectile","chain","zone"]:
			_base_errors.append("invalid_item")
			continue
		for field in ["damage","damage_per_level","range","range_per_level"]:
			if not number_valid(row.get(field),0,1000000): _base_errors.append("invalid_item")
		for field in ["cooldown_ticks","cooldown_per_level"]:
			if not integer_valid(row.get(field),0,MAX_COUNTER): _base_errors.append("invalid_item")
		if number_valid(row.get("cooldown_ticks"),0,MAX_COUNTER) and number_valid(row.get("cooldown_per_level"),0,MAX_COUNTER) and row.cooldown_ticks-4*row.cooldown_per_level < 1: _base_errors.append("invalid_item")
		if row.mode == "zone":
			if not integer_valid(row.get("pulse_count"),1,8) or not integer_valid(row.get("pulse_per_level"),0,1) or row.pulse_count+4*row.pulse_per_level > 8 or not integer_valid(row.get("pulse_interval"),1,60): _base_errors.append("invalid_item")
			if not number_valid(row.get("zone_radius"),1,10000) or not number_valid(row.get("zone_radius_per_level"),0,1000): _base_errors.append("invalid_item")
		if row.mode == "chain":
			if not integer_valid(row.get("chain_count"),1,12) or not integer_valid(row.get("chain_per_level"),0,2) or row.chain_count+4*row.chain_per_level > 12: _base_errors.append("invalid_item")
			if not number_valid(row.get("hop_range"),1,10000) or not number_valid(row.get("hop_range_per_level"),0,1000): _base_errors.append("invalid_item")
		if row.mode == "sector" and not number_valid(row.get("arc_degrees"),1,360): _base_errors.append("invalid_item")
		if row.mode == "line" and not number_valid(row.get("width"),1,1000000): _base_errors.append("invalid_item")
		if row.mode == "combo" and not integer_valid(row.get("hits"),1,64): _base_errors.append("invalid_item")
		if row.mode == "projectile":
			if not number_valid(row.get("projectile_speed"),1,1000000) or not number_valid(row.get("splash_radius"),0,1000000): _base_errors.append("invalid_item")
	for id in _passives:
		var row = _passives[id]
		if not _row_valid(row) or not PASSIVE_STATS.has(id) or row.get("stat") != PASSIVE_STATS[id] or not number_valid(row.get("increment"),-1000000,1000000):
			_base_errors.append("invalid_item")
		elif (id == "fire_interval" and (row.increment >= 0 or 1+5*row.increment <= 0)) or (id != "fire_interval" and row.increment <= 0): _base_errors.append("invalid_item")
func _row_valid(row: Variant) -> bool:
	return row is Dictionary and row.get("name") is String and not row.name.is_empty() and row.get("description") is String and integer_valid(row.get("max_level"),MAX_LEVEL,MAX_LEVEL)
func validate() -> Array[String]:
	var errors := _base_errors.duplicate()
	errors.append_array(evolutions.validate())
	return errors
func state_valid(state: Dictionary) -> bool:
	if not _base_errors.is_empty() or not state.get("equipment") is Dictionary or not state.get("passives") is Dictionary or not state.get("rules") is Dictionary: return false
	if not number_valid(state.rules.get("permanent_damage_bonus",0.0),0.0,0.25): return false
	var allowed = state.rules.get("allowed_equipment_ids")
	if not number_valid(state.rules.get("character_blade_cooldown_multiplier",1.0),0.85,1.0): return false
	if not allowed is Array or allowed.size() > _equipment.size(): return false
	var unique := {}
	for id in allowed:
		if not id is String or not _equipment.has(id) or unique.has(id): return false
		unique[id] = true
	for kind in ["equipment","passive"]:
		var owned: Dictionary = state.equipment if kind == "equipment" else state.passives
		var catalog: Dictionary = _equipment if kind == "equipment" else _passives
		if owned.size() > SLOT_LIMIT or not integer_valid(state.rules.get(kind+"_slots",SLOT_LIMIT),SLOT_LIMIT,SLOT_LIMIT): return false
		for id in owned:
			if not (id is String or id is StringName) or not catalog.has(id) or not integer_valid(owned[id],1,MAX_LEVEL): return false
			if kind == "equipment" and not id in allowed: return false
	return true
func candidates(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not state_valid(state) or not validate().is_empty(): return result
	for kind in ["equipment","passive"]:
		var catalog: Dictionary = _equipment if kind == "equipment" else _passives
		var owned: Dictionary = state.equipment if kind == "equipment" else state.passives
		var item_ids := catalog.keys()
		item_ids.sort()
		for id in item_ids:
			if kind == "equipment" and not id in state.rules.allowed_equipment_ids: continue
			if not owned.has(id) and owned.size() >= SLOT_LIMIT: continue
			var level := int(owned.get(id,0))
			if level >= MAX_LEVEL: continue
			result.append({"option_id":kind+":"+id,"item_id":id,"kind":kind,"level":level,"next_level":level+1,"name":catalog[id].name,"description":catalog[id].description})
	return result
# Compatibility wrapper; Core's NEW activation path uses GrowthOfferService instead.
func options(state: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var pool := candidates(state)
	var result: Array[Dictionary] = []
	while not pool.is_empty() and result.size() < 3:
		var index := rng.randi_range(0,pool.size()-1)
		result.append(pool[index].duplicate(true))
		pool.remove_at(index)
	return result
func option_well_formed(state: Dictionary, option: Dictionary) -> bool:
	if not state_valid(state): return false
	for field in ["option_id","item_id","kind"]:
		if not option.get(field) is String or option[field].is_empty(): return false
	if not integer_valid(option.get("level"),0,MAX_LEVEL) or not integer_valid(option.get("next_level"),1,MAX_LEVEL+1): return false
	if option.kind == "evolution":
		if not option.get("evolution_id") is String: return false
		var definition: Dictionary = evolutions.definition(option.evolution_id)
		return not definition.is_empty() and option.item_id == definition.base_item_id and option.option_id == "evolution:"+option.evolution_id and option.level == MAX_LEVEL and option.next_level == evolutions.final_stage_level()
	if not option.kind in ["equipment","passive"]: return false
	var catalog: Dictionary = _equipment if option.kind == "equipment" else _passives
	if not catalog.has(option.item_id) or int(option.level) >= MAX_LEVEL or int(option.next_level) != int(option.level)+1: return false
	if option.kind == "equipment" and not option.item_id in state.rules.allowed_equipment_ids: return false
	return option.option_id == option.kind+":"+option.item_id
func option_valid(state: Dictionary, option: Dictionary) -> bool:
	if not option_well_formed(state,option): return false
	if option.kind == "evolution": return evolutions.evaluate(state,option.evolution_id).get("can_evolve",false)
	var owned: Dictionary = state.equipment if option.kind == "equipment" else state.passives
	return int(option.level) == int(owned.get(option.item_id,0)) and (owned.has(option.item_id) or owned.size() < SLOT_LIMIT)
# Retained for callers, but never repairs/re-rolls a stale materialized offer.
func rebase_options(state: Dictionary, choices: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var identities := {}
	if choices.size() > 3: return result
	for original in choices:
		if not original is Dictionary or not option_valid(state,original) or identities.has(original.option_id): return []
		identities[original.option_id] = true
		result.append(original.duplicate(true))
	return result
func stat(state: Dictionary, stat_name: String, base: float) -> float:
	if not is_finite(base): return 0.0
	if not validate().is_empty() or not state_valid(state): return base
	var value := base
	if stat_name == "damage_multiplier": value += float(state.rules.get("permanent_damage_bonus",0.0))
	var owned = state.get("passives",{})
	if not owned is Dictionary: return value
	var ids: Array = owned.keys()
	ids.sort()
	for id in ids:
		if _passives.has(id) and _passives[id].stat == stat_name and integer_valid(owned[id],1,MAX_LEVEL): value += float(_passives[id].increment)*int(owned[id])
	return value
func weapon_stats(state: Dictionary, item_id: String, level: int) -> Dictionary:
	if not validate().is_empty() or not state_valid(state) or not _equipment.has(item_id) or level < 1 or level > MAX_LEVEL: return {}
	var row: Dictionary = _equipment[item_id]
	var offset := level-1
	var range_scale := stat(state,"range_multiplier",1.0)
	var character_cooldown := float(state.rules.get("character_blade_cooldown_multiplier",1.0)) if item_id == "blade_slash" else 1.0
	var result := {"damage":(float(row.damage)+float(row.damage_per_level)*offset)*stat(state,"damage_multiplier",1.0),"range":(float(row.range)+float(row.range_per_level)*offset)*range_scale,"cooldown_ticks":maxi(1,int(round((float(row.cooldown_ticks)-float(row.cooldown_per_level)*offset)*stat(state,"cooldown_multiplier",1.0)*character_cooldown)))}
	# Range scales linear geometry only, never angle, hit count or projectile speed.
	for field in ["width","splash_radius"]:
		if row.has(field): result[field] = float(row[field])*range_scale
	for field in ["arc_degrees","hits","projectile_speed"]:
		if row.has(field): result[field] = row[field]
	if row.mode == "chain":
		result.chain_count = int(row.chain_count)+offset*int(row.chain_per_level)
		result.hop_range = (float(row.hop_range)+offset*float(row.hop_range_per_level))*range_scale
	if row.mode == "zone":
		result.pulse_count = int(row.pulse_count)+offset*int(row.pulse_per_level)
		result.pulse_interval = int(row.pulse_interval)
		result.zone_radius = (float(row.zone_radius)+offset*float(row.zone_radius_per_level))*range_scale
	return result
func presentation_state_valid(state: Dictionary) -> bool:
	if not evolutions.progression_state_valid(state) or not state.get("run_config") is Dictionary or not json_data_valid(state.run_config): return false
	var target = state.run_config.get("target_evolution_id")
	if not target is String or evolutions.definition(target).is_empty(): return false
	for field in ["base_hp","pickup_radius"]:
		if state.rules.has(field) and not number_valid(state.rules[field],1.0 if field == "base_hp" else 0.0,1000000.0): return false
	return true
func decorate_option(state: Dictionary, original: Dictionary, presentation_only: bool = false) -> Dictionary:
	if not presentation_state_valid(state) or not json_data_valid(original) or not option_well_formed(state,original): return {}
	# Explicit scalar identity projection. Arbitrary source metadata is never copied.
	var option := {}
	for field in ["option_id","item_id","kind","level","next_level"]: option[field] = original[field]
	if original.kind == "evolution": option.evolution_id = original.evolution_id
	# Historical offer decoration is persisted authority, not a UI projection.
	if evolutions._schema_version == 2 or presentation_only:
		option.max_level = MAX_LEVEL
		if original.kind != "passive":
			for id in evolutions.ids():
				if evolutions.definition(id).base_item_id != original.item_id: continue
				option.max_level = MAX_LEVEL+1
				break
		option.display_level = int(original.level)
		option.display_next_level = 6 if original.kind == "evolution" else int(original.next_level)
		option.display_max_level = int(option.max_level)
		option.icon_id = "skill_"+str(original.get("evolution_id",original.item_id))
	option.can_select = option_valid(state,original)
	option.blocked_reason = "" if option.can_select else "invalid_option"
	option.slot_warning = ""
	option.tradeoff_text = ""
	option.effect_delta = {}
	option.requirements = []
	var target_id: String = state.get("run_config",{}).get("target_evolution_id","")
	var detail: Dictionary = evolutions.evaluate(state,option.get("evolution_id",target_id),presentation_only)
	if not detail.is_empty(): option.requirements = detail.requirements.duplicate(true)
	if option.kind == "evolution":
		for key in detail: option[key] = detail[key]
		return option
	var catalog: Dictionary = _equipment if option.kind == "equipment" else _passives
	var row: Dictionary = catalog[option.item_id]
	option.name = row.name
	option.description = row.description
	if option.kind == "equipment":
		var before := weapon_stats(state,option.item_id,int(option.level)) if option.level > 0 else {"damage":0.0,"range":0.0,"cooldown_ticks":0}
		var after := weapon_stats(state,option.item_id,int(option.next_level))
		for field in ["damage","range","cooldown_ticks"]:
			option.effect_delta[field+"_before"] = before[field]
			option.effect_delta[field+"_after"] = after[field]
		option.description = "%s · 피해 %s → %s"%[row.description,str(before.damage),str(after.damage)]
	else:
		var base := _stat_base(state,row.stat)
		if row.stat == "damage_multiplier": base += float(state.rules.get("permanent_damage_bonus",0.0))
		option.effect_delta = {"stat":row.stat,"before":base+float(row.increment)*int(option.level),"after":base+float(row.increment)*int(option.next_level)}
	if option.can_select and option.level == 0 and not detail.is_empty() and detail.status == "collecting":
		var owned: Dictionary = state.equipment if option.kind == "equipment" else state.passives
		if owned.size() == SLOT_LIMIT-1:
			for required in detail.requirements:
				if required.kind == option.kind and required.current == 0 and required.item_id != option.item_id:
					option.slot_warning = "이 선택으로 목표 진화의 필수 기술을 새로 배울 수 없습니다"
					option.tradeoff_text = "마지막 슬롯을 사용하므로 아직 없는 %s을(를) 얻을 수 없습니다."%required.name
	return option
func _stat_base(state: Dictionary, stat_name: String) -> float:
	if stat_name.ends_with("_multiplier"): return 1.0
	if stat_name == "max_hp": return float(state.rules.get("base_hp",100.0))
	if stat_name == "pickup_radius": return float(state.rules.get("pickup_radius",30.0))
	return 0.0
static func json_data_valid(value: Variant) -> bool:
	return _json_visit(value,0,[4096])
static func _json_visit(value: Variant, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if depth > 8 or budget[0] < 0: return false
	if value is Dictionary:
		if value.size() > 64: return false
		for key in value:
			if not (key is String or key is StringName) or key.length() > 80 or not _json_visit(value[key],depth+1,budget): return false
		return true
	if value is Array:
		if value.size() > 64: return false
		for child in value:
			if not _json_visit(child,depth+1,budget): return false
		return true
	if value is String: return value.length() <= 2048
	if value is int or value is float: return is_finite(float(value))
	return value == null or value is bool
static func integer_valid(value: Variant, minimum: int = 0, maximum: int = MAX_COUNTER) -> bool:
	return number_valid(value,float(minimum),float(maximum)) and float(value) == floor(float(value))
static func number_valid(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func xp_to_next(level: int, curve: Dictionary) -> int:
	return int(curve.base_xp)+(level-1)*int(curve.xp_per_level)
