extends "res://tests/dev5_mobility_autosave/mobility_app_fixture.gd"
func run(t) -> void:
	if not Motion.available(t): return
	await _late_result(t,false)
	await _late_result(t,true)
	await _known_failure_retry(t)
	await t.create_timer(0.25).timeout
func _late_result(t,unknown: bool) -> void:
	var app = boosting(t,"unknown" if unknown else "late")
	if app == null: return
	var core = app.simulation
	var saved: Dictionary = core.snapshot(app.state)
	var revision: int = app.game_save.store_revision
	if unknown: app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint()
	t.check(app._autosave_job.get("snapshot",{}).get("player_mobility") == saved.player_mobility,"worker capture contains exact actual boost authority")
	stop_boost(t,app)
	var stopped: Dictionary = core.snapshot(app.state)
	await _drain(t,app)
	if unknown:
		t.check(not app._autosave_unknown.is_empty(),"uncertain boost commit retains exact reconciliation job")
		t.check(app.simulation == core and Motion.same(core.snapshot(app.state),stopped),"uncertain result preserves stopped live state")
		app.autosave_test_fault = {}
		app.retry_save_recovery()
		await _drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app._autosave_unknown.is_empty(),"real boost saved authority is admitted without envelope mismatch")
	t.check(app.game_save.store_revision == revision+1,"boost save/reconciliation advances one durable revision")
	t.check(Motion.same(app.game_save.checkpoint.player_mobility,saved.player_mobility),"durable checkpoint keeps original actual boost phase")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),stopped),"late worker never rewinds stopped live position/mobility/events")
	var read: Dictionary = app.save_store.read_game()
	t.check(read.get("ok",false) and Motion.same(read.game_save.checkpoint.player_mobility,saved.player_mobility),"boost disk bytes restore to matching canonical mobility authority")
	app.free()
func _known_failure_retry(t) -> void:
	var app = boosting(t,"failure")
	if app == null: return
	var core = app.simulation
	var revision: int = app.game_save.store_revision
	app.autosave_test_fault = {"stage":"write","return_error":true}
	app._save_checkpoint()
	stop_boost(t,app)
	var stopped: Dictionary = core.snapshot(app.state)
	await _drain(t,app)
	t.check(app._autosave_known_failure and app.game_save.store_revision == revision,"known failed boost write preserves predecessor authority")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),stopped),"known write failure preserves live stopped position")
	app.autosave_test_fault = {}
	app.retry_save_recovery()
	await _drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app.game_save.store_revision == revision+1,"retry of actual known write failure commits once")
	t.check(Motion.same(app.game_save.checkpoint.player_mobility,stopped.player_mobility),"known-failure retry recaptures latest live stopped authority")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),stopped),"retry does not replace live Core or restore older boost state")
	app.free()
