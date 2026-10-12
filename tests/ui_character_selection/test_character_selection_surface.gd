extends RefCounted
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Service = preload("res://game/economy/supply_service.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var save: Dictionary = Fixture.new().game_save()
	var service := Service.new(Callable())
	var view := service.shop_view(save)
	var ui = UI.new()
	t.root.add_child(ui)
	ui.present_supply(view)
	ui.open_loadout()
	var panel = ui._supply_panel
	var locked: Button = panel.option_button("character_id","mikasa_01")
	t.check(locked != null,"existing loadout displays authoritative character choices")
	if locked == null:
		ui.free()
		return
	t.check(locked.disabled and locked.text.contains("시나리오") and locked.text.contains("클리어"),"first run explains clear requirement and cannot change protagonist")
	t.check(locked.text.contains("미구현") and locked.text.contains("시제품"),"prototype character never claims finished unique skills or art")
	var events: Array = []
	ui.character_selected.connect(func(id,revision): events.append([id,revision]))
	locked.pressed.emit()
	t.check(events.is_empty(),"locked direct signal cannot select a character")
	save.profile.cleared_chapter_ids = ["chapter_01_shiganshina"]
	save.profile.unlocked_character_ids.append("mikasa_01")
	view = service.shop_view(save)
	view.view_revision = 89
	ui.present_supply(view)
	panel = ui._supply_panel
	var button: Button = panel.option_button("character_id","mikasa_01")
	t.check(not button.disabled and button.text.contains("8%") and button.text.contains("15%"),"unlocked prototype explains both actual traits")
	for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		button.grab_focus()
		for frame in 6: await t.process_frame
		t.check(ui._scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),"character choice stays fully readable "+str(screen))
	button.pressed.emit()
	button.pressed.emit()
	t.check(events == [["mikasa_01",89]],"one original character and revision are emitted with duplicate protection")
	t.check(not button.text.contains("[선택]"),"pending character is not optimistically marked selected")
	ui.present_action_result({"ok":false,"action":"character_selection","error_code":"write_failed"})
	t.check(panel.display_text().contains("저장에 실패") and panel.option_button("character_id","mikasa_01").disabled,"failed selection retains authority and waits for requery")
	ui.free()
