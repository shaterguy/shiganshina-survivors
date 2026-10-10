extends RefCounted
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	t.check(ui.has_method("open_settings"),"settings menu available")
	if not ui.has_method("open_settings"):
		ui.free()
		return
	ui.set_settings({"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false})
	var received: Array = []
	ui.settings_changed.connect(func(values): received.append(values.duplicate(true)))
	ui.open_settings()
	ui.navigate("accept")
	t.check(received.size() == 1 and is_equal_approx(received[0].deadzone,0.25),"gamepad changes deadzone")
	ui.navigate("down")
	ui.navigate("down")
	ui.navigate("down")
	ui.navigate("accept")
	t.check(received[-1].reduce_effects,"gamepad toggles reduced effects")
	ui.navigate("cancel")
	t.check(ui._mode == "title","B returns from settings")
	ui.free()
