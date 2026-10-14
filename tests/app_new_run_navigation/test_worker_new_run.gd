extends "res://tests/app_async_autosave/test_default_worker.gd"
# Real worker, Core and disk authority; an unadopted completed writer makes the
# deferred-command boundary deterministic without mocked save outcomes.
func run(t) -> void:
	await _replacement(t,false)
	await _replacement(t,true)
func _replacement(t,interrupt: bool) -> void:
	var app = _fixture(t,"new_run_worker_"+str(interrupt))
	if app == null: return
	var old_id: String = app.state.run_id
	app._save_checkpoint()
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and app._autosave_thread.is_alive() and Time.get_ticks_usec() < deadline:
		await t.create_timer(0.003).timeout
	var completed: bool = app._autosave_thread != null and not app._autosave_thread.is_alive()
	t.check(completed,"new-run input targets a real completed, unadopted worker")
	if not completed: app.free(); return
	app.request_new_run(44,true,old_id)
	var intent: Dictionary = app._autosave_intent.duplicate(true)
	app.request_new_run(44,true,old_id)
	t.check(intent.get("action") == "new_run" and app._autosave_intent == intent and app.state.run_id == old_id,"duplicate replacement is retained once without ending under writer reservation")
	if interrupt:
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _drain(t,app)
	app.advance_frame(0)
	if interrupt:
		t.check(app._autosave_intent.is_empty() and app.state.run_id == old_id and app.game_save.next_run_serial == 2,"obsolete worker-held replacement never crosses a newer lifecycle generation")
		app.request_new_run(45,true,old_id)
		await _drain(t,app)
		t.check(app.state.seed == 45 and app.state.run_serial == 2,"fresh confirmed request releases ambient pause and replaces the old run once")
	else:
		t.check(app.state.seed == 44 and app.state.run_serial == 2,"confirmed predecessor permits exactly the original retained replacement")
	t.check(app.game_save.settlement_receipts.size() == 1 and app._new_run_intent.is_empty() and app._autosave_intent.is_empty(),"worker replacement settles once and releases both intent slots")
	var bytes := var_to_bytes(app.game_save)
	for i in 4: app.advance_frame(0)
	t.check(var_to_bytes(app.game_save) == bytes,"late polls cannot repeat replacement or settlement")
	app.free()
