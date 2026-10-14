extends RefCounted
# Pixel review found ordinary growth masquerading as a gated evolution choice.
# Use the actual ordinary Core offer and actual target context, not injected DTOs.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Card = preload("res://game/ui/growth_card.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = F.earn_offer(sim,21,24)
	var before := state.duplicate(true)
	var view := View.new().build(state)
	t.check(not view.get("active_offer",{}).is_empty() and not view.get("target",{}).get("requirements",[]).is_empty(),"actual ordinary offer retains an unrelated target condition context")
	if view.get("active_offer",{}).is_empty(): return
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	var ordinary_checked := 0
	for screen in [Vector2i(360,800),Vector2i(800,450)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		for frame in range(6): await t.process_frame
		for index in view.active_offer.options.size():
			var option: Dictionary = view.active_offer.options[index]
			if option.kind == "evolution": continue
			ordinary_checked += 1
			var rows: VBoxContainer = ui._growth_cards[index].get_node("Requirements")
			var card: Button = ui._growth_cards[index]
			var expected_rows := 0
			for recipe in option.evolution_previews:
				var shown: Array = recipe.requirements.filter(func(required): return option.kind != "equipment" or required.item_id != option.item_id)
				expected_rows += 1+shown.size()
				t.check(card.tooltip_text.contains("궁극 · "+recipe.name),"ordinary detail names this skill's own future ultimate")
				for required in shown:
					t.check(card.tooltip_text.contains(Card.evolution_requirement_text(required)),"own recipe retains every other named prerequisite and fulfilment")
			t.check(rows.get_child_count() == expected_rows and rows.is_visible_in_tree() == (expected_rows > 0),"ordinary card displays only its own early recipes, not an unrelated run target")
			t.check(not card.disabled and not card.tooltip_text.contains("목표 진화 조건"),"unmet future recipe does not gate normal selection or masquerade as unrelated target conditions")
		var subtitle: Label = ui._subtitle
		if screen.x < screen.y:
			t.check(subtitle.text.begins_with("무기") and subtitle.text.contains("보조") and not subtitle.text.contains("터치/A") and not subtitle.text.contains("i 상세"),"mobile growth keeps a complete Korean-word slot row without an instruction heading")
		for line in subtitle.text.split("\n"):
			var width: float = subtitle.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,subtitle.get_theme_font_size("font_size")).x
			t.check(width <= subtitle.size.x,"each authored subtitle row fits without splitting a Korean skill-slot word")
	t.check(ordinary_checked > 0,"ordinary condition-scope assertions really execute on actual offers")
	t.check(state == before,"choice scope and readable slot summary never change progression authority")
	ui.free()
