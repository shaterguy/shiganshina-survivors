extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	app.start_run(85)
	if app.state.is_empty():
		t.check(false,"real run is available for shop modal boundary")
		app.free()
		return
	app.advance_frame(1.0/60.0)
	var tick: int = app.state.active_tick
	app.ui.open_supply_shop()
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var position: Array = app.state.player.position.duplicate()
	app.advance_frame(1.0)
	t.check(app.state.active_tick == tick,"shop modal owns the clock even without a persisted Core pause tag")
	t.check(app.state.player.position == position,"held movement cannot move behind shop modal")
	t.check(app.audio._music.stream_paused,"combat music pauses behind shop modal")
	t.check(not "shop" in app.state.pause_reasons,"transient shop view is not written into the Core pause schema")
	var restored: Dictionary = app.save_store.load_game()
	t.check(restored.ok,"shop presentation preserves a valid durable authority")
	app.ui.close_supply_shop()
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick+1,"closing modal advances only one fresh tick with no backlog")
	app.free()
