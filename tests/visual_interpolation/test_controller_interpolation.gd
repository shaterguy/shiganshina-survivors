extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")

func run(t) -> void:
	var app = Support.new().make(t).app
	app.start_run(42)
	t.check(app.world.has_method("set_render_alpha"),"controller exposes the actual render interpolation consumer")
	if not app.world.has_method("set_render_alpha"): app.free(); return
	var start := Vector2(app.state.player.position[0],app.state.player.position[1])
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	var finish := Vector2(app.state.player.position[0],app.state.player.position[1])
	t.check(app.world._camera == start and finish.x > start.x,"successful tick updates Core immediately while display is one tick behind at alpha zero")
	var saved := var_to_bytes(app.simulation.snapshot(app.state))
	app.advance_frame(1.0/120.0)
	t.check(app.world._camera.is_equal_approx(start.lerp(finish,0.5)),"no-tick 120Hz frame advances display to midpoint")
	t.check(var_to_bytes(app.simulation.snapshot(app.state)) == saved,"no-tick interpolated frame leaves all Core state unchanged")
	app.set_user_pause(true)
	var paused: Dictionary = app.simulation.snapshot(app.state)
	app.advance_frame(0.75)
	t.check(app.world._camera == finish and app.simulation.snapshot(app.state) == paused,"pause freezes at authority without delayed catch-up")
	app.request_resume()
	t.check(app.world._camera == finish,"resume starts from frozen current position")
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var tick: int = app.state.active_tick
	app.advance_frame(8.0/60.0)
	t.check(app.state.active_tick == tick+8,"render interpolation does not alter eight-tick catch-up budget")
	var after := Vector2(app.state.player.position[0],app.state.player.position[1])
	var velocity := Vector2(app.state.player.velocity[0],app.state.player.velocity[1])
	t.check(app.world._camera.is_equal_approx(after-velocity/60.0),"controller captures each catch-up tick for the final adjacent pair")
	app.world.reset_presentation()
	app._present()
	t.check(app.world._camera == after,"explicit presentation reset seeds current without old-run movement")
	app.free()
