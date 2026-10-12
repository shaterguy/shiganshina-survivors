extends RefCounted
# Removing either real controller reset must let the old hit pose leak into a new/restored run.
func run(t) -> void:
	var app = load("res://tests/app/controller_test_support.gd").new().make(t).app
	app.start_run(42)
	var events: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"player","amount":1,"hp":99}}]
	app.world.consume_events(events)
	t.check(app.world.player_animation(app.state)=="hit","real damage event presents a hit before boundary")
	app.set_user_pause(true)
	app.request_resume()
	t.check(app.world.player_animation(app.state)=="hit","ordinary pause resume preserves current presentation phase")
	var previous_run: String = app.state.run_id
	app.start_run(42)
	t.check(app.state.run_id == previous_run,"unsettled active run cannot be silently replaced")
	app.request_end_run()
	app.start_run(42)
	t.check(app.state.run_id != previous_run and app.world.player_animation(app.state)=="idle","settled same-seed new run clears previous run hit pose")
	var saved: Dictionary = app.simulation.snapshot(app.state)
	app.world.consume_events(events)
	app.state = {}
	app.pending_checkpoint = saved
	app.request_resume()
	t.check(not app.state.is_empty() and app.state.seed==42,"checkpoint restored through real controller")
	t.check(app.world.player_animation(app.state)=="idle","successful checkpoint restore clears stale hit pose")
	app.free()
