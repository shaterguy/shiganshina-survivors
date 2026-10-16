extends RefCounted
# Real Core offers; only prerequisite ownership is arranged in the fixture.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Card = preload("res://game/ui/growth_card.gd")
func _settle(t) -> void:
	for frame in range(8): await t.process_frame
func _mouse(point: Vector2, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	return event
func _rows(ui, index: int) -> VBoxContainer:
	var card: Button = ui._growth_cards[index]
	var inside = card.get_node_or_null("Requirements")
	return inside if inside != null else ui._growth_groups[index].get_node("Requirements")
func run(t) -> void:
	var sim = F.simulation(t)
	var catalog := Catalog.new()
	var visited: Array[String] = []
	for id in ["evo_whirlwind"]:
		var recipe: Dictionary = catalog.evolutions.definition(id)
		var state: Dictionary = sim.new_run(F.chapter(),512,F.run_config(1,"doctrine_standard",str(id)))
		state.equipment = {recipe.base_item_id:5}
		state.passives = {}
		for material in recipe.get("required_equipment",[]): state.equipment[material.equipment_id] = int(material.level)
		for material in recipe.get("required_passives",[]): state.passives[material.passive_id] = int(material.level)
		for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
		t.check(sim.restore(state).get("ok",false),"inline UI fixture is an actual restorable current Core state: "+str(id))
		F.drop_xp(sim,state,Catalog.xp_to_next(int(state.player.level),state.rules.progression),"inline:xp:"+str(id))
		var view := View.new(catalog).build(state)
		var evolution_index := -1
		for index in view.get("active_offer",{}).get("options",[]).size():
			if view.active_offer.options[index].get("evolution_id","") == id: evolution_index = index
		t.check(evolution_index >= 0 and view.active_offer.options.size() == 3,"inline layout uses the actual Core final evolution among three choices: "+str(id))
		if evolution_index < 0: continue
		visited.append(str(id))
		var before_state := state.duplicate(true)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(800,450)
		t.root.add_child(viewport)
		var ui := UI.new()
		viewport.add_child(ui)
		var selected: Array = []
		ui.upgrade_chosen.connect(func(offer,option): selected.append([offer,option]))
		ui.present(sim.snapshot(state))
		ui.present_progression(view)
		for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800),Vector2i(640,360)]:
			viewport.size = screen
			ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
			await _settle(t)
			t.check(not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세"),"choice face has no relocated always-on manipulation instructions")
			for index in view.active_offer.options.size():
				var option: Dictionary = view.active_offer.options[index]
				var card: Button = ui._growth_cards[index]
				var info: Button = ui._growth_details[index]
				var rows := _rows(ui,index)
				var context := str(id)+" "+str(screen)+" "+str(option.option_id)
				t.check(ui._growth_groups[index].get_child_count() == 1 and rows.get_parent() == card and info.get_parent() == card,"no condition or information action consumes a separate outside-card row: "+context)
				t.check(info.is_visible_in_tree() and info.text == "i" and info.size.x >= 48 and info.size.y >= 48,"internal information retains its independent 48px native target: "+context)
				t.check(card.get_global_rect().encloses(info.get_global_rect()),"information target is fully inside the same visible choice border: "+context)
				t.check(info.get_global_rect().position.y-card.get_global_rect().position.y <= 18 and card.get_global_rect().end.x-info.get_global_rect().end.x <= 24,"information stays in the card upper-right corner: "+context)
				t.check(info.mouse_filter == Control.MOUSE_FILTER_STOP,"internal information consumes pointer input before its selecting parent: "+context)
				var native_style: StyleBox = card.get_theme_stylebox("normal")
				var body := Rect2(card.get_global_rect().position+Vector2(native_style.get_margin(SIDE_LEFT),native_style.get_margin(SIDE_TOP)),card.size-native_style.get_minimum_size())
				t.check(not body.intersects(info.get_global_rect()),"native skill identity and benefit area cannot sit behind the internal information target: "+context)
				var selected_attack := str(option.item_id) if option.kind in ["equipment","evolution","passive"] else ""
				var final_requirements: Array = option.requirements.filter(func(required): return required.item_id != selected_attack)
				var expected_rows: int = final_requirements.size() if option.kind == "evolution" else 0
				for preview in option.get("evolution_previews",[]): expected_rows += 1+preview.requirements.filter(func(required): return required.item_id != selected_attack).size()
				t.check(rows.get_child_count() == expected_rows,"cards show exactly their actual evolution criteria or early recipe title and criteria: "+context)
				var preview_row := 0
				for preview in option.get("evolution_previews",[]):
					var heading: Label = rows.get_child(preview_row)
					t.check(heading.text == "궁극 · "+preview.name,"early recipe heading names the exact ultimate for this skill: "+context)
					preview_row += 1
					for required in preview.requirements.filter(func(required): return required.item_id != selected_attack):
						var row: Control = rows.get_child(preview_row)
						var icon: TextureRect = row.get_node("Icon")
						var label: Label = row.get_node("Text")
						t.check(icon.texture != null and label.text == Card.evolution_requirement_text(required),"early criterion preserves its actual icon, name, current level, required level and fulfilment: "+context)
						t.check(card.get_global_rect().encloses(icon.get_global_rect()) and card.get_global_rect().encloses(label.get_global_rect()),"early recipe icon and wrapped text stay inside the card border: "+context)
						preview_row += 1
				if expected_rows > 0:
					t.check(not info.get_global_rect().intersects(rows.get_global_rect()) and not body.intersects(rows.get_global_rect()),"early and final recipe rows cannot obscure the information target or native skill text: "+context)
				if option.kind == "evolution":
					var level_row: String = card.get_node("CardTitle").text
					var level_width: float = card.get_theme_font("font").get_string_size(level_row,HORIZONTAL_ALIGNMENT_LEFT,-1,card.get_theme_font_size("font_size")).x
					var available_level_width: float = body.size.x-card.get_theme_constant("icon_max_width")-card.get_theme_constant("h_separation")
					t.check(level_row == option.name+" 5/6","final evolution title shows current progress and actual maximum: "+context)
					t.check(card.get_theme_font_size("font_size") >= 15 and card.get_node("CardTitle").size.x <= available_level_width+1 and card.get_node("CardTitle").get_line_count() >= 1,"final evolution title remains readable and wraps beside the 40px icon: "+context)
					t.check(rows.is_visible_in_tree() and card.get_global_rect().encloses(rows.get_global_rect()),"all combination requirements stay inside the evolution border: "+context)
					t.check(not info.get_global_rect().intersects(rows.get_global_rect()),"internal information never overlaps named combination requirements: "+context)
					t.check(not body.intersects(rows.get_global_rect()),"native skill name and benefit area cannot be covered by internal requirements: "+context)
					if card.size.x >= 480:
						t.check(rows.get_global_rect().position.x >= card.get_global_rect().get_center().x-1,"roomy cards use their right-side space for requirements: "+context)
					for row_index in rows.get_child_count():
						var row: Control = rows.get_child(row_index)
						var icon: TextureRect = row.get_node("Icon")
						var label: Label = row.get_node("Text")
						t.check(row.is_visible_in_tree() and icon.is_visible_in_tree() and label.is_visible_in_tree() and icon.texture != null and icon.size.x >= 18 and icon.size.y >= 18,"actual requirement silhouette and text remain visible: "+context)
						t.check(label.text.contains(str(final_requirements[row_index].name)) and label.text.contains("보유 ✓"),"complete skill name and held check remain together inside the card: "+context)
						t.check(card.get_global_rect().encloses(icon.get_global_rect()) and card.get_global_rect().encloses(label.get_global_rect()),"actual requirement icon and wrapped text cannot escape the card border: "+context)
				for focused in [card,info]:
					focused.grab_focus()
					await _settle(t)
					var clip: Rect2 = ui._scroll.get_global_rect().grow(1)
					t.check(clip.encloses(card.get_global_rect()),"controller focus reveals the complete internally grouped card: "+context)
					if rows.is_visible_in_tree(): t.check(clip.encloses(rows.get_global_rect()),"controller keeps the full internal criteria in the scroll clip: "+context)
				info.grab_focus()
				ui.accept_released()
				ui.navigate("accept")
				await _settle(t)
				t.check(ui._detail_id == "option:"+str(option.option_id) and selected.is_empty(),"A on internal information opens only its exact read-only detail")
				ui.navigate("cancel")
				await _settle(t)
				t.check(ui.get_viewport().gui_get_focus_owner() == info and selected.is_empty(),"B restores the same internal information focus without a choice")
				ui.accept_released()
				var point := info.get_global_rect().get_center()
				viewport.push_input(_mouse(point,true),true)
				t.check(info.is_pressed() and not card.is_pressed(),"actual GUI information down does not arm the selecting parent")
				viewport.push_input(_mouse(point,false),true)
				await _settle(t)
				t.check(ui._detail_id == "option:"+str(option.option_id) and selected.is_empty(),"actual internal information release never bubbles a selection")
				ui.navigate("cancel")
				await _settle(t)
			t.check(state == before_state,"all internal layout and information reading remain read-only Core presentation")
		ui._growth_cards[evolution_index].grab_focus()
		await _settle(t)
		var choose_point: Vector2 = ui._growth_cards[evolution_index].get_global_rect().position+Vector2(24,24)
		viewport.push_input(_mouse(choose_point,true),true)
		t.check(ui._growth_cards[evolution_index].is_pressed(),"actual main-card GUI down still arms the choice")
		viewport.push_input(_mouse(choose_point,false),true)
		await _settle(t)
		t.check(selected == [[view.active_offer.offer_id,view.active_offer.options[evolution_index].option_id]],"main card release emits exactly one current evolution intent")
		viewport.free()
	t.check(visited == ["evo_whirlwind"],"internal layout fixture actually visits its requested Core evolution")
