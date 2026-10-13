extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
class HiddenStore:
	extends "res://game/persistence/game_save_store.gd"
	var hide_load := false
	var read_calls := 0
	func read_game() -> Dictionary:
		read_calls += 1
		return {"ok":false,"error_code":"read_failed"} if hide_load else super.read_game()
func run(t) -> void:
	for action in ["run_start","upgrade"]:
		for reason in ["background","controller_lost"]:
			_test_unknown_publication_preserves_latest_lifecycle(t,action,reason)
	_test_stale_live_checkpoint_cannot_rollback_evolution(t)
	_test_stale_pending_checkpoint_requires_fresh_explicit_resume(t)
func _test_unknown_publication_preserves_latest_lifecycle(t,action: String,reason: String) -> void:
	var support := Support.new()
	var f := support.make(t)
	var app = f.app
	if action == "upgrade":
		app.start_run(42)
		support.evolution_offer(app)
	var store = HiddenStore.new(f.directory,Callable(app.simulation,"restore"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hide_load = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	# Real input is held when the unknown commit crosses the lifecycle boundary.
	var move := InputEventJoypadMotion.new()
	move.device = 0
	move.axis = JOY_AXIS_LEFT_X
	move.axis_value = 1.0
	app.input_router.handle_event(move)
	app.input_router.set_touch_vector(Vector2.RIGHT)
	if action == "run_start": app.start_run(42)
	else: app.apply_upgrade(app.state.upgrade_offer.offer_id,app.state.upgrade_offer.options[0].option_id)
	t.check(store.read_calls > 0,"unknown fixture hides the actual existing-authority read_game API")
	t.check(not app._pending_transaction.is_empty(),"unknown %s fixture reaches actual post-rename boundary" % action)
	if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	else:
		app.input_router.active_device = 0
		app.input_router._on_connection(0,false)
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	app.input_router.handle_event(press)
	store.hide_load = false
	store._fault_injector = Callable()
	app.resolve_pending_transaction()
	var label := "unknown %s after %s" % [action,reason]
	t.check(reason in app.state.pause_reasons,label+" publishes latest runtime pause")
	t.check(not reason in app.game_save.checkpoint.pause_reasons,label+" leaves committed candidate environmental state untouched")
	t.check(app.input_router.sample_move() == Vector2.ZERO and not app.input_router._accept_armed,label+" clears retained movement and accept input")
	var before: Dictionary = app.simulation.snapshot(app.state)
	var sounds: Dictionary = app.audio._last_played.duplicate(true)
	t.check(not sounds.has("select") and not sounds.has("slash") and not sounds.has("cannon") and not sounds.has("gas"),label+" cannot play pending selection or attack sounds")
	t.check(app.audio._music.stream_paused,label+" presents paused combat music")
	for frame in 4: app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == before.active_tick and app.state.survival_tick == before.survival_tick and app.state.player.position == before.player.position and app.state.event_seq == before.event_seq,label+" advances zero combat or survival ticks")
	t.check(app.audio._last_played == sounds,label+" emits no new sounds while paused")
	if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == before.active_tick and reason in app.state.pause_reasons,label+" never auto-resumes on focus return or reconnect opportunity")
	app.request_resume()
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == before.active_tick+1 and not reason in app.state.pause_reasons,label+" resumes only after explicit continue")
	app.free()
func _test_stale_live_checkpoint_cannot_rollback_evolution(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var old = f.app
	old.start_run(42)
	support.evolution_offer(old)
	# A second controller is a disposable authority-change fixture, not a supported
	# real concurrent-play assumption. Both commits use the actual validated store.
	var writer = support.restart(t,f.directory)
	writer.request_resume()
	writer.apply_upgrade(writer.state.upgrade_offer.offer_id,writer.state.upgrade_offer.options[0].option_id)
	var newer: Dictionary = writer.save_store.load_game().game_save
	t.check(newer.checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and newer.checkpoint.tactical_seals == 1,"newer authority fixture commits real evolution")
	old.apply_upgrade(old.state.upgrade_offer.offer_id,old.state.upgrade_offer.options[0].option_id)
	t.check(old.ui._notice.text.contains("stale_revision"),"obsolete intent is rejected at authority refresh")
	t.check(old.state.is_empty() and old.pending_checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and old.pending_checkpoint.tactical_seals == 1,"authority refresh quarantines obsolete live offer and seal until explicit resume")
	old.set_user_pause(true)
	old._save_checkpoint()
	var settings: Dictionary = old.game_save.profile.settings.duplicate(true)
	settings.reduce_effects = true
	old._apply_settings(settings)
	var disk: Dictionary = old.save_store.load_game().game_save
	t.check(disk.checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and disk.checkpoint.tactical_seals == 1 and disk.checkpoint.upgrade_offer.is_empty(),"pause checkpoint and settings after stale refresh never roll back confirmed evolution")
	old.advance_frame(1.0/60.0)
	t.check(old.state.is_empty(),"quarantined authority does not automatically resume combat")
	old.request_resume()
	t.check(old.state.evolutions.get("blade_slash") == "evo_wing_cut" and old.state.tactical_seals == 1 and old.state.upgrade_offer.is_empty(),"explicit continue adopts only the newest authoritative growth checkpoint")
	old.free()
	writer.free()
func _test_stale_pending_checkpoint_requires_fresh_explicit_resume(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	f.app.start_run(42)
	support.evolution_offer(f.app)
	f.app.free()
	var reader = support.restart(t,f.directory)
	var writer = support.restart(t,f.directory)
	writer.request_resume()
	writer.apply_upgrade(writer.state.upgrade_offer.offer_id,writer.state.upgrade_offer.options[0].option_id)
	reader.request_resume()
	t.check(reader.state.is_empty() and reader.pending_checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and reader.pending_checkpoint.tactical_seals == 1,"stale pending resume quarantines current authority before exposing an obsolete run")
	reader.request_resume()
	t.check(reader.state.evolutions.get("blade_slash") == "evo_wing_cut" and reader.state.tactical_seals == 1,"fresh explicit continue restores latest pending checkpoint")
	var disk: Dictionary = reader.save_store.load_game().game_save
	t.check(disk.checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and disk.checkpoint.tactical_seals == 1,"pending-resume checkpoint write retains committed evolution")
	reader.free()
	writer.free()
