extends RefCounted
# Arranged prerequisites are not natural-leveling evidence. The XP collection,
# Core offer queue, materializer, DTO and every displayed Control are real.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _visible_rows(t, ui, rows: VBoxContainer, context: String) -> void:
	var viewport: Rect2 = ui._scroll.get_global_rect().grow(1)
	t.check(rows.get_child_count() == 2,"actual final evolution has base and combination-material rows: "+context)
	t.check(rows.is_visible_in_tree(),"actual prerequisite rows are visible in the current modal tree: "+context)
	for row in rows.get_children():
		var icon: TextureRect = row.get_node("Icon")
		var label: Label = row.get_node("Text")
		t.check(row.is_visible_in_tree() and icon.is_visible_in_tree() and label.is_visible_in_tree(),"actual prerequisite shape and full name are visible Controls: "+context)
		t.check(icon.size.x >= 18 and icon.size.y >= 18,"actual prerequisite shape retains at least an 18px reading size: "+context)
		t.check(icon.texture != null and label.text.contains("보유 ✓"),"actual prerequisite icon and held-state label are rendered together: "+context)
		t.check(viewport.encloses(icon.get_global_rect()) and viewport.encloses(label.get_global_rect()),"actual prerequisite icon and full label stay inside the scroll viewport: "+context)
func run(t) -> void:
	var sim = F.simulation(t)
	var catalog := Catalog.new()
	var visited: Array[String] = []
	for id in catalog.evolutions.ids():
		var recipe: Dictionary = catalog.evolutions.definition(id)
		var state: Dictionary = sim.new_run(F.chapter(),512,F.run_config(1,"doctrine_standard",str(id)))
		t.check(not state.has("error_code"),"real current Core creates UI fixture for "+str(id))
		if state.has("error_code"): continue
		state.equipment = {recipe.base_item_id:5}
		state.passives = {}
		for material in recipe.get("required_equipment",[]): state.equipment[material.equipment_id] = int(material.level)
		for material in recipe.get("required_passives",[]): state.passives[material.passive_id] = int(material.level)
		for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
		t.check(sim.restore(state).get("ok",false),"UI prerequisites retain an actual restorable Core state: "+str(id))
		F.drop_xp(sim,state,24,"ui:xp:"+str(id))
		var view := View.new(catalog).build(state)
		var index := -1
		for slot in view.get("active_offer",{}).get("options",[]).size():
			var option: Dictionary = view.active_offer.options[slot]
			if option.get("kind","") == "evolution" and option.get("evolution_id","") == id: index = slot
		t.check(index >= 0,"real XP queues and materializes the requested final evolution: "+str(id))
		if index < 0: continue
		visited.append(str(id))
		var before := state.duplicate(true)
		var ui := UI.new()
		t.root.add_child(ui)
		ui.present(sim.snapshot(state))
		ui.present_progression(view)
		for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800)]:
			ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
			await _settle(t)
			var rows: VBoxContainer = ui._growth_cards[index].get_node("Requirements")
			var card: Button = ui._growth_cards[index]
			var details: Button = ui._growth_details[index]
			t.check(rows.get_parent() == card and details.get_parent() == card and card.get_global_rect().encloses(rows.get_global_rect()) and card.get_global_rect().encloses(details.get_global_rect()),"all eight actual evolutions keep requirements and information inside their own choice border")
			t.check(card.text.contains(recipe.name) and card.icon != null and card.text.contains("5/6") and card.text.contains("6/6"),"real final choice shows its authored name, icon and sixth stage")
			for focused in [card,details]:
				focused.grab_focus()
				await _settle(t)
				_visible_rows(t,ui,rows,str(id)+str(screen)+str(focused.get_meta("semantic_id","")))
			var target: Label = ui._owned_hud.get_node("TargetRequirements")
			t.check(target.is_visible_in_tree() and ui._owned_hud.get_global_rect().grow(1).encloses(target.get_global_rect()),"actual target label stays visible within the HUD bounds")
			t.check(target.text.begins_with(str(recipe.name)),"visible target uses the actual authored evolution name")
			ui.open_evolution_details(str(id))
			await _settle(t)
			var panel
			for child in ui._choices.get_children():
				if child.has_method("display_text"): panel = child
			t.check(panel != null,"actual target opens the existing detail panel")
			if panel != null:
				var detail_rows: VBoxContainer = panel.get_node("Requirements")
				var bar: VScrollBar = ui._scroll.get_v_scroll_bar()
				var steps := int(ceil(maxf(0,bar.max_value-bar.page)/96.0))+1
				for step in steps:
					if ui._scroll.get_global_rect().grow(1).encloses(detail_rows.get_global_rect()): break
					var before_scroll: int = ui._scroll.scroll_vertical
					ui.navigate("down")
					await _settle(t)
					if ui._scroll.scroll_vertical == before_scroll: break
				_visible_rows(t,ui,detail_rows,"target detail "+str(id)+str(screen))
			ui.close_evolution_details()
			await _settle(t)
			t.check(state == before,"all actual icon/condition/detail presentation remains read-only")
		ui.free()
	t.check(visited.size() == 8,"the live UI integration test really exercises all eight final evolutions")
