extends RefCounted
func run(t) -> void:
	var apis := {
		"game/contracts/game_contracts.gd":["validate_snapshot"],
		"game/core/run_simulation.gd":["new_run","step","choose_upgrade","set_pause","set_offer_focus","abandon_run","snapshot","restore"],
		"game/director/spawn_director.gd":["plan"],
		"game/director/chapter_catalog.gd":["load_chapter"],
		"game/input/input_router.gd":["sample_move","clear_transient_input","handle_event","set_active"],
		"game/input/lifecycle_guard.gd":["map_safe_area"],
		"game/ui/game_ui.gd":["present","reflow","navigate","set_settings"],
		"game/persistence/save_store.gd":["save_checkpoint","load_checkpoint","save_profile","load_profile"],
		"game/app/run_controller.gd":["start_run","advance_frame","request_resume","request_end_run","checkpoint_matches_chapter"]
	}
	for path in apis:
		var instance = load("res://"+path).new()
		for method in apis[path]: t.check(instance.has_method(method),path+" exposes "+method)
		if path.ends_with("input_router.gd"):
			for signal_name in ["ui_action","active_controller_lost","input_hint_changed"]: t.check(instance.has_signal(signal_name),"router signal "+signal_name)
		if path.ends_with("game_ui.gd"):
			for signal_name in ["upgrade_chosen","upgrade_focus_changed","pause_changed","new_run_requested","resume_requested","settings_changed","end_run_requested","touch_move_changed"]: t.check(instance.has_signal(signal_name),"UI signal "+signal_name)
		if instance is Node: instance.free()
	var chapter: Dictionary = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter
	var sim = load("res://game/core/run_simulation.gd").new()
	var state: Dictionary = sim.new_run(chapter,42,load("res://tests/core/core_fixture.gd").run_config())
	state.active_tick = 17999
	state.survival_tick = 17999
	var original := state.duplicate(true)
	var planned: Array[Dictionary] = load("res://game/director/spawn_director.gd").new().plan(state,chapter)
	t.check(not planned.is_empty() and state == original,"director plans actual boss boundary without mutating snapshot")
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	ui.present(state)
	ui.reflow(Vector2i(450,800),Rect2i(0,0,450,800))
	await t.process_frame
	await t.process_frame
	await t.process_frame
	t.check(state == original,"UI presentation and reflow never mutate core state")
	ui.free()
