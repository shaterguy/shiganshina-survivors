extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Main = preload("res://tests/app_bootstrap/test_city_bootstrap.gd")
const EXPECTED := "ch01.3-rebuild.7-grabber-hand"
func run(t) -> void:
	t.check(Core.CONTENT_REVISION == EXPECTED,"harmless recovery has a distinct product content revision")
	for kind in ["finite","city"]: _legacy(t,kind)
func _legacy(t,kind: String) -> void:
	var source_root := ProjectSettings.globalize_path("res://tests/fixtures/grabber_previous_recovery/"+kind+"/saves")
	var source := FileAccess.get_file_as_string(source_root.path_join("game_save.json"))
	var old: Dictionary = JSON.parse_string(source)
	t.check(old.checkpoint.content_revision == "ch01.3-rebuild.6-harmless-recovery",kind+" input is an actual .6 producer save")
	t.check(Core.new().restore(old.checkpoint).get("error_code") == "content_mismatch",kind+" previous .6 gameplay is rejected before reinterpretation")
	var tools := Main.new()
	var directory: String = tools._directory("real_previous_"+kind)
	_copy_tree(source_root,directory)
	var all_before: Dictionary = tools._directory_bytes(directory)
	var backup := FileAccess.get_file_as_string(directory.path_join("game_save.json.bak"))
	var boot = tools._main(t)
	if boot == null: return
	tools._enter(t,boot,directory)
	var app = boot.app
	t.check(app._startup_view.get("kind") == "checkpoint" and app.state.is_empty() and app.game_save.is_empty(),kind+" actual main refuses automatic .6 adoption")
	if app._startup_view.get("kind") != "checkpoint": boot.free(); return
	t.check(app.ui.focused_semantic_id() == "recovery_keep",kind+" .6 recovery defaults to keeping the save")
	t.check(tools._directory_bytes(directory) == all_before,kind+" inspecting .6 leaves source, backup and all world bytes intact")
	app.ui.recovery_keep_requested.emit()
	t.check(app._startup_view.get("kind") == "kept" and tools._directory_bytes(directory) == all_before,kind+" explicit keep is read-only")
	app.ui.recovery_retry_requested.emit()
	app.ui.recovery_start_requested.emit()
	t.check(not app.state.is_empty() and app.state.content_revision == EXPECTED and app.state.has("world"),kind+" explicit preserve/new departure starts actual .7 city")
	if app.state.is_empty(): boot.free(); return
	t.check(app.game_save.career_id == old.career_id and app._same_json(app.game_save.profile,old.profile),kind+" replacement preserves full career/profile including balance and inventory")
	t.check(app._same_json(app.game_save.purchase_receipts,old.purchase_receipts) and app._same_json(app.game_save.settlement_receipts,old.settlement_receipts) and app.game_save.settled_through_serial == old.settled_through_serial,kind+" purchase/settlement receipts and high-water remain exact")
	t.check(app.state.run_serial == old.next_run_serial and app.game_save.next_run_serial == old.next_run_serial+1,kind+" replacement allocates only one new run serial")
	t.check(FileAccess.get_file_as_string(directory.path_join("archives").path_join(source.sha256_text()+".json")) == source and FileAccess.get_file_as_string(directory.path_join("game_save.json.bak")) == backup,kind+" exact .6 authority archived and backup preserved")
	var after: Dictionary = tools._directory_bytes(directory)
	for path in all_before:
		if path.begins_with("world/"): t.check(after.get(path) == all_before[path],kind+" prior immutable world bytes preserved: "+path)
	var committed: Dictionary = app.game_save.duplicate(true)
	var new_source := FileAccess.get_file_as_string(directory.path_join("game_save.json"))
	boot.free()
	boot = tools._main(t)
	tools._enter(t,boot,directory)
	app = boot.app
	t.check(app._startup_view.is_empty() and app.game_save == committed and not app.pending_checkpoint.is_empty(),kind+" fresh main offers explicit resume for .7 replacement")
	t.check(FileAccess.get_file_as_string(directory.path_join("game_save.json")) == new_source,kind+" fresh .7 startup performs no save rewrite")
	app.ui.resume_requested.emit()
	t.check(not app.state.is_empty() and app.state.content_revision == EXPECTED and app.simulation._streamed.readiness(app.state).get("ok",false),kind+" resumed .7 Core/world pair is ready")
	boot.free()
func _copy_tree(source: String,target: String) -> void:
	DirAccess.make_dir_recursive_absolute(target)
	var directory := DirAccess.open(source)
	for file in directory.get_files():
		var output := FileAccess.open(target.path_join(file),FileAccess.WRITE)
		output.store_buffer(FileAccess.get_file_as_bytes(source.path_join(file))); output.close()
	for folder in directory.get_directories(): _copy_tree(source.path_join(folder),target.path_join(folder))
