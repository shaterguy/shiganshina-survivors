extends RefCounted
# Real Godot GUI emulated-touch drag: ScrollContainer handles its normal
# touchscreen scroll path, and scrolling across a Button must cancel its press.
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _mouse(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = -1
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	return event
func run(t) -> void:
	var old_emulation := Input.is_emulating_touch_from_mouse()
	Input.set_emulate_touch_from_mouse(true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,360)
	t.root.add_child(viewport)
	var ui := UI.new()
	viewport.add_child(ui)
	ui.set_checkpoint_available(true)
	ui.present_supply({"view_revision":1})
	ui.reflow(viewport.size,Rect2i(24,12,592,336))
	ui.open_settings()
	await _settle(t)
	var changed: Array = []
	ui.settings_changed.connect(func(values): changed.append(values))
	var rect: Rect2 = ui._scroll.get_global_rect()
	var start := rect.position+Vector2(rect.size.x*0.5,rect.size.y-20)
	viewport.push_input(_mouse(start,true),true)
	for step in range(1,5):
		var event := InputEventMouseMotion.new()
		event.device = -1
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		event.relative = Vector2(0,-40)
		event.position = start+Vector2(0,-40*step)
		event.global_position = event.position
		viewport.push_input(event,true)
		await t.process_frame
	viewport.push_input(_mouse(start+Vector2(0,-160),false),true)
	await _settle(t)
	t.check(ui._scroll.scroll_vertical > 0,"touchscreen drag scrolls overflowing small-landscape settings")
	t.check(ui._scroll.get_global_rect().grow(1).encloses(ui._buttons[-1].get_global_rect()),"touch scroll exposes complete Back action inside safe viewport")
	t.check(changed.is_empty() and ui._mode == "settings","touch scrolling does not activate a setting or the Back action")
	var back: Vector2 = ui._buttons[-1].get_global_rect().get_center()
	viewport.push_input(_mouse(back,true),true)
	viewport.push_input(_mouse(back,false),true)
	await _settle(t)
	t.check(ui._mode == "title","exposed Back action remains touch tappable after scrolling")
	viewport.free()
	Input.set_emulate_touch_from_mouse(old_emulation)
