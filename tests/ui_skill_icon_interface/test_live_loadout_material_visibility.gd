extends RefCounted
# Real pre-run DTO -> existing GameUI loadout -> controller navigation.
# Visibility means actual native scroll bounds, not a tooltip or hidden rect.
const Service = preload("res://game/economy/supply_service.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	var profile := {"owned_doctrine_ids":["doctrine_standard"],"consumables":{"field_bandage":0}}
	var before := profile.duplicate(true)
	var service := Service.new(Callable())
	var options: Dictionary = service._loadout_options(profile,false)
	var view := {"view_revision":1,"loadout":{},"loadout_options":options,"can_start":true}
	var view_before := view.duplicate(true)
	for screen in [Vector2i(360,800),Vector2i(800,450)]:
		var ui := UI.new()
		t.root.add_child(ui)
		ui.present_supply(view)
		ui.open_loadout()
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		var visited: Array[String] = []
		for step in range(ui._buttons.size()+1):
			var focus := ui.get_viewport().gui_get_focus_owner()
			if focus is Button:
				var semantic := str(focus.get_meta("semantic_id",""))
				if semantic.begins_with("loadout:target_evolution_id:"):
					var id := semantic.trim_prefix("loadout:target_evolution_id:")
					if not id in visited:
						visited.append(id)
						var context := id+str(screen)
						var viewport: Rect2 = ui._scroll.get_global_rect().grow(1)
						var rows: VBoxContainer = ui._supply_panel.get_node("Requirements_"+id)
						t.check(focus.is_visible_in_tree() and viewport.encloses(focus.get_global_rect()),"controller target button is actually visible: "+context)
						t.check(rows.is_visible_in_tree() and rows.get_child_count() == 2,"controller target retains both actual material rows: "+context)
						for row in rows.get_children():
							var icon: TextureRect = row.get_node("Icon")
							var label: Label = row.get_node("Text")
							t.check(icon.is_visible_in_tree() and label.is_visible_in_tree() and icon.texture != null and icon.size.x >= 18 and icon.size.y >= 18,"pre-run material shape and label are visible and readable: "+context)
							t.check(viewport.encloses(icon.get_global_rect()) and viewport.encloses(label.get_global_rect()),"controller focus reveals the target's actual icon/name material rows inside the viewport: "+context)
							t.check(label.text.contains("필요") and not label.text.contains("✓"),"pre-run actual label identifies a need without invented ownership: "+context)
			ui.navigate("down")
			await _settle(t)
		t.check(visited.size() == 8,"controller really visits all eight pre-run targets at "+str(screen))
		ui.free()
	t.check(profile == before and view == view_before,"reading actual target conditions never changes profile, inventory, selection or DTO")
