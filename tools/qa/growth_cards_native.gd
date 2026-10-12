extends Node
# Disposable real-Core offer/UI/input fixture. No SaveStore or user data access.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Router = preload("res://game/input/input_router.gd")
var simulation
var state: Dictionary
var ui
var router
var _view_key := ""
var _choice_count := 0
var _last_choice := "없음"
var _caption: Label
var _portrait := false
func check(value: bool, message: String) -> void:
	if not value: push_error(message)
func _ready() -> void:
	simulation = Fixture.simulation(self)
	state = Fixture.earn_offer(simulation,21,24)
	ui = UI.new()
	add_child(ui)
	ui.present(simulation.snapshot(state))
	router = Router.new()
	add_child(router)
	router.ui_action.connect(ui.navigate)
	ui.upgrade_focus_changed.connect(func(id): simulation.set_offer_focus(state,id))
	ui.upgrade_chosen.connect(func(_offer,id): _choice_count += 1; _last_choice = id)
	get_viewport().size_changed.connect(_resize)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(8,8)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size",11)
	layer.add_child(_caption)
	_resize()
func _process(_delta: float) -> void:
	var key := "%d:%s" % [state.view_revision,state.upgrade_offer.selected_option_id]
	if key != _view_key:
		_view_key = key
		ui.present_progression(View.new().build(state))
	_caption.text = "UI 격리 · F11 화면비 · 선택 %d회\n%s · %s" % [_choice_count, _last_choice, str(get_viewport().get_visible_rect().size)]
func _resize() -> void:
	var dimensions := Vector2i(get_viewport().get_visible_rect().size)
	ui.reflow(dimensions,Rect2i(Vector2i.ZERO,dimensions))
	if is_instance_valid(_caption):
		_caption.position = Vector2(55, dimensions.y-42)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_portrait = not _portrait
		# Godot's embedded host intercepts F10 and fixes the native child aspect.
		# Exercise the real UI/input in a portrait logical viewport, letterboxed
		# by the engine. This is desktop presentation QA, not Android rotation QA.
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		get_window().content_scale_size = Vector2i(450,800) if _portrait else Vector2i(800,450)
		_resize()
