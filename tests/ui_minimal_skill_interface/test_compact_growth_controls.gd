extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _mouse(point: Vector2, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	return event
func run(t) -> void:
	var sim = F.simulation(t)
	var catalog := Catalog.new()
	var recipe: Dictionary = catalog.evolutions.definition("evo_whirlwind")
	var state: Dictionary = sim.new_run(F.chapter(),621,F.run_config(1,"doctrine_standard","evo_whirlwind"))
	state.equipment = {recipe.base_item_id:5}
	state.passives = {}
	for material in recipe.get("required_equipment",[]): state.equipment[material.equipment_id] = int(material.level)
	for material in recipe.get("required_passives",[]): state.passives[material.passive_id] = int(material.level)
	for id in state.equipment: state.player.attack_ready_ticks[id] = 2147483647
	t.check(sim.restore(state).get("ok",false),"minimal choice fixture restores the actual authored prerequisites")
	F.drop_xp(sim,state,Catalog.xp_to_next(int(state.player.level),state.rules.progression),"minimal:xp")
	var view := View.new(catalog).build(state)
	t.check(view.get("active_offer",{}).get("options",[]).size() == 3,"compact layout really presents three actual Core choices")
	if view.get("active_offer",{}).get("options",[]).size() != 3: return
	var viewport_root := SubViewport.new()
	viewport_root.size = Vector2i(800,450)
	t.root.add_child(viewport_root)
	var ui := UI.new()
	viewport_root.add_child(ui)
	var selected: Array = []
	ui.upgrade_chosen.connect(func(offer,id): selected.append([offer,id]))
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	var evolution_index := -1
	for index in view.active_offer.options.size():
		if view.active_offer.options[index].get("evolution_id","") == "evo_whirlwind": evolution_index = index
	t.check(evolution_index >= 0,"compact controls include the real final evolution")
	for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800),Vector2i(640,360)]:
		viewport_root.size = screen
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		t.check(not ui._target_button.is_visible_in_tree(),"growth selection has no duplicate full-width target-reader action")
		t.check(not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세"),"selection face omits persistent manipulation instructions")
		for index in view.active_offer.options.size():
			var option: Dictionary = view.active_offer.options[index]
			var card: Button = ui._growth_cards[index]
			var info: Button = ui._growth_details[index]
			t.check(not card.face_text().contains("선택") and not card.face_text().contains("자세히") and card.face_text().split("\n").size() <= 3,"choice face contains only identity, level and one short change")
			t.check(card.icon != null and card.get_theme_constant("icon_max_width") >= 40 and (card.expand_icon or card.icon.get_width() >= 40),"choice actually allows its reused or generated skill icon to render at 40px")
			if card.icon != null and card.face_text().split("\n").size() >= 2:
				var benefit: String = card.face_text().split("\n")[1]
				var measured := card.get_theme_font("font").get_string_size(benefit,HORIZONTAL_ALIGNMENT_LEFT,-1,card.get_theme_font_size("font_size")).x
				var icon_width := float(card.get_theme_constant("icon_max_width")) if card.expand_icon else minf(card.icon.get_width(),card.get_theme_constant("icon_max_width"))
				var available := card.size.x-card.get_theme_stylebox("normal").get_minimum_size().x-icon_width-card.get_theme_constant("h_separation")
				if measured > available:
					print("UI_BENEFIT_WIDTH "+JSON.stringify({"screen":[screen.x,screen.y],"option_id":option.option_id,"name":option.name,"benefit":benefit,"measured":measured,"available":available,"card_size":[card.size.x,card.size.y],"style_min_x":card.get_theme_stylebox("normal").get_minimum_size().x,"icon_width":icon_width,"font_size":card.get_theme_font_size("font_size")}))
				t.check(measured <= available,"actual measured benefit stays one readable row beside the large icon")
			t.check(info.text.strip_edges() == "i" and info.size.x >= 48 and info.size.y >= 48 and info.size.x <= 50,"information is a small glyph with a full independent 48px hit target")
			t.check(card.get_global_rect().encloses(info.get_global_rect()) and info.mouse_filter == Control.MOUSE_FILTER_STOP,"internal information keeps an independent pointer target inside the choice border")
			var rows: VBoxContainer = card.get_node("Requirements")
			var selected_attack := str(option.item_id) if option.kind in ["equipment","evolution","passive"] else ""
			var expected_rows: int = option.requirements.filter(func(required): return required.item_id != selected_attack).size() if option.kind == "evolution" else 0
			for preview in option.get("evolution_previews",[]): expected_rows += 1+preview.requirements.filter(func(required): return required.item_id != selected_attack).size()
			t.check(rows.get_child_count() == expected_rows,"early and final choices show their actual other conditions without repeating the selected attack")
			card.grab_focus()
			await _settle(t)
			var viewport: Rect2 = ui._scroll.get_global_rect().grow(1)
			t.check(viewport.encloses(card.get_global_rect()),"large-icon choice remains fully readable after actual focus")
			if screen == Vector2i(450,800):
				for group in ui._growth_groups:
					t.check(viewport.encloses(group.get_global_rect()),"450px portrait shows all three complete choice groups without trimming material names")
			ui.navigate("right")
			await _settle(t)
			t.check(ui.get_viewport().gui_get_focus_owner() == info,"controller focus goes from choice to its separate information action")
			ui.accept_released()
			ui.navigate("accept")
			await _settle(t)
			t.check(ui._mode == "evolution_detail" and ui._detail_id == "option:"+str(option.option_id) and selected.is_empty(),"A on the information action opens only its read-only detail")
			ui.navigate("cancel")
			await _settle(t)
			t.check(ui._mode == "upgrade" and ui.get_viewport().gui_get_focus_owner() == info and selected.is_empty(),"B restores the same information focus without choosing a skill")
			ui.accept_released()
			var point := info.get_global_rect().get_center()
			viewport_root.push_input(_mouse(point,true),true)
			t.check(info.is_pressed() and not card.is_pressed(),"actual GUI pointer holds only the independent information hit target")
			viewport_root.push_input(_mouse(point,false),true)
			await _settle(t)
			t.check(ui._mode == "evolution_detail" and ui._detail_id == "option:"+str(option.option_id) and selected.is_empty(),"fresh GUI information press and release opens details without selecting")
			ui.navigate("cancel")
			await _settle(t)
			t.check(ui._mode == "upgrade" and ui.get_viewport().gui_get_focus_owner() == info and selected.is_empty(),"B after GUI information returns to the independent information target")
	if evolution_index >= 0:
		ui._growth_cards[evolution_index].grab_focus()
		ui.accept_released()
		ui.navigate("accept")
		t.check(selected == [[view.active_offer.offer_id,view.active_offer.options[evolution_index].option_id]],"fresh A on the separate main choice still emits exactly one real evolution intent")
		var result: Dictionary = sim.choose_upgrade(state,selected[0][0],selected[0][1]) if selected.size() == 1 else {}
		t.check(result.get("ok",false),"compact choice intent still selects the actual Core final stage")
		ui.present(sim.snapshot(state))
		ui.present_progression(View.new(catalog).build(state))
		await _settle(t)
		var slot: Control = ui._owned_hud.slot_controls()[0]
		t.check(slot.get_node("Status").text == "6/6" and slot.get_node("Icon").texture != null and slot.get_node("Status").is_visible_in_tree() and slot.get_node("Icon").is_visible_in_tree(),"completed HUD visibly keeps the actual evolved shape and sixth/max level")
		t.check(slot.tooltip_text.contains(recipe.name),"full acquired evolution name remains available through explicit information")
		var support: Control = ui._owned_hud.slot_controls()[4]
		var support_icon: TextureRect = support.get_node("Icon")
		var support_level: Label = support.get_node("Status")
		t.check(support.get_meta("item_id","") == "movement" and support_level.text == "1/5","actual Core combination material uses the support fifth-stage maximum")
		t.check(support_icon.texture != null and support_icon.is_visible_in_tree() and support_level.is_visible_in_tree() and support_icon.size.x >= 24 and support_icon.size.y >= 24,"actual acquired support has a visible readable silhouette and level")
		t.check(ui._owned_hud.get_global_rect().encloses(support_icon.get_global_rect()) and ui._owned_hud.get_global_rect().encloses(support_level.get_global_rect()),"actual support icon and numeric level remain inside HUD bounds")
		t.check(not ui._owned_hud.get_node("TargetRequirements").is_visible_in_tree() and not ui._owned_hud.get_node("TargetIcon").is_visible_in_tree(),"completed target is not repeated below its evolved HUD slot")
	viewport_root.free()
