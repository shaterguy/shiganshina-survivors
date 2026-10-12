class_name GameContracts
extends RefCounted
# NEW v2 bounded structural boundary. Semantic combat validation is owned by Core.
const SCHEMA_VERSION := 2
const CONTENT_REVISION := "ch01.3-rebuild.7-grabber-hand"
const MAX_COUNTER := 2147483647
const FINAL_TICK := 108000
const BOSS_TICKS := [18000,36000,54000,72000,90000]
const PHASES := ["survival","evacuation","won","dead","abandoned"]
const REQUIRED := ["schema_version","content_revision","chapter_id","character_id","seed","rng_state","active_tick","survival_tick","next_entity_id","event_seq","phase","pause_reasons","player","equipment","passives","entities","projectiles","drops","telegraphs","boss_ids_fired","reward_ids_claimed","command_ids_applied","upgrade_offer","pending_offers","final_started_tick","evacuation_ready","escape_zone","stats","rules","run_id","run_serial","run_config","evolutions","tactical_seals","progression_rng_state","attack_seq","offer_seq","view_revision","player_attack_instances","enemy_attack_instances","evolution_runtime","supply_used"]
const ARRAY_CAPS := {"pause_reasons":6,"entities":512,"projectiles":256,"drops":256,"telegraphs":1024,"boss_ids_fired":6,"reward_ids_claimed":4096,"command_ids_applied":16384,"pending_offers":256,"player_attack_instances":64,"enemy_attack_instances":128}
func validate_snapshot(value: Dictionary) -> Array[String]:
	if not _json_safe(value): return ["invalid_snapshot"]
	if not _counter(value.get("schema_version")) or value.schema_version != SCHEMA_VERSION: return ["unsupported_schema"]
	for key in REQUIRED:
		if not value.has(key): return ["missing:"+key]
	for key in value:
		if not key in REQUIRED and key != "world": return ["invalid_snapshot"]
	for key in ["content_revision","chapter_id","character_id","phase","run_id","rng_state","progression_rng_state"]:
		if not value[key] is String or value[key].is_empty(): return ["invalid_snapshot"]
	if not value.phase in PHASES: return ["invalid_snapshot"]
	for key in ["seed","active_tick","survival_tick","next_entity_id","event_seq","run_serial","tactical_seals","attack_seq","offer_seq","view_revision"]:
		if not _counter(value[key]): return ["invalid_snapshot"]
	if value.next_entity_id < 1 or value.run_serial < 1 or value.view_revision < 1 or value.survival_tick > FINAL_TICK or value.tactical_seals > 5: return ["invalid_snapshot"]
	if not _counter(value.final_started_tick,-1) or not _rng_state(value.rng_state) or not _rng_state(value.progression_rng_state): return ["invalid_snapshot"]
	if not value.evacuation_ready is bool or not value.supply_used is bool: return ["invalid_snapshot"]
	for key in ARRAY_CAPS:
		if not value[key] is Array or value[key].size() > ARRAY_CAPS[key]: return ["invalid_snapshot"]
	for key in ["player","equipment","passives","upgrade_offer","stats","rules","run_config","evolutions","evolution_runtime"]:
		if not value[key] is Dictionary: return ["invalid_snapshot"]
	if value.has("world") and not value.world is Dictionary: return ["invalid_snapshot"]
	return []
func _json_safe(value: Variant) -> bool:
	return _visit(value,0,[200000])
func _visit(value: Variant, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if depth > 32 or budget[0] < 0: return false
	if value == null or value is bool or value is int: return true
	if value is String: return value.length() <= 4096
	if value is float: return is_finite(value)
	if value is Array:
		if value.size() > 16384: return false
		for child in value:
			if not _visit(child,depth+1,budget): return false
		return true
	if value is Dictionary:
		if value.size() > 16384: return false
		for key in value:
			if not (key is String or key is StringName) or key.length() > 256 or not _visit(value[key],depth+1,budget): return false
		return true
	return false
static func _counter(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= MAX_COUNTER
static func _rng_state(value: Variant) -> bool:
	return value is String and value.length() <= 20 and value.is_valid_int() and str(value.to_int()) == value
