extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,330.0])
	t.check(app.state.world.stage == "city" and not app.state.world.evacuation.is_empty(),"worker barrier fixture has durable selected passage outside overlap")
	app.autosave_test_prepare_delay_ms = 400
	app._save_checkpoint()
	t.check(app._worker_reserved(),"actual autosave thread reserves sole writer")
	var worker_tick: int = app.state.active_tick
	app.input_router.set_touch_vector(Vector2.DOWN)
	for frame in 5: app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick > worker_tick and app.state.player.position[1] >= 336 and app.state.world.stage == "city" and app._final_intent.is_empty(),"moving into passage while writer reserved never prepares competing dock candidate")
	var live_tick: int = app.state.active_tick
	var live_position: Array = app.state.player.position.duplicate()
	for frame in 1000:
		if not app._worker_reserved(): break
		await t.create_timer(0.002).timeout
		app.advance_frame(0)
	t.check(not app._worker_reserved() and app.state.active_tick == live_tick and app.state.player.position == live_position,"older autosave acknowledgment preserves latest position/tick without rewind")
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app.state.active_tick == live_tick+1 and app.game_save.checkpoint.active_tick == live_tick+1,"released writer permits one dock commit captured from latest live tick")
	t.check(S.count_actions(app,"dock_transition") == 1 and app._final_intent.is_empty(),"writer release cannot replay or strand automatic transition")
	app.free()
