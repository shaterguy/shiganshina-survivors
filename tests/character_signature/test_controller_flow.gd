extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
const Characters = preload("res://game/progression/character_catalog.gd")
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var app = f.app
	t.check(app.has_method("apply_character_selection"),"Controller exposes the authoritative character selection path")
	if not app.has_method("apply_character_selection"):
		app.free()
		return
	app.start_run(45)
	var base_move_speed: float = app.state.rules.move_speed
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
	app.ui.open_loadout()
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.ui._supply_panel.option_button("character_id","mikasa_01").pressed.emit()
	t.check(app.profile.get("selected_character_id","garrison_01") == "garrison_01","failed character save cannot alter authoritative selection")
	t.check(not app.ui._supply_panel.option_button("character_id","mikasa_01").text.contains("[선택]"),"failed save cannot mark the prototype selected")
	app.save_store._fault_injector = Callable()
	app.ui._supply_panel.option_button("character_id","mikasa_01").pressed.emit()
	t.check(app.profile.selected_character_id == "mikasa_01" and app.ui._supply_panel.option_button("character_id","mikasa_01").text.contains("[선택]"),"readback-confirmed profile alone marks new character selected")
	var restored = support.restart(t,f.directory)
	t.check(restored.profile.selected_character_id == "mikasa_01","cold Controller preserves selected character")
	restored.start_run(46)
	t.check(restored.state.character_id == "mikasa_01" and is_equal_approx(restored.state.rules.move_speed,base_move_speed*1.08),"selected character reaches next actual run and its movement trait")
	var before: Dictionary = restored.game_save.duplicate(true)
	restored.apply_character_selection("garrison_01",restored._view_revision)
	t.check(restored.game_save == before and restored.state.character_id == "mikasa_01","active run cannot switch character through direct Controller action")
	t.check(restored.state.run_config.get("character_skill_revision") == 1,"confirmed next-run transaction opts into signature revision 1")
	t.check(Characters.new().definition("mikasa_01").unique_skill.implementation_status == "implemented","only implemented unique skill metadata is promoted")
	if not restored.state.has("character_skill"):
		app.free()
		restored.free()
		return
	var profile_before: Dictionary = restored.game_save.profile.duplicate(true)
	var receipts_before: Array = restored.game_save.get("settlement_receipts",[]).duplicate(true)
	restored.state.player.attack_ready_ticks.blade_slash = 10000
	var first := F.step(restored.simulation,restored.state,Vector2.ZERO,[F.spawn("cold-target",[65,0],"brute")])
	t.check(_strikes(first).size() == 1,"actual selected run uses first signature strike")
	restored._save_checkpoint()
	var cold = support.restart(t,f.directory)
	cold.request_resume()
	t.check(cold.state.get("character_skill",{}).get("pending_cast_id","") != "" and cold.state.player_attack_instances.size() == 2,"cold Store and Controller resume only two future stages")
	var counts := 0
	for i in 8: counts += _strikes(F.step(cold.simulation,cold.state,Vector2.ZERO)).size()
	t.check(counts == 1 and cold.state.active_tick == 9,"cold Controller resumes second hit once")
	cold._save_checkpoint()
	var final_cold = support.restart(t,f.directory)
	final_cold.request_resume()
	t.check(final_cold.state.player_attack_instances.size() == 1,"second cold Store round trip retains only final stage")
	counts = 0
	for i in 8: counts += _strikes(F.step(final_cold.simulation,final_cold.state,Vector2.ZERO)).size()
	t.check(counts == 1 and final_cold.state.character_skill.pending_cast_id == "" and final_cold.state.character_skill.ready_tick == 721,"cold final strike neither replays previous strikes nor resets cooldown")
	t.check(final_cold.game_save.profile == profile_before and final_cold.game_save.get("settlement_receipts",[]) == receipts_before,"signature checkpoints preserve profile wallet unlocks and receipts")
	app.free()
	restored.free()
	cold.free()
	final_cold.free()
func _strikes(events: Array) -> Array:
	return events.filter(func(e): return e.type == "player_attack" and e.payload.get("base_item_id") == Signature.TOKEN and e.payload.get("phase") == "executed")
