class_name EvolutionCatalog
extends RefCounted
# NEW recipe/evaluation authority. Only the approved 845 chapter is supported.
# A weak owner avoids a Catalog -> EvolutionCatalog -> Catalog reference cycle.
const CHAPTER_YEARS := {"chapter_01_shiganshina":845}
const EFFECT_BASES := {"wing_cut":"blade_slash","crossfire":"wall_cannon"}
var _owner: WeakRef
var _items: Dictionary = {}
var _errors: Array[String] = []
func _init(upgrade_catalog, definitions_override = null) -> void:
	_owner = weakref(upgrade_catalog)
	var data = upgrade_catalog._read("res://data/evolutions.json") if definitions_override == null else definitions_override
	if not upgrade_catalog.json_data_valid(data) or not data is Dictionary or data.get("schema_version") != 1 or not data.get("items") is Dictionary or data.items.is_empty() or data.items.size() > 32:
		_errors.append("invalid_item")
		return
	var equipment: Dictionary = upgrade_catalog.equipment
	var passives: Dictionary = upgrade_catalog.passives
	var bases := {}
	for id in data.items:
		var row = data.items[id]
		if not _recipe_valid(id,row,equipment,passives) or bases.has(row.get("base_item_id") if row is Dictionary else ""):
			_errors.append("invalid_item")
		else: bases[row.base_item_id] = true
	if _errors.is_empty(): _items = data.items.duplicate(true)
func validate() -> Array[String]: return _errors.duplicate()
func ids() -> Array:
	var result := _items.keys()
	result.sort()
	return result
func definition(id: String) -> Dictionary: return _items.get(id,{}).duplicate(true)
func _recipe_valid(id: Variant, row: Variant, equipment: Dictionary, passives: Dictionary) -> bool:
	if not id is String or not id.begins_with("evo_") or id.length() > 80 or not row is Dictionary: return false
	if row.get("recipe_id") != id or not row.get("base_item_id") is String or not equipment.has(row.base_item_id): return false
	if not _integer(row.get("story_year"),845,845) or not _integer(row.get("required_weapon_level"),5,5) or not _integer(row.get("seal_cost"),1,1): return false
	for field in ["name","description","tradeoff_text"]:
		if not row.get(field) is String or row[field].is_empty(): return false
	if not row.get("effect_id") is String or not EFFECT_BASES.has(row.effect_id) or EFFECT_BASES[row.effect_id] != row.base_item_id: return false
	if not row.get("chapter_ids") is Array or row.chapter_ids.is_empty() or row.chapter_ids.size() > CHAPTER_YEARS.size(): return false
	var seen := {}
	for chapter in row.chapter_ids:
		if not chapter is String or not CHAPTER_YEARS.has(chapter) or CHAPTER_YEARS[chapter] != row.story_year or seen.has(chapter): return false
		seen[chapter] = true
	if not row.get("required_passives") is Array or row.required_passives.is_empty() or row.required_passives.size() > 4: return false
	seen.clear()
	for required in row.required_passives:
		if not required is Dictionary or required.size() != 2 or not required.get("passive_id") is String or not passives.has(required.passive_id) or not _integer(required.get("level"),3,3) or seen.has(required.passive_id): return false
		seen[required.passive_id] = true
	return _effect_valid(row.effect_id,row.get("effect_params"))
func _effect_valid(effect_id: String, params: Variant) -> bool:
	if not params is Dictionary: return false
	var fields := ["damage_multipliers","stage_delays","radius","cooldown_ticks"]
	fields.append_array(["arc_degrees"] if effect_id == "wing_cut" else ["acquisition_range","point_offset"])
	if params.size() != fields.size() or not params.has_all(fields): return false
	if not params.damage_multipliers is Array or params.damage_multipliers.size() != 2 or not params.stage_delays is Array or params.stage_delays.size() != 2: return false
	for multiplier in params.damage_multipliers:
		if not _number(multiplier,0.001,100): return false
	for delay in params.stage_delays:
		if not _integer(delay,0,3600): return false
	if params.stage_delays[1] <= params.stage_delays[0]: return false
	if (effect_id == "wing_cut" and params.stage_delays[0] != 0) or (effect_id == "crossfire" and params.stage_delays[0] == 0): return false
	if not _number(params.radius,1,10000) or not _integer(params.cooldown_ticks,1,36000): return false
	if effect_id == "wing_cut": return _number(params.arc_degrees,1,360)
	return _number(params.acquisition_range,1,10000) and _number(params.point_offset,1,10000)
