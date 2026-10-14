extends RefCounted
# Real city/Core/Store flow. Only prerequisite levels and earned XP are arranged;
# the offer, evolution choice, durable save, resume and replacement are product APIs.
const Async = preload("res://tests/app_async_autosave/test_default_worker.gd")
const CitySupport = preload("res://tests/app_city_controller/controller_city_support.gd")
const Legacy = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const Frozen = preload("res://tests/core/frozen_gameplay_fixture.gd")
const Supply = preload("res://game/economy/supply_service.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const ROOT := "res://tests/fixtures/evolution_supply_grabber/"
func run(t) -> void:
	await _current_city(t)
	_legacy_choice(t)
func _current_city(t) -> void:
	var support := Async.new()
	var app = support._fixture(t,"evolved_settlement")
	if app == null: return
	var directory: String = app.save_store._directory
	app.state.equipment = {"blade_slash":5,"odm_dash":1}
	app.state.player.attack_ready_ticks = {"blade_slash":2147483647,"odm_dash":2147483647}
	app.state.player.xp = int(app.state.rules.progression.base_xp)
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation._last_step_status.get("ok",false),"current arranged prerequisites reach actual XP offer through an accepted city tick")
	t.check(not app.state.upgrade_offer.is_empty(),"actual city XP produces an evolution selection window")
	if app.state.upgrade_offer.is_empty(): app.free(); return
	var offer_id: String = app.state.upgrade_offer.offer_id
	app.apply_upgrade(offer_id,"evolution:evo_wing_cut")
	await support._drain(t,app)
	t.check(app.state.evolutions == {"blade_slash":"evo_wing_cut"} and app.state.upgrade_offer.is_empty(),"actual Controller evolution choice commits")
	if app.state.evolutions.is_empty(): app.free(); return
	t.check(app.state.tactical_seals == 0 and app.state.stats.minibosses_defeated == 0,"schema2 evolution spends no boss seal")
	var disk: Dictionary = app.save_store.read_game()
	t.check(disk.get("ok",false) and disk.game_save.checkpoint.evolutions == app.state.evolutions,"real Store confirms evolved checkpoint before restart")
	var old_id: String = app.state.run_id
	var serial: int = app.state.run_serial
	var profile: Dictionary = app.profile.duplicate(true)
	var old_receipts: int = app.game_save.settlement_receipts.size()
	app.free()
	var cold := CitySupport.make(t,directory)
	if cold.is_empty(): return
	app = cold.app
	app.autosave_worker_enabled = true
	t.check(app.state.is_empty() and not app.pending_checkpoint.is_empty(),"cold current city exposes the durable evolved checkpoint")
	app.request_resume()
	await support._drain(t,app)
	t.check(not app.state.is_empty() and app.state.get("evolutions",{}) == {"blade_slash":"evo_wing_cut"},"Continue resumes the actual evolved checkpoint")
	if app.state.is_empty(): app.free(); return
	var terminal: Dictionary = app.simulation.snapshot(app.state)
	app.simulation.abandon_run(terminal)
	_evidence_guards(t,app.supply_service,app.game_save,terminal,0)
	var before: Dictionary = app.game_save.duplicate(true)
	var prepared: Dictionary = app.supply_service.prepare_settlement(before,terminal)
	t.check(prepared.get("ok",false),"current seal-free evolved terminal is accepted for settlement: "+str(prepared.get("error_code","")))
	t.check(app.game_save == before,"settlement proposal preserves original authority")
	app.request_new_run(43,true,old_id)
	await support._drain(t,app)
	t.check(app.state.get("run_serial",0) == serial+1 and app.state.get("seed",0) == 43 and app.state.get("phase","") == "survival","resumed evolved run settles and starts a fresh run without invalid_snapshot")
	t.check(app.game_save.settled_through_serial == serial and app.game_save.settlement_receipts.size() == old_receipts+1,"evolved replacement produces exactly one settlement receipt")
	for key in ["permanent_upgrades","unlocked_character_ids","selected_character_id","owned_doctrine_ids","consumables"]:
		t.check(app.profile.get(key) == profile.get(key),"evolved replacement preserves career field "+key)
	var final_authority: Dictionary = app.game_save.duplicate(true)
	app.request_new_run(43,true,old_id)
	await support._drain(t,app)
	t.check(app.game_save == final_authority,"stale replacement cannot settle or start the old evolved run twice")
	app.free()
