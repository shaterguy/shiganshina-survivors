extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
class HiddenStore:
	extends "res://game/persistence/game_save_store.gd"
	var hide_load := false
	func read_game() -> Dictionary:
		return {"ok":false,"error_code":"read_failed"} if hide_load else super.read_game()
func run(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var app = f.app
	app.start_run(45)
	# Existing finite pre-final fixture; real director, Core escape and Store
	# settlement execute. This does not certify a complete streamed playthrough.
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	app.advance_frame(1.0/60.0)
	var skipped := 112499-int(app.state.active_tick)
	app.state.active_tick = 112499
	for entity in app.state.entities:
		for field in ["action_started_tick","action_ends_tick","next_action_tick"]: entity[field] = int(entity[field])+skipped
	for hazard in app.state.telegraphs:
		for field in ["created_tick","active_from_tick","expires_tick"]: hazard[field] = int(hazard[field])+skipped
	app.state.player.position = [0,350]
	t.check(app.simulation.restore(app.state).get("ok",false),"real pre-exit fixture remains restorable")
	app.advance_frame(1.0/60.0)
	t.check(app.state.phase == "won" and "mikasa_01" in app.game_save.profile.unlocked_character_ids,"actual victory settlement unlocks the visible character")
	var store = HiddenStore.new(f.directory,Callable(app.simulation,"restore"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hide_load = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.ui.open_loadout()
	app.ui._supply_panel.option_button("character_id","mikasa_01").pressed.emit()
	t.check(not app._pending_transaction.is_empty(),"unknown character save preserves existing pending transaction barrier")
	t.check(app.profile.get("selected_character_id","garrison_01") == "garrison_01" and not app.ui._supply_panel.option_button("character_id","mikasa_01").text.contains("[선택]"),"unknown save never marks the candidate selected")
	for option in app.supply_view().character_options:
		t.check(not option.can_select and option.blocked_reason == "commit_outcome_unknown","pending character projection cannot offer another selection")
	var serial: int = app.game_save.store_revision
	app.apply_character_selection("garrison_01",app._view_revision)
	t.check(app.game_save.store_revision == serial,"another input cannot commit through unknown outcome")
	store.hide_load = false
	store._fault_injector = Callable()
	app.resolve_pending_transaction()
	t.check(app._pending_transaction.is_empty() and app.profile.selected_character_id == "mikasa_01" and app.ui._supply_panel.option_button("character_id","mikasa_01").text.contains("[선택]"),"confirmed readback publishes the durable character selection")
	app.free()
