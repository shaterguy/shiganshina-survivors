extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var assembly: Dictionary = Support.new().make(t)
	var app = assembly.app
	app.start_run(42)
	var pause_requests := [0]
	app.ui.pause_changed.connect(func(_enabled):pause_requests[0] += 1)
	app.ui.get_node("Pause").pressed.emit()
	t.check(pause_requests[0] == 1 and "user" in app.state.pause_reasons and app.audio._last_played.has("cancel"),"actual touch pause produces one pause action and one mapped cancel sound")
	var state_bytes: String = JSON.stringify(app.state)
	var save_bytes: String = JSON.stringify(app.game_save)
	var ui = app.ui
	var counts := {"actions":0,"audio":0,"last":""}
	ui.audio_requested.connect(func(id): counts.audio += 1;counts.last = id)
	ui._clear_choices()
	var button: Button = ui._add_button("오디오 검증",func(): counts.actions += 1)
	ui._register_button(button);ui._register_button(button)
	ui.reflow(Vector2i(1600,900),Rect2i(0,0,1600,900))
	ui.reflow(Vector2i(900,1600),Rect2i(0,0,900,1600))
	ui._focus_index = 0;ui.accept_released();app.audio.reset_presentation()
	ui.navigate("accept")
	t.check(counts.actions == 1 and counts.audio == 1 and counts.last == "select","registered/reflowed gamepad accept emits one action and one audio signal")
	t.check(app.audio._last_played.has("select"),"real Controller connects UI confirmation to actual audio player")
	t.check(JSON.stringify(app.state) == state_bytes and JSON.stringify(app.game_save) == save_bytes,"UI-only audio leaves paused Core and save authority bytes unchanged")
	ui._accept_transition_gate = true;ui.navigate("accept")
	t.check(counts.actions == 1 and counts.audio == 1,"transition accept gate suppresses both repeat action and audio")
	ui.accept_released();button.disabled = true;ui.navigate("accept")
	t.check(counts.actions == 1 and counts.audio == 1,"disabled gamepad choice emits neither action nor audio")
	button.pressed.emit()
	t.check(counts.audio == 1,"even directly emitted disabled button signal cannot request audio")
	button.disabled = false
	var actions_before: int = counts.actions
	button.text = "돌아가기";button.pressed.emit()
	t.check(counts.actions == actions_before+1 and counts.audio == 2 and counts.last == "cancel","pointer-style button press invokes one action and tactile cancel")
	app.audio.reset_presentation();app._foreground = false;ui.audio_requested.emit("select")
	t.check(not app.audio._last_played.has("select"),"background Controller rejects UI audio without touching authority")
	app._foreground = true
	ui.present_recovery({"kind":"blocked","lifecycle_blocked":true})
	var before: int = counts.audio;ui.navigate("cancel")
	t.check(counts.audio == before,"blocked recovery cancel remains silent")
	t.check(JSON.stringify(app.state) == state_bytes and JSON.stringify(app.game_save) == save_bytes,"lifecycle and recovery audio guards preserve exact state and save bytes")
	app.request_end_run()
	await t.process_frame;await t.process_frame
	var previous_run: String = app.state.run_id
	t.check(not ui._buttons.is_empty(),"settled screen exposes a current button before new-run rebuild")
	if ui._buttons.is_empty():
		app.free();return
	var old_button: WeakRef = weakref(ui._buttons[0])
	app.start_run(42)
	await t.process_frame;await t.process_frame
	t.check(app.state.run_id != previous_run and old_button.get_ref() == null,"actual changed run releases the immediately preceding button callback owner")
	t.check(ui.audio_requested.get_connections().size() == 2,"new run does not duplicate Controller or observation hookup")
	var saved: Dictionary = app.simulation.snapshot(app.state)
	t.check(app.game_save.checkpoint == saved,"restore fixture is the exact currently committed checkpoint")
	app.state = {};app.pending_checkpoint = saved.duplicate(true);app.request_resume()
	t.check(not app.state.is_empty() and app.pending_checkpoint.is_empty() and app.state.run_id == saved.run_id and app.state.active_tick == saved.active_tick and app.state.rng_state == saved.rng_state and app.game_save.checkpoint == app.simulation.snapshot(app.state) and app._pending_transaction.is_empty() and app._city_step_error.is_empty() and app._city_render_error.is_empty(),"actual committed checkpoint restores successfully with exact identity and no pending transaction/error")
	t.check(ui.audio_requested.get_connections().size() == 2,"restore keeps exactly one Controller audio hookup")
	var restored_state: String = JSON.stringify(app.state)
	var restored_save: String = JSON.stringify(app.game_save)
	app.audio.reset_presentation();ui.audio_requested.emit("select")
	t.check(app.audio._last_played.has("select") and JSON.stringify(app.state) == restored_state and JSON.stringify(app.game_save) == restored_save,"restored Controller plays UI audio without rewriting current snapshot or save")
	var old_ui: WeakRef = weakref(ui)
	app.free();await t.process_frame
	t.check(old_ui.get_ref() == null,"Controller teardown frees signal owner without stale UI callback")
