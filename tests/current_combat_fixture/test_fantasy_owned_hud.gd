extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config(1,"doctrine_standard","evo_storm_chain"))
	if state.has("error_code"): return
	state.equipment = {"chain_lightning":5}
	var before := state.duplicate(true)
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(View.new().build(state))
	var hud = ui.get_node("ProgressionHUD")
	var text: String = hud.display_text()
	t.check(hud.slot_controls()[0].tooltip_text.contains("연쇄번개") and hud.slot_controls()[0].get_node("Icon").texture != null and text.contains("폭풍 연쇄") and not text.contains("화염지대"),"HUD identifies the owned attack by its real icon/information and never claims the unowned partner")
	var target: Label = hud.get_node("TargetRequirements")
	t.check(hud.slot_controls()[0].get_node("Status").text == "5/6" and target.text.contains("재료 부족"),"visible HUD exposes attack-six cap and unmet target state")
	t.check(target.tooltip_text.contains("미보유") and target.tooltip_text.contains("화염지대"),"separate target tooltip names the missing prerequisite")
	state.equipment.fire_zone = 1
	ui.present_progression(View.new().build(state))
	t.check(hud.get_node("TargetRequirements").text.contains("준비"),"cross-skill level one displays ready evolution without a seal")
	state.evolutions.chain_lightning = "evo_storm_chain"
	state.tactical_seals = 0
	ui.present_progression(View.new().build(state))
	t.check(hud.slot_controls()[0].tooltip_text.contains("폭풍 연쇄") and hud.slot_controls()[0].get_node("Status").text == "6/6" and not hud.get_node("TargetRequirements").is_visible_in_tree(),"current evolved HUD preserves actual name information and sixth level without repeated completion text")
	t.check(state.player == before.player and state.run_config == before.run_config,"current fantasy HUD reads combat authority without changing player or selection")
	ui.free()
