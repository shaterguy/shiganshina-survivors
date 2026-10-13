extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	_full_queue(t)
	_cross_family_identity(t)
func _old_evolved(sim) -> Dictionary:
	var state: Dictionary = X.state(sim)
	state.equipment = {"wall_cannon":5,"fire_zone":1,"chain_lightning":1,"ally_cover":1}
	state.player.attack_ready_ticks.ally_cover = 2147483647
	state.tactical_seals = 1
	state.passives = {"fire_interval":3}
	var recipe: Dictionary = sim._catalog.evolutions.definition("evo_crossfire")
	for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
	state.evolutions = {"wall_cannon":"evo_crossfire"}
	state.active_tick = 18099
	state.survival_tick = 18099
	state.boss_ids_fired = ["ch01_b05"]
	state.reward_ids_claimed = ["boss:ch01_b05"]
	state.stats.minibosses_defeated = 1
	state.stats.kills = 1
	return state
func _full_queue(t) -> void:
	var sim = X.simulation()
	var state := _old_evolved(sim)
	for cast in 32:
		var proposal: Dictionary = sim._evolved.reserve(state,"wall_cannon",Vector2(500,0),Vector2.RIGHT,state.run_id+":attack:"+str(int(state.attack_seq)+1))
		state.attack_seq = int(state.attack_seq)+1
		state.player_attack_instances.append_array(proposal.records)
	state.player.attack_ready_ticks.wall_cannon = 20000
	t.check(sim.restore(state).get("ok",false),"64 actual legacy reservations form a valid bounded state")
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("capacity-target",[100,0],"brute")])
	var deferred := F.types(events,"player_attack_deferred")
	t.check(deferred.size() == 2,"both new skills observably defer when the complete reservation does not fit")
	t.check(state.attack_seq == 32 and state.player_attack_instances.size() == 64,"capacity rejection never partially reserves or consumes cast IDs")
	var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state)))
	t.check(cold.get("ok",false),"capacity retry readiness cold restores")
	if not cold.get("ok",false): return
	for tick in 36:
		var live := F.step(sim,state,Vector2.ZERO)
		var replay := F.step(sim,cold.state,Vector2.ZERO)
		t.check(live == replay,"capacity retry and release replay exactly")
		if tick < 35: t.check(F.types(live,"player_attack_deferred").is_empty(),"capacity waits until known release instead of logging every tick")
	t.check(state.attack_seq > 32,"new cast resumes automatically after finite reservations release")
func _cross_family_identity(t) -> void:
	var sim = X.simulation()
	var state := _old_evolved(sim)
	state.player.attack_ready_ticks = {"wall_cannon":20000,"chain_lightning":20000,"ally_cover":2147483647}
	F.step(sim,state,Vector2.ZERO,[F.spawn("identity-target",[100,0],"brute")])
	t.check(state.player_attack_instances.size() == 3,"fire identity fixture has actual pending pulses")
	if state.player_attack_instances.size() != 3: return
	var proposal: Dictionary = sim._evolved.reserve(state,"wall_cannon",Vector2(80,0),Vector2.RIGHT,state.run_id+":attack:"+str(int(state.attack_seq)+1))
	state.attack_seq = int(state.attack_seq)+1
	state.player_attack_instances.append_array(proposal.records)
	t.check(sim.restore(state).get("ok",false),"distinct fantasy and legacy cast identities coexist")
	var collision: Dictionary = state.duplicate(true)
	var first: Dictionary = collision.player_attack_instances[0]
	for record in collision.player_attack_instances:
		if record.base_item_id == "wall_cannon":
			record.cast_id = first.cast_id
			record.attack_id = first.cast_id+":"+str(int(record.stage_index))
	t.check(not sim.restore(collision).get("ok",false),"cross-family cast identity collisions fail closed")
