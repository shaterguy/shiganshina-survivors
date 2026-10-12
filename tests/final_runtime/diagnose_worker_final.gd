extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t) -> void:
	var f := S.make(t)
	var app = f.app
	S.boundary(f,[384.0,384.0])
	app.advance_frame(1.0/60.0)
	for step in 149:
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
	app._latch_lifecycle_pause("controller_lost")
	app.request_resume()
	for frame in 1000:
		if app._autosave_thread == null: break
		await t.create_timer(0.002).timeout
		app.advance_frame(0)
	print("WORKER_FINAL ",app.state.active_tick," ",app._autosave_blocker," diagnostics=",app.worker_diagnostics.size())
	t.check(app._autosave_blocker.is_empty(),"existing final hazard snapshot autosave admits normalized authority")
	app.free()
