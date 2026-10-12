extends RefCounted
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Service = preload("res://game/economy/supply_service.gd")
const UI = preload("res://game/ui/game_ui.gd")
const ShopPanel = preload("res://game/ui/supply_shop_panel.gd")
func run(t) -> void:
	var save: Dictionary = Fixture.new().game_save()
	save.profile.supply_credits = 500
	var before := save.duplicate(true)
	var service := Service.new(Callable())
	var view := service.shop_view(save)
	view.view_revision = 81
	var ui = UI.new()
	t.root.add_child(ui)
	ui.present_supply(view)
	var found := false
	for button in ui._buttons:
		if button.get_meta("semantic_id","") == "shop_open":
			found = button.text.contains("상점") and button.text.contains("영구 강화")
	t.check(found,"actual first title exposes permanent upgrade shop by name")
	ui.open_supply_shop()
	var panel = ui._supply_panel
	for item in view.items:
		if item.kind != "permanent_upgrade": continue
		var button: Button = panel.item_button(item.item_id)
		t.check(button != null and button.text.contains("영구 강화") and button.text.contains("Lv 0/5"),"permanent card distinguishes its current bounded career level")
		t.check(button.text.contains(item.current_effect_text) and button.text.contains(item.next_effect_text),"permanent card uses authoritative current and next effect descriptions")
		t.check(button.text.contains(str(item.next_price)) and button.text.contains(str(item.balance_after)) and button.text.contains("모든 새 출격"),"permanent card exposes price, after-balance and scope")
	var purchases: Array = []
	ui.purchase_requested.connect(func(id,revision): purchases.append([id,revision]))
	panel.item_button("permanent_might").pressed.emit()
	panel.item_button("permanent_might").pressed.emit()
	t.check(purchases == [["permanent_might",81]],"pending permanent purchase keeps the existing one-request revision contract")
	ui.present_action_result({"ok":false,"action":"purchase","error_code":"write_failed"})
	t.check(panel.display_text().contains("저장에 실패") and not panel.display_text().contains("구매 완료"),"failed permanent save never displays purchase success")
	ui.free()
	save.profile.permanent_upgrades = {"permanent_might":5,"permanent_vitality":5,"permanent_magnet":5}
	view = service.shop_view(save)
	var max_panel := ShopPanel.new()
	t.root.add_child(max_panel)
	max_panel.present(view)
	for item in view.items:
		if item.kind != "permanent_upgrade": continue
		var button: Button = max_panel.item_button(item.item_id)
		t.check(button.disabled and button.text.contains("MAX 5/5") and button.text.contains("강화 완료"),"maximum career level stays readable and unpurchasable")
		t.check(not button.text.contains("가격") and not button.text.contains("A · 구매"),"maximum permanent card offers no fictitious next price or action")
	t.check(before.profile.supply_credits == save.profile.supply_credits,"shop presentation never spends currency")
	max_panel.free()
