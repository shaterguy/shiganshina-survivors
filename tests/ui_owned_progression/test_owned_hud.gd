extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = sim.new_run(Fixture.chapter(),71,Fixture.run_config())
	state.equipment = {"blade_slash":5,"reentry_combo":5,"wall_cannon":2}
	state.passives = {"movement":2,"damage":5}
	var before := state.duplicate(true)
	var ui = UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(View.new().build(state))
	var hud = ui.get_node_or_null("ProgressionHUD")
	t.check(hud != null,"combat has a persistent owned progression HUD")
	if hud == null:
		ui.free()
		return
	t.check(hud.slot_controls().size() == 8,"HUD keeps four equipment and four passive slots")
	var text: String = hud.display_text()
	var expected_levels := {"blade_slash":"5/6","reentry_combo":"5/6","wall_cannon":"2/6","movement":"2/5","damage":"5/5"}
	for slot in hud.slot_controls():
		var id := str(slot.get_meta("item_id",""))
		if id.is_empty():
			t.check(slot.get_node("Name").text.is_empty() and slot.get_node("Status").text.is_empty() and slot.get_node("Icon").texture == null,"empty HUD slots never label a fake held skill")
		else:
			t.check(slot.get_node("Status").text == expected_levels[id] and slot.get_node("Icon").texture != null,"HUD preserves each actual skill identity and its exact attack-six/passive-five cap")
	var target_info: Label = hud.get_node("TargetRequirements")
	t.check(target_info.text.contains("재료 부족") and not target_info.text.contains("보유 기술에서 조건 보기"),"visible target keeps unmet state without repeating reader instructions")
	t.check(target_info.tooltip_text.contains("입체기동 돌진") and target_info.tooltip_text.contains("미보유"),"target tooltip separately retains the named level-one partner criterion")
	t.check(state == before,"initial HUD presentation never changes gameplay authority")
	var ids: Array = []
	for control in hud.slot_controls(): ids.append(control.get_instance_id())
	for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
		var safe := Rect2i(12,8,screen.x-24,screen.y-16)
		ui.reflow(screen,safe)
		for frame in 5: await t.process_frame
		t.check(Rect2(safe).encloses(hud.get_global_rect()),"HUD respects safe area "+str(screen))
		for control in hud.slot_controls():
			t.check(hud.get_global_rect().encloses(control.get_global_rect()),"fixed slot stays inside HUD "+str(screen))
			var status: Label = control.get_node("Status")
			t.check(status.size.x+0.5 >= status.get_minimum_size().x,"numeric level and MAX are not clipped "+str(screen))
		var target: Label = hud.get_node("TargetRequirements")
		for line in target.text.split("\n"):
			t.check(target.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x <= target.size.x,"every target condition fits without clipping "+str(screen))
		var generation: int = ui._layout_generation
		for frame in 5: ui.present(sim.snapshot(state)); await t.process_frame
		t.check(ui._layout_generation == generation,"idle HUD does not cause frame-level relayout")
	for index in 8: t.check(ids[index] == hud.slot_controls()[index].get_instance_id(),"HUD reuses fixed slot controls")
	state.passives.movement = 3
	state.equipment.odm_dash = 1
	ui.present_progression(View.new().build(state))
	t.check(target_info.text.contains("준비") and not target_info.text.contains("보유 기술에서 조건 보기"),"ready target uses one short authored-name/status row")
	ui.reflow(Vector2i(320,568),Rect2i(12,8,296,552))
	var target: Label = hud.get_node("TargetRequirements")
	for line in target.text.split("\n"):
		t.check(target.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x <= target.size.x,"ready conditions fit smallest supported width")
	state.evolutions.blade_slash = "evo_wing_cut"
	state.tactical_seals = 0
	ui.present_progression(View.new().build(state))
	t.check(hud.slot_controls()[0].tooltip_text.contains("입체기동 연속참") and hud.slot_controls()[0].get_node("Status").text == "6/6" and not target_info.is_visible_in_tree(),"evolved icon keeps its full actual information and numeric level without a duplicate completed target row")
	ui.present_progression({})
	t.check(hud.display_text().contains("기술 정보 확인 중") and not hud.display_text().contains("Lv 0/5"),"missing DTO never invents levels")
	t.check(before.player == state.player and state.equipment == {"blade_slash":5,"reentry_combo":5,"wall_cannon":2,"odm_dash":1},"UI preserves authority after the test explicitly acquires its partner")
	ui.free()
