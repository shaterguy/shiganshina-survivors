extends RefCounted
func run(t) -> void:
	var app = load("res://game/app/run_controller.gd").new()
	app.save_store = load("res://game/persistence/save_store.gd").new("user://result_"+str(OS.get_process_id()))
	t.root.add_child(app)
	app.set_process(false)
	app.start_run(45)
	# Valid near-exit checkpoint fixture; production time remains30min+75sec.
	app.state.active_tick = 112499
	app.state.survival_tick = 108000
	app.state.final_started_tick = 108000
	app.state.phase = "evacuation"
	app.state.boss_ids_fired = ["ch01_b05","ch01_b10","ch01_b15","ch01_b20","ch01_b25","ch01_final_armored"]
	app.state.player.position = [0,350]
	app.advance_frame(1.0/60.0)
	t.check(app.state.phase == "won","result fixture reaches valid evacuation win")
	var profile: Dictionary = app.save_store.load_profile().profile
	t.check("chapter_01_shiganshina" in profile.cleared_chapter_ids,"chapter clear persists in profile")
	t.check(profile.best_runs.has("chapter_01_shiganshina"),"best run persists for future chapter expansion")
	app.free()
