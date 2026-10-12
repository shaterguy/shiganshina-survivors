extends RefCounted
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	_test_source_disappears_after_inspection(t)
	_test_pending_missing_keeps_request(t)
func _move_sources(directory: String) -> void:
	for name in ["game_save.json","game_save.json.bak"]:
		var path := directory.path_join(name)
		if FileAccess.file_exists(path): assert(DirAccess.rename_absolute(path,path+".retained-missing-probe") == OK)
func _test_source_disappears_after_inspection(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	var career: String = app.game_save.career_id
	# Trigger the retry screen before changing the next read boundary.
	app.save_store._fault_injector = func(stage): return ERR_CANT_OPEN if stage == "read_primary" else OK
	app._apply_settings(app.profile.settings.duplicate(true))
	var reads := {"count":0}
	app.save_store._fault_injector = func(stage):
		if stage == "read_primary":
			reads.count += 1
			# The inspection has completed its three bounded primary reads.
			if reads.count == 4: _move_sources(fixture.directory)
		return OK
	app.retry_save_recovery()
	t.check(not FileAccess.file_exists(fixture.directory.path_join("game_save.json")),"disappearance inside post-inspection read cannot create an authority")
	t.check(app.game_save.career_id == career and app._startup_view.get("kind") in ["blocked","retry"],"post-inspection disappearance retains established career and blocks startup")
	app.free()
func _test_pending_missing_keeps_request(t) -> void:
	var fixture := Recovery.new()._incompatible_fixture(t)
	var app = Recovery.new()._restart_observed(t,fixture.directory)
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.confirm_preserved_run_start(905)
	var request: String = app._pending_recovery.request_id
	_move_sources(fixture.directory)
	app.save_store._fault_injector = Callable()
	app.retry_save_recovery()
	t.check(not app._pending_recovery.is_empty() and app._pending_recovery.get("request_id") == request,"missing recovery source retains immutable request identity")
	t.check(not FileAccess.file_exists(fixture.directory.path_join("game_save.json")) and app.game_save.is_empty(),"missing pending source never creates or adopts fresh authority")
	app.keep_saved_authority()
	t.check(app._startup_view.get("kind") == "kept" and app._pending_recovery.get("request_id") == request,"missing pending source can be kept without discarding same-ID request")
	app.free()
