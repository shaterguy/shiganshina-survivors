extends RefCounted
func run(t) -> void:
	var script = load("res://game/app/run_controller.gd")
	var app = script.new()
	t.check(app.get("save_store") != null,"app owns checkpoint store")
	if app.get("save_store") == null:
		app.free()
		return
	var store = load("res://game/persistence/save_store.gd").new("user://app_resume_"+str(OS.get_process_id()))
	app.save_store = store
	t.root.add_child(app)
	app.set_process(false)
	app.start_run(42)
	app.advance_frame(1.0/60.0)
	app.set_user_pause(true)
	var before: Dictionary = app.simulation.snapshot(app.state)
	app.free()
	var restored = script.new()
	restored.save_store = store
	t.root.add_child(restored)
	restored.set_process(false)
	restored.request_resume()
	t.check(restored.state.seed == 42 and restored.state.active_tick == before.active_tick,"restart resumes previous run clocks")
	t.check(restored.state.player.position == before.player.position,"restart preserves player position")
	t.check(not "user" in restored.state.pause_reasons,"explicit continue resumes saved pause")
	restored.free()
