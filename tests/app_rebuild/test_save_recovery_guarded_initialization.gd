extends RefCounted
const Store = preload("res://game/persistence/game_save_store.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
const CAREER := "0123456789abcdef0123456789abcdef"
func run(t) -> void:
	var validator = Core.new()
	var probe = Store.new(Recovery.new()._unique_directory("guard_api"),Callable(validator,"restore"))
	t.check(probe.has_method("initialize_game"),"Store exposes source-bound initialization while ordinary load_game stays unchanged")
	if not probe.has_method("initialize_game"): return
	_test_missing_source(t,validator)
	_test_changed_source_at_replace(t,validator)
	_test_read_retry(t,validator)
	_test_unknown_same_candidate(t,validator)
	_test_fresh_empty_map(t,validator)
	_test_new_known_file(t,validator)
	_test_same_career_wrong_candidate(t,validator)
	_test_invalid_intent(t,validator)
func _legacy(validator) -> Dictionary:
	var directory: String = Recovery.new()._unique_directory("guarded_legacy")
	var profile := {"schema_version":1,"settings":{"deadzone":0.25,"audio_master":0.4,"screen_shake":0.2,"reduce_effects":true},"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	var source := JSON.stringify(profile,"",true,true)
	Recovery.new()._write(directory.path_join("profile.json"),source)
	Recovery.new()._write(directory.path_join("checkpoint.json"),"opaque retained dev1 checkpoint")
	var store = Store.new(directory,Callable(validator,"restore"))
	var locations: Dictionary = store.inspect_known_locations(directory.get_base_dir())
	return {"directory":directory,"store":store,"observed":locations.locations[0].files.duplicate(true),"source":source}
func _test_missing_source(t,validator) -> void:
	var f := _legacy(validator)
	for name in ["profile.json","checkpoint.json"]:
		assert(DirAccess.rename_absolute(f.directory.path_join(name),f.directory.path_join(name+".retained")) == OK)
	var result: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(not result.ok and not FileAccess.file_exists(f.directory.path_join("game_save.json")),"guarded initialization cannot default a disappeared observed legacy source")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("profile.json.retained")) == f.source,"missing-source refusal preserves retained exact profile bytes")
func _test_changed_source_at_replace(t,validator) -> void:
	var f := _legacy(validator)
	var changed: String = f.source+" "
	f.store._fault_injector = func(stage):
		if stage == "replace": Recovery.new()._write(f.directory.path_join("profile.json"),changed)
		return OK
	var result: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(not result.ok and not FileAccess.file_exists(f.directory.path_join("game_save.json")),"final source revalidation blocks post-read legacy identity change")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("profile.json")) == changed,"final guard keeps externally changed legacy source intact")
	f.store._fault_injector = Callable()
func _test_read_retry(t,validator) -> void:
	var f := _legacy(validator)
	f.store._fault_injector = func(stage): return ERR_CANT_OPEN if stage == "read_file" else OK
	var failed: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(not failed.ok and failed.error_code == "read_failed","guarded legacy read failure retains exact transient diagnosis")
	f.store._fault_injector = Callable()
	var result: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(result.ok and result.game_save.career_id == CAREER and result.game_save.profile.settings.reduce_effects,"same guarded request can retry validated legacy initialization")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("profile.json")) == f.source and FileAccess.get_file_as_string(f.directory.path_join("checkpoint.json")) == "opaque retained dev1 checkpoint","successful guarded migration retains exact dev1 files")
func _test_unknown_same_candidate(t,validator) -> void:
	var f := _legacy(validator)
	var writes := {"count":0}
	f.store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			writes.count += 1
			return ERR_CANT_CREATE
		return OK
	var failed: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(not failed.ok and failed.error_code == "commit_outcome_unknown" and failed.get("pending_initialization_candidate") is Dictionary,"uncertain initialization returns private exact candidate only for readback")
	var read: Dictionary = f.store.read_game()
	t.check(read.ok and read.source_sha256 == failed.get("pending_initialization_sha256"),"uncertain initialization readback matches exact expected canonical bytes")
	var repeated: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(repeated.ok and repeated.get("already_applied",false) and repeated.game_save.store_revision == 1 and writes.count == 1,"same initialization identity returns exact confirmed readback without a second write")
func _test_fresh_empty_map(t,validator) -> void:
	var directory: String = Recovery.new()._unique_directory("guarded_fresh")
	var store = Store.new(directory,Callable(validator,"restore"))
	var result: Dictionary = store.initialize_game({},CAREER)
	t.check(result.ok and result.game_save.career_id == CAREER and result.game_save.store_revision == 1,"guarded empty-map initial installation creates exactly one requested career")
	var repeated: Dictionary = store.initialize_game({},CAREER)
	t.check(repeated.ok and repeated.get("already_applied",false),"fresh guarded initialization repeat confirms exact existing authority")
func _test_new_known_file(t,validator) -> void:
	var f := _legacy(validator)
	Recovery.new()._write(f.directory.path_join("checkpoint.json.bak"),"unexpected retained source")
	var result: Dictionary = f.store.initialize_game(f.observed,CAREER)
	t.check(not result.ok and not FileAccess.file_exists(f.directory.path_join("game_save.json")),"new known source blocks initialization bound to original observed map")
func _test_same_career_wrong_candidate(t,validator) -> void:
	var directory: String = Recovery.new()._unique_directory("same_career_changed")
	var store = Store.new(directory,Callable(validator,"restore"))
	var initial: Dictionary = store.initialize_game({},CAREER)
	var changed: Dictionary = initial.game_save.duplicate(true)
	changed.profile.settings.reduce_effects = true
	Recovery.new()._write(directory.path_join("game_save.json"),JSON.stringify(changed,"",true,true))
	var result: Dictionary = store.initialize_game({},CAREER)
	t.check(not result.ok and result.error_code == "stale_revision" and store.read_game().game_save.profile.settings.reduce_effects,"same career alone never confirms a different initialization candidate")
func _test_invalid_intent(t,validator) -> void:
	var directory: String = Recovery.new()._unique_directory("invalid_initial_intent")
	var store = Store.new(directory,Callable(validator,"restore"))
	for observed in [[],{"unknown.json":{"readable":true,"sha256":"a".repeat(64)}},{"profile.json":{"readable":"true","sha256":"a".repeat(64)}},{"game_save.json":{"readable":true,"sha256":"a".repeat(64)}}]:
		var result: Dictionary = store.initialize_game(observed,CAREER)
		t.check(not result.ok and result.error_code == "invalid_game_save","invalid/authority-bearing initialization intent is rejected before writes")
	var invalid_career: Dictionary = store.initialize_game({},123)
	t.check(not invalid_career.ok and not FileAccess.file_exists(directory.path_join("game_save.json")),"initializer validates career identity without typed coercion or writes")
