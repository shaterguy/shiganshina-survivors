extends "res://tests/app_async_autosave/test_default_worker.gd"
const Motion = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Planner = preload("res://game/world/mobility_anchor_query.gd")
# Uses the genuine default provider, disk/runtime/controller and worker. Only
# initial safe approach and input are arranged; no airborne state is injected.
func airborne(t,label: String,phase: String = "over"):
	var directory: String = "user://mobility_autosave_%d_%d_%s/saves" % [OS.get_process_id(),Time.get_ticks_usec(),label]
	var provider = City.new()
	var disk = Disk.new(directory.path_join("world"))
	var runtime = Runtime.new(provider,disk)
	var initialized: Dictionary = Save.new(directory,Callable(runtime,"validate_checkpoint")).initialize_game({},"0123456789abcdef0123456789abcdef")
	t.check(initialized.get("ok",false),"mobility actual disk fixture initializes")
	if not initialized.get("ok",false): return null
	var app = Controller.new()
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	t.check(configured.get("ok",false),"mobility default current controller configures")
	if not configured.get("ok",false): app.free(); return null
	t.root.add_child(app)
	app.set_process(false); app.world.set_process(false)
	app.start_run(Motion.seed_for_cast())
	t.check(not app.state.is_empty(),"mobility default controller starts actual run")
	if app.state.is_empty(): app.free(); return null
	var terrain: Dictionary = app.simulation.world_render_view(app.state)
	var arranged: Dictionary = {}
	for chunk in terrain.get("chunks",[]):
		if chunk.chunk_id != "0,0": continue
		for prop in chunk.props:
			var candidate: Dictionary = app.state.duplicate(true)
			var approach: Vector2 = prop.position+Vector2(0,32)
			if not app.simulation._streamed.walkable(approach,8).get("walkable",false): continue
			candidate.player.position = [approach.x,approach.y]
			if not Planner.plan(candidate,Vector2.UP,app.simulation._streamed).get("ok",false): continue
			arranged = candidate
			break
		if not arranged.is_empty(): break
	t.check(not arranged.is_empty(),"actual dense current city has an approved forward roof route")
	if arranged.is_empty(): app.free(); return null
	arranged.player.attack_ready_ticks.blade_slash = 200000
	var needed: Dictionary = Helper.requirements(arranged)
	var hydrated: Dictionary = disk.hydrate(arranged.world.delta_root,needed.chunks)
	var checked: Dictionary = app.simulation.prepare_world(arranged,hydrated.deltas)
	t.check(checked.get("ok",false),"arranged approach is fully validated by real Core")
	if not checked.get("ok",false): app.free(); return null
	app.state = arranged
	app.input_router.set_touch_vector(Vector2.UP)
	for tick in 64:
		if app.state.get("player_mobility",{}).get("phase") == phase: break
		var stepped: Dictionary = app._step_city_tick()
		t.check(stepped.get("ok",false),"actual controller roof fixture tick succeeds")
		if not stepped.get("ok",false): app.free(); return null
	t.check(app.state.get("player_mobility",{}).get("phase") == phase,"actual dense city Core emits airborne "+phase+" checkpoint")
	if app.state.get("player_mobility",{}).get("phase") != phase: app.free(); return null
	return app
func land(t,app) -> void:
	app.input_router.clear_transient_input()
	for tick in 40:
		if app.state.player_mobility.phase == "ground": break
		var stepped: Dictionary = app._step_city_tick()
		t.check(stepped.get("ok",false),"live safe landing controller tick succeeds while worker is unpolled")
		if not stepped.get("ok",false): return
	t.check(app.state.player_mobility.phase == "ground","live lands before asynchronous result is adopted")
