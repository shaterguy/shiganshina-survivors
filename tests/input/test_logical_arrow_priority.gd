extends RefCounted
# Native QA observed logical Down + physical keypad Enter. Navigation arrows
# must keep their logical meaning; letter movement must keep physical layout.
const Support = preload("res://tests/app/controller_test_support.gd")
const Router = preload("res://game/input/input_router.gd")
const ARROWS := {"up":KEY_UP,"down":KEY_DOWN,"left":KEY_LEFT,"right":KEY_RIGHT}
const VECTORS := {"up":Vector2.UP,"down":Vector2.DOWN,"left":Vector2.LEFT,"right":Vector2.RIGHT}

func run(t) -> void:
	_test_mismatched_arrow_state(t)
	await _test_mismatched_viewport_delivery(t)
	_test_physical_letter_layout(t)

func _test_mismatched_arrow_state(t) -> void:
	for direction in ARROWS:
		# Cover the exact observed non-navigation physical code and a conflicting
		# movement letter; neither may override an explicit logical arrow.
		for physical in [KEY_KP_ENTER,KEY_W if direction != "up" else KEY_S]:
			var router = Router.new()
			var actions: Array[String] = []
			router.ui_action.connect(func(action): actions.append(action))
			var label: String = direction+" with physical "+str(physical)
			router.handle_event(_key(ARROWS[direction],physical,true))
			t.check(actions == [direction] and router.sample_move() == VECTORS[direction],label+" preserves logical arrow on press")
			router._process(0.016)
			t.check(actions == [direction],label+" does not duplicate initial navigation during processing")
			router.handle_event(_key(ARROWS[direction],physical,false))
			router._process(1.0)
			t.check(actions == [direction] and router.sample_move() == Vector2.ZERO,label+" release clears the same logical arrow and repeat")
			router.handle_event(_key(ARROWS[direction],physical,true))
			router.handle_event(_key(ARROWS[direction],physical,false))
			router._process(0.016)
			t.check(actions == [direction,direction] and router.sample_move() == Vector2.ZERO,label+" same-frame tap survives without retained movement")
			router.free()

func _test_mismatched_viewport_delivery(t) -> void:
	var fixture := Support.new().make(t)
	fixture.app.start_run(159)
	var old: Dictionary = fixture.app.game_save.duplicate(true)
	fixture.app.free()
	old.checkpoint.content_revision = "old-logical-arrow-regression"
	var source := JSON.stringify(old,"",true,true)
	var file := FileAccess.open(fixture.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(source)
	file.close()
	var app = Support.new().restart(t,fixture.directory)
	app.input_router.set_process(false)
	await t.process_frame
	await t.process_frame
	t.check(app.ui._mode == "save_recovery","logical arrow viewport fixture reaches actual recovery controller")
	var actions: Array[String] = []
	var gui_events: Array[InputEvent] = []
	app.input_router.ui_action.connect(func(action): actions.append(action))
	for button in app.ui._buttons:
		button.gui_input.connect(func(event): gui_events.append(event))
	for direction in ARROWS:
		app.input_router.clear_transient_input()
		app.ui._buttons[0].grab_focus()
		actions.clear()
		gui_events.clear()
		var step := 1 if direction in ["down","right"] else -1
		var target := posmod(step,app.ui._buttons.size())
		while app.ui._buttons[target].disabled: target = posmod(target+step,app.ui._buttons.size())
		t.root.push_input(_key(ARROWS[direction],KEY_KP_ENTER,true),true)
		t.root.push_input(_key(ARROWS[direction],KEY_KP_ENTER,false),true)
		app.input_router._process(0.016)
		t.check(actions == [direction],direction+" mismatched viewport tap emits one logical intent")
		t.check(app.ui._focus_index == target and t.root.gui_get_focus_owner() == app.ui._buttons[target],direction+" mismatched viewport tap moves recovery focus exactly once")
		t.check(gui_events.is_empty(),direction+" mismatched viewport tap has no duplicate native GUI handling")
		t.check(app.input_router.sample_move() == Vector2.ZERO,direction+" mismatched viewport release leaves movement neutral")
		app.input_router.set_active(false)
		app.ui._buttons[0].grab_focus()
		actions.clear()
		gui_events.clear()
		t.root.push_input(_key(ARROWS[direction],KEY_KP_ENTER,true),true)
		t.root.push_input(_key(ARROWS[direction],KEY_KP_ENTER,false),true)
		t.check(actions.is_empty() and app.input_router.sample_move() == Vector2.ZERO,direction+" mismatched disabled input emits no intent or movement")
		t.check(not gui_events.is_empty(),direction+" mismatched disabled input passes through to native GUI")
		app.input_router.set_active(true)
		app.input_router._process(1.0)
		t.check(actions.is_empty(),direction+" mismatched disabled tap does not replay on activation")
	t.check(app.state.is_empty() and FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source,"mismatched arrow navigation neither activates nor changes saved recovery authority")
	app.free()

func _test_physical_letter_layout(t) -> void:
	for case in [
		{"logical":KEY_Z,"physical":KEY_W,"direction":"up"},
		{"logical":KEY_Q,"physical":KEY_A,"direction":"left"},
		{"logical":KEY_W,"physical":KEY_D,"direction":"right"},
		{"logical":KEY_D,"physical":KEY_S,"direction":"down"},
		{"logical":KEY_W,"physical":KEY_Z,"direction":""},
		{"logical":KEY_A,"physical":KEY_Q,"direction":""},
		{"logical":KEY_S,"physical":KEY_KP_ENTER,"direction":""},
		{"logical":KEY_D,"physical":0,"direction":"right"}
	]:
		var router = Router.new()
		var actions: Array[String] = []
		router.ui_action.connect(func(action): actions.append(action))
		router.handle_event(_key(case.logical,case.physical,true))
		var expected: Array = [] if case.direction.is_empty() else [case.direction]
		var vector: Vector2 = Vector2.ZERO if case.direction.is_empty() else VECTORS[case.direction]
		t.check(actions == expected and router.sample_move() == vector,"ordinary letter mapping retains physical priority: "+str(case))
		router.handle_event(_key(case.logical,case.physical,false))
		router._process(1.0)
		t.check(actions == expected and router.sample_move() == Vector2.ZERO,"ordinary letter mapping retains clean release: "+str(case))
		router.free()

func _key(logical: int,physical: int,pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = logical
	event.physical_keycode = physical
	event.pressed = pressed
	return event
