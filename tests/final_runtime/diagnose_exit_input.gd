extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t) -> void:
	var f := S.make(t)
	var app = f.app
	S.boundary(f,[384.0,384.0]); app.advance_frame(1.0/60.0)
	app.state.active_tick = 112500; app.state.evacuation_ready = true
	app.input_router.set_touch_vector(Vector2.DOWN)
	for frame in 300:
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
		if app._worker_reserved(): await t.process_frame
		if frame % 30 == 0 or app.state.phase == "won": print("EXIT ",frame," ",app.state.active_tick," ",app.state.player.position," move=",app.input_router.sample_move()," phase=",app.state.phase," w=",app._autosave_blocker," c=",app._city_step_error," pauses=",app.state.pause_reasons)
		if app.state.phase == "won": break
	t.check(app.state.phase == "won","continuously held input survives autosave and exits")
	app.free()
