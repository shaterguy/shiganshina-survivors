extends RefCounted
# Explicit legacy test arrangement: already-earned boss ledger plus prerequisites.
# The current production runtime must resolve this archived city fingerprint,
# create the actual legacy offer and spend the original one-seal recipe cost.
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var directory := F.install("evolved_settlement_route")
	var fixture := S.make(t,directory)
	if fixture.is_empty(): return
	var app = fixture.app
	app.request_resume()
	t.check(not app.state.is_empty() and app.simulation._catalog.evolutions._schema_version == 1,"production runtime resumes the archived schema1 city")
	if app.state.is_empty(): app.free(); return
	var recipe: Dictionary = app.simulation._catalog.evolutions.definition("evo_wing_cut")
	app.state.equipment = {recipe.base_item_id:5}
	for requirement in recipe.required_passives: app.state.passives[requirement.passive_id] = int(requirement.level)
	app.state.player.attack_ready_ticks = {recipe.base_item_id:2147483647}
	app.state.world.dormant.entities.clear()
	app.state.world.dormant.drops.clear()
	app.state.stats.kills = 1
	app.state.stats.minibosses_defeated = 1
	app.state.reward_ids_claimed.append("boss:ch01_b05")
	app.state.tactical_seals = 1
	var prepared: Dictionary = app._city_runtime.refresh_coverage(app.state)
	t.check(prepared.get("ok",false),"complete arranged legacy earned-seal checkpoint passes full production Core admission")
	if not prepared.get("ok",false): app.free(); return
	app._adopt_city_simulation(prepared.simulation)
	app.state = prepared.state
	app.state.player.xp = int(app.state.rules.progression.base_xp)
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation._last_step_status.get("ok",false) and not app.state.upgrade_offer.is_empty(),"production legacy Core opens the actual ready evolution offer")
	if app.state.upgrade_offer.is_empty(): app.free(); return
	app.apply_upgrade(app.state.upgrade_offer.offer_id,"evolution:evo_wing_cut")
	t.check(app.state.evolutions == {"blade_slash":"evo_wing_cut"} and app.state.tactical_seals == 0,"Controller commits actual legacy evolution and spends one seal")
	if app.state.evolutions.is_empty(): app.free(); return
	var saved: Dictionary = app.save_store.read_game()
	t.check(saved.get("ok",false) and saved.game_save.checkpoint.evolutions == app.state.evolutions,"production Store verifies legacy city evolved checkpoint")
	var terminal: Dictionary = app.state.duplicate(true)
	app.simulation.abandon_run(terminal)
	t.check(app.supply_service._upgrades.evolutions._schema_version == 2 and app.supply_service._content_resolver.is_valid(),"shop remains current while settlement resolves saved content independently")
	var settled: Dictionary = app.supply_service.prepare_settlement(app.game_save,terminal)
	t.check(settled.get("ok",false),"content resolver uses archived seal1 rather than current seal0 for settlement")
	if settled.get("ok",false):
		var files_before := F.bytes(directory)
		for mutation in ["kept_spent_seal","current_fingerprint","inflated_reward"]:
			var bad: Dictionary = settled.candidate.duplicate(true)
			match mutation:
				"kept_spent_seal": bad.checkpoint.tactical_seals = 1
				"current_fingerprint": bad.checkpoint.rules.content_fingerprint = app._city_runtime.resolve_content().chapter.content_fingerprint
				"inflated_reward":
					bad.profile.supply_credits += 1
					bad.settlement_receipts.back().total += 1
					bad.settlement_receipts.back().balance_after += 1
					bad.settlement_receipts.back().breakdown.minibosses += 1
			var rejected: Dictionary = app.save_store.commit_game(bad,int(app.game_save.store_revision))
			t.check(not rejected.get("ok",false) and F.bytes(directory) == files_before,"real Store rejects "+mutation+" without changing any authority bytes")
		var adapter_authority := F.legacy_authority(directory)
		t.check(not adapter_authority.is_empty() and adapter_authority.store._transition_valid(app.game_save,settled.candidate),"world adapter settlement uses its bound legacy Core catalog too")
	var forged := terminal.duplicate(true)
	forged.tactical_seals = 1
	t.check(not app.supply_service.prepare_settlement(app.game_save,forged).get("ok",false),"legacy city cannot keep its spent seal even though current recipes are free")
	var old_id: String = app.state.run_id
	var old_serial: int = app.state.run_serial
	app.request_new_run(77,true,old_id)
	t.check(app.state.get("run_serial",0) == old_serial+1 and app.state.get("seed",0) == 77 and app.simulation._catalog.evolutions._schema_version == 2,"legacy evolved run settles under old rules then starts under current rules")
	app.free()
