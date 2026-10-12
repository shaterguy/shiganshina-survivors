class_name SaveMigrations
extends RefCounted
# NEW pure migration. Only the Store reads/preserves legacy bytes or commits authority.
# Missing known settings use exactly the preserved v1 SaveStore defaults. Other
# JSON-safe legacy metadata is copied, never inferred into the new economy.
const DEFAULT_SETTINGS := {"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false}
const MAX_COUNTER := 2147483647
const MAX_DEPTH := 64
const MAX_JSON_VALUES := 262144
const MAX_PROFILE_BYTES := 16*1024*1024

func from_v1(profile: Variant, legacy_checkpoint_present: Variant, career_id: Variant) -> Dictionary:
	# Variant arguments intentionally avoid Godot's typed-parameter coercions.
	if not profile is Dictionary: return _fail("invalid_profile")
	if not _counter(profile.get("schema_version")) or profile.schema_version != 1:
		return _fail("unsupported_schema")
	if not legacy_checkpoint_present is bool or not _career_valid(career_id):
		return _fail("invalid_game_save")
	var budget: Array[int] = [MAX_JSON_VALUES]
	if not _json_safe(profile,0,budget) or not _profile_valid(profile):
		return _fail("invalid_profile")
	if JSON.stringify(profile,"",true,true).to_utf8_buffer().size() > MAX_PROFILE_BYTES:
		return _fail("invalid_profile")
	var migrated: Dictionary = profile.duplicate(true)
	for key in DEFAULT_SETTINGS:
		if not migrated.settings.has(key): migrated.settings[key] = DEFAULT_SETTINGS[key]
	migrated.schema_version = 2
	migrated.supply_credits = 0
	migrated.owned_doctrine_ids = ["doctrine_standard"]
	migrated.consumables = {"field_bandage":0}
	migrated.loadout = {"doctrine_id":"doctrine_standard","target_evolution_id":"evo_wing_cut","supply_item_id":""}
	# This creates only a never-started v2 career. A legacy checkpoint presence
	# flag cannot supply a v2 run identity, settlement or a reusable serial.
	return {"ok":true,"game_save":{"schema_version":2,"career_id":career_id,"store_revision":0,"next_run_serial":1,"settled_through_serial":0,"profile":migrated,"checkpoint":null,"purchase_receipts":[],"settlement_receipts":[],"legacy_checkpoint_present":legacy_checkpoint_present}}

func _profile_valid(profile: Dictionary) -> bool:
	for field in ["settings","best_runs"]:
		if not profile.get(field) is Dictionary: return false
	for field in ["cleared_chapter_ids","unlocked_character_ids"]:
		if not _unique_ids(profile.get(field)): return false
	# These fields never existed in v1. Do not erase claimed existing economics
	# in a mislabeled profile by silently replacing them with a fresh balance.
	for field in ["supply_credits","owned_doctrine_ids","consumables","loadout","permanent_upgrades"]:
		if profile.has(field): return false
	var settings: Dictionary = profile.settings
	for key in ["deadzone","audio_master","screen_shake"]:
		if not settings.has(key): continue
		var number: Variant = settings[key]
		if not (number is int or number is float): return false
		if not is_finite(float(number)): return false
		if number < (0.10 if key == "deadzone" else 0.0): return false
		if number > (0.35 if key == "deadzone" else 1.0): return false
	if settings.has("reduce_effects") and not settings.reduce_effects is bool: return false
	for chapter_id in profile.best_runs:
		if not chapter_id is String or chapter_id.is_empty(): return false
		var record: Variant = profile.best_runs[chapter_id]
		if not record is Dictionary: return false
		for key in ["survival_tick","kills"]:
			if record.has(key) and not _counter(record[key]): return false
		if record.has("won") and not record.won is bool: return false
	return true

func _career_valid(value: Variant) -> bool:
	if not value is String: return false
	if value.length() != 32: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

func _unique_ids(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for id in value:
		if not id is String: return false
		if id.is_empty() or seen.has(id): return false
		seen[id] = true
	return true

func _counter(value: Variant) -> bool:
	if not (value is int or value is float): return false
	if not is_finite(float(value)): return false
	return value >= 0 and value <= MAX_COUNTER and value == floor(value)

func _json_safe(value: Variant, depth: int, budget: Array[int]) -> bool:
	if depth > MAX_DEPTH or budget[0] <= 0: return false
	budget[0] -= 1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			if value.size() > budget[0]: return false
			for child in value:
				if not _json_safe(child,depth+1,budget): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > budget[0]: return false
			for key in value:
				if not key is String or not _json_safe(value[key],depth+1,budget): return false
			return true
	return false

func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
