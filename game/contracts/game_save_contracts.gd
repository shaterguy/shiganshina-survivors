class_name GameSaveContracts
extends RefCounted
const Catalog = preload("res://game/economy/supply_catalog.gd")
const MAX_COUNTER := 2147483647
const CONTENT_REVISION := "ch01.3-rebuild.7-grabber-hand"
const TERMINAL := ["dead","won","abandoned"]
var _validator: Callable
var _catalog
func _init(checkpoint_validator: Callable, catalog_context: Variant = null) -> void:
	_validator = checkpoint_validator
	if catalog_context == null:
		_catalog = Catalog.new()
	else:
		_catalog = Catalog.new({}, {}, {}, {})
		_catalog._items = catalog_context.items.duplicate(true)
		_catalog._doctrines = catalog_context.doctrines.duplicate(true)
		_catalog._errors.assign(catalog_context.errors)
func validate_economy(value: Variant) -> Array[String]:
	if not value is Dictionary: return ["invalid_game_save"]
	var errors: Array[String] = []
	# Recognizable unknown schemas are compatibility barriers before deep parsing.
	if not version_number(value.get("schema_version")) or value.schema_version != 2: return ["unsupported_schema"]
	if value.get("profile") is Dictionary and version_number(value.profile.get("schema_version")) and value.profile.schema_version != 2: return ["unsupported_schema"]
	if not _json_safe(value): return ["invalid_game_save"]
	if not _career_valid(value.get("career_id")): return ["invalid_game_save"]
	for key in ["store_revision","next_run_serial","settled_through_serial"]:
		if not counter(value.get(key)): return ["invalid_game_save"]
	if value.next_run_serial < 1 or value.settled_through_serial >= value.next_run_serial: return ["invalid_game_save"]
	if not value.get("legacy_checkpoint_present") is bool or not value.has("checkpoint"): return ["invalid_game_save"]
	if not value.get("profile") is Dictionary or not _profile_valid(value.profile): return ["invalid_profile"]
	if not value.get("purchase_receipts") is Array or value.purchase_receipts.size() > 64 or not value.get("settlement_receipts") is Array or value.settlement_receipts.size() > 20: return ["invalid_game_save"]
	var seen := {}
	for receipt in value.purchase_receipts:
		if not _purchase_receipt_valid(receipt,value) or seen.has(receipt.get("request_id","")): return ["invalid_game_save"]
		seen[receipt.request_id] = true
	seen.clear()
	for receipt in value.settlement_receipts:
		if not _settlement_receipt_valid(receipt,value) or seen.has(receipt.get("run_serial",0)): return ["invalid_game_save"]
		seen[receipt.run_serial] = true
	if value.settled_through_serial > 0 and not seen.has(value.settled_through_serial): return ["invalid_game_save"]
	if value.get("checkpoint_recovery_receipt") != null and not _recovery_receipt_valid(value.checkpoint_recovery_receipt,value): return ["invalid_game_save"]
	return errors
func validate(value: Variant, scope = null, context: Dictionary = {}) -> Array[String]:
	return _validate(value,null,scope,context)
