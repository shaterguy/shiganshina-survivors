extends RefCounted
func run(t) -> void:
	var support = load("res://tests/app/controller_test_support.gd").new()
	var fixture = support.make(t)
	var app = fixture.app
	t.check(app.get("save_store") != null,"app owns checkpoint store")
	if app.get("save_store") == null:
		app.free()
		return
	app.start_run(42)
	app.advance_frame(1.0/60.0)
	app.set_user_pause(true)
	var before: Dictionary = app.simulation.snapshot(app.state)
	app.free()
	var restored = support.restart(t,fixture.directory)
	restored.request_resume()
	t.check(restored.state.seed == 42 and restored.state.active_tick == before.active_tick,"restart resumes previous run clocks")
	t.check(restored.state.player.position == before.player.position,"restart preserves player position")
	t.check(not "user" in restored.state.pause_reasons,"explicit continue resumes saved pause")
	restored.free()
