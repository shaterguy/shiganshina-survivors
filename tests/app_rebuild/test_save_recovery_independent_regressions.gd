extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	_test_live_missing_retry(t)
	_test_pending_missing_retry(t)
	_test_midframe_conflict(t)
	_test_preservation_lifecycle(t)
	_test_keep_missing_retry(t)
	_test_pending_conflict_controls(t)
	_test_duplicate_progression_boundary(t)
func _move_authorities(directory: String) -> void:
	for name in ["game_save.json","game_save.json.bak"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path):
			var result := DirAccess.rename_absolute(path,path+".review-retained")
			assert(result == OK)
func _test_live_missing_retry(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	app.start_run(901)
	var authority: Dictionary = app.game_save.duplicate(true)
	authority.profile.supply_credits = 123
	authority.profile.settings.reduce_effects = true
	app.free()
	Recovery.new()._write(fixture.directory.path_join("game_save.json"),JSON.stringify(authority,"",true,true))
	app = Support.new().restart(t,fixture.directory)
	var career: String = app.game_save.career_id
	t.check(app.profile.supply_credits == 123,"setup: actual Store accepts preserved nonzero currency")
	app.save_store._fault_injector = func(stage): return ERR_CANT_OPEN if stage == "read_primary" else OK
	app._apply_settings(app.profile.settings.duplicate(true))
	t.check(app._startup_view.get("kind") == "retry","setup: live authority read failure creates explicit retry")
	_move_authorities(fixture.directory)
	app.save_store._fault_injector = Callable()
	app.retry_save_recovery()
	print("REVIEW live_missing_retry ",JSON.stringify({"view":app._startup_view,"career_changed":app.game_save.get("career_id") != career,"primary_created":FileAccess.file_exists(fixture.directory.path_join("game_save.json")),"credits":app.profile.get("supply_credits",-1)}))
	t.check(not FileAccess.file_exists(fixture.directory.path_join("game_save.json")),"live read retry must not create fresh authority after established source disappears")
	t.check(app.game_save.get("career_id") == career,"live retry must retain established career identity")
	t.check(app.profile.supply_credits == 123 and app.profile.settings.reduce_effects,"live retry must not reset retained credits or profile settings")
	app.free()
func _test_pending_missing_retry(t) -> void:
	var fixture := Recovery.new()._incompatible_fixture(t)
	var app = Recovery.new()._restart_observed(t,fixture.directory)
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.confirm_preserved_run_start(902)
	t.check(not app._pending_recovery.is_empty(),"setup: failed recovery retains pending immutable candidate")
	_move_authorities(fixture.directory)
	app.save_store._fault_injector = Callable()
	app.retry_save_recovery()
	print("REVIEW pending_missing_retry ",JSON.stringify({"view":app._startup_view,"primary_created":FileAccess.file_exists(fixture.directory.path_join("game_save.json"))}))
	t.check(not FileAccess.file_exists(fixture.directory.path_join("game_save.json")),"pending recovery readback must not create a fresh career when source disappears")
	app.free()
func _test_midframe_conflict(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	app.start_run(903)
	var distinct: Dictionary = app.game_save.duplicate(true)
	distinct.profile.settings.reduce_effects = not distinct.profile.settings.reduce_effects
	Recovery.new()._write(fixture.directory.get_base_dir().path_join("game_save.json"),JSON.stringify(distinct,"",true,true))
	app._last_save_tick = -1799
	app.advance_frame(8.0/60.0)
	print("REVIEW midframe_conflict ",JSON.stringify({"kind":app._startup_view.get("kind"),"tick":app.state.active_tick,"paused":app.audio._music.stream_paused}))
	t.check(app._startup_view.get("kind") == "conflict","setup: checkpoint boundary discovers late lineage conflict")
	t.check(app.state.active_tick == 1,"new recovery modal discovered inside tick loop must prevent every later tick in same frame")
	app.free()
func _test_preservation_lifecycle(t) -> void:
	for reason in ["background","controller_lost"]:
		var fixture := Recovery.new()._incompatible_fixture(t)
		var app = Recovery.new()._restart_observed(t,fixture.directory)
		app.save_store._fault_injector = func(stage):
			if stage == "archive_write":
				if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				else: app._latch_lifecycle_pause("controller_lost")
			return OK
		app.confirm_preserved_run_start(904)
		t.check(not app._pending_recovery.is_empty() and app.state.is_empty(),"setup: "+reason+" during archive retains prepared candidate without publishing")
		app.save_store._fault_injector = Callable()
		if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		app.request_recovery_continue()
		var ids: Array = Recovery.new()._button_ids(app.ui)
		print("REVIEW archive_lifecycle ",JSON.stringify({"reason":reason,"kind":app._startup_view.get("kind"),"pending":not app._pending_recovery.is_empty(),"buttons":ids}))
		t.check(ids.has("recovery_retry"),reason+" during archive must expose usable same-request retry after explicit continue")
		app.confirm_preserved_run_start(999)
		app.keep_saved_authority()
		t.check(app._startup_view.get("kind") != "checkpoint" or app._pending_recovery.is_empty(),reason+" recovery must not strand user on inert start/keep buttons")
		app.free()

func _test_keep_missing_retry(t) -> void:
	var fixture := Recovery.new()._incompatible_fixture(t)
	var app = Recovery.new()._restart_observed(t,fixture.directory)
	app.keep_saved_authority()
	_move_authorities(fixture.directory)
	app.retry_save_recovery()
	print("REVIEW keep_missing_retry ",JSON.stringify({"kind":app._startup_view.get("kind"),"primary_created":FileAccess.file_exists(fixture.directory.path_join("game_save.json")),"adopted":not app.game_save.is_empty()}))
	t.check(not FileAccess.file_exists(fixture.directory.path_join("game_save.json")) and app.game_save.is_empty(),"return from keep must not create fresh career if observed old source disappears")
	app.free()
func _test_pending_conflict_controls(t) -> void:
	var fixture := Recovery.new()._incompatible_fixture(t)
	var app = Recovery.new()._restart_observed(t,fixture.directory)
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.confirm_preserved_run_start(905)
	app.save_store._fault_injector = Callable()
	Recovery.new()._write(fixture.directory.get_base_dir().path_join("game_save.json"),fixture.backup)
	app.retry_save_recovery()
	var before: Dictionary = app._startup_view.duplicate(true)
	var ids: Array = Recovery.new()._button_ids(app.ui)
	app.keep_saved_authority()
	print("REVIEW pending_conflict_controls ",JSON.stringify({"kind":before.get("kind"),"buttons":ids,"keep_changed_view":before != app._startup_view,"pending":not app._pending_recovery.is_empty()}))
	t.check(before.get("kind") == "conflict","setup: pending recovery detects later alternate authority")
	t.check(ids.has("recovery_retry") or before != app._startup_view,"pending recovery conflict must provide a usable control, not an inert keep-only button")
	app.free()
func _test_duplicate_progression_boundary(t) -> void:
	var fixture := Support.new().make(t)
	fixture.app.start_run(906)
	fixture.app.free()
	var source: String = FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json"))
	var alternate: String = fixture.directory.get_base_dir().path_join("game_save.json")
	Recovery.new()._write(alternate,source)
	var app = Support.new().restart(t,fixture.directory)
	t.check(app._startup_inspection.duplicate_copy and app._startup_view.is_empty(),"supported exact duplicate initially permits canonical startup")
	app.request_resume()
	app._apply_settings(app.profile.settings.duplicate(true))
	print("REVIEW duplicate_progression_boundary ",JSON.stringify({"kind_after_resume_then_settings":app._startup_view.get("kind"),"alternate_retained":FileAccess.get_file_as_string(alternate)==source}))
	# Conservative reblocking is an explicitly documented lineage-design boundary,
	# not a failing test or authority to ignore the now-distinct alternate.
	t.check(app._startup_view.get("kind") == "conflict" and FileAccess.get_file_as_string(alternate)==source,"observed boundary: legitimate canonical progression makes retained duplicate distinct and blocks later commands")
	app.free()
