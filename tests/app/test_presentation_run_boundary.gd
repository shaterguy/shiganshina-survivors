extends RefCounted
# Removing either real controller reset must let the old hit pose leak into a new/restored run.
func run(t) -> void:
	var app = load("res://game/app/run_controller.gd").new()
	app.save_store = load("res://game/persistence/save_store.gd").new("user://presentation_boundary_"+str(OS.get_process_id()))
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	app.start_run(42)
	var events: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"player","amount":1,"hp":99}}]
	app.world.consume_events(events)
	t.check(app.world.player_animation(app.state)=="hit","real damage event presents a hit before boundary")
	app.set_user_pause(true)
	app.request_resume()
	t.check(app.world.player_animation(app.state)=="hit","ordinary pause resume preserves current presentation phase")
	app.start_run(42)
	t.check(app.world.player_animation(app.state)=="idle","same-seed new run clears previous run hit pose")
	var saved: Dictionary = app.simulation.snapshot(app.state)
	app.world.consume_events(events)
	app.state = {}
	app.pending_checkpoint = saved
	app.request_resume()
	t.check(not app.state.is_empty() and app.state.seed==42,"checkpoint restored through real controller")
	t.check(app.world.player_animation(app.state)=="idle","successful checkpoint restore clears stale hit pose")
	app.free()
