extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
func run(t) -> void:
	var catalog := Catalog.new()
	t.check(catalog.equipment.has("chain_lightning"),"chain lightning is registered in actual equipment catalog")
	if not catalog.equipment.has("chain_lightning"): return
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	t.check(not state.has("error_code"),"fantasy provider starts current Core")
	if state.has("error_code"): return
	var selected := false
	for seed in range(1,65):
		state = X.state(sim,seed)
		F.drop_xp(sim,state,24,"xp")
		for option in state.upgrade_offer.get("options",[]):
			if option.item_id == "chain_lightning":
				selected = sim.choose_upgrade(state,state.upgrade_offer.offer_id,option.option_id).get("ok",false)
				break
		if selected: break
	t.check(selected and state.equipment.get("chain_lightning") == 1,"actual XP offer selection acquires chain lightning")
	if not selected: return
	state.player.attack_ready_ticks.blade_slash = 10000
	var commands := [F.spawn("z",[100,-20],"brute"),F.spawn("a",[100,20],"brute"),F.spawn("c",[150,20],"brute"),F.spawn("d",[200,20],"brute")]
	var events := F.step(sim,state,Vector2.ZERO,commands)
	var hits := X.hits(events)
	t.check(hits.size() == 3,"Lv1 chain hits exactly three separate targets")
	var ids := []
	for event in hits: ids.append(str(event.payload.target_id))
	t.check(ids == ["a","z","c"],"nearest link order uses stable ID ties and previous target origin")
	var attacks: Array = F.types(events,"player_attack").filter(func(e): return e.payload.base_item_id == "chain_lightning")
	t.check(attacks.size() == 3,"each actual chain segment has a player_attack event")
	for event in attacks:
		t.check(event.payload.geometry.shape == "line" and event.payload.execute_tick == state.active_tick and event.tick == state.active_tick,"chain geometry is actual same-tick line geometry")
	t.check(Bridge.new().validate_batch(events,sim.snapshot(state)),"chain event batch satisfies existing VFX bridge boundary")
	t.check(state.player_attack_instances.is_empty(),"instant chains leave no phantom pending state")
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state))))
	t.check(restored.get("ok",false),"actual chain combat snapshot cold-restores")
	if restored.get("ok",false):
		t.check(F.step(sim,state,Vector2.ZERO) == F.step(sim,restored.state,Vector2.ZERO),"restored chain run has exact next-tick events")
	for level in range(1,6):
		var stats: Dictionary = catalog.weapon_stats(state,"chain_lightning",level)
		t.check(stats.get("chain_count") == level+2,"chain count grows finitely to seven at Lv5")
	state.equipment.chain_lightning = 5
	t.check(not catalog.candidates(state).any(func(o): return o.item_id == "chain_lightning"),"max-level chain never appears as an unlimited upgrade")
