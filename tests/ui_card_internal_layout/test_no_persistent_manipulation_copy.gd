extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _labels(node: Node) -> String:
	var visible_text: String = node.text+"\n" if (node is Label or node is Button) and node.is_visible_in_tree() else ""
	for child in node.get_children(): visible_text += _labels(child)
	return visible_text
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),621,F.run_config())
	var ui := UI.new()
	t.root.add_child(ui)
	for screen in [Vector2i(360,800),Vector2i(450,800),Vector2i(800,450),Vector2i(640,360)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		for kind in ["touch","gamepad"]:
			ui.set_input_hint(kind)
			ui.present(sim.snapshot(state))
			for frame in range(6): await t.process_frame
			t.check(not ui._hint.is_visible_in_tree() and ui._hint.text.is_empty(),"play has no persistent movement or automatic-attack instruction: "+str(screen)+kind)
			var visible := _labels(ui)
			t.check(not visible.contains("드래그해 이동") and not visible.contains("스틱/D-pad 이동"),"removed manipulation copy is not relocated into another visible label")
	F.drop_xp(sim,state,24,"no-hint:xp")
	ui.present(sim.snapshot(state))
	ui.present_progression(View.new().build(state))
	for frame in range(6): await t.process_frame
	t.check(ui._mode == "upgrade" and not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세"),"growth keeps the real offer without obvious always-on action instructions")
	t.check(not _labels(ui).contains("터치/A 선택") and not _labels(ui).contains("i 상세"),"growth action instructions are deleted rather than moved outside the subtitle")
	ui.free()
