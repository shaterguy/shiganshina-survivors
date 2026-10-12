extends RefCounted
const UI = preload("res://game/ui/game_ui.gd")
const TOUCH_ID := 7

func run(t) -> void:
	_refresh_preserves_held_touch(t)
	_refresh_preserves_mouse_drag(t)
	_layout_and_modal_transitions_cancel(t)
	_menu_refresh_still_rebuilds(t)

func _snapshot() -> Dictionary:
	return {"phase":"survival","survival_tick":1200,"active_tick":1200,"pause_reasons":[],"player":{"hp":90,"max_hp":100,"xp":3,"level":2},"stats":{"kills":4},"upgrade_offer":{}}

func _make(t):
	var ui := UI.new()
	t.root.add_child(ui)
	ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
	ui.present(_snapshot())
	return ui

func _hold(ui) -> void:
	var down := InputEventScreenTouch.new()
	down.index = TOUCH_ID
	down.pressed = true
	down.position = Vector2(100,300)
	ui._input(down)
	_drag(ui,Vector2(136,300))

func _drag(ui,position: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = TOUCH_ID
	drag.position = position
	ui._input(drag)

func _refresh_preserves_held_touch(t) -> void:
	var ui = _make(t)
	var emitted: Array[Vector2] = []
	ui.touch_move_changed.connect(func(value: Vector2): emitted.append(value))
	_hold(ui)
	t.check(ui._touch_vector == Vector2.RIGHT,"real touch press and drag acquire movement")
	var origin: Vector2 = ui._touch_origin
	var layout: int = ui._layout_generation
	emitted.clear()
	for revision in range(1,4):
		var snapshot := _snapshot()
		snapshot.survival_tick += revision*150
		snapshot.player.hp -= revision
		ui.set_save_notice("저장 완료 %d" % revision)
		ui.present(snapshot)
		ui.present_supply({"view_revision":revision,"supply_credits":revision*10})
	t.check(ui._touch_id == TOUCH_ID and ui._touch_origin == origin,"save/HUD refresh preserves the held pointer owner and origin")
	t.check(ui._touch_vector == Vector2.RIGHT and emitted.is_empty(),"save/HUD refresh emits no zero or replacement movement")
	t.check(ui._layout_generation == layout,"data-only save refresh does not schedule a layout change")
	t.check(ui._health.value == 87 and ui._supply_view.view_revision == 3,"HUD and cached supply data still update during a hold")
	_drag(ui,Vector2(100,336))
	t.check(ui._touch_vector == Vector2.DOWN,"same held finger continues steering after save refresh")
	var up := InputEventScreenTouch.new()
	up.index = TOUCH_ID
	up.pressed = false
	ui._input(up)
	t.check(ui._touch_id == -1 and ui._touch_vector == Vector2.ZERO,"physical touch release still cancels after save refresh")
	ui.free()

func _refresh_preserves_mouse_drag(t) -> void:
	var ui = _make(t)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(100,300)
	ui._input(down)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(136,300)
	ui._input(drag)
	ui.present_supply({"view_revision":1})
	t.check(ui._touch_id == UI.MOUSE_POINTER_ID and ui._touch_vector == Vector2.RIGHT,"save refresh preserves an actual held mouse drag too")
	down.pressed = false
	ui._input(down)
	t.check(ui._touch_vector == Vector2.ZERO,"mouse release remains effective after save refresh")
	ui.free()

func _layout_and_modal_transitions_cancel(t) -> void:
	for transition in ["viewport","safe_area","explicit_layout","pause","settings","shop","title","recovery"]:
		var ui = _make(t)
		ui.present_supply({"view_revision":1})
		_hold(ui)
		match transition:
			"viewport": ui.reflow(Vector2i(450,800),Rect2i(0,0,450,800))
			"safe_area": ui.reflow(Vector2i(800,450),Rect2i(24,12,752,426))
			"explicit_layout": ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
			"pause":
				var snapshot := _snapshot()
				snapshot.pause_reasons = ["manual"]
				ui.present(snapshot)
			"settings": ui.open_settings()
			"shop": ui.open_supply_shop()
			"title": ui.present({})
			"recovery": ui.present_recovery({"kind":"retry","error_code":"read_failed"})
		t.check(ui._touch_id == -1 and ui._touch_vector == Vector2.ZERO,transition+" still cancels owned movement")
		_drag(ui,Vector2(100,336))
		t.check(ui._touch_vector == Vector2.ZERO,transition+" does not revive an old drag without a new press")
		ui.free()

func _menu_refresh_still_rebuilds(t) -> void:
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present_supply({"view_revision":1})
	var shop_button: Button
	for button in ui._buttons:
		if button.get_meta("semantic_id","") == "shop_open": shop_button = button
	t.check(shop_button != null,"supply refresh adds the title menu shop action")
	if shop_button != null:
		shop_button.grab_focus()
		ui.present_supply({"view_revision":2})
		t.check(ui.focused_semantic_id() == "shop_open","menu data refresh retains semantic focus")
	ui.open_supply_shop()
	var panel = ui._supply_panel
	ui.present_supply({"view_revision":3})
	t.check(ui._supply_panel != panel and ui._supply_view.view_revision == 3,"visible shop still rebuilds for a changed supply revision")
	ui.free()
