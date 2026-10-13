extends "res://tests/dev5_mobility_autosave/mobility_app_fixture.gd"
func run(t) -> void:
	if not Motion.available(t): return
	await _late_result(t,false)
	await _late_result(t,true)
	await _known_failure_retry(t)
	await t.create_timer(0.25).timeout
func _late_result(t,unknown: bool) -> void:
	var app = airborne(t,"unknown" if unknown else "late")
	if app == null: return
	var core = app.simulation
	var saved: Dictionary = core.snapshot(app.state)
	var revision: int = app.game_save.store_revision
	if unknown: app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint()
	t.check(app._autosave_job.get("snapshot",{}).get("player_mobility") == saved.player_mobility,"worker capture contains exact actual airborne authority")
	land(t,app)
	var landed: Dictionary = core.snapshot(app.state)
	await _drain(t,app)
	if unknown:
		t.check(not app._autosave_unknown.is_empty(),"uncertain airborne commit retains exact reconciliation job")
		t.check(app.simulation == core and Motion.same(core.snapshot(app.state),landed),"uncertain result preserves landed live state")
		app.autosave_test_fault = {}
		app.retry_save_recovery()
		await _drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app._autosave_unknown.is_empty(),"real airborne saved authority is admitted without envelope mismatch")
	t.check(app.game_save.store_revision == revision+1,"airborne save/reconciliation advances one durable revision")
	t.check(Motion.same(app.game_save.checkpoint.player_mobility,saved.player_mobility),"durable checkpoint keeps original actual roof phase")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),landed),"late worker never rewinds landed live position/mobility/events")
	var read: Dictionary = app.save_store.read_game()
	t.check(read.get("ok",false) and Motion.same(read.game_save.checkpoint.player_mobility,saved.player_mobility),"airborne disk bytes restore to matching canonical mobility authority")
	app.free()
func _known_failure_retry(t) -> void:
	var app = airborne(t,"failure")
	if app == null: return
	var core = app.simulation
	var revision: int = app.game_save.store_revision
	app.autosave_test_fault = {"stage":"write","return_error":true}
	app._save_checkpoint()
	land(t,app)
	var landed: Dictionary = core.snapshot(app.state)
	await _drain(t,app)
	t.check(app._autosave_known_failure and app.game_save.store_revision == revision,"known failed airborne write preserves predecessor authority")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),landed),"known write failure preserves live landing")
	app.autosave_test_fault = {}
	app.retry_save_recovery()
	await _drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app.game_save.store_revision == revision+1,"retry of actual known write failure commits once")
	t.check(Motion.same(app.game_save.checkpoint.player_mobility,landed.player_mobility),"known-failure retry recaptures latest live landed authority")
	t.check(app.simulation == core and Motion.same(core.snapshot(app.state),landed),"retry does not replace live Core or restore older airborne state")
	app.free()
