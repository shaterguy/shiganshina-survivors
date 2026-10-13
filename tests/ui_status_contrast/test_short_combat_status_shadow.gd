extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const HUD = preload("res://game/ui/progression_hud.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	var before: Dictionary = state.duplicate(true)
	var snapshot: Dictionary = sim.snapshot(state)
	var view: Dictionary = View.new().build(state)
	t.check(not view.is_empty() and not view.get("target",{}).is_empty(),"status contrast uses a real current Core target")
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(snapshot)
	ui.present_progression(view)
	for geometry in [{"size":Vector2i(360,800),"safe":Rect2i(0,0,360,800)},{"size":Vector2i(800,450),"safe":Rect2i(0,0,800,450)},{"size":Vector2i(360,800),"safe":Rect2i(12,24,336,748)}]:
		ui.reflow(geometry.size,geometry.safe)
		for frame in 6: await t.process_frame
		var target: Label = ui._owned_hud.get_node("TargetRequirements")
		t.check(ui._objective.text == ui.objective_text(snapshot) and target.text == HUD.target_summary(view.target),"contrast styling does not add or rewrite combat status copy")
		for label in [ui._objective,target]:
			var shadow: Color = label.get_theme_color("font_shadow_color")
			t.check(label.has_theme_color_override("font_shadow_color") and shadow.a >= 0.9 and maxf(shadow.r,maxf(shadow.g,shadow.b)) <= 0.15,"short combat status has a dark visible shadow above bright roofs: "+label.text)
			t.check(label.get_theme_constant("shadow_offset_x") == 1 and label.get_theme_constant("shadow_offset_y") == 1 and label.get_theme_constant("shadow_outline_size") == 0,"status shadow remains one thin offset pixel without a thick outline: "+label.text)
			t.check(label.is_visible_in_tree() and label.get_theme_font_size("font_size") == 13 and Rect2(geometry.safe).encloses(label.get_global_rect().grow(1)),"status font and its one-pixel shadow remain readable inside the same safe area")
		var safe: Rect2i = geometry.safe
		var portrait: bool = geometry.size.y > geometry.size.x
		var signature_height: int = 24 if ui._owned_hud.signature_visible() else 0
		t.check(ui._objective.position == Vector2(safe.position)+Vector2(8,162+signature_height if portrait else 52),"timer retains the existing product position")
		t.check(target.position == Vector2(20,69) and target.size == Vector2(ui._owned_hud.size.x-20,39),"target retains the existing 39px row geometry")
		t.check(not ui._hint.is_visible_in_tree() and ui._hint.text.is_empty(),"contrast does not reintroduce persistent manipulation instructions")
	t.check(state == before,"status styling and rotation leave Core state untouched")
	ui.free()
