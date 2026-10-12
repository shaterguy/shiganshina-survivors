extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
const Fantasy = preload("res://game/combat/fantasy_attack_resolver.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func _state(sim, permanent := false) -> Dictionary:
	var config := F.run_config()
	config.character_id = "mikasa_01"
	config.character_skill_revision = 1
	if permanent: config.permanent_upgrades = {"permanent_might":1}
	var state: Dictionary = sim.new_run(F.chapter(),91,config)
	state.player.attack_ready_ticks.blade_slash = Signature.MAX_COUNTER
	return state
func _hits(events: Array) -> Array:
	return events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == Signature.TOKEN)
func run(t) -> void:
	_permanent_damage(t)
	_counter_edges(t)
	_identity_rejection(t)
func _permanent_damage(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim,true)
	state.passives.damage = 1
	t.check(state.rules.permanent_damage_bonus == 0.05,"signature uses permanent bonus derived by actual new-run authority")
	var first := F.step(sim,state,Vector2.ZERO,[F.spawn("permanent-signature",[65,0],"brute")])
	var amounts := []
	var ticks := []
	var small: float = 18.0*(1.0+0.05+0.15)
	var large: float = 36.0*(1.0+0.05+0.15)
	var expected_total := small
	var expected_hp := 100.0-small
	for hit in _hits(first): amounts.append(hit.payload.amount); ticks.append(hit.tick)
	var saved := JSON.stringify(state,"",true,true)
	for checkpoint_tick in [1,9]:
		# Aggregate stats and HP retain the existing JSON numeric representation.
		# Unlike pending damage, they are not canonicalized on restore.
		expected_total = float(JSON.parse_string(JSON.stringify(expected_total,"",true,true)))
		expected_hp = float(JSON.parse_string(JSON.stringify(expected_hp,"",true,true)))
		var cold = F.simulation(t)
		var restored: Dictionary = cold.restore(JSON.parse_string(saved))
		t.check(restored.get("ok",false),"permanent plus passive signature cold-restores after strike at tick %d" % checkpoint_tick)
		if not restored.get("ok",false): return
		state = restored.state
		for record in state.player_attack_instances:
			var expected: float = Signature.DAMAGE[int(record.stage_index)]*(1.0+0.05+0.15)
			t.check(record.damage == expected and record.cast_damage_level == 1,"cold signature damage is uniquely canonicalized from frozen global bonuses")
		for i in 8:
			for hit in _hits(F.step(cold,state,Vector2.ZERO)):
				amounts.append(hit.payload.amount); ticks.append(hit.tick)
		expected_total += small if checkpoint_tick == 1 else large
		expected_hp -= small if checkpoint_tick == 1 else large
		saved = JSON.stringify(state,"",true,true)
	t.check(ticks == [1,9,17] and amounts == [small,small,large],"actual three hits apply permanent and passive bonuses exactly once through both JSON resumes")
	t.check(state.stats.kills == 0 and state.entities.size() == 1 and state.stats.damage_dealt == expected_total and state.entities[0].hp == expected_hp,"permanent signature totals agree with real HP and damage authority without an early kill")
	var bad: Dictionary = JSON.parse_string(saved)
	bad.rules.permanent_damage_bonus += 0.00000001
	t.check(not sim.restore(bad).get("ok",false),"restoration cannot substitute a different permanent bonus")
func _counter_edges(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	state.active_tick = Signature.MAX_COUNTER-Signature.COOLDOWN-1
	state.survival_tick = 108000
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("last-legal-cast",[65,0],"brute")])
	t.check(sim.step_status().get("ok",false) and _hits(events).size() == 1,"actual Core admits a cast exactly at MAX_COUNTER minus cooldown")
	t.check(state.character_skill.ready_tick == Signature.MAX_COUNTER and state.character_skill.next_probe_tick == Signature.MAX_COUNTER and state.player_attack_instances.size() == 2,"last legal cast retains MAX cooldown and only two future stages without wrap")
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false),"last legal cast checkpoint cold-restores at the counter boundary")
	var next := _state(sim)
	next.active_tick = Signature.MAX_COUNTER-Signature.COOLDOWN
	next.survival_tick = 108000
	events = F.step(sim,next,Vector2.ZERO,[F.spawn("too-late-cast",[65,0],"brute")])
	t.check(sim.step_status().get("ok",false) and _hits(events).is_empty() and next.attack_seq == 0 and next.character_skill == Signature.initial_state(),"next tick refuses new cast before query or clock mutation")
	# Runtime admission stops 720 ticks before MAX. The closed saved-clock
	# validator still clamps its six-tick allowance; it must never wrap to zero.
	var resolver := Signature.new()
	var probe := _state(sim)
	probe.active_tick = 40; probe.survival_tick = 40
	probe.character_skill.next_probe_tick = 46
	t.check(resolver.validate_records(probe),"six-tick no-target allowance accepts its exact boundary")
	probe.character_skill.next_probe_tick = 47
	t.check(not resolver.validate_records(probe),"six-tick no-target allowance rejects the next tick")
	probe.active_tick = Signature.MAX_COUNTER-5; probe.survival_tick = 108000
	probe.character_skill.next_probe_tick = Signature.MAX_COUNTER
	t.check(sim.restore(JSON.parse_string(JSON.stringify(probe,"",true,true))).get("ok",false),"six-tick saved probe bound saturates at MAX and cold-restores")
	probe.character_skill.next_probe_tick = Signature.MAX_COUNTER+1
	t.check(not resolver.validate_records(probe),"saturated probe rejects overflow instead of wrapping")
	probe.character_skill.next_probe_tick = 0
	t.check(not resolver.validate_records(probe),"saturated probe rejects zero wrap")
func _identity_rejection(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	F.step(sim,state,Vector2.ZERO,[F.spawn("identity-target",[65,0],"brute")])
	for mode in ["mixed_cast","duplicate_id","mixed_owner"]:
		var bad := state.duplicate(true)
		if mode == "mixed_cast":
			bad.attack_seq = 2
			bad.player_attack_instances[1].cast_id = bad.run_id+":attack:2"
			bad.player_attack_instances[1].attack_id = bad.run_id+":attack:2:2"
		elif mode == "duplicate_id": bad.player_attack_instances.append(bad.player_attack_instances[0].duplicate(true))
		else:
			var other: Dictionary = bad.player_attack_instances[0].duplicate(true)
			other.base_item_id = "blade_slash"
			other.attack_id = other.cast_id+":0"
			bad.player_attack_instances.append(other)
		var before := JSON.stringify(bad,"",true,true)
		t.check(not sim.restore(bad).get("ok",false),"Core rejects signature "+mode)
		t.check(JSON.stringify(bad,"",true,true) == before,"rejected signature "+mode+" is side-effect free")
	# These intentionally minimal records isolate the retained whole-array ID
	# and owner guards from the family-specific closed-record validators.
	var global_only := {"player_attack_instances":[{"attack_id":"same:1","cast_id":"cast","base_item_id":Signature.TOKEN},{"attack_id":"same:1","cast_id":"cast","base_item_id":Signature.TOKEN}]}
	t.check(not Fantasy.validate_records(global_only,Catalog.new()),"whole-array guard rejects duplicate signature IDs before per-family validation")
	global_only.player_attack_instances[1].attack_id = "different:2"
	global_only.player_attack_instances[1].base_item_id = "blade_slash"
	t.check(not Fantasy.validate_records(global_only,Catalog.new()),"whole-array guard rejects mixed ownership of one cast")
