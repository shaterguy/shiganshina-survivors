extends RefCounted
# Real viewport delivery: a complete tap can arrive before the next process tick.
# Removing event-time direction edge handling must make these regressions fail.
const Support = preload("res://tests/app/controller_test_support.gd")
const Router = preload("res://game/input/input_router.gd")

func run(t) -> void:
	await _test_controller_batched_taps(t)
	_test_repeat_release_and_reset(t)
	_test_slow_frame_repeat_ownership(t)
	_test_mixed_direction_state(t)

func _test_controller_batched_taps(t) -> void:
	var fixture := Support.new().make(t)
	fixture.app.start_run(158)
	var old: Dictionary = fixture.app.game_save.duplicate(true)
	fixture.app.free()
	old.checkpoint.content_revision = "old-menu-direction-regression"
	var source := JSON.stringify(old,"",true,true)
	var file := FileAccess.open(fixture.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(source)
	file.close()
	var app = Support.new().restart(t,fixture.directory)
	app.input_router.set_process(false)
	await t.process_frame
	await t.process_frame
	t.check(app.ui._mode == "save_recovery" and app.ui.focused_semantic_id() == "recovery_keep","direction fixture reaches the real controller's safe recovery choice")
	var actions: Array[String] = []
	app.input_router.ui_action.connect(func(action): actions.append(action))
	var gui_events: Array[InputEvent] = []
	for button in app.ui._buttons:
		button.gui_input.connect(func(event): gui_events.append(event))
	for source_kind in ["keycode","physical","dpad","stick"]:
		app.input_router.clear_transient_input()
		app.ui._buttons[0].grab_focus()
		actions.clear()
		gui_events.clear()
		var pressed := _direction_event(source_kind,"down",true)
		var released := _direction_event(source_kind,"down",false)
		# Both events are dispatched synchronously through Godot's actual viewport;
		# no idle frame or manually called router handler occurs between them.
		t.root.push_input(pressed,true)
		t.root.push_input(released,true)
		app.input_router._process(0.016)
		t.check(actions == ["down"],source_kind+" complete tap between process calls emits exactly one direction")
		t.check(app.ui.focused_semantic_id() == "recovery_start",source_kind+" complete tap moves actual recovery focus exactly once")
		t.check(gui_events.is_empty(),source_kind+" direction is not dispatched a second time to native GUI")
		t.check(app.input_router.sample_move() == Vector2.ZERO,source_kind+" release clears movement")
		app.input_router._process(1.0)
		t.check(actions == ["down"],source_kind+" released tap produces no delayed repeat")
		# A second complete tap, also within one frame, must not be coalesced away.
		t.root.push_input(_direction_event(source_kind,"up",true),true)
		t.root.push_input(_direction_event(source_kind,"up",false),true)
		app.input_router._process(0.016)
		t.check(actions == ["down","up"] and app.ui.focused_semantic_id() == "recovery_keep",source_kind+" successive batched tap returns recovery focus once")
	for source_kind in ["keycode","physical","dpad"]:
		app.ui._buttons[0].grab_focus()
		app.input_router.set_active(false)
		actions.clear()
		gui_events.clear()
		t.root.push_input(_direction_event(source_kind,"down",true),true)
		t.root.push_input(_direction_event(source_kind,"down",false),true)
		app.input_router._process(1.0)
		t.check(actions.is_empty() and app.input_router.sample_move() == Vector2.ZERO,source_kind+" disabled router ignores directions")
		t.check(not gui_events.is_empty(),source_kind+" disabled router relinquishes event delivery to native GUI")
		app.input_router.set_active(true)
		app.input_router._process(1.0)
		t.check(actions.is_empty(),source_kind+" disabled tap does not replay on reactivation")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source and app.state.is_empty(),"direction navigation never activates or replaces the recovery authority")
	app.free()

