class_name UpgradeCatalog
extends RefCounted
var equipment: Dictionary
var passives: Dictionary
var progression: Dictionary
func _init() -> void:
	equipment = _read_items("res://data/equipment.json")
	passives = _read_items("res://data/passives.json")
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	progression = parsed.progression
func _read_items(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get("items",{}) if parsed is Dictionary else {}
func options(state: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for kind in ["equipment","passive"]:
		var catalog: Dictionary = equipment if kind == "equipment" else passives
		var equipped: Dictionary = state.equipment if kind == "equipment" else state.passives
		var item_ids: Array = catalog.keys()
		item_ids.sort()
		for item_id in item_ids:
			if kind == "equipment" and not item_id in state.rules.allowed_equipment_ids: continue
			if kind == "equipment" and not equipped.has(item_id) and equipped.size() >= 4: continue
			var level := int(equipped.get(item_id,0))
			if level >= int(catalog[item_id].max_level): continue
			candidates.append({"option_id":"%s:%s:%d"%[kind,item_id,level+1],"item_id":item_id,"kind":kind,"level":level,"next_level":level+1,"name":catalog[item_id].name,"description":catalog[item_id].description})
	var result: Array[Dictionary] = []
	while not candidates.is_empty() and result.size() < 3:
		var index := rng.randi_range(0,candidates.size()-1)
		result.append(candidates[index])
		candidates.remove_at(index)
	while result.size() < 3:
		var amount: float = [25.0,40.0,60.0][result.size()]
		result.append({"option_id":"recovery:%d"%int(amount),"item_id":"field_recovery_%d"%int(amount),"kind":"recovery","level":0,"next_level":1,"amount":amount,"name":"야전 응급 보급","description":"체력 %d 회복"%int(amount)})
	return result
func option_well_formed(state: Dictionary, option: Dictionary) -> bool:
	for key in ["option_id","item_id","kind"]:
		if not option.get(key,null) is String or option[key].is_empty(): return false
	for key in ["level","next_level"]:
		if not _integer_valid(option.get(key,null)): return false
	var kind: String = option.kind
	if kind == "recovery":
		var amount = option.get("amount",null)
		if not _integer_valid(amount) or not int(amount) in [25,40,60]: return false
		return option.level == 0 and option.next_level == 1 and option.option_id == "recovery:%d"%int(amount) and option.item_id == "field_recovery_%d"%int(amount)
	if not kind in ["equipment","passive"]: return false
	var catalog: Dictionary = equipment if kind == "equipment" else passives
	var item_id: String = option.item_id
	if not catalog.has(item_id) or int(option.level) >= int(catalog[item_id].max_level) or int(option.next_level) != int(option.level)+1: return false
	if kind == "equipment" and not item_id in state.rules.allowed_equipment_ids: return false
	return option.option_id == "%s:%s:%d"%[kind,item_id,int(option.next_level)]
func option_valid(state: Dictionary, option: Dictionary) -> bool:
	if not option_well_formed(state,option): return false
	if option.kind == "recovery": return true
	var equipped: Dictionary = state.equipment if option.kind == "equipment" else state.passives
	var item_id: String = option.item_id
	return int(option.level) == int(equipped.get(item_id,0)) and (option.kind != "equipment" or equipped.has(item_id) or equipped.size() < 4)
func rebase_options(state: Dictionary, choices: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var identities: Array[String] = []
	var semantic_ids: Array[String] = []
	for original in choices:
		if not original is Dictionary or not option_well_formed(state,original): return []
		var identity := "%s:%s"%[original.kind,original.item_id]
		if identity in identities: return []
		identities.append(identity)
		var option: Dictionary = original.duplicate(true)
		if option.kind != "recovery":
			var equipped: Dictionary = state.equipment if option.kind == "equipment" else state.passives
			option.level = int(equipped.get(option.item_id,0))
			option.next_level = int(option.level)+1
			option.option_id = "%s:%s:%d"%[option.kind,option.item_id,int(option.next_level)]
		if not option_valid(state,option) or option.option_id in semantic_ids: return []
		semantic_ids.append(option.option_id)
		result.append(option)
	return result
func _integer_valid(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floor(float(value))
func stat(state: Dictionary, stat_name: String, base: float) -> float:
	var value := base
	for item_id in state.passives:
		if passives.has(item_id) and passives[item_id].stat == stat_name:
			value += float(passives[item_id].increment)*int(state.passives[item_id])
	return value
static func xp_to_next(level: int, curve: Dictionary) -> int:
	return int(curve.base_xp)+(level-1)*int(curve.xp_per_level)
