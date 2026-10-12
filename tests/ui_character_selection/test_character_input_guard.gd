extends RefCounted
const F = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Service = preload("res://game/economy/supply_service.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var save: Dictionary = F.new().game_save()
	save.profile.cleared_chapter_ids = ["chapter_01_shiganshina"]
	save.profile.unlocked_character_ids.append("mikasa_01")
	var service := Service.new(Callable())
	var view := service.shop_view(save)
	view.view_revision = 10
	var ui = UI.new()
	t.root.add_child(ui)
	ui.present_supply(view)
	ui.open_loadout()
	var actions: Array = []
	ui.character_selected.connect(func(id,revision):
		actions.append([id,revision])
		# DTO fixture for synchronous authority ACK; actual disk tested separately.
		save.profile.selected_character_id = id
		var next := service.shop_view(save)
		next.view_revision = revision+1
		ui.present_action_result({"ok":true,"action":"character_selection"})
		ui.present_supply(next))
	ui._restore_focus("character:mikasa_01")
	ui.navigate("accept")
	t.check(actions.size() == 1 and ui.focused_semantic_id() == "character:mikasa_01","selection ACK retains the selected character focus")
	ui.navigate("left")
	ui.navigate("accept")
	t.check(actions.size() == 1,"held A cannot select another character across authority ACK")
	ui.accept_released()
	ui.navigate("accept")
	t.check(actions.size() == 2 and actions[1][0] == "garrison_01","fresh A may select the previous character")
	for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
		ui.reflow(screen,Rect2i(12,24,screen.x-24,screen.y-48))
		for row in ui._supply_view.character_options:
			ui._restore_focus("character:"+row.id)
			for frame in 5: await t.process_frame
			var button: Button = ui._supply_panel.option_button("character_id",row.id)
			t.check(ui.focused_semantic_id() == "character:"+row.id,"locked and planned character information stays keyboard readable")
			t.check(ui._scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),"safe inset preserves complete character card "+str(screen)+row.id)
	var alien: Button = ui._add_button("not a character",func(): pass)
	alien.disabled = true
	alien.set_meta("semantic_id","character:mikasa_01")
	t.check(not ui._can_focus_button(alien),"metadata alone does not authorize disabled character focus")
	var real: Button = ui._supply_panel.option_button("character_id","eren_01")
	real.hide()
	t.check(not ui._can_focus_button(real),"hidden character card cannot receive read focus")
	ui.free()