func _validate(value: Variant, normalized: Variant = null, scope = null, context: Dictionary = {}) -> Array[String]:
	if not _validator.is_valid(): return ["invalid_snapshot"]
	var errors := validate_economy(value)
	if not errors.is_empty(): return errors
	if value.checkpoint == null:
		if value.next_run_serial != 1 or value.settled_through_serial != 0: return ["invalid_game_save"]
		if normalized is Array: normalized.append(value.duplicate(true))
		return errors
	if not value.checkpoint is Dictionary: return ["invalid_snapshot"]
	var state: Dictionary = value.checkpoint
	if not version_number(state.get("schema_version")): return ["invalid_snapshot"]
	if state.schema_version != 2: return ["unsupported_schema"]
	if not state.get("content_revision") is String: return ["invalid_snapshot"]
	if state.content_revision != CONTENT_REVISION: return ["content_mismatch"]
	if not counter(state.get("seed")) or not state.get("chapter_id") is String or state.chapter_id.is_empty(): return ["invalid_snapshot"]
	if not counter(state.get("run_serial")) or state.run_serial < 1 or state.run_serial != value.next_run_serial-1 or not state.get("run_id") is String or state.run_id != "%s:%d" % [value.career_id,int(state.run_serial)]: return ["invalid_snapshot"]
	if not state.get("run_config") is Dictionary: return ["invalid_snapshot"]
	var config: Dictionary = state.run_config
	if config.size() != 5 or not config.get("run_id") is String or not counter(config.get("run_serial")): return ["invalid_snapshot"]
	if config.run_id != state.run_id or config.run_serial != state.run_serial or not _selection_valid(value.profile,{"doctrine_id":config.get("doctrine_id"),"target_evolution_id":config.get("target_evolution_id"),"supply_item_id":config.get("prepared_supply")}): return ["invalid_snapshot"]
	if not state.get("supply_used") is bool or (config.prepared_supply == "" and state.supply_used): return ["invalid_snapshot"]
	if not state.get("phase") is String or not state.phase in ["survival","evacuation","dead","won","abandoned"]: return ["invalid_snapshot"]
	if state.phase in TERMINAL:
		if state.run_serial != value.settled_through_serial: return ["invalid_game_save"]
	elif state.run_serial <= value.settled_through_serial: return ["invalid_game_save"]
	# Capture the entire checked value before invoking external validation. A
	# callback receives its own checkpoint and cannot poison this owned snapshot.
	var snapshot: Dictionary = value.duplicate(true) if normalized is Array else {}
	var restored: Variant
	if scope != null and scope.accepts_validator(_validator):
		restored = _validator.get_object().validate_checkpoint_scoped(state.duplicate(true),scope,context,value)
	else:
		restored = _validator.call(state.duplicate(true))
	if not restored is Dictionary or not restored.get("ok") is bool: return ["invalid_snapshot"]
	if not restored.ok:
		var code: String = restored.error_code if restored.get("error_code") is String and not restored.error_code.is_empty() else "invalid_snapshot"
		return [code]
	if not restored.get("state") is Dictionary: return ["invalid_snapshot"]
	if normalized is Array:
		snapshot.checkpoint = restored.state.duplicate(true)
		normalized.append(snapshot)
	return errors
func normalize(value: Variant, scope = null, context: Dictionary = {}) -> Dictionary:
	# Direct callers still perform the full contract. No receipt/cache can be
	# supplied by a caller, and no validation result survives this invocation.
	var checked := validate_and_normalize(value,scope,context)
	return checked.game_save if checked.ok else {}
func validate_and_normalize(value: Variant, scope = null, context: Dictionary = {}) -> Dictionary:
	var snapshots := []
	var errors := _validate(value,snapshots,scope,context)
	if not errors.is_empty(): return {"ok":false,"error_code":errors[0],"errors":errors}
	var result: Dictionary = snapshots[0]
	for key in ["schema_version","store_revision","next_run_serial","settled_through_serial"]: result[key] = int(result[key])
	result.profile.schema_version = 2
	result.profile.supply_credits = int(result.profile.supply_credits)
	result.profile.consumables.field_bandage = int(result.profile.consumables.field_bandage)
	for record in result.profile.best_runs.values():
		for key in ["survival_tick","kills"]:
			if record.has(key): record[key] = int(record[key])
	for receipt in result.purchase_receipts:
		for key in ["expected_revision","price","balance_after","owned_after"]: receipt[key] = int(receipt[key])
	for receipt in result.settlement_receipts:
		for key in ["run_serial","total","balance_after"]: receipt[key] = int(receipt[key])
		for key in receipt.breakdown: receipt.breakdown[key] = int(receipt.breakdown[key])
	if result.get("checkpoint_recovery_receipt") is Dictionary:
		for key in ["source_store_revision","preserved_run_serial","replacement_run_serial"]: result.checkpoint_recovery_receipt[key] = int(result.checkpoint_recovery_receipt[key])
	return {"ok":true,"game_save":result}
