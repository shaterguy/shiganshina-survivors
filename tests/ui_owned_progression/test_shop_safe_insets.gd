extends RefCounted
const F = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Service = preload("res://game/economy/supply_service.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	for started in [false,true]:
		var save: Dictionary = F.new().game_save("started" if started else "empty")
		var view := Service.new(Callable()).shop_view(save)
		var ui = UI.new()
		t.root.add_child(ui)
		ui.present_supply(view)
		ui.open_supply_shop()
		for screen in [Vector2i(320,568),Vector2i(450,800),Vector2i(640,360),Vector2i(800,450)]:
			var safe := Rect2i(12,24,screen.x-24,screen.y-48)
			ui.reflow(screen,safe)
			for frame in 5: await t.process_frame
			for item in view.items:
				var card: Button = ui._supply_panel.item_button(item.item_id)
				card.grab_focus()
				for frame in 5: await t.process_frame
				t.check(ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"safe inset shop preserves whole focused card "+str(screen)+" "+str(started)+" "+item.item_id)
				t.check(Rect2(safe).encloses(ui._panel.get_global_rect()),"short shop stays within safe area")
		ui.free()
