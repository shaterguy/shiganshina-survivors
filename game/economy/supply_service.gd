class_name SupplyService
extends RefCounted
const Characters = preload("res://game/progression/character_catalog.gd")
var _characters = Characters.new()
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Catalog = preload("res://game/economy/supply_catalog.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
const MAX_COUNTER := 2147483647
# NEW E1 changes are recorded separately from the preserved transcript body.
const CONTENT_REVISION := "ch01.3-rebuild.7-grabber-hand"
const TERMINAL := ["dead", "won", "abandoned"]
var _catalog = Catalog.new()
var _upgrades = Upgrades.new()
var _contracts = Contracts.new(Callable())
var _run_factory: Callable
var _content_resolver: Callable
func _init(run_factory: Callable) -> void:
	_run_factory = run_factory
	var owner = run_factory.get_object()
	if owner != null and owner.get_script() == load("res://game/app/prepared_city_runtime.gd") and owner._content_router != null:
		_content_resolver = Callable(owner,"resolve_content")
func shop_view(game_save: Variant, chapter_id: String = Characters.DEFAULT_CHAPTER) -> Dictionary:
	var validation := _validate_economy(game_save)
	var error: String = str(validation.get("error_code","invalid_game_save"))
	if validation.get("ok") != true: return {"view_revision":1,"store_revision":int(game_save.get("store_revision",0)) if game_save is Dictionary and _counter(game_save.get("store_revision")) else 0,"balance":0,"items":[],"loadout":{},"can_shop":false,"lock_reason":error,"legacy_checkpoint_present":game_save.get("legacy_checkpoint_present",false) == true if game_save is Dictionary and game_save.get("legacy_checkpoint_present") is bool else false,"loadout_options":{"doctrines":[],"targets":[],"supplies":[]},"can_start":false,"start_blocked_reason":error}
	var profile: Dictionary = game_save.profile
	var active := _has_unsettled_run(game_save)
	var items: Array[Dictionary] = []
	for id in _catalog.item_ids():
		var definition: Dictionary = _catalog.item(id)
		var owned := _owned(profile, definition)
		var blocked := _purchase_blocked(game_save, definition)
		var price := _catalog.purchase_price(definition,owned)
		var row := {"item_id":id,"kind":definition.kind,"price":price,"owned":owned,"max_owned":int(definition.max_owned),"can_purchase":blocked.is_empty(),"blocked_reason":blocked,"balance_after":int(profile.supply_credits) - price if blocked.is_empty() else int(profile.supply_credits)}
		for key in ["name","description","tradeoff_text"]: row[key] = definition[key]
		if definition.kind == "doctrine":
			var doctrine: Dictionary = _catalog.doctrine(str(definition.effect_params.doctrine_id))
			row.description = doctrine.description
		if definition.kind == "permanent_upgrade":
			row.merge({"level":owned,"max_level":int(definition.max_owned),"is_max":owned >= definition.max_owned,"current_effect_text":_catalog.permanent_effect_text(definition,owned),"next_effect_text":_catalog.permanent_effect_text(definition,owned+1) if owned < definition.max_owned else "최고 단계","next_price":price if owned < definition.max_owned else null})
		items.append(row)
	return {"view_revision":1,"store_revision":int(game_save.store_revision),"balance":int(profile.supply_credits),"items":items,"loadout":profile.loadout.duplicate(true),"can_shop":not active,"lock_reason":"active_run" if active else "","legacy_checkpoint_present":game_save.legacy_checkpoint_present,"loadout_options":_loadout_options(profile,active),"selected_character_id":_characters.run_character_id(profile,chapter_id),"character_options":_characters.selection_rows(profile,chapter_id,active),"can_start":_start_blocked(game_save).is_empty(),"start_blocked_reason":_start_blocked(game_save)}
func prepare_purchase(game_save: Variant, item_id: Variant, request_id: Variant, expected_revision: Variant) -> Dictionary:
	if not item_id is String: return _fail("invalid_item")
	if not request_id is String: return _fail("request_conflict")
	if not _counter(expected_revision): return _fail("stale_revision")
	expected_revision = int(expected_revision)
	var validation := _validate_economy(game_save)
	if validation.get("ok") != true: return _fail(str(validation.get("error_code","invalid_game_save")))
	for receipt in game_save.purchase_receipts:
		if receipt.get("request_id") == request_id:
			if receipt.get("item_id") != item_id or receipt.get("expected_revision") != expected_revision: return _fail("request_conflict")
			return {"ok":true,"already_applied":true,"receipt":receipt.duplicate(true)}
	if expected_revision != game_save.store_revision: return _fail("stale_revision")
	if request_id != "purchase:%s:%d:%s" % [game_save.career_id,expected_revision,item_id]: return _fail("request_conflict")
	var definition: Dictionary = _catalog.item(item_id)
	if definition.is_empty(): return _fail("invalid_item")
	var error := _purchase_blocked(game_save,definition)
	if not error.is_empty(): return _fail(error)
	var candidate: Dictionary = game_save.duplicate(true)
	var price := _catalog.purchase_price(definition,_owned(game_save.profile,definition))
	candidate.profile.supply_credits = int(candidate.profile.supply_credits) - price
	if definition.kind == "doctrine": candidate.profile.owned_doctrine_ids.append(item_id)
	elif definition.kind == "permanent_upgrade":
		candidate.profile.permanent_upgrades = _catalog.permanent_levels(candidate.profile)
		candidate.profile.permanent_upgrades[item_id] = _owned(game_save.profile,definition)+1
	else: candidate.profile.consumables[item_id] = int(candidate.profile.consumables[item_id]) + 1
	var receipt := {"request_id":request_id,"item_id":item_id,"expected_revision":expected_revision,"price":price,"balance_after":int(candidate.profile.supply_credits),"owned_after":_owned(candidate.profile,definition)}
	candidate.purchase_receipts.append(receipt.duplicate(true))
	while candidate.purchase_receipts.size() > 64: candidate.purchase_receipts.pop_front()
	return {"ok":true,"candidate":candidate,"receipt":receipt,"already_applied":false}
func _purchase_blocked(save: Dictionary, definition: Dictionary) -> String:
	if _has_unsettled_run(save): return "active_run"
	if save.store_revision >= MAX_COUNTER: return "counter_exhausted"
	if _owned(save.profile,definition) >= definition.max_owned: return "max_level" if definition.kind == "permanent_upgrade" else ("already_owned" if definition.kind == "doctrine" else "inventory_full")
	if save.profile.supply_credits < _catalog.purchase_price(definition,_owned(save.profile,definition)): return "insufficient_funds"
	return ""
func _owned(profile: Dictionary, definition: Dictionary) -> int:
	if definition.kind == "doctrine": return int(definition.item_id in profile.owned_doctrine_ids)
	if definition.kind == "permanent_upgrade": return int(profile.get("permanent_upgrades",{}).get(definition.item_id,0))
	return int(profile.consumables.get(definition.item_id,0))
func _has_unsettled_run(save: Dictionary) -> bool:
	if save.checkpoint == null: return false
	return not save.checkpoint.get("phase") in TERMINAL or save.checkpoint.get("run_serial",MAX_COUNTER) > save.settled_through_serial
func _validate_economy(save: Variant) -> Dictionary:
	if not save is Dictionary: return _fail("invalid_game_save")
	# A positive success envelope is required. A Godot early-abort default {} is failure.
	if not _counter(save.get("schema_version")): return _fail("unsupported_schema")
	if save.get("profile") is Dictionary and not _contracts.version_number(save.profile.get("schema_version")): return _fail("invalid_profile")
	var errors: Array[String] = _contracts.validate_economy(save)
	if not errors.is_empty(): return _fail(errors[0])
	if not _catalog.validate().is_empty() or not _upgrades.validate().is_empty(): return _fail("invalid_item")
	if save.checkpoint == null:
		return {"ok":true} if save.next_run_serial == 1 and save.settled_through_serial == 0 else _fail("invalid_game_save")
	if not save.checkpoint is Dictionary: return _fail("invalid_game_save")
	var state: Dictionary = save.checkpoint
	if not state.get("content_revision") is String or state.content_revision != CONTENT_REVISION: return _fail("content_mismatch")
	if not _run_envelope_valid(state): return _fail("invalid_snapshot")
	if state.character_id != _characters.protagonist_id(state.chapter_id) and not _characters.selection_error(save.profile,state.chapter_id,state.character_id).is_empty(): return _fail("invalid_snapshot")
	if state.run_serial != save.next_run_serial-1 or state.run_id != "%s:%d" % [save.career_id,int(state.run_serial)]: return _fail("invalid_snapshot")
	var config: Dictionary = state.run_config
	var selection := {"doctrine_id":config.doctrine_id,"target_evolution_id":config.target_evolution_id,"supply_item_id":config.prepared_supply}
	if not _selection_valid(save.profile,selection): return _fail("invalid_snapshot")
	if _content_resolver.is_valid():
		var route: Dictionary = _content_resolver.call(state)
		if not route.get("ok",false): return _fail(str(route.get("error_code","content_mismatch")))
		var definitions: Dictionary = route.immutable_inputs
		var selected := Upgrades.new(definitions["data/equipment.json"],definitions["data/passives.json"],definitions["data/evolutions.json"])
		if selected.evolutions.definition(config.target_evolution_id).is_empty(): return _fail("invalid_snapshot")
	if state.phase in TERMINAL:
		if state.run_serial != save.settled_through_serial: return _fail("invalid_game_save")
	elif state.run_serial <= save.settled_through_serial: return _fail("invalid_game_save")
	return {"ok":true}
func _run_envelope_valid(state: Dictionary) -> bool:
	# Economic identity/type checks only; this is not real Core or escape validation.
	if not _contracts._json_safe(state): return false
	if not _counter(state.get("schema_version")) or state.schema_version != 2: return false
	for key in ["run_id","chapter_id","content_revision","phase"]:
		if not state.get(key) is String or state[key].is_empty(): return false
	if not _counter(state.get("run_serial")) or state.run_serial < 1 or not _counter(state.get("seed")): return false
	if not state.phase in ["survival","evacuation","dead","won","abandoned"] or not state.get("supply_used") is bool or not state.get("evacuation_ready") is bool: return false
	if not state.get("rules") is Dictionary or not state.rules.get("content_fingerprint") is String or state.rules.content_fingerprint.is_empty(): return false
	if not state.get("run_config") is Dictionary: return false
	var config: Dictionary = state.run_config
	if not _catalog.run_upgrade_config_valid(config) or not _counter(config.get("run_serial")): return false
	if not Loot.validate(state): return false
	for key in ["run_id","doctrine_id","target_evolution_id","prepared_supply"]:
		if not config.get(key) is String: return false
	if config.run_id != state.run_id or config.run_serial != state.run_serial: return false
	if state.get("character_id") != config.get("character_id",Characters.DEFAULT_CHARACTER): return false
	if config.doctrine_id.is_empty() or config.target_evolution_id.is_empty() or not config.prepared_supply in ["","field_bandage"]: return false
	return not (config.prepared_supply == "" and state.supply_used)
func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= MAX_COUNTER and value == floor(value)
func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
func prepare_loadout(game_save: Variant, selection: Variant, expected_revision: Variant) -> Dictionary:
	if not selection is Dictionary: return _fail("invalid_loadout")
	if not _counter(expected_revision): return _fail("stale_revision")
	expected_revision = int(expected_revision)
	var validation := _validate_economy(game_save)
	if validation.get("ok") != true: return _fail(str(validation.get("error_code","invalid_game_save")))
	if expected_revision != game_save.store_revision: return _fail("stale_revision")
	if game_save.store_revision >= MAX_COUNTER: return _fail("counter_exhausted")
	if _has_unsettled_run(game_save): return _fail("active_run")
	if not _loadout_valid(game_save.profile,selection): return _fail("invalid_loadout")
	var candidate: Dictionary = game_save.duplicate(true)
	candidate.profile.loadout = selection.duplicate(true)
	return {"ok":true,"candidate":candidate}
func prepare_character_selection(game_save: Variant, chapter_id: Variant, character_id: Variant, expected_revision: Variant) -> Dictionary:
	if not chapter_id is String or not character_id is String: return _fail("invalid_character")
	if not _counter(expected_revision): return _fail("stale_revision")
	var validation := _validate_economy(game_save)
	if validation.get("ok") != true: return _fail(str(validation.get("error_code","invalid_game_save")))
	if expected_revision != game_save.store_revision: return _fail("stale_revision")
	if game_save.store_revision >= MAX_COUNTER: return _fail("counter_exhausted")
	if _has_unsettled_run(game_save): return _fail("active_run")
	var error := _characters.selection_error(game_save.profile,chapter_id,character_id)
	if not error.is_empty(): return _fail(error)
	var candidate: Dictionary = game_save.duplicate(true)
	candidate.profile.selected_character_id = character_id
	return {"ok":true,"candidate":candidate}
func prepare_run_start(game_save: Variant, chapter: Variant, seed: Variant, request_id: Variant, expected_revision: Variant) -> Dictionary:
	if not chapter is Dictionary: return _fail("invalid_chapter")
	if not request_id is String: return _fail("request_conflict")
	if not _counter(expected_revision): return _fail("stale_revision")
	if not _counter(seed): return _fail("invalid_run_config")
	expected_revision = int(expected_revision)
	seed = int(seed)
	var validation := _validate_economy(game_save)
	if validation.get("ok") != true: return _fail(str(validation.get("error_code","invalid_game_save")))
	if not _chapter_shape_valid(chapter): return _fail("invalid_chapter")
	var prior = game_save.checkpoint
	if prior is Dictionary and request_id == "start:%s:%d" % [game_save.career_id,int(prior.get("run_serial",0))]:
		if prior.get("seed") != seed or prior.get("chapter_id") != chapter.get("chapter_id") or prior.get("content_revision") != chapter.get("content_revision"): return _fail("request_conflict")
		return {"ok":true,"already_applied":true,"receipt":_start_receipt(prior,request_id)}
	if expected_revision != game_save.store_revision: return _fail("stale_revision")
	var prefix := "start:%s:" % game_save.career_id
	if request_id.begins_with(prefix) and request_id.trim_prefix(prefix).is_valid_int() and int(request_id.trim_prefix(prefix)) < int(game_save.next_run_serial): return _fail("stale_revision")
	if request_id != prefix+str(int(game_save.next_run_serial)): return _fail("request_conflict")
	if _has_unsettled_run(game_save): return _fail("active_run")
	if game_save.next_run_serial == MAX_COUNTER or game_save.store_revision == MAX_COUNTER: return _fail("counter_exhausted")
	var selection: Dictionary = game_save.profile.loadout
	if not _loadout_valid(game_save.profile,selection): return _fail("invalid_loadout")
	if not _run_factory.is_valid(): return _fail("invalid_run_config")
	if chapter.get("content_revision") != CONTENT_REVISION: return _fail("content_mismatch")
	if chapter.has("doctrine_ids") and not selection.doctrine_id in chapter.doctrine_ids: return _fail("invalid_loadout")
	if chapter.has("evolution_ids") and not selection.target_evolution_id in chapter.evolution_ids: return _fail("invalid_loadout")
	var serial := int(game_save.next_run_serial)
	return _prepare_start_candidate(game_save,chapter,seed,selection,serial,request_id)
func _prepare_start_candidate(game_save: Dictionary, chapter: Dictionary, seed: int, selection: Dictionary, serial: int, request_id: String) -> Dictionary:
	var config := {"run_id":"%s:%d" % [game_save.career_id,serial],"run_serial":serial,"doctrine_id":selection.doctrine_id,"target_evolution_id":selection.target_evolution_id,"prepared_supply":selection.supply_item_id,"loot_rules_version":Loot.VERSION}
	var character_id := _characters.run_character_id(game_save.profile,chapter.chapter_id)
	if character_id.is_empty(): return _fail("invalid_character")
	if character_id != Characters.DEFAULT_CHARACTER: config.character_id = character_id
	if character_id == "mikasa_01": config.character_skill_revision = 1
	var levels := _catalog.permanent_levels(game_save.profile)
	if not levels.is_empty(): config.permanent_upgrades = levels
	var state = _run_factory.call(chapter.duplicate(true),seed,config.duplicate(true))
	if not state is Dictionary: return _fail("invalid_snapshot")
	if state.has("ok"):
		if not state.get("ok") is bool or state.ok != false or not state.get("error_code") is String or state.error_code.is_empty() or not _contracts._json_safe(state): return _fail("invalid_snapshot")
		var failure := _fail(state.error_code)
		if state.get("diagnostics") is Dictionary: failure.diagnostics = state.diagnostics.duplicate(true)
		return failure
	if not _run_envelope_valid(state): return _fail("invalid_snapshot")
	if state.get("schema_version") != 2 or state.get("run_id") != config.run_id or state.get("run_serial") != serial or state.get("seed") != seed or state.get("content_revision") != chapter.content_revision or state.get("chapter_id") != chapter.get("chapter_id") or state.get("run_config") != config or state.get("supply_used") != false: return _fail("invalid_snapshot")
	var candidate: Dictionary = game_save.duplicate(true)
	if selection.supply_item_id != "": candidate.profile.consumables[selection.supply_item_id] = int(candidate.profile.consumables[selection.supply_item_id])-1
	candidate.next_run_serial = serial+1
	candidate.checkpoint = state.duplicate(true)
	return {"ok":true,"candidate":candidate,"receipt":_start_receipt(state,request_id),"already_applied":false}
func _chapter_shape_valid(chapter: Dictionary) -> bool:
	if not _contracts._json_safe(chapter): return false
	for key in ["chapter_id","content_revision"]:
		if not chapter.get(key) is String or chapter[key].is_empty(): return false
	for key in ["doctrine_ids","evolution_ids"]:
		if not chapter.has(key): continue
		if not chapter[key] is Array: return false
		var seen := {}
		for id in chapter[key]:
			if not id is String or id.is_empty() or seen.has(id): return false
			seen[id] = true
	return true
func prepare_settlement(game_save: Variant, terminal_state: Variant) -> Dictionary:
	if not terminal_state is Dictionary: return _fail("invalid_snapshot")
	var validation := _validate_economy(game_save)
	if validation.get("ok") != true: return _fail(str(validation.get("error_code","invalid_game_save")))
	if not _run_envelope_valid(terminal_state): return _fail("invalid_snapshot")
	var serial = terminal_state.get("run_serial")
	if not _counter(serial) or serial < 1 or terminal_state.get("run_id") != "%s:%d" % [game_save.career_id,int(serial)]: return _fail("invalid_snapshot")
	var request_id := "settle:"+str(terminal_state.run_id)
	if serial <= game_save.settled_through_serial:
		for receipt in game_save.settlement_receipts:
			if receipt.get("request_id") == request_id: return {"ok":true,"already_applied":true,"receipt":receipt.duplicate(true)}
		return {"ok":true,"already_applied":true,"receipt":{"request_id":request_id,"run_id":terminal_state.run_id,"run_serial":int(serial),"details_unavailable":true}}
	if game_save.store_revision == MAX_COUNTER: return _fail("counter_exhausted")
	if not game_save.checkpoint is Dictionary or game_save.checkpoint.get("run_id") != terminal_state.run_id or serial != game_save.next_run_serial-1: return _fail("invalid_snapshot")
	if terminal_state.get("schema_version") != 2 or not terminal_state.get("phase") in TERMINAL or not terminal_state.get("stats") is Dictionary or not terminal_state.get("chapter_id") is String: return _fail("invalid_snapshot")
	for key in ["kills","minibosses_defeated"]:
		if not _counter(terminal_state.stats.get(key)): return _fail("invalid_snapshot")
	if not _counter(terminal_state.get("survival_tick")) or not _counter(terminal_state.get("active_tick")) or terminal_state.survival_tick > terminal_state.active_tick or terminal_state.stats.minibosses_defeated > 5: return _fail("invalid_snapshot")
	for key in ["run_config","seed","chapter_id","content_revision","character_id"]:
		if not _same(terminal_state.get(key),game_save.checkpoint.get(key)): return _fail("invalid_snapshot")
	if not terminal_state.get("rules") is Dictionary or not game_save.checkpoint.get("rules") is Dictionary: return _fail("invalid_snapshot")
	if not terminal_state.rules.get("content_fingerprint") is String or terminal_state.rules.content_fingerprint.is_empty() or terminal_state.rules.content_fingerprint != game_save.checkpoint.rules.get("content_fingerprint"): return _fail("invalid_snapshot")
	if not _settlement_evidence_valid(terminal_state): return _fail("invalid_snapshot")
	var breakdown := settlement_breakdown(terminal_state)
	var total := int(breakdown.kills + breakdown.survival + breakdown.minibosses + breakdown.clear) + int(breakdown.get("loot",0))
	if game_save.profile.supply_credits > MAX_COUNTER-total: return _fail("counter_exhausted")
	var candidate: Dictionary = game_save.duplicate(true)
	candidate.profile.supply_credits = int(candidate.profile.supply_credits)+total
	candidate.settled_through_serial = int(serial)
	candidate.checkpoint = terminal_state.duplicate(true)
	_record_result(candidate.profile,terminal_state)
	var receipt := {"request_id":request_id,"run_id":terminal_state.run_id,"run_serial":int(serial),"breakdown":breakdown,"total":total,"balance_after":int(candidate.profile.supply_credits)}
	if Loot.enabled(terminal_state): receipt.loot_rules_version = int(terminal_state.run_config.loot_rules_version)
	candidate.settlement_receipts.append(receipt.duplicate(true))
	while candidate.settlement_receipts.size() > 20: candidate.settlement_receipts.pop_front()
	return {"ok":true,"candidate":candidate,"receipt":receipt,"already_applied":false}
func settlement_breakdown(state: Dictionary) -> Dictionary:
	var survival := 0
	for milestone in [10800,18000,36000,72000]:
		if int(state.survival_tick) >= milestone: survival += 10
	var breakdown := {"kills":mini(int(state.stats.kills)/10,40),"survival":survival,"minibosses":mini(int(state.stats.minibosses_defeated),5)*15,"clear":30 if state.phase == "won" else 0}
	if Loot.enabled(state): breakdown.loot = int(state.loot.gold)
	return breakdown
func _record_result(profile: Dictionary, state: Dictionary) -> void:
	if state.phase == "won":
		for id in _characters.unlocks_for_clear(profile,state.chapter_id): profile.unlocked_character_ids.append(id)
	if state.phase == "won" and not state.chapter_id in profile.cleared_chapter_ids: profile.cleared_chapter_ids.append(state.chapter_id)
	var old: Dictionary = profile.best_runs.get(state.chapter_id,{})
	if (state.phase == "won" and not old.get("won",false)) or int(state.survival_tick) >= int(old.get("survival_tick",-1)):
		profile.best_runs[state.chapter_id] = {"survival_tick":int(state.survival_tick),"kills":int(state.stats.kills),"won":state.phase == "won" or old.get("won",false)}
func _selection_valid(profile: Dictionary, selection: Dictionary) -> bool:
	if not _contracts._json_safe(selection) or selection.size() != 3 or not selection.get("supply_item_id") is String or not selection.get("doctrine_id") is String or not selection.doctrine_id in profile.owned_doctrine_ids: return false
	if not selection.get("target_evolution_id") is String or _upgrades.evolutions.definition(selection.target_evolution_id).is_empty(): return false
	return selection.get("supply_item_id") in ["","field_bandage"]
func _loadout_valid(profile: Dictionary, selection: Dictionary) -> bool:
	return _selection_valid(profile,selection) and (selection.supply_item_id == "" or profile.consumables.field_bandage > 0)
func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true)) == JSON.parse_string(JSON.stringify(b,"",true,true))
func _start_receipt(state: Dictionary, request_id: String) -> Dictionary:
	return {"request_id":request_id,"run_id":state.run_id,"run_serial":int(state.run_serial),"seed":state.seed,"chapter_id":state.chapter_id,"content_revision":state.content_revision,"run_config":state.run_config.duplicate(true)}

