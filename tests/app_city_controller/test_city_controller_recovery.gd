extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	_preserved_choice(t)
	_missing_authority(t)
func _preserved_choice(t) -> void:
	var legacy: Dictionary = Recovery.new()._incompatible_fixture(t,true)
	var f := S.make(t,legacy.directory)
	if f.is_empty(): return
	var app = f.app
	t.check(app.state.is_empty() and app.game_save.is_empty() and app._startup_view.get("kind") == "checkpoint","city injection preserves unsupported old checkpoint behind explicit choice")
	app.advance_frame(1.0/60.0)
	t.check(FileAccess.get_file_as_string(f.directory.path_join("game_save.json")) == legacy.source,"city startup never replaces unsupported authority automatically")
	var attempts := {"count":0}
	app.save_store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			attempts.count += 1
			return ERR_CANT_CREATE
		return OK
	app.confirm_preserved_run_start(146)
	t.check(not app._pending_recovery.is_empty() and app.state.is_empty(),"uncertain preserved city start retains private original intent")
	if app._pending_recovery.is_empty():
		app.free()
		return
	var intent: Dictionary = app._pending_recovery.duplicate(true)
	app.confirm_preserved_run_start(999)
	app.retry_save_recovery()
	t.check(not app.state.is_empty() and app.state.has("world") and app.state.seed == 146,"same preserved request confirms actual prepared city replacement")
	if app.state.is_empty():
		app.free()
		return
	t.check(app.simulation._streamed.readiness(app.state).ok and app.game_save.checkpoint_recovery_receipt.request_id == intent.request_id,"preserved replacement adopts matching prepared Core and receipt")
	t.check(attempts.count == 1 and app.game_save.career_id == legacy.save.career_id and app.game_save.next_run_serial == legacy.save.next_run_serial+1,"unknown recovery retry creates no replacement career, extra run or second write")
	t.check(app.profile.supply_credits == legacy.save.profile.supply_credits and app.profile.consumables.field_bandage == legacy.save.profile.consumables.field_bandage-1 and app.profile.settings == legacy.save.profile.settings,"city recovery retains economy and settings with exactly one supply debit")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("archives").path_join(legacy.source.sha256_text()+".json")) == legacy.source and FileAccess.get_file_as_string(f.directory.path_join("game_save.json.bak")) == legacy.backup,"city replacement preserves exact unsupported source archive and backup")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("world/opaque-page")) == "opaque original world bytes","new city root staging preserves prior opaque world storage")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 1,"confirmed preserved city run executes actual next tick")
	app.free()
func _missing_authority(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var authority: Dictionary = app.game_save.duplicate(true)
	for name in ["game_save.json","game_save.json.bak"]:
		var path: String = f.directory.path_join(name)
		if FileAccess.file_exists(path):
			t.check(DirAccess.rename_absolute(path,path+".retained") == OK,"city missing-source fixture retains existing bytes")
	app._save_checkpoint()
	app.retry_save_recovery()
	app.start_run(43)
	t.check(app.game_save == authority and app._startup_view.get("error_code") == "authority_missing","city controller keeps established career and profile when authority disappears")
	t.check(not FileAccess.file_exists(f.directory.path_join("game_save.json")),"missing city authority never auto-initializes new career")
	app.free()
