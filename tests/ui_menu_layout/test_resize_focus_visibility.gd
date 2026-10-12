extends RefCounted
# Regression: orientation/safe-area changes do not emit focus_changed; the
# settled existing scroll viewport must nevertheless keep the same action visible.
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(450,800)
	t.root.add_child(viewport)
	var ui := UI.new()
	viewport.add_child(ui)
	ui.set_checkpoint_available(true)
	ui.present_supply({"view_revision":1})
	ui.reflow(viewport.size,Rect2i(Vector2i.ZERO,viewport.size))
	ui.open_settings()
	await _settle(t)
	for step in range(4): ui.navigate("down")
	await _settle(t)
	t.check(ui.focused_semantic_id() == "뒤로","pad navigation reaches the settings Back action")
	for target in [[Vector2i(640,360),Rect2i(24,12,592,336)],[Vector2i(568,320),Rect2i(16,12,536,296)],[Vector2i(800,450),Rect2i(0,0,800,450)],[Vector2i(450,800),Rect2i(0,24,450,752)]]:
		viewport.size = target[0]
		ui.reflow(target[0],target[1])
		await _settle(t)
		var safe := Rect2(Vector2(target[1].position),Vector2(target[1].size))
		t.check(safe.grow(1).encloses(ui._panel.get_global_rect()),"settings panel stays inside resized safe area "+str(target[0]))
		t.check(ui.focused_semantic_id() == "뒤로","rotation keeps the same semantic settings action")
		t.check(ui._scroll.get_global_rect().grow(1).encloses(ui._buttons[-1].get_global_rect()),"rotation fully reveals already-focused Back without another pad input "+str(target[0]))
		for step in range(ui._buttons.size()):
			ui.navigate("down")
			await _settle(t)
			var focused: Button = ui._buttons[ui._focus_index]
			t.check(ui._scroll.get_global_rect().grow(1).encloses(focused.get_global_rect()),"pad focus fully reveals "+focused.text+" in "+str(target[0]))
	viewport.free()
