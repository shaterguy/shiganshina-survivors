extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var directory := F.install("controller")
	var arranged := F.enrich(directory)
	var fixture := S.make(t,directory)
	if fixture.is_empty(): return
	var app = fixture.app
	t.check(app._startup_view.is_empty() and not app.pending_checkpoint.is_empty(),"current Controller opens the archived dev4 run as resumable")
	if not app._startup_view.is_empty() or app.pending_checkpoint.is_empty(): app.free(); return
	t.check(F.same(app.profile,arranged.profile),"startup exposes preserved permanent economic authority")
	app.request_resume()
	t.check(not app.state.is_empty() and app.state.rules.content_fingerprint == F.FINGERPRINT,"Controller resumes the exact legacy run")
	if app.state.is_empty(): app.free(); return
	t.check(app.progression_view._catalog == app.simulation._catalog and app.simulation._catalog.evolutions._schema_version == 1,"Controller progression DTO uses the resumed legacy Core catalog")
	var before: Dictionary = app.state.duplicate(true)
	var core = app.simulation
	var revision: int = app.game_save.store_revision
	app.autosave_worker_enabled = true
	app._save_checkpoint()
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread == null and app.game_save.store_revision == revision+1,"legacy default worker validates and commits with matching pinned content")
	t.check(app.simulation == core and app.state == before,"legacy worker completion preserves live Core and full state")
	var old_job: Dictionary = app._capture_worker_job(991)
	app.request_end_run()
	t.check(app.state.phase == "abandoned" and app.game_save.settled_through_serial == app.state.run_serial,"legacy Controller settles its run through the real economy boundary")
	var gold: int = app.profile.supply_credits
	app.start_run(77)
	t.check(app.state.rules.content_fingerprint != F.FINGERPRINT and app.simulation._catalog.evolutions._schema_version == 2,"next Controller run uses dev5 recipe catalog")
	t.check(app.progression_view._catalog == app.simulation._catalog and app.profile.supply_credits == gold,"new-run display follows new Core while preserving settled balance")
	var state_after: Dictionary = app.state.duplicate(true)
	var rejection: String = app._admit_worker_result({"ok":false,"error_code":"autosave_cancelled","sequence":991,"generation":old_job.generation},old_job)
	t.check(rejection == "stale_worker_generation" and app.state == state_after,"late legacy worker cannot replace a new dev5 run")
	app.free()
