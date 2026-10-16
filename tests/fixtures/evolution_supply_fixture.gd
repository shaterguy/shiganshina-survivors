extends RefCounted
# Transcript-backed helper, NEW case routing for NEW R0 DTOs.
# Test-only fixtures, never an alternative production simulation/validator.
const Loot = preload("res://game/loot/loot_rules.gd")
const ROOT := "res://tests/fixtures/evolution_supply_grabber/"
func _read(name: String) -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(ROOT+name))
	return value.duplicate(true) if value is Dictionary else {}
func _case(name: String,case_id: String) -> Dictionary:
	var value = _read(name).get(case_id,{})
	return value.duplicate(true) if value is Dictionary else {}
func run_state(case_id: String = "initial") -> Dictionary:
	return _case("run_v2.json",case_id)
func game_save(case_id: String = "initial") -> Dictionary:
	return _case("game_save_v2.json","empty" if case_id == "initial" else case_id)
func progression_view(case_id: String) -> Dictionary:
	return _case("progression_views.json","blocked" if case_id == "last_slot_warning" else case_id)
func progression_source_offer(case_id: String) -> Dictionary:
	return _case("progression_source_offers.json","blocked" if case_id == "last_slot_warning" else case_id)
func supply_view(case_id: String) -> Dictionary:
	return _case("supply_views.json",case_id)
func attack_events(case_id: String) -> Array[Dictionary]:
	return _attack_array(case_id,"events")
func attack_reservations(case_id: String) -> Array[Dictionary]:
	return _attack_array(case_id,"reservations")
func _attack_array(case_id: String,key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var value = _case("attack_events.json",case_id).get(key,[])
	if value is Array:
		for item in value:
			if item is Dictionary: result.append(item.duplicate(true))
	return result
func make_run(_chapter: Dictionary,seed: int,config: Dictionary) -> Dictionary:
	# SHAPE-ONLY FAKE: identity transformation for E isolation, no real Core rules.
	var result := run_state()
	result.seed = seed
	result.run_config = config.duplicate(true)
	result.run_id = config.run_id
	result.run_serial = config.run_serial
	# Only newly requested rules receive fresh loot; historical JSON stays exact.
	if Loot.version_valid(config.get("loot_rules_version")): result.loot = Loot.initial(int(config.loot_rules_version))
	return result
func validate_checkpoint(value: Dictionary) -> Dictionary:
	# SHAPE-ONLY FAKE: never evidence of semantic/streamed checkpoint validity.
	if value.get("schema_version") != 2 or not value.get("run_id") is String or not value.get("player") is Dictionary:
		return {"ok":false,"error_code":"invalid_snapshot"}
	return {"ok":true,"state":value.duplicate(true)}
