extends RefCounted
# Real Controller/Core/Store/UI in a resized logical viewport. Android hardware,
# Activity recreation and native joypad detection remain a separate QA boundary.
const Support = preload("res://tests/app/controller_test_support.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	for mode in ["play","pause","upgrade"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(450,800)
		t.root.add_child(viewport)
		var support := Support.new()
		var fixture: Dictionary = support.make({"root":viewport})
		var app = fixture.app
		app.input_router.set_process(false)
		app.start_run(72)
		if mode == "pause":
			app.set_user_pause(true)
			# An independently owned rotation hold must survive this synchronous
			# UI resize rather than being removed by a temporary true/false pair.
			app.simulation.set_pause(app.state,"rotation",true)
			app._present()
		elif mode == "upgrade": support.evolution_offer(app)
		await _settle(t)
		var axis := InputEventJoypadMotion.new()
		axis.device = 21
		axis.axis = JOY_AXIS_LEFT_X
		axis.axis_value = 0.75
		app.input_router.handle_event(axis)
		var held_pad: Vector2 = app.input_router.sample_move()
		t.check(held_pad.x > 0.0,"fixture holds real gamepad input in "+mode)
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.pressed = true
		app.input_router.handle_event(key)
		var held_keys: Vector2 = app.input_router._keys
		var held_stick: Vector2 = app.input_router._stick
		var direction_before: String = app.input_router._menu_direction
		var repeat_before: float = app.input_router._repeat_remaining
		held_pad = app.input_router.sample_move()
		var accepted: Array[String] = []
		app.input_router.ui_action.connect(func(action):
			if action == "accept": accepted.append(action))
		# A held through a connection/rotation cannot become a fresh confirmation.
		app.input_router._accept_armed = false
		var accept := InputEventJoypadButton.new()
		accept.device = 21
		accept.button_index = JOY_BUTTON_A
		accept.pressed = true
		if mode == "play":
			var press := InputEventScreenTouch.new()
			press.index = 4
			press.position = Vector2(90,650)
			press.pressed = true
			app.ui._input(press)
			var drag := InputEventScreenDrag.new()
			drag.index = 4
			drag.position = Vector2(90,710)
			app.ui._input(drag)
			t.check(app.ui._touch_id == 4 and app.ui._touch_vector.y > 0.0,"fixture holds a portrait touch drag before rotation")
		var runtime_before: Dictionary = app.state.duplicate(true)
		var save_before: Dictionary = app.game_save.duplicate(true)
		var disk_before: Dictionary = app.save_store.load_game().game_save
		var focused_before: String = app.ui.focused_semantic_id()
		var input_accept_before: bool = app.input_router._accept_armed
		for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(800,450)]:
			viewport.size = screen
			app._resize()
			await _settle(t)
			t.check(app.state == runtime_before,"resize preserves complete runtime including combat, pending offer, focus and pause reasons in "+mode+str(screen))
			t.check(app.game_save == save_before and app.save_store.load_game().game_save == disk_before,"resize does not commit or replace saved authority in "+mode+str(screen))
			t.check(app.input_router.sample_move().is_equal_approx(held_pad),"resize preserves held gamepad movement in "+mode+str(screen))
			t.check(app.input_router._accept_armed == input_accept_before,"resize preserves gamepad accept latch in "+mode)
			t.check(app.input_router._keys == held_keys and app.input_router._stick == held_stick and app.input_router._menu_direction == direction_before and app.input_router._repeat_remaining == repeat_before,"resize preserves keyboard/pad held state and menu repeat edge in "+mode)
			app.input_router.handle_event(accept)
			t.check(accepted.is_empty() and app.state == runtime_before,"held A across resize cannot confirm or duplicate a level-up selection in "+mode)
			t.check(app.ui._touch_id == -1 and app.ui._touch_vector == Vector2.ZERO,"resize discards old touch ownership and coordinates in "+mode)
			t.check(app.ui._screen_size == screen and app.ui.size == Vector2(screen),"HUD uses the resized logical viewport in "+mode+str(screen))
			if mode != "play":
				t.check(app.ui.focused_semantic_id() == focused_before,"resize preserves the same selected semantic menu action in "+mode)
				t.check(Rect2(Vector2.ZERO,Vector2(screen)).grow(1).encloses(app.ui._panel.get_global_rect()),"resized modal remains inside the logical viewport in "+mode+str(screen))
		var stale_drag := InputEventScreenDrag.new()
		stale_drag.index = 4
		stale_drag.position = Vector2(100,720)
		app.ui._input(stale_drag)
		t.check(app.ui._touch_vector == Vector2.ZERO and app.input_router.sample_move().is_equal_approx(held_pad),"stale portrait drag cannot override held gamepad input after rotation in "+mode)
		key.pressed = false
		app.input_router.handle_event(key)
		t.check(app.input_router._keys == Vector2.ZERO and app.input_router._stick == held_stick and app.input_router.sample_move().x > 0.0,"keyboard release after rotation removes only the matching held key in "+mode)
		if mode == "upgrade":
			# Release reaches both production owners, then one fresh A press performs
			# one real upgrade. Repeated press without release must not commit twice.
			app.ui._restore_focus(str(app.state.upgrade_offer.options[0].option_id))
			accept.pressed = false
			app.input_router.handle_event(accept)
			app.ui._input(accept)
			var upgrade_requests: Array = []
			app.ui.upgrade_chosen.connect(func(offer,option): upgrade_requests.append([offer,option]))
			accept.pressed = true
			app.input_router.handle_event(accept)
			app.input_router.handle_event(accept)
			t.check(accepted.size() == 1 and upgrade_requests.size() == 1,"post-rotation A release/press propagates exactly one real level-up selection")
		viewport.free()