func _test_repeat_release_and_reset(t) -> void:
	for source_kind in ["keycode","physical","dpad","stick"]:
		var router = Router.new()
		var actions: Array[String] = []
		router.ui_action.connect(func(action): actions.append(action))
		router.handle_event(_direction_event(source_kind,"right",true))
		t.check(actions == ["right"],source_kind+" pressed edge is emitted before the next process tick")
		router._process(0.0)
		router.handle_event(_direction_event(source_kind,"right",true))
		if source_kind in ["keycode","physical"]:
			var echo := _direction_event(source_kind,"right",true) as InputEventKey
			echo.echo = true
			router.handle_event(echo)
		router._process(0.15)
		router._process(0.149)
		t.check(actions == ["right"],source_kind+" held or echoed press does not duplicate initial navigation")
		router._process(0.002)
		t.check(actions == ["right","right"],source_kind+" held direction first repeats after 0.30 seconds")
		router._process(0.098)
		t.check(actions.size() == 2,source_kind+" repeat respects the 0.10 second interval")
		router._process(0.003)
		t.check(actions == ["right","right","right"],source_kind+" held direction repeats again at the normal cadence")
		router.handle_event(_direction_event(source_kind,"right",false))
		router._process(1.0)
		t.check(actions.size() == 3 and router.sample_move() == Vector2.ZERO,source_kind+" release stops all held movement and repeats")
		router.handle_event(_direction_event(source_kind,"right",true))
		router.handle_event(_direction_event(source_kind,"right",false))
		router.handle_event(_direction_event(source_kind,"right",true))
		router.handle_event(_direction_event(source_kind,"right",false))
		router._process(0.01)
		t.check(actions.size() == 5,source_kind+" two same-direction taps in one frame each navigate once")
		router.handle_event(_direction_event(source_kind,"right",true))
		router.set_active(false)
		router.set_active(true)
		router._process(1.0)
		t.check(actions.size() == 6 and router.sample_move() == Vector2.ZERO,source_kind+" deactivate clears direction and pending repeat")
		router.handle_event(_direction_event(source_kind,"right",true))
		t.check(actions.size() == 7,source_kind+" first fresh direction after reactivation is preserved")
		router.clear_transient_input()
		router._process(1.0)
		t.check(actions.size() == 7 and router.sample_move() == Vector2.ZERO,source_kind+" transient reset clears held state without repeat")
		router.free()

func _test_slow_frame_repeat_ownership(t) -> void:
	for source_kind in ["keycode","physical","dpad","stick"]:
		var router = Router.new()
		var actions: Array[String] = []
		router.ui_action.connect(func(action): actions.append(action))
		router.handle_event(_direction_event(source_kind,"down",true))
		router._process(1.0)
		var after_process := actions.size()
		router.handle_event(_direction_event(source_kind,"down",true))
		if source_kind in ["keycode","physical"]:
			var echo := _direction_event(source_kind,"down",true) as InputEventKey
			echo.echo = true
			router.handle_event(echo)
		t.check(after_process == 2 and actions.size() == after_process,source_kind+" duplicate events cannot drive held repeat after a slow frame")
		router.handle_event(_direction_event(source_kind,"down",false))
		router._process(1.0)
		t.check(actions.size() == after_process,source_kind+" release clears slow-frame repeat debt")
		router.free()

func _test_mixed_direction_state(t) -> void:
	for source_kind in ["keycode","physical","dpad"]:
		var router = Router.new()
		var actions: Array[String] = []
		router.ui_action.connect(func(action): actions.append(action))
		router.handle_event(_direction_event(source_kind,"left",true))
		router.handle_event(_direction_event(source_kind,"right",true))
		t.check(actions == ["left"] and router.sample_move() == Vector2.ZERO,source_kind+" opposing held directions cancel without extra intent")
		router.handle_event(_direction_event(source_kind,"right",false))
		t.check(actions == ["left","left"] and router.sample_move() == Vector2.LEFT,source_kind+" releasing opposite input preserves remaining held direction")
		router.handle_event(_direction_event(source_kind,"left",false))
		router._process(1.0)
		t.check(actions.size() == 2 and router.sample_move() == Vector2.ZERO,source_kind+" final opposing release leaves no retained direction")
		router.free()

func _direction_event(kind: String,direction: String,pressed: bool) -> InputEvent:
	if kind == "dpad":
		var event := InputEventJoypadButton.new()
		event.device = 23
		event.button_index = {"down":JOY_BUTTON_DPAD_DOWN,"up":JOY_BUTTON_DPAD_UP,"left":JOY_BUTTON_DPAD_LEFT,"right":JOY_BUTTON_DPAD_RIGHT}[direction]
		event.pressed = pressed
		return event
	if kind == "stick":
		var event := InputEventJoypadMotion.new()
		event.device = 23
		event.axis = JOY_AXIS_LEFT_Y if direction in ["up","down"] else JOY_AXIS_LEFT_X
		event.axis_value = (1.0 if direction in ["down","right"] else -1.0) if pressed else 0.0
		return event
	var event := InputEventKey.new()
	var key: int = {"down":KEY_DOWN,"up":KEY_UP,"left":KEY_LEFT,"right":KEY_RIGHT}[direction]
	if kind == "physical": event.physical_keycode = key
	else: event.keycode = key
	event.pressed = pressed
	return event