func _legacy_choice(t) -> void:
	var core = Frozen.simulation()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"actual_evolution_ready.json"))
	var restored: Dictionary = core.restore(source)
	t.check(restored.get("ok",false),"genuine schema1 pending evolution fixture restores")
	if not restored.get("ok",false): return
	var state: Dictionary = restored.state
	var choice: Dictionary = core.choose_upgrade(state,state.upgrade_offer.offer_id,"evolution:evo_wing_cut")
	t.check(choice.get("ok",false) and state.evolutions == {"blade_slash":"evo_wing_cut"} and state.tactical_seals == 0,"actual legacy choice still spends its one earned boss seal")
	if not choice.get("ok",false): return
	var directory := "user://legacy_evolved_settlement_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec()]
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"game_save_v2.json")).started
	envelope.checkpoint = state
	Legacy.write(directory.path_join("game_save.json"),JSON.stringify(envelope,"",true,true))
	var cold = Frozen.simulation()
	var store := Save.new(directory,Callable(cold,"restore"))
	var loaded: Dictionary = store.read_game()
	t.check(loaded.get("ok",false),"real Store cold-loads legacy chosen evolution")
	if not loaded.get("ok",false): return
	var service := Supply.new(Callable(cold,"new_run"))
	var definitions := Frozen.inputs()
	service._upgrades = Upgrades.new(definitions["data/equipment.json"],definitions["data/passives.json"],definitions["data/evolutions.json"])
	var terminal: Dictionary = loaded.game_save.checkpoint.duplicate(true)
	cold.abandon_run(terminal)
	_evidence_guards(t,service,loaded.game_save,terminal,1)
	var prepared: Dictionary = service.prepare_settlement(loaded.game_save,terminal)
	t.check(prepared.get("ok",false),"legacy seal-cost-one evolved run still settles")
	if not prepared.get("ok",false): return
	var committed: Dictionary = store.commit_game(prepared.candidate,int(loaded.game_save.store_revision))
	t.check(committed.get("ok",false),"real Store persists legacy evolved settlement")
	if not committed.get("ok",false): return
	var repeated: Dictionary = service.prepare_settlement(committed.game_save,terminal)
	t.check(repeated.get("ok",false) and repeated.get("already_applied",false) and not repeated.has("candidate"),"legacy evolved settlement retry is receipt-only")
func _evidence_guards(t,service,save: Dictionary,terminal: Dictionary,expected_spent: int) -> void:
	t.check(int(terminal.stats.minibosses_defeated) == int(terminal.tactical_seals)+expected_spent,"fixture boss/seal relationship matches its actual content recipe")
	for mutation in ["extra_seal","unknown_evolution","duplicate_boss","unknown_reward","boss_count"]:
		var bad: Dictionary = terminal.duplicate(true)
		match mutation:
			"extra_seal": bad.tactical_seals += 1
			"unknown_evolution": bad.evolutions.blade_slash = "evo_unknown"
			"duplicate_boss": bad.reward_ids_claimed.append("boss:ch01_b05"); bad.reward_ids_claimed.append("boss:ch01_b05")
			"unknown_reward": bad.reward_ids_claimed.append("unearned:reward")
			"boss_count": bad.stats.minibosses_defeated += 1
		var before := save.duplicate(true)
		var result: Dictionary = service.prepare_settlement(save,bad)
		t.check(not result.get("ok",false) and not result.has("candidate") and save == before,"settlement rejects "+mutation+" under seal cost "+str(expected_spent))
