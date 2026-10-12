extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),71,F.run_config())
	var ui = UI.new()
	t.root.add_child(ui)
	for recipe in ["evo_wing_cut","evo_crossfire"]:
		state.run_config.target_evolution_id = recipe
		state.equipment = {"blade_slash":1}
		state.passives = {"armor":1,"attack_range":1,"damage":1,"pickup_radius":1}
		ui.present(sim.snapshot(state))
		ui.present_progression(View.new().build(state))
		for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
			var safe := Rect2i(12,8,screen.x-24,screen.y-16)
			ui.reflow(screen,safe)
			for frame in 5: await t.process_frame
			var target: Label = ui._owned_hud.get_node("TargetRequirements")
			t.check(Rect2(safe).encloses(target.get_global_rect()),"blocked target natural size respects safe inset "+recipe+str(screen))
			t.check(ui._owned_hud.get_global_rect().encloses(target.get_global_rect()),"Noto target natural two-line height stays within owned HUD "+str(screen))
			if screen.y > screen.x:
				t.check(target.get_global_rect().end.y <= ui._objective.get_global_rect().position.y,"target never enters objective row "+str(screen))
			t.check(target.text.contains("0/3") and target.text.contains("0/1") and target.text.contains("부족") and target.text.contains("슬롯"),"blocked target preserves every unmet requirement and slot explanation")
	ui.free()
