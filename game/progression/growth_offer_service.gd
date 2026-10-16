class_name GrowthOfferService
extends RefCounted
# NEW pure materialization. The caller activates this result exactly once.
const Loot = preload("res://game/loot/loot_rules.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
var _catalog
func _init(upgrade_catalog = null) -> void:
	_catalog = Upgrades.new() if upgrade_catalog == null else upgrade_catalog
func materialize(state: Dictionary, descriptor: Dictionary) -> Dictionary:
	if not _catalog.validate().is_empty() or not _catalog.presentation_state_valid(state): return _failure("invalid_core_state")
	if not state.get("phase","") in ["survival","evacuation"] or not state.get("upgrade_offer") is Dictionary or not state.upgrade_offer.is_empty(): return _failure("invalid_offer")
	if not _descriptor_valid(state,descriptor): return _failure("invalid_offer_queue")
	if not _rng_valid(state.get("progression_rng_state")): return _failure("invalid_core_state")
	if not state.get("run_config") is Dictionary or not state.run_config.get("target_evolution_id") is String or _catalog.evolutions.definition(state.run_config.target_evolution_id).is_empty(): return _failure("invalid_run_config")
	var rng := RandomNumberGenerator.new()
	rng.state = state.progression_rng_state.to_int()
	var pool: Array[Dictionary] = _catalog.candidates(state)
	var chosen: Array[Dictionary] = []
	for id in _catalog.evolutions.ids():
		var detail: Dictionary = _catalog.evolutions.evaluate(state,id)
		if not detail.get("can_evolve",false): continue
		var option := {"option_id":"evolution:"+id,"item_id":detail.base_item_id,"kind":"evolution","level":5,"next_level":_catalog.evolutions.final_stage_level(),"evolution_id":id}
		chosen.append(_catalog.decorate_option(state,option))
		if chosen.size() == 3: break
	if descriptor.source == "level" and int(descriptor.level_ordinal)%2 == 0 and chosen.size() < 3:
		var target := _target_option(state)
		for index in range(pool.size()):
			if pool[index].option_id == target:
				chosen.append(_catalog.decorate_option(state,pool[index]))
				pool.remove_at(index)
				break
	while chosen.size() < 3 and not pool.is_empty():
		var index := rng.randi_range(0,pool.size()-1)
		chosen.append(_catalog.decorate_option(state,pool[index]))
		pool.remove_at(index)
	if chosen.is_empty(): return {"ok":true,"offer":{},"next_rng_state":state.progression_rng_state}
	var offer := descriptor.duplicate(true)
	offer.level_ordinal = int(descriptor.level_ordinal)
	offer.options = chosen
	offer.selected_option_id = chosen[0].option_id
	return {"ok":true,"offer":offer,"next_rng_state":str(rng.state)}
func _target_option(state: Dictionary) -> String:
	var id: String = state.run_config.target_evolution_id
	var detail: Dictionary = _catalog.evolutions.evaluate(state,id)
	if detail.get("status","") != "collecting": return ""
	var recipe: Dictionary = _catalog.evolutions.definition(id)
	for required in recipe.get("required_equipment",[]):
		if not state.equipment.has(required.equipment_id): return "equipment:"+required.equipment_id
	for required in recipe.required_passives:
		if not state.passives.has(required.passive_id): return "passive:"+required.passive_id
	if not state.equipment.has(recipe.base_item_id): return "equipment:"+recipe.base_item_id
	if int(state.equipment[recipe.base_item_id]) < int(recipe.required_weapon_level): return "equipment:"+recipe.base_item_id
	for required in recipe.required_passives:
		if int(state.passives[required.passive_id]) < int(required.level): return "passive:"+required.passive_id
	for required in recipe.get("required_equipment",[]):
		if int(state.equipment[required.equipment_id]) < int(required.level): return "equipment:"+required.equipment_id
	return ""
func _descriptor_valid(state: Dictionary, descriptor: Dictionary) -> bool:
	if state.get("run_config") is Dictionary and state.run_config.has("loot_rules_version") and not Loot.enabled(state): return false
	if not descriptor.has_all(["offer_id","source","level_ordinal"]) or not descriptor.source is String: return false
	if descriptor.size() != (4 if descriptor.source == "chest" else 3): return false
	if not descriptor.source is String or not descriptor.source in ["level","boss","chest"] or not descriptor.offer_id is String: return false
	if not Upgrades.integer_valid(descriptor.level_ordinal,1) or not Upgrades.integer_valid(state.get("offer_seq"),1): return false
	if not state.get("player") is Dictionary or not Upgrades.integer_valid(state.player.get("level"),1) or descriptor.level_ordinal > state.player.level: return false
	if descriptor.source == "chest":
		if not Loot.enabled(state) or not descriptor.get("chest_id") is String: return false
		var chest: Dictionary = Loot.find_chest(state,descriptor.chest_id)
		if chest.is_empty(): return false
		for field in ["status","reward","offer_id"]:
			if not chest.get(field) is String: return false
		if chest.status != "queued" or chest.reward != "skill" or chest.offer_id != descriptor.offer_id: return false
	elif descriptor.source == "boss" and Loot.enabled(state): return false
	if not _run_id_valid(state.get("run_id")): return false
	var prefix: String = state.run_id+":offer:"
	if not descriptor.offer_id.begins_with(prefix): return false
	var serial_text: String = descriptor.offer_id.substr(prefix.length())
	if not serial_text.is_valid_int() or str(serial_text.to_int()) != serial_text: return false
	return Upgrades.integer_valid(serial_text.to_int(),1,int(state.offer_seq))
static func _run_id_valid(value: Variant) -> bool:
	if not value is String or value.length() > 43: return false
	var parts: PackedStringArray = value.split(":")
	if parts.size() != 2 or parts[0].length() != 32: return false
	for character in parts[0]:
		if not character in "0123456789abcdef": return false
	return parts[1].is_valid_int() and str(parts[1].to_int()) == parts[1] and Upgrades.integer_valid(parts[1].to_int(),1)
static func _rng_valid(value: Variant) -> bool:
	return value is String and value.length() <= 20 and value.is_valid_int() and str(value.to_int()) == value
static func _failure(code: String) -> Dictionary: return {"ok":false,"error_code":code}

