extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),71,F.run_config())
	var catalog := Catalog.new()
	var ui = UI.new()
	t.root.add_child(ui)
	for recipe in ["evo_wing_cut","evo_crossfire"]:
		state.run_config.target_evolution_id = recipe
		var definition: Dictionary = catalog.evolutions.definition(recipe)
		state.equipment = {definition.base_item_id:1}
		state.passives = {}
		var missing: Array[String] = []
		for material in definition.get("required_equipment",[]): missing.append(str(material.equipment_id))
		for material in definition.get("required_passives",[]): missing.append(str(material.passive_id))
		for id in catalog.equipment.keys():
			if state.equipment.size() < 4 and not id in missing: state.equipment[id] = 1
		for id in catalog.passives.keys():
			if state.passives.size() < 4 and not id in missing: state.passives[id] = 1
		ui.present(sim.snapshot(state))
		var view := View.new().build(state)
		t.check(not view.is_empty() and view.get("target",{}).get("status","") == "blocked","full slots and a genuinely missing material produce the real blocked target")
		ui.present_progression(view)
		for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
			var safe := Rect2i(12,8,screen.x-24,screen.y-16)
			ui.reflow(screen,safe)
			for frame in 5: await t.process_frame
			var target: Label = ui._owned_hud.get_node("TargetRequirements")
			t.check(target.is_visible_in_tree() and Rect2(safe).encloses(target.get_global_rect()),"blocked target natural size respects safe inset "+recipe+str(screen))
			t.check(ui._owned_hud.get_global_rect().encloses(target.get_global_rect()),"Noto target natural two-line height stays within owned HUD "+str(screen))
			if screen.y > screen.x:
				t.check(target.get_global_rect().end.y <= ui._objective.get_global_rect().position.y,"target never enters objective row "+str(screen))
			t.check(target.text.contains("슬롯") and target.tooltip_text.contains("미보유") and target.tooltip_text.contains("1/5"),"compact blocked target discloses slot reason and retains named complete criteria in its reader")
			t.check(not target.text.contains("보유 기술에서 조건 보기") and target.tooltip_text.contains("미보유"),"compact target avoids repeated navigation copy while its information keeps complete criteria")
	ui.free()
