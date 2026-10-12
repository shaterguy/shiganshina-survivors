extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config(1,"doctrine_standard","evo_storm_chain"))
	if state.has("error_code"): return
	state.equipment = {"chain_lightning":5,"fire_zone":2}
	var before := state.duplicate(true)
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(View.new().build(state))
	var hud = ui.get_node("ProgressionHUD")
	var text: String = hud.display_text()
	t.check(text.contains("연쇄번개") and text.contains("화염지대") and text.contains("폭풍 연쇄"),"assembled current owned HUD names both fantasy attacks and selected ultimate")
	t.check(text.contains("MAX 5/5") and text.contains("Lv 2/5") and text.contains("2/3") and text.contains("0/1"),"current owned HUD exposes weapon cap, cross-skill requirement and missing boss seal")
	state.equipment.fire_zone = 3
	state.tactical_seals = 1
	ui.present_progression(View.new().build(state))
	t.check(hud.display_text().contains("진화 준비 완료"),"cross-skill Lv3 plus seal displays ready current ultimate")
	state.evolutions.chain_lightning = "evo_storm_chain"
	state.tactical_seals = 0
	ui.present_progression(View.new().build(state))
	t.check(hud.display_text().contains("폭풍 연쇄") and hud.display_text().contains("궁극"),"current owned HUD displays actual ultimate name after evolution")
	t.check(state.player == before.player and state.run_config == before.run_config,"current fantasy HUD reads combat authority without changing player or selection")
	ui.free()
