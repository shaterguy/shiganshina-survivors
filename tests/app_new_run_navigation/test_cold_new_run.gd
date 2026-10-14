extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func _press(ui, id: String) -> void:
	for button in ui._buttons:
		if button.get_meta("semantic_id","") == id:
			button.pressed.emit()
			return
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	f.app.start_run(42)
	var old_id: String = f.app.state.run_id
	var old_profile: Dictionary = f.app.profile.duplicate(true)
	f.app.free()
	var cold := S.make(t,f.directory)
	var app = cold.app
	t.check(app.state.is_empty() and not app.pending_checkpoint.is_empty(),"replacement fixture begins at cold common main with an active save")
	var original := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.start_run(43)
	t.check(app.state.is_empty() and app.ui._notice.text.contains("active_run") and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == original,"original direct-start path still refuses active saves without weakening the safety guard")
	app.request_new_run(43,false)
	t.check(app.state.is_empty() and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == original,"unconfirmed new run cannot end or overwrite an active save")
	_press(app.ui,"new_run_open")
	_press(app.ui,"scenario:chapter_01_shiganshina")
	_press(app.ui,"scenario_start")
	t.check(FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == original,"navigating to replacement confirmation does not mutate the active save")
	_press(app.ui,"new_run_confirm")
	t.check(app.state.get("run_serial") == 2 and app.state.get("phase") == "survival" and app.ui._mode == "play","actual confirmed cold UI path settles old run then enters the new run")
	var seed: int = app.state.seed
	t.check(app.game_save.settled_through_serial == 1 and app.game_save.settlement_receipts.size() == 1,"old run is settled exactly once before replacement")
	for key in old_profile:
		if key != "best_runs": t.check(app.profile[key] == old_profile[key],"zero-performance restart preserves permanent profile field "+key)
	var replaced := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.request_new_run(44,true,old_id)
	t.check(app.state.seed == seed and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == replaced,"stale repeated confirmation cannot end the replacement run")
	app.free()
