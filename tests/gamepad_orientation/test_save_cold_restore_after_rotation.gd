extends RefCounted
# Persistence regression only. No native controller or Android screen is faked
# into a real-device claim; Core/Store/Controller cold start are real.
const Support = preload("res://tests/app/controller_test_support.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	for mode in ["play","pause","upgrade"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(450,800)
		t.root.add_child(viewport)
		var support := Support.new()
		var fixture: Dictionary = support.make({"root":viewport})
		var app = fixture.app
		app.input_router.set_process(false)
		app.start_run(91)
		if mode == "pause": app.set_user_pause(true)
		elif mode == "upgrade": support.evolution_offer(app)
		await _settle(t)
		var before: Dictionary = app.simulation.snapshot(app.state)
		viewport.size = Vector2i(800,450)
		app._resize()
		await _settle(t)
		app._save_checkpoint()
		var disk: Dictionary = app.save_store.load_game().game_save
		t.check(disk.checkpoint == before,"real post-rotation checkpoint preserves complete combat/offer/pause state in "+mode)
		var expected: Dictionary = disk.checkpoint.duplicate(true)
		app.free()
		var restored = support.restart({"root":viewport},fixture.directory)
		restored.input_router.set_process(false)
		t.check(restored.state.is_empty() and restored.pending_checkpoint == expected,"cold startup retains the exact saved checkpoint pending explicit Continue in "+mode)
		t.check(restored.game_save == disk,"cold startup reads the exact saved authority without resetting the run in "+mode)
		restored.request_resume()
		for reason in ["user","background","controller_lost","slow_frame"]: expected.pause_reasons.erase(reason)
		t.check(restored.simulation.snapshot(restored.state) == expected,"cold Continue restores the rotated combat/offer and applies only the existing explicit-resume pause policy in "+mode)
		t.check(restored.state.active_tick == before.active_tick and restored.state.player.position == before.player.position and restored.state.upgrade_offer == before.upgrade_offer,"rotation/save/cold Continue advances no combat tick and retains level-up selection in "+mode)
		t.check(restored.input_router.sample_move() == Vector2.ZERO,"cold Continue uses existing neutral-input policy in "+mode)
		viewport.free()
