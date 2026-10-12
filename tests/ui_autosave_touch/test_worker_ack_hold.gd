extends "res://tests/app_async_autosave/test_default_worker.gd"
# Real Controller, Core, disk store and asynchronous worker. Only input events
# are supplied by the test; no synthetic ACK or replacement input is injected.
func run(t) -> void:
	var app = _fixture(t,"held_touch_ack")
	if app == null: return
	app.ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
	var press := InputEventScreenTouch.new()
	press.index = 7
	press.pressed = true
	press.position = Vector2(100,300)
	app.ui._input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = press.index
	drag.position = Vector2(136,300)
	app.ui._input(drag)
	t.check(app.input_router.sample_move() == Vector2.RIGHT,"actual held touch reaches the Controller input router")
	for iteration in 2:
		var revision: int = app.game_save.store_revision
		app._save_checkpoint()
		await _drain(t,app)
		t.check(app.game_save.store_revision == revision+1,"real asynchronous save ACK adopted exactly once")
		t.check(app.ui._touch_id == press.index and app.input_router.sample_move() == Vector2.RIGHT,"real save ACK preserves held touch without reinjecting movement")
	press.pressed = false
	app.ui._input(press)
	t.check(app.input_router.sample_move() == Vector2.ZERO,"physical release still clears the Controller after ACK")
	app.free()
