extends RefCounted
const UI = preload("res://game/ui/game_ui.gd")
const Router = preload("res://game/input/input_router.gd")
const Supply = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const TARGETS := [["landscape",Vector2i(800,450),Rect2i(0,0,800,450)], ["tablet_landscape",Vector2i(720,450),Rect2i(0,0,720,450)], ["portrait",Vector2i(450,720),Rect2i(0,0,450,720)], ["physical_568x320_mapped",Vector2i(798,450),Rect2i(23,17,752,416)]]
static func ids(view: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for item in view.items: result.append("purchase:"+str(item.item_id))
	result.append_array(["loadout_open","supply_back"])
	return result
static func settle(t, frames: int = 8) -> void:
	for ignored in range(frames): await t.process_frame
static func active_view() -> Dictionary:
	# Real service computes the lock from the test-only persisted run fixture.
	return Supply.new(Callable()).shop_view(Fixture.new().game_save("started"))
static func create(t, view: Dictionary, target: Array = TARGETS[0]) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = target[1]
	t.root.add_child(viewport)
	var ui = UI.new()
	viewport.add_child(ui)
	var router = Router.new()
	viewport.add_child(router)
	router.ui_action.connect(ui.navigate)
	ui.reflow(target[1],target[2])
	ui.present_supply(view)
	ui.open_supply_shop()
	var purchases: Array = []
	ui.purchase_requested.connect(func(id, revision): purchases.append([id,revision]))
	return {"viewport":viewport,"ui":ui,"router":router,"purchases":purchases}
static func joy(viewport, key: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = key
	event.pressed = pressed
	viewport.push_input(event,true)
static func direction(h: Dictionary, action: String) -> void:
	var key: int = {"down":JOY_BUTTON_DPAD_DOWN,"up":JOY_BUTTON_DPAD_UP,"right":JOY_BUTTON_DPAD_RIGHT,"left":JOY_BUTTON_DPAD_LEFT}[action]
	joy(h.viewport,key,true)
	joy(h.viewport,key,false)
static func reach(t,h: Dictionary,id: String) -> bool:
	for ignored in range(h.ui._buttons.size()+1):
		if h.ui.focused_semantic_id() == id:
			await settle(t)
			return true
		direction(h,"down")
		await settle(t)
	return false
static func mouse(viewport,point: Vector2,pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event,true)
static func check_focus(t,h: Dictionary,id: String,label: String) -> void:
	var focused = h.viewport.gui_get_focus_owner()
	t.check(h.ui.focused_semantic_id() == id,label+" preserves semantic focus "+id)
	t.check(focused != null and str(focused.get_meta("semantic_id","")) == id,label+" preserves real GUI focus "+id)
	if focused != null:
		var safe := Rect2(Vector2(h.ui._safe_rect.position),Vector2(h.ui._safe_rect.size))
		var visible: Rect2 = h.ui._scroll.get_global_rect().intersection(safe)
		t.check(visible.grow(1).encloses(focused.get_global_rect()),label+" reveals complete focused card/action")
static func blocked_attempts(t,h: Dictionary,button: Button,label: String) -> void:
	var before: int = h.purchases.size()
	# Guard tests isolate activation safety even when the navigation RED cannot reach it.
	button.grab_focus()
	await settle(t)
	t.check(button.disabled,label+" Button stays disabled")
	h.ui.accept_released()
	for ignored in range(8): h.ui.navigate("accept")
	t.check(h.purchases.size() == before,label+" repeated semantic accept emits no purchase")
	button.pressed.emit()
	t.check(h.purchases.size() == before,label+" direct pressed signal cannot bypass panel guard")
	var point := button.get_global_rect().get_center()
	mouse(h.viewport,point,true)
	await settle(t,90)
	t.check(not button.is_pressed(),label+" real GUI long press never arms disabled button")
	mouse(h.viewport,point,false)
	for ignored in range(8): joy(h.viewport,JOY_BUTTON_A,true)
	await settle(t,90)
	joy(h.viewport,JOY_BUTTON_A,false)
	t.check(h.purchases.size() == before,label+" real GUI pointer and held/repeated A emit no purchase")
	t.check(button.disabled,label+" rejected inputs preserve disabled state")
