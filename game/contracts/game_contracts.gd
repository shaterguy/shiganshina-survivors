class_name GameContracts
extends RefCounted
const SCHEMA_VERSION := 1
const FINAL_TICK := 108000
const BOSS_TICKS := [18000, 36000, 54000, 72000, 90000, 108000]
const PHASES := ["survival", "evacuation", "won", "dead"]
const REQUIRED := ["schema_version", "content_revision", "chapter_id", "character_id", "seed", "rng_state", "active_tick", "survival_tick", "phase", "pause_reasons", "player", "entities", "projectiles", "drops", "telegraphs", "equipment", "passives", "boss_ids_fired", "reward_ids_claimed", "command_ids_applied", "upgrade_offer", "pending_offers", "stats", "next_entity_id", "event_seq", "final_started_tick", "evacuation_ready", "escape_zone"]
func validate_snapshot(value: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in REQUIRED:
		if not value.has(key):
			errors.append("missing:" + key)
	if not errors.is_empty():
		return errors
	if value.schema_version != SCHEMA_VERSION:
		errors.append("unsupported_schema")
	for key in ["content_revision", "chapter_id", "character_id", "phase"]:
		if not value[key] is String:
			errors.append("not_string:" + key)
	if not value.phase in PHASES:
		errors.append("invalid_phase")
	for key in ["active_tick", "survival_tick", "next_entity_id", "event_seq"]:
		if not _integer_number(value[key]) or value[key] < 0:
			errors.append("invalid:" + key)
	if _integer_number(value.survival_tick) and value.survival_tick > FINAL_TICK:
		errors.append("survival_time_overflow")
	if not value.rng_state is String or not value.rng_state.is_valid_int():
		errors.append("invalid_rng_state")
	for key in ["pause_reasons", "entities", "projectiles", "drops", "telegraphs", "boss_ids_fired", "reward_ids_claimed", "command_ids_applied", "pending_offers"]:
		if not value[key] is Array:
			errors.append("not_array:" + key)
	for key in ["player", "equipment", "passives", "upgrade_offer", "stats"]:
		if not value[key] is Dictionary:
			errors.append("not_dictionary:" + key)
	if not _json_safe(value):
		errors.append("not_json_safe")
	return errors
func _integer_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))
func _json_safe(value: Variant) -> bool:
	if value == null or value is String or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child in value:
			if not _json_safe(child): return false
		return true
	if value is Dictionary:
		for key in value:
			# Godot dot assignment interns generated field keys as StringName;
			# JSON serializes those exactly like String keys. Other key types and
			# non-JSON values (Object, Callable, vectors, etc.) remain invalid.
			if not (key is String or key is StringName) or not _json_safe(value[key]): return false
		return true
	return false