func progression_state_valid(state: Dictionary) -> bool:
	var owner = _owner.get_ref()
	if owner == null or not owner.state_valid(state) or not _errors.is_empty(): return false
	var applied = state.get("evolutions",{})
	if not applied is Dictionary or applied.size() > 4 or not _integer(state.get("tactical_seals",0),0,5) or applied.size()+int(state.get("tactical_seals",0)) > 5: return false
	for base in applied:
		if not (base is String or base is StringName) or not applied[base] is String or not _items.has(applied[base]): return false
		var recipe: Dictionary = _items[applied[base]]
		if recipe.base_item_id != base or state.equipment.get(base,0) != recipe.required_weapon_level or not state.get("chapter_id","") in recipe.chapter_ids: return false
		for passive in recipe.required_passives:
			if state.passives.get(passive.passive_id,0) < passive.level: return false
	return true
func evaluate(state: Dictionary, evolution_id: String) -> Dictionary:
	if not _items.has(evolution_id) or not progression_state_valid(state): return {}
	var owner = _owner.get_ref()
	var recipe: Dictionary = _items[evolution_id]
	var equipment: Dictionary = owner.equipment
	var passives: Dictionary = owner.passives
	var allowed: bool = state.get("chapter_id","") in recipe.chapter_ids and recipe.base_item_id in state.rules.allowed_equipment_ids
	var requirements: Array[Dictionary] = []
	var weapon_level := int(state.equipment.get(recipe.base_item_id,0))
	var weapon_reason := ""
	if not allowed: weapon_reason = "chapter_not_allowed"
	elif weapon_level == 0: weapon_reason = "equipment_slots" if state.equipment.size() >= 4 else "missing_weapon"
	elif weapon_level < recipe.required_weapon_level: weapon_reason = "weapon_level"
	requirements.append(_requirement("equipment",recipe.base_item_id,equipment[recipe.base_item_id].name,weapon_level,int(recipe.required_weapon_level),weapon_reason))
	for passive in recipe.required_passives:
		var current := int(state.passives.get(passive.passive_id,0))
		var reason := ""
		if current == 0: reason = "passive_slots" if state.passives.size() >= 4 else "missing_passive"
		elif current < passive.level: reason = "passive_level"
		requirements.append(_requirement("passive",passive.passive_id,passives[passive.passive_id].name,current,int(passive.level),reason))
	var seals := int(state.get("tactical_seals",0))
	requirements.append(_requirement("seal","tactical_seal","전술 개조권",seals,int(recipe.seal_cost),"" if seals >= recipe.seal_cost else "seal_required"))
	var complete := true
	var blocked := false
	for requirement in requirements:
		complete = complete and requirement.met
		blocked = blocked or requirement.blocked_reason in ["equipment_slots","passive_slots"]
	var status := "collecting"
	if not allowed: status = "unavailable"
	elif state.get("evolutions",{}).get(recipe.base_item_id,"") == evolution_id: status = "evolved"
	elif blocked: status = "blocked"
	elif complete: status = "ready"
	return {"evolution_id":evolution_id,"base_item_id":recipe.base_item_id,"name":recipe.name,"description":recipe.description,"status":status,"can_evolve":status == "ready","requirements":requirements,"effect_delta":_effect_delta(state,recipe),"tradeoff_text":recipe.tradeoff_text}
func _requirement(kind: String, id: String, label: String, current: int, required: int, reason: String) -> Dictionary:
	return {"kind":kind,"item_id":id,"name":label,"current":current,"required":required,"met":current >= required,"blocked_reason":reason}
func _effect_delta(state: Dictionary, recipe: Dictionary) -> Dictionary:
	var owner = _owner.get_ref()
	var params: Dictionary = recipe.effect_params
	var weapon: Dictionary = owner.weapon_stats(state,recipe.base_item_id,int(recipe.required_weapon_level))
	var scale: float = owner.stat(state,"range_multiplier",1.0)
	var character_cooldown := float(state.rules.get("character_blade_cooldown_multiplier",1.0)) if recipe.base_item_id == "blade_slash" else 1.0
	var damage := []
	for multiplier in params.damage_multipliers: damage.append(float(weapon.damage)*float(multiplier))
	var result := {"stages":2,"stage_damage":damage,"stage_delays":[int(params.stage_delays[0]),int(params.stage_delays[1])],"radius":float(params.radius)*scale,"cooldown_ticks":maxi(1,int(round(float(params.cooldown_ticks)*owner.stat(state,"cooldown_multiplier",1.0)*character_cooldown)))}
	# Linear distances scale once. Sector angles and tick delays never scale.
	if recipe.effect_id == "wing_cut": result.arc_degrees = params.arc_degrees
	else:
		result.acquisition_range = float(params.acquisition_range)*scale
		result.point_offset = float(params.point_offset)*scale
	return result
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,minimum,maximum) and float(value) == floor(float(value))
static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
