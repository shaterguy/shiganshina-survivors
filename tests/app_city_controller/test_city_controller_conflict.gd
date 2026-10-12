extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Faults = preload("res://tests/app_city_controller/test_city_controller_transactions.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var a = app.simulation
	var before: Dictionary = app.state.duplicate(true)
	var store := Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hidden = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	var candidate: Dictionary = app.game_save.duplicate(true)
	candidate.checkpoint.player.hp = 73.0
	app._commit_candidate(candidate,"checkpoint")
	t.check(not app._pending_transaction.is_empty(),"conflict fixture has actual uncertain committed city candidate")
	store.hidden = false
	store._fault_injector = Callable()
	var different: Dictionary = store.read_game().game_save
	different.checkpoint.player.hp = 62.0
	var file := FileAccess.open(f.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(different,"",true,true)); file.close()
	t.check(not app.resolve_pending_transaction() and app.state == before and app.simulation == a,"same run/revision with different full authority cannot publish prepared B")
	t.check(app._startup_view.get("error_code") == "authority_mismatch","different confirmed authority exposes bounded explicit recovery choice")
	app.retry_save_recovery()
	t.check(app._pending_transaction.is_empty() and app.state.is_empty() and app.pending_checkpoint.get("player",{}).get("hp") == 62.0,"explicit retry prepares/confirms changed authority then waits for new resume choice")
	app.request_resume()
	app.advance_frame(1.0/60.0)
	t.check(not app.state.is_empty() and app.state.player.hp == 62.0 and app.state.active_tick == 1,"explicit changed-authority resume uses its own prepared Core without permanent lock")
	app.free()
