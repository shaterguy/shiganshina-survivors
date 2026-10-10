extends RefCounted
func run(t) -> void:
	var path := "res://game/app/run_controller.gd"
	t.check(FileAccess.file_exists(path),"RunController exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	t.check(script != null and script.can_instantiate(),"RunController compiles")
	if script == null or not script.can_instantiate(): return
	var app = script.new()
	app.save_store = load("res://game/persistence/save_store.gd").new("user://app_vertical_"+str(OS.get_process_id()))
	t.root.add_child(app)
	app.set_process(false)
	app.start_run(42)
	for frame in range(1800):
		var move := Vector2.ZERO
		if not app.state.entities.is_empty():
			var player := Vector2(app.state.player.position[0],app.state.player.position[1])
			var nearest := Vector2(10000,10000)
			for enemy in app.state.entities:
				var offset := Vector2(enemy.position[0],enemy.position[1])-player
				if offset.length() < nearest.length(): nearest = offset
			if nearest.length() > 65: move = nearest.normalized()
			elif nearest.length() < 45: move = -nearest.normalized()
			else: move = nearest.normalized().orthogonal()
		app.input_router.set_touch_vector(move)
		app.advance_frame(1.0/60.0)
		if not app.state.upgrade_offer.is_empty():
			var offer: Dictionary = app.state.upgrade_offer
			app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(app.state.active_tick == 1800,"first30 seconds advance exactly")
	t.check(app.state.stats.kills > 0,"real director and core produce kills")
	t.check(app.state.player.level >= 2,"first growth choice reached in30seconds")
	var tick: int = app.state.active_tick
	app.set_user_pause(true)
	app.advance_frame(1.0)
	t.check(app.state.active_tick == tick,"pause freezes app loop")
	app.request_resume()
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick+1,"resume uses explicit request")
	app.free()
