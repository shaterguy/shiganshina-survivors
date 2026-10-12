extends RefCounted
# Reverting GameUI's shop-only read focus predicate must fail this suite.
# Actual InputRouter D-pad events drive real disabled SupplyShopPanel buttons.
const H = preload("res://tests/ui_locked_shop/helpers.gd")
const Shop = preload("res://game/ui/supply_shop_panel.gd")
func run(t) -> void:
	var view := H.active_view()
	t.check(view.get("can_shop") == false and view.get("lock_reason") == "active_run" and view.get("items",[]).size() == preload("res://game/economy/supply_catalog.gd").new().item_ids().size(),"real service supplies every catalog product locked during active run")
	var before := view.duplicate(true)
	for target in H.TARGETS:
		var h := H.create(t,view,target)
		await H.settle(t)
		for action in ["down","right","up","left"]:
			var visited: Array[String] = []
			for ignored in range(H.ids(view).size()):
				H.direction(h,action)
				await H.settle(t)
				var id: String = h.ui.focused_semantic_id()
				if not id in visited: visited.append(id)
				H.check_focus(t,h,id,str(target[0])+" "+action)
				if id.begins_with("purchase:"):
					var button: Button = h.ui._supply_panel.item_button(id.trim_prefix("purchase:"))
					var item: Dictionary = view.items.filter(func(row): return "purchase:"+row.item_id == id)[0]
					t.check(button.disabled and button.focus_mode == Control.FOCUS_ALL,"readable product remains disabled with native focus")
					var expected: Array = [item.name,item.description,item.tradeoff_text,"가격 %d" % item.price,Shop.reason_text("active_run"),"구매 불가"]
					if item.kind == "permanent_upgrade":
						expected = [item.name,item.current_effect_text,item.next_effect_text,"Lv %d/%d" % [item.level,item.max_level],"모든 새 출격","가격 %d" % item.price,Shop.reason_text("active_run"),"구매 불가"]
						t.check(button.tooltip_text.contains(item.description) and button.tooltip_text.contains(item.tradeoff_text),"compact permanent card retains supplementary authored detail")
					for text in expected:
						t.check(button.text.contains(text),"focused disabled card retains complete DTO text: "+text)
					t.check(not button.clip_text and button.size.y >= button.get_minimum_size().y,"focused disabled prose keeps unclipped native minimum height")
					print("LOCKED_SHOP_OBSERVATION ",JSON.stringify({"target":target[0],"direction":action,"id":id,"disabled":button.disabled,"full_visible":h.ui._scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),"height":button.size.y,"text":button.text}))
				else:
					t.check(id in ["loadout_open","supply_back"],"only shop actions and actual product cards are traversed")
			for id in H.ids(view): t.check(id in visited,str(target[0])+" "+action+" reaches "+id+" using directions only")
		t.check(h.purchases.is_empty() and view == before and h.ui._supply_view == before,"read-only D-pad navigation emits no purchase or DTO mutation")
		h.viewport.free()