func _start_blocked(save: Dictionary) -> String:
	if _has_unsettled_run(save): return "active_run"
	if save.next_run_serial >= MAX_COUNTER or save.store_revision >= MAX_COUNTER: return "counter_exhausted"
	if not _loadout_valid(save.profile,save.profile.loadout): return "invalid_loadout"
	return ""
func _loadout_options(profile: Dictionary, active: bool) -> Dictionary:
	var doctrines: Array[Dictionary] = []
	for id in ["doctrine_standard","doctrine_mobile","doctrine_artillery"]:
		var definition: Dictionary = _catalog.doctrine(id)
		var blocked := "active_run" if active else ("" if id in profile.owned_doctrine_ids else "not_owned")
		doctrines.append({"id":id,"name":definition.name,"description":definition.description,"tradeoff_text":definition.tradeoff_text,"can_select":blocked.is_empty(),"blocked_reason":blocked})
	var targets: Array[Dictionary] = []
	for id in _upgrades.evolutions.ids():
		var definition: Dictionary = _upgrades.evolutions.definition(id)
		var requirements: Array[Dictionary] = [{"kind":"equipment","item_id":definition.base_item_id,"name":_upgrades.equipment[definition.base_item_id].name,"required":int(definition.required_weapon_level),"requirement_type":"base_level","icon_id":"skill_"+str(definition.base_item_id)}]
		for passive in definition.required_passives:
			requirements.append({"kind":"passive","item_id":passive.passive_id,"name":_upgrades.passives[passive.passive_id].name,"required":int(passive.level),"requirement_type":"owned_skill" if int(passive.level) == 1 else "level","icon_id":"skill_"+str(passive.passive_id)})
		for required in definition.get("required_equipment",[]):
			requirements.append({"kind":"equipment","item_id":required.equipment_id,"name":_upgrades.equipment[required.equipment_id].name,"required":int(required.level),"requirement_type":"owned_skill" if int(required.level) == 1 else "level","icon_id":"skill_"+str(required.equipment_id)})
		targets.append({"id":id,"name":definition.name,"icon_id":"skill_"+str(id),"description":definition.description,"tradeoff_text":definition.tradeoff_text,"requirements":requirements,"seal_cost":int(definition.seal_cost),"can_select":not active,"blocked_reason":"active_run" if active else ""})
	var supplies: Array[Dictionary] = [{"id":"","name":"장착 안 함","description":"보급품을 소비하지 않음","tradeoff_text":"","can_select":not active,"blocked_reason":"active_run" if active else "","owned":0}]
	var bandage: Dictionary = _catalog.item("field_bandage")
	var owned := int(profile.consumables.field_bandage)
	var blocked := "active_run" if active else ("" if owned > 0 else "not_owned")
	supplies.append({"id":"field_bandage","name":bandage.name,"description":bandage.description,"tradeoff_text":bandage.tradeoff_text,"can_select":blocked.is_empty(),"blocked_reason":blocked,"owned":owned})
	return {"doctrines":doctrines,"targets":targets,"supplies":supplies}

