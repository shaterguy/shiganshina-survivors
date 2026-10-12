extends RefCounted
func run(t) -> void:
	var app = load("res://tests/app/controller_test_support.gd").new().make(t).app
	app.start_run(45)
	# Arranged finite pre-final state; actual command enters the final phase.
	# This does not certify streamed passage or a full-length chapter playthrough.
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	app.advance_frame(1.0/60.0)
	var skipped := 112499-int(app.state.active_tick)
	app.state.active_tick = 112499
	# Preserve the physical final action's remaining phase during this arranged
	# pre-exit settlement fixture; the full director test executes all4500ticks.
	for entity in app.state.entities:
		for field in ["action_started_tick","action_ends_tick","next_action_tick"]: entity[field] = int(entity[field])+skipped
	for hazard in app.state.telegraphs:
		for field in ["created_tick","active_from_tick","expires_tick"]: hazard[field] = int(hazard[field])+skipped
	app.state.player.position = [0,350]
	t.check(app.simulation.restore(app.state).get("ok",false),"arranged finite pre-exit state passes actual Core restore")
	app.advance_frame(1.0/60.0)
	t.check(app.state.phase == "won","result fixture reaches valid evacuation win")
	var profile: Dictionary = app.save_store.load_game().game_save.profile
	t.check("chapter_01_shiganshina" in profile.cleared_chapter_ids,"chapter clear persists in profile")
	t.check(profile.best_runs.has("chapter_01_shiganshina"),"best run persists for future chapter expansion")
	app.free()
