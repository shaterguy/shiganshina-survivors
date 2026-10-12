extends RefCounted
# Regression: a newly available fourth title action must not start clipped;
# ordinary landscape settings must show their complete Back action too.
const UI = preload("res://game/ui/game_ui.gd")
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _inside_actions(t, ui, label: String) -> void:
	var viewport: Rect2 = ui._scroll.get_global_rect()
	for button in ui._buttons:
		t.check(viewport.grow(1).encloses(button.get_global_rect()),label+" initially shows complete action: "+button.text)
		t.check(not button.text.is_empty() and button.size.y >= 48,label+" retains readable text and touch-sized action")
func run(t) -> void:
	var viewport := SubViewport.new()
	t.root.add_child(viewport)
	var ui := UI.new()
	viewport.add_child(ui)
	ui.set_checkpoint_available(true)
	ui.present_supply({"view_revision":1})
	for screen in [Vector2i(800,450),Vector2i(450,800)]:
		viewport.size = screen
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		t.check(ui._buttons.size() == 4,"checkpoint and supply expose all four title actions")
		_inside_actions(t,ui,"title "+str(screen))
		ui.open_settings()
		await _settle(t)
		t.check(ui._buttons.size() == 5,"settings exposes all five actions including Back")
		_inside_actions(t,ui,"settings "+str(screen))
		ui.close_settings()
	# Use an actual Core snapshot for HUD fields; terminal phases below are
	# deliberate presentation arrangements, not naturally won/dead run evidence.
	var sim = Fixture.simulation(t)
	var snapshot: Dictionary = sim.snapshot(sim.new_run(Fixture.chapter(),96,Fixture.run_config()))
	for target in [[Vector2i(800,450),Rect2i(0,0,800,450)],[Vector2i(450,800),Rect2i(0,24,450,752)],[Vector2i(640,360),Rect2i(24,12,592,336)],[Vector2i(568,320),Rect2i(16,12,536,296)]]:
		viewport.size = target[0]
		ui.reflow(target[0],target[1])
		for mode in ["title","pause","won","dead","abandoned"]:
			var arranged := snapshot.duplicate(true)
			arranged.phase = "active" if mode == "pause" else mode
			arranged.pause_reasons = ["user"] if mode == "pause" else []
			ui.present({} if mode == "title" else arranged)
			await _settle(t)
			t.check(ui._mode == mode,"presentation arrangement enters "+mode)
			var safe := Rect2(Vector2(target[1].position),Vector2(target[1].size))
			t.check(safe.grow(1).encloses(ui._panel.get_global_rect()),mode+" panel fits safe area "+str(target[0]))
			if target[0] in [Vector2i(800,450),Vector2i(450,800)]: _inside_actions(t,ui,mode+" "+str(target[0]))
			for step in range(ui._buttons.size()):
				ui.navigate("down")
				await _settle(t)
				var focused: Button = ui._buttons[ui._focus_index]
				t.check(ui._scroll.get_global_rect().grow(1).encloses(focused.get_global_rect()),mode+" pad focus reveals "+focused.text+" in "+str(target[0]))
	viewport.free()
