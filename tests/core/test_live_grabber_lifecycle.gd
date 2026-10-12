extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
func run(t) -> void:
	var fixture := G.setup()
	var sim = fixture.sim
	var state: Dictionary = fixture.state
	F.step(sim,state,Vector2.ZERO,[G.spawn("fixture:grabber")])
	if state.enemy_attack_instances.is_empty():
		t.check(false,"lifecycle starts with actual owned role attack")
		return

	var published: Dictionary = sim.enemy_attack_view(state)
	var other := state.duplicate(true)
	other.entities[0].position[0] += 10.0
	for key in ["locked_origin","locked_target"]:
		other.entities[0][key][0] += 10.0
		other.enemy_attack_instances[0][key][0] += 10.0
	t.check(sim.restore(other).get("ok",false),"different same-tick finite candidate is valid without adoption")
	t.check(sim.enemy_attack_view(state) == published,"read-only restore cannot replace currently published finite hand packet")
	var fresh_finite = load("res://game/core/run_simulation.gd").new()
	var candidate: Dictionary = fresh_finite.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(candidate.get("ok",false) and not fresh_finite.enemy_attack_view(candidate.state).ok,"finite validation alone does not adopt derived hand data")
	var candidate_before: Dictionary = candidate.state.duplicate(true)
	t.check(fresh_finite.prepare_enemy_attack_view(candidate.state).ok and candidate.state == candidate_before and fresh_finite.enemy_attack_view(candidate.state) == published,"explicit finite sample adoption preserves state clocks ledger and packet identity")

	var original := state.duplicate(true)
	for invalid_source in [null,{},[],true,5.5]:
		var bad_source := state.duplicate(true)
		bad_source.enemy_attack_instances[0].source_id = invalid_source
		var bad_before := bad_source.duplicate(true)
		var rejected: Dictionary = sim.restore(bad_source)
		t.check(not rejected.get("ok",true) and rejected.get("error_code") == "invalid_core_state" and bad_source == bad_before and state == original and sim.enemy_attack_view(state) == published,"non-String raw source fails safely without mutating candidate live state or packet: "+str(typeof(invalid_source)))
	for kind in ["orphan","duplicate","foreign","serial","profile","ledger","cap","phase","clock","lock","velocity"]:
		var bad := state.duplicate(true)
		match kind:
			"orphan": bad.entities.clear()
			"duplicate": bad.enemy_attack_instances.append(bad.enemy_attack_instances[0].duplicate(true))
			"foreign": bad.enemy_attack_instances[0].attack_id = "foreign:1:enemy:fixture:grabber:1"
			"serial": bad.enemy_attack_instances[0].attack_id = state.run_id+":enemy:fixture:grabber:01"
			"profile": bad.enemy_attack_instances[0].profile.warning_ticks = 1
			"ledger": bad.enemy_attack_instances[0].hit_target_ids = ["other"]
			"cap": bad.entities[0].role_hand_reach = 211.0
			"phase": bad.entities[0].action_state = "attack"
			"clock": bad.enemy_attack_instances[0].recover_ends_tick += 1
			"lock": bad.entities[0].locked_origin[0] += 1.0
			"velocity": bad.entities[0].velocity = [1.0,0.0]
		t.check(not sim.restore(bad).get("ok",false),"restore rejects forged role "+kind)
	t.check(state == original,"hostile restore never aliases live role")
	var copy: Dictionary = sim._tick_candidate(state)
	copy.enemy_attack_instances[0].hit_target_ids.append("player")
	t.check(state.enemy_attack_instances[0].hit_target_ids.is_empty(),"tick candidate owns nested one-hit ledger")
	for tick in range(2,80):
		if tick == 61: state.player.invulnerable_until = 70
		F.step(sim,state,Vector2.ZERO)
		if tick == 69:
			t.check(state.enemy_attack_instances[0].hit_target_ids.is_empty(),"invulnerable overlap is not an accepted hit")
		if tick == 70:
			t.check(state.enemy_attack_instances[0].hit_target_ids == ["player"],"later overlap records actual accepted damage")
		if tick in [30,60,61,70,76,77,79]:
			var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
			t.check(cold.get("ok",false) and cold.get("state") == state,"JSON cold role clock and cap roundtrip at "+str(tick))
	var before := state.duplicate(true)
	sim.set_pause(state,"user",true)
	var paused := state.duplicate(true)
	F.step(sim,state,Vector2.ZERO)
	t.check(state == paused,"pause freezes cap clocks ledger and wait")
	sim.set_pause(state,"user",false)
	t.check(state == before,"pause resume does not replay hand damage")
	var view: Dictionary = sim.enemy_attack_view(state)
	var view_before := view.duplicate(true)
	view.attacks.clear()
	t.check(sim.enemy_attack_view(state) == view_before,"view packet is detached and read-only")
	sim.abandon_run(state)
	t.check(state.enemy_attack_instances.is_empty() and sim.enemy_attack_view(state).get("attacks",[1]).is_empty(),"terminal cancels ownership and published hands")
	fixture = G.setup(); sim = fixture.sim; state = fixture.state
	F.step(sim,state,Vector2.ZERO,[G.spawn()])
	state.entities[0].hp = 1.0
	state.player.position = [130.0,0.0]
	state.player.attack_ready_ticks.blade_slash = 2
	F.step(sim,state,Vector2.ZERO)
	t.check(state.entities.is_empty() and state.enemy_attack_instances.is_empty(),"source death removes owned hand before incoming player damage")
	fixture = G.setup(); sim = fixture.sim; state = fixture.state
	F.step(sim,state,Vector2.ZERO,[G.spawn()])
	while state.active_tick < 69: F.step(sim,state,Vector2.ZERO)
	state.entities[0].hp = 1.0
	state.equipment = {"odm_dash":5}
	state.player.attack_ready_ticks = {"odm_dash":70}
	var hp: float = state.player.hp
	var death_events: Array = F.step(sim,state,Vector2.ZERO)
	t.check(state.entities.is_empty() and state.enemy_attack_instances.is_empty() and state.player.hp == hp and F.types(death_events,"damage").filter(func(e): return str(e.payload.target_id) == "player").is_empty(),"source dies on the would-be accepted hand-hit tick without ghost damage")

	fixture = G.setup(); sim = fixture.sim; state = fixture.state
	F.step(sim,state,Vector2.ZERO,[G.spawn()])
	while state.active_tick < 161: F.step(sim,state,Vector2.ZERO)
	var broken_cooldown := state.duplicate(true)
	broken_cooldown.entities[0].next_action_tick = 161
	t.check(not sim.restore(broken_cooldown).get("ok",false),"saved role cooldown cannot be shortened after its raw attack finishes")
	for field in ["attack_seq","active_tick"]:
		fixture = G.setup(); sim = fixture.sim; state = fixture.state
		state[field] = 2147483647
		var snapshot := state.duplicate(true)
		var overflow_events: Array = F.step(sim,state,Vector2.ZERO,[G.spawn()])
		t.check(state == snapshot and overflow_events.is_empty() and not sim.step_status().ok,"role counter exhaustion is atomic: "+field)