func _settlement_evidence_valid(state: Dictionary) -> bool:
	if not Loot.validate(state): return false
	if not state.get("reward_ids_claimed") is Array or not _counter(state.get("offer_seq")): return false
	var bosses := {}
	var seen := {}
	var offer_prefix: String = "offer:"+state.run_id+":offer:"
	for id in state.reward_ids_claimed:
		if not id is String or seen.has(id): return false
		seen[id] = true
		if id in ["boss:ch01_b05","boss:ch01_b10","boss:ch01_b15","boss:ch01_b20","boss:ch01_b25"]:
			bosses[id] = true
		elif id.begins_with(offer_prefix):
			# Growth-choice receipts prevent replay; they never earn supply credits.
			var serial: String = id.trim_prefix(offer_prefix)
			if serial.length() > 10 or not serial.is_valid_int() or str(serial.to_int()) != serial or serial.to_int() < 1 or serial.to_int() > state.offer_seq: return false
		else: return false
	if bosses.size() != int(state.stats.minibosses_defeated): return false
	if not _counter(state.get("tactical_seals")) or not state.get("evolutions") is Dictionary: return false
	# Settlement follows the checkpoint's immutable recipe costs, just as Core
	# does. Current evolutions cost zero; preserved schema1 recipes still cost one.
	var selected = _upgrades
	if _content_resolver.is_valid():
		var route: Dictionary = _content_resolver.call(state)
		if not route.get("ok",false): return false
		var definitions: Dictionary = route.immutable_inputs
		selected = Upgrades.new(definitions["data/equipment.json"],definitions["data/passives.json"],definitions["data/evolutions.json"])
	if not selected.validate().is_empty(): return false
	var spent: int = selected.evolutions.spent_seals(state)
	if spent < 0 or state.tactical_seals+spent != bosses.size(): return false
	if state.phase == "won":
		if state.get("evacuation_ready") != true or not _counter(state.get("final_started_tick")) or state.survival_tick < 108000: return false
		if not state.get("rules") is Dictionary or not _counter(state.rules.get("evacuation_ticks")) or state.rules.evacuation_ticks != 4500: return false
		if state.active_tick-state.final_started_tick < state.rules.evacuation_ticks: return false
	return true