func _profile_valid(profile: Dictionary) -> bool:
	if not counter(profile.get("schema_version")) or profile.schema_version != 2 or not counter(profile.get("supply_credits")): return false
	for key in ["settings","best_runs","consumables","loadout"]:
		if not profile.get(key) is Dictionary: return false
	for key in ["cleared_chapter_ids","unlocked_character_ids","owned_doctrine_ids"]:
		if not _unique_strings(profile.get(key)): return false
	if not "doctrine_standard" in profile.owned_doctrine_ids: return false
	for id in profile.owned_doctrine_ids:
		if _catalog.doctrine(id).is_empty(): return false
	if profile.consumables.size() != 1 or not counter(profile.consumables.get("field_bandage")) or profile.consumables.field_bandage > 9: return false
	if not _selection_valid(profile,profile.loadout): return false
	for key in ["deadzone","audio_master","screen_shake"]:
		var number = profile.settings.get(key)
		if not (number is int or number is float) or not is_finite(float(number)): return false
		if number < (0.10 if key == "deadzone" else 0.0) or number > (0.35 if key == "deadzone" else 1.0): return false
	if not profile.settings.get("reduce_effects") is bool: return false
	for record in profile.best_runs.values():
		if not record is Dictionary: return false
		for key in ["survival_tick","kills"]:
			if record.has(key) and not counter(record[key]): return false
		if record.has("won") and not record.won is bool: return false
	return true
func _selection_valid(profile: Dictionary, selection: Dictionary) -> bool:
	if selection.size() != 3: return false
	for key in ["doctrine_id","target_evolution_id","supply_item_id"]:
		if not selection.get(key) is String: return false
	return selection.get("doctrine_id") in profile.owned_doctrine_ids and selection.get("target_evolution_id") in ["evo_wing_cut","evo_crossfire"] and selection.get("supply_item_id") in ["","field_bandage"]
func _purchase_receipt_valid(receipt: Variant, save: Dictionary) -> bool:
	if not receipt is Dictionary or not receipt.get("item_id") is String or not receipt.get("request_id") is String: return false
	var item: Dictionary = _catalog.item(receipt.item_id)
	if item.is_empty(): return false
	for key in ["expected_revision","price","balance_after","owned_after"]:
		if not counter(receipt.get(key)): return false
	return receipt.expected_revision <= save.store_revision and receipt.get("request_id") == "purchase:%s:%d:%s" % [save.career_id,int(receipt.expected_revision),receipt.item_id] and receipt.price == item.price and receipt.owned_after >= 1 and receipt.owned_after <= item.max_owned
func _settlement_receipt_valid(receipt: Variant, save: Dictionary) -> bool:
	if not receipt is Dictionary or not receipt.get("run_id") is String or not receipt.get("request_id") is String: return false
	for key in ["run_serial","total","balance_after"]:
		if not counter(receipt.get(key)): return false
	if receipt.run_serial < 1 or receipt.run_serial > save.settled_through_serial or receipt.get("run_id") != "%s:%d" % [save.career_id,int(receipt.run_serial)] or receipt.get("request_id") != "settle:"+str(receipt.run_id): return false
	if not receipt.get("breakdown") is Dictionary: return false
	var parts: Dictionary = receipt.breakdown
	for key in ["kills","survival","minibosses","clear"]:
		if not counter(parts.get(key)): return false
	return parts.size() == 4 and parts.kills <= 40 and parts.survival <= 40 and int(parts.survival)%10 == 0 and parts.minibosses <= 75 and int(parts.minibosses)%15 == 0 and (parts.clear == 0 or parts.clear == 30) and receipt.total == parts.kills+parts.survival+parts.minibosses+parts.clear
