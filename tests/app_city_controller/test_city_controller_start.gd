extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	t.check(app.chapter.get("world_mode") == "streamed_city" and app.simulation._chapter_provider == f.provider,"configured controller uses exact city provider")
	t.check(app.save_store._directory == f.directory and app.game_save.store_revision == 1,"isolated save initializes once without touching shipped saves")
	app.start_run(42)
	t.check(not app.state.is_empty() and app.state.has("world"),"real Supply factory starts a streamed city run")
	if app.state.is_empty():
		app.free()
		return
	t.check(app.simulation._streamed.readiness(app.state).ok,"confirmed controller start owns ready Core/state pair")
	t.check(app.game_save.checkpoint == app.state and f.disk.verify_root(app.state.world.delta_root).ok,"initial city root is staged and exact authority adopted")
	var active_core = app.simulation
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 1 and app.simulation.step_status().ok,"actual controller next tick advances prepared city")
	t.check(app.simulation == active_core,"ordinary covered tick does not rebuild Core or terrain")
	t.check(app.game_save.checkpoint.active_tick == 0,"live step cannot alias saved authority")
	app._save_checkpoint()
	var saved: Dictionary = app.game_save.duplicate(true)
	var expected: Dictionary = f.runtime.refresh_coverage(saved.checkpoint)
	var commands: Array[Dictionary] = app.director.plan(expected.state,app.chapter)
	var expected_events: Array = expected.simulation.step(expected.state,Vector2.RIGHT,commands)
	var directory: String = f.directory
	app.free()
	var cold := S.make(t,directory)
	var resumed = cold.app
	t.check(resumed.state.is_empty() and not resumed.pending_checkpoint.is_empty(),"city cold startup waits for explicit resume")
	resumed.request_resume()
	t.check(not resumed.state.is_empty() and resumed.simulation._streamed.readiness(resumed.state).ok,"cold resume confirms a private prepared pair")
	resumed.input_router.set_touch_vector(Vector2.RIGHT)
	resumed.advance_frame(1.0/60.0)
	t.check(resumed.state == expected.state and expected_events.is_empty(),"cold controller actual next tick matches independent prepared Core")
	t.check(not resumed.configure_city_runtime(cold.provider,cold.runtime,cold.disk,directory).get("ok",false),"late configuration cannot replace live controller dependencies")
	resumed.free()
