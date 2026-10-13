extends "res://tests/dev5_mobility_autosave/mobility_app_fixture.gd"
# Genuine save/reopen/resume through a fresh Controller and the default runtime.
func run(t) -> void:
	if not Motion.available(t): return
	var app = airborne(t,"reopen")
	if app == null: return
	app._save_checkpoint()
	await _drain(t,app)
	t.check(app._autosave_blocker.is_empty(),"actual airborne save confirms before cold controller restart")
	if not app._autosave_blocker.is_empty(): app.free(); return
	var saved: Dictionary = app.game_save.checkpoint.duplicate(true)
	var directory: String = app.save_store._directory
	app.free()
	var provider = City.new()
	var disk = Disk.new(directory.path_join("world"))
	var runtime = Runtime.new(provider,disk)
	var resumed = Controller.new()
	resumed.autosave_worker_enabled = false
	t.check(resumed.configure_city_runtime(provider,runtime,disk,directory).get("ok",false),"fresh current runtime targets only the unique saved fixture")
	t.root.add_child(resumed)
	resumed.set_process(false); resumed.world.set_process(false)
	t.check(not resumed.pending_checkpoint.is_empty() and resumed.state.is_empty(),"cold controller offers actual durable airborne checkpoint")
	resumed.input_router.set_touch_vector(Vector2.UP)
	resumed.request_resume()
	t.check(not resumed.state.is_empty(),"real controller Continue resumes exact airborne checkpoint")
	if resumed.state.is_empty(): resumed.free(); return
	t.check(Motion.same(resumed.state.player_mobility,saved.player_mobility) and resumed.state.player.position == saved.player.position and resumed.state.active_tick == saved.active_tick,"Continue preserves roof phase/progress/plane position before active tick")
	t.check(resumed.input_router.sample_move() == Vector2.ZERO,"real cold Continue applies existing input-zero policy")
	var stepped: Dictionary = resumed._step_city_tick()
	t.check(stepped.get("ok",false),"first resumed zero-input actual tick succeeds")
	var script = load(Motion.PATH)
	var sample: Dictionary = script.visual_sample(resumed.simulation.snapshot(resumed.state))
	t.check(resumed.state.player_mobility.cancelled and sample.anchor.is_empty() and float(sample.height) > 0.0,"first active zero-input tick detaches wire and safely retains roof height")
	land(t,resumed)
	t.check(resumed.simulation._streamed.walkable(Motion.vec(resumed.state.player.position),8).get("walkable",false) and resumed.state.player.invulnerable_until == 0,"cold controller completes legal safe landing without additional invulnerability")
	resumed.free()