func _career_valid(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
func _unique_strings(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for item in value:
		if not item is String or item.is_empty() or seen.has(item): return false
		seen[item] = true
	return true
func version_number(value: Variant) -> bool:
	# A recognizable future version is not an economy counter. Never cap it at MAX_COUNTER.
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(value)
func counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= MAX_COUNTER and value == floor(value)
# Shared total-node/depth/UTF-8 bounds for public authority and Service DTO checks.
const MAX_JSON_VALUES := 262144
const MAX_JSON_BYTES := 16*1024*1024
func _json_safe(value: Variant, depth: int = 0) -> bool:
	var budget: Array[int] = [MAX_JSON_VALUES,MAX_JSON_BYTES]
	if not _json_bounded(value,depth,budget): return false
	return JSON.stringify(value,"",true,true).to_utf8_buffer().size() <= MAX_JSON_BYTES
func _json_bounded(value: Variant, depth: int, budget: Array[int]) -> bool:
	if depth > 64 or budget[0] <= 0: return false
	budget[0] -= 1
	if value == null or value is bool or value is int: return true
	if value is float: return is_finite(value)
	if value is String:
		if value.length() > budget[1]: return false
		budget[1] -= value.to_utf8_buffer().size()
		return budget[1] >= 0
	if value is Array:
		if value.size() > budget[0]: return false
		for child in value:
			if not _json_bounded(child,depth+1,budget): return false
		return true
	if value is Dictionary:
		if value.size() > budget[0]: return false
		for key in value:
			if not (key is String or key is StringName): return false
			var text_key := str(key)
			if text_key.length() > budget[1]: return false
			budget[1] -= text_key.to_utf8_buffer().size()
			if budget[1] < 0 or not _json_bounded(value[key],depth+1,budget): return false
		return true
	return false

func validate_recovery_source(value: Variant) -> Array[String]:
	# Independent economic/run identity only. Never treat this as a playable checkpoint.
	var errors := validate_economy(value)
	if not errors.is_empty(): return errors
	if not value.checkpoint is Dictionary: return ["invalid_snapshot"]
	var state: Dictionary = value.checkpoint
	if not counter(state.get("schema_version")) or state.schema_version != 2: return ["unsupported_schema"]
	for key in ["run_id","content_revision","chapter_id","phase"]:
		if not state.get(key) is String or state[key].is_empty(): return ["invalid_snapshot"]
	if not counter(state.get("run_serial")) or state.run_serial < 1 or state.run_serial != value.next_run_serial-1 or state.run_id != "%s:%d" % [value.career_id,int(state.run_serial)]: return ["invalid_snapshot"]
	if not counter(state.get("seed")) or not state.get("supply_used") is bool: return ["invalid_snapshot"]
	if not state.get("run_config") is Dictionary: return ["invalid_snapshot"]
	var config: Dictionary = state.run_config
	if config.size() != 5 or not config.get("run_id") is String or not counter(config.get("run_serial")) or config.run_id != state.run_id or config.run_serial != state.run_serial: return ["invalid_snapshot"]
	if not _selection_valid(value.profile,{"doctrine_id":config.get("doctrine_id"),"target_evolution_id":config.get("target_evolution_id"),"supply_item_id":config.get("prepared_supply")}): return ["invalid_snapshot"]
	if config.prepared_supply == "" and state.supply_used: return ["invalid_snapshot"]
	if not state.phase in ["survival","evacuation","dead","won","abandoned"]: return ["invalid_snapshot"]
	if (state.phase in TERMINAL and state.run_serial != value.settled_through_serial) or (not state.phase in TERMINAL and state.run_serial <= value.settled_through_serial): return ["invalid_game_save"]
	return []
func hash_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
func _recovery_receipt_valid(receipt: Variant, save: Dictionary) -> bool:
	if not receipt is Dictionary or receipt.size() != 6: return false
	if not receipt.get("request_id") is String or not hash_valid(receipt.get("source_sha256")) or not hash_valid(receipt.get("payload_sha256")): return false
	for key in ["source_store_revision","preserved_run_serial","replacement_run_serial"]:
		if not counter(receipt.get(key)): return false
	if receipt.source_store_revision > save.store_revision or receipt.preserved_run_serial < 1 or receipt.replacement_run_serial != receipt.preserved_run_serial+1 or receipt.replacement_run_serial >= save.next_run_serial: return false
	return receipt.request_id == "recover:%s:%s:%d" % [save.career_id,receipt.source_sha256,int(receipt.replacement_run_serial)]
