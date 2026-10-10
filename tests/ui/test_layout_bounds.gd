extends RefCounted
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	ui.set_checkpoint_available(true)
	ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
	await t.process_frame
	await t.process_frame
	await t.process_frame
	t.check(ui._panel.position.y >= 0 and ui._panel.position.y+ui._panel.size.y <= 450,"settled landscape title panel remains visible")
	t.check(ui._scroll.get_v_scroll_bar().max_value <= ui._scroll.get_v_scroll_bar().page,"landscape title shows all three primary actions")
	ui.set_save_notice("저장 상태 안내")
	t.check(ui._notice.get_parent() == ui._panel.get_node("Body"),"modal notice participates in layout instead of overlapping cards")
	ui.open_settings()
	ui.reflow(Vector2i(360,800),Rect2i(0,24,360,752))
	await t.process_frame
	await t.process_frame
	await t.process_frame
	t.check(ui._panel.position.y >= 24 and ui._panel.position.y+ui._panel.size.y <= 776,"portrait settings fits safe-area height")
	ui.free()
