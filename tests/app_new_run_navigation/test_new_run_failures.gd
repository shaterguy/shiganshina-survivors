extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
class HiddenStore:
	extends "res://game/persistence/game_save_store.gd"
	var hidden := false
	func read_game() -> Dictionary:
		return {"ok":false,"error_code":"read_failed"} if hidden else super.read_game()
func _cold(t) -> Dictionary:
	var first := S.make(t)
	first.app.start_run(41)
	first.app.free()
	return S.make(t,first.directory)
func run(t) -> void:
	_known_failure(t)
	_unknown_result(t,false)
	_unknown_result(t,true)
func _known_failure(t) -> void:
	var f := _cold(t)
	var app = f.app
	var old_id: String = app.pending_checkpoint.run_id
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.request_new_run(42,true,old_id)
	t.check(app._new_run_intent.is_empty() and app.game_save.next_run_serial == 2,"definite settlement failure does not leave automatic restart intent")
	t.check(FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"failed replacement settlement preserves the exact active saved authority")
	app.advance_frame(0)
	t.check(FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"definite failure is not silently retried by the frame loop")
	app.save_store._fault_injector = Callable()
	app.request_new_run(42,false)
	t.check(app.state.seed == 42 and app.state.run_serial == 2 and app.game_save.settlement_receipts.size() == 1,"explicit retry completes pending terminal settlement and starts once")
	app.free()
func _unknown_result(t,interrupt: bool) -> void:
	var f := _cold(t)
	var app = f.app
	var old_id: String = app.pending_checkpoint.run_id
	var store := HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hidden = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.request_new_run(42,true,old_id)
	t.check(not app._pending_transaction.is_empty() and not app._new_run_intent.is_empty(),"uncertain settlement retains exact replacement intent")
	var intent: Dictionary = app._new_run_intent.duplicate(true)
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.request_new_run(99,true,old_id)
	t.check(app._new_run_intent == intent and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"repeated uncertain request neither changes seed nor writes again")
	if interrupt: app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	store.hidden = false
	store._fault_injector = Callable()
	app.advance_frame(0)
	app.advance_frame(0)
	if interrupt:
		t.check(app.state.run_id == old_id and app.game_save.next_run_serial == 2,"background interruption can confirm settlement but cannot start a new sortie")
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		app.advance_frame(0)
		t.check(app.game_save.next_run_serial == 2,"foreground return never automatically starts the cancelled sortie")
		app.request_new_run(43,false)
		t.check(app.state.seed == 43 and app.state.run_serial == 2,"new foreground user request starts after interrupted settlement")
	else:
		t.check(app.state.seed == 42 and app.state.run_serial == 2,"readback-confirmed settlement resumes the exact once-only new sortie")
	t.check(app.game_save.settlement_receipts.size() == 1,"unknown-outcome recovery never awards the old settlement twice")
	app.free()
