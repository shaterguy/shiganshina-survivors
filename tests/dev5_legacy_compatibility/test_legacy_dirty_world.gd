extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Worker = preload("res://game/app/autosave_worker.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
func run(t) -> void:
	var directory := F.install("dirty_world")
	var reference := F.legacy_authority(directory)
	t.check(reference.store.read_game().get("ok",false),"dirty-world test starts with valid pinned dev4 authority and pages")
	var fixture := S.make(t,directory)
	if fixture.is_empty(): return
	var app = fixture.app
	app.request_resume()
	if app.state.is_empty(): t.check(false,"dirty-world test resumes real archived dev4 state"); app.free(); return
	var helper = app.simulation._streamed
	var target := {}
	for prop in helper._world.localized_chunk("0,0").props:
		if prop.destructible and not prop.destroyed: target = prop; break
	t.check(not target.is_empty(),"legacy dirty-world change targets an actual original destructible prop")
	if target.is_empty(): app.free(); return
	var tick: int = app.state.active_tick
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"dev4-compatibility-damage","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":tick,"expires_tick":tick,"structure_damage":1}
	var damage: Dictionary = helper.destruction_proposal(app.state,attack,{"prop_id":target.prop_id,"reached":true,"tick":tick,"fraction":1.0})
	t.check(damage.get("ok",false),"legacy helper proposes legitimate unsaved structural damage")
	if not damage.get("ok",false): app.free(); return
	app.state.world = damage.world
	t.check(not app.state.world.dirty_chunks.is_empty() and helper._world.apply_props(app.state.world.dirty_chunks,int(app.state.world.world_revision)).get("ok",false),"dirty is valid unsaved world state, not corrupt source pages")
	helper._remember_identity(app.state)
	var identity := var_to_bytes(app.state.world.dormant)
	var old_root: Dictionary = app.state.world.delta_root.duplicate(true)
	var core = app.simulation
	var job: Dictionary = app._capture_worker_job(777)
	var forged: Dictionary = job.duplicate(true)
	forged.content_route.rules_version = "dev5"
	var before := F.bytes(directory)
	var refused: Dictionary = Worker.new(forged)._execute()
	t.check(refused.get("error_code") == "content_mismatch" and F.bytes(directory) == before,"worker refuses stale/mixed content identity before any authority or page write")
	var revision: int = app.game_save.store_revision
	app.autosave_worker_enabled = true
	app.autosave_test_prepare_delay_ms = 500
	app._save_checkpoint()
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and not app._autosave_worker.phase() in ["preparing","finished"] and Time.get_ticks_usec() < deadline:
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread != null and app._autosave_worker.phase() == "preparing","legacy worker remains pending at the deliberate pre-commit preparation gate")
	var saved_tick: int = app.state.active_tick
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == saved_tick+1 and app.simulation == core and app._autosave_thread != null,"real legacy simulation advances a gameplay tick while its dirty checkpoint worker is pending")
	var live_gameplay: Dictionary = app.state.duplicate(true)
	live_gameplay.erase("world")
	while app._autosave_thread != null and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread == null and app.game_save.store_revision == revision+1 and app.state.world.dirty_chunks.is_empty(),"legacy worker publishes legitimate dirty pages and acknowledges only the accepted receipt")
	t.check(app.simulation == core and helper.matches(app.state) and app.state.world.delta_root != old_root and var_to_bytes(app.state.world.dormant) == identity,"legacy worker preserves live Core, exact old geometry and dormant population")
	var acknowledged_gameplay: Dictionary = app.state.duplicate(true)
	acknowledged_gameplay.erase("world")
	t.check(app.game_save.checkpoint.active_tick == saved_tick and acknowledged_gameplay == live_gameplay,"successful delayed dirty ack retains the saved older tick without rewinding any newer live gameplay field")
	var cold := Runtime.new(F.City.new(),F.Disk.new(directory.path_join("world")))
	var loaded: Dictionary = F.Save.new(directory,Callable(cold,"validate_checkpoint")).read_game()
	t.check(loaded.get("ok",false) and F.same(loaded.game_save,app.game_save),"cold routed read verifies changed original geometry pages with full authority")
	app.free()