func prepare_preserved_run_start(source: Variant, chapter: Variant, seed: Variant, selection: Variant, request_id: Variant, archive_receipt: Variant, expected_revision: Variant) -> Dictionary:
	if not source is Dictionary: return _fail("invalid_game_save")
	if not chapter is Dictionary or not _chapter_shape_valid(chapter): return _fail("invalid_chapter")
	if not _counter(seed): return _fail("invalid_run_config")
	if not selection is Dictionary: return _fail("invalid_loadout")
	if not request_id is String: return _fail("request_conflict")
	if not _counter(expected_revision): return _fail("stale_revision")
	if not _archive_receipt_valid(archive_receipt): return _fail("invalid_game_save")
	var errors: Array[String] = _contracts.validate_economy(source)
	if not errors.is_empty(): return _fail(errors[0])
	if not _selection_valid(source.profile,selection): return _fail("invalid_loadout")
	var previous = source.get("checkpoint_recovery_receipt")
	if previous is Dictionary and previous.request_id == request_id:
		if previous.source_sha256 != archive_receipt.source_sha256 or previous.source_store_revision != expected_revision or previous.payload_sha256 != _recovery_payload_hash(source.career_id,archive_receipt.source_sha256,int(expected_revision),int(previous.replacement_run_serial),chapter,int(seed),selection): return _fail("request_conflict")
		return {"ok":true,"already_applied":true,"receipt":previous.duplicate(true)}
	errors = _contracts.validate_recovery_source(source)
	if not errors.is_empty(): return _fail(errors[0])
	if source.store_revision != expected_revision or archive_receipt.source_store_revision != expected_revision or archive_receipt.preserved_run_serial != source.checkpoint.run_serial: return _fail("stale_revision")
	var serial := int(source.next_run_serial)
	if request_id != "recover:%s:%s:%d" % [source.career_id,archive_receipt.source_sha256,serial]: return _fail("request_conflict")
	if serial >= MAX_COUNTER or expected_revision >= MAX_COUNTER: return _fail("counter_exhausted")
	if not _loadout_valid(source.profile,selection): return _fail("invalid_loadout")
	if chapter.content_revision != CONTENT_REVISION: return _fail("content_mismatch")
	if chapter.has("doctrine_ids") and not selection.doctrine_id in chapter.doctrine_ids: return _fail("invalid_loadout")
	if chapter.has("evolution_ids") and not selection.target_evolution_id in chapter.evolution_ids: return _fail("invalid_loadout")
	if not _run_factory.is_valid(): return _fail("invalid_run_config")
	var prepared := _prepare_start_candidate(source,chapter,int(seed),selection,serial,request_id)
	if prepared.get("ok") != true: return prepared
	prepared.candidate.profile.loadout = selection.duplicate(true)
	var receipt := {"request_id":request_id,"source_sha256":archive_receipt.source_sha256,"source_store_revision":int(expected_revision),"preserved_run_serial":int(source.checkpoint.run_serial),"replacement_run_serial":serial,"payload_sha256":_recovery_payload_hash(source.career_id,archive_receipt.source_sha256,int(expected_revision),serial,chapter,int(seed),selection)}
	prepared.candidate.checkpoint_recovery_receipt = receipt.duplicate(true)
	prepared.receipt = receipt
	return prepared
func _archive_receipt_valid(receipt: Variant) -> bool:
	if not receipt is Dictionary or receipt.size() != 4: return false
	return _contracts.hash_valid(receipt.get("source_sha256")) and _contracts.hash_valid(receipt.get("pins_sha256")) and _counter(receipt.get("source_store_revision")) and _counter(receipt.get("preserved_run_serial")) and receipt.preserved_run_serial >= 1
func _recovery_payload_hash(career_id: String, source_hash: String, revision: int, serial: int, chapter: Dictionary, seed: int, selection: Dictionary) -> String:
	return JSON.stringify({"career_id":career_id,"source_sha256":source_hash,"source_store_revision":revision,"replacement_run_serial":serial,"chapter_id":chapter.chapter_id,"content_revision":chapter.content_revision,"seed":seed,"selection":selection},"",true,true).sha256_text()

