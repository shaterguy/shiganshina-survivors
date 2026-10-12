extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
const TOKEN := Signature.TOKEN
func _state(sim) -> Dictionary:
	var config := F.run_config()
	config.character_id = "mikasa_01"
	config.character_skill_revision = 1
	var state: Dictionary = sim.new_run(F.chapter(),16,config)
	state.player.attack_ready_ticks.blade_slash = 10000
	return state
func _attacks(events: Array) -> Array:
	return events.filter(func(e): return e.type == "player_attack" and e.payload.get("base_item_id") == TOKEN and e.payload.get("phase") == "executed")
func _hits(events: Array) -> Array:
	return events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == TOKEN)
func run(t) -> void:
	var sim = F.simulation(t)
	var state := _state(sim)
	t.check(sim.restore(state).get("ok",false),"new signature snapshot is structurally and semantically restorable")
	var first := F.step(sim,state,Vector2.ZERO,[F.spawn("signature-target",[65,0],"brute")])
	t.check(_attacks(first).size() == 1 and _hits(first).size() == 1,"stage zero executes and hits in the exact acquisition tick")
	if _attacks(first).is_empty(): return
	t.check(state.active_tick == 1 and state.player_attack_instances.size() == 2,"same-tick stage zero never persists as pending")
	t.check(state.character_skill.ready_tick == 721 and state.character_skill.next_probe_tick == 721,"cooldown starts at first strike and ignores blade cooldown trait")
	t.check(not _attacks(first)[0].payload.geometry.has("target_id"),"signature geometry cannot trigger wire-anchor entity scan")
	var saved := JSON.stringify(state,"",true,true)
	var cold = F.simulation(t)
	var resumed: Dictionary = cold.restore(JSON.parse_string(saved))
	t.check(resumed.get("ok",false),"first-hit JSON restores remaining two stages")
	if not resumed.get("ok",false): return
	var restored: Dictionary = resumed.state
	var ticks := [1]
	var amounts := [float(_hits(first)[0].payload.amount)]
	var ids := [_attacks(first)[0].payload.attack_id]
	for tick in 16:
		var events := F.step(cold,restored,Vector2.ZERO)
		for event in _attacks(events):
			ticks.append(event.tick)
			ids.append(event.payload.attack_id)
		for event in _hits(events): amounts.append(float(event.payload.amount))
		if restored.active_tick == 9:
			t.check(restored.player_attack_instances.size() == 1,"second hit leaves one stage")
			var second_cold = F.simulation(t)
			var second: Dictionary = second_cold.restore(JSON.parse_string(JSON.stringify(restored,"",true,true)))
			t.check(second.get("ok",false),"second-hit JSON restores only final stage")
			if second.get("ok",false):
				cold = second_cold
				restored = second.state
	t.check(ticks == [1,9,17] and amounts == [18.0,18.0,36.0],"actual three damage events retain distinct timed strike identity")
	t.check(ids[0] != ids[1] and ids[1] != ids[2] and restored.character_skill.pending_cast_id == "","final stage consumes pointer exactly once")
	t.check(restored.stats.damage_dealt == 72.0,"authoritative damage tally matches all three hits")
	_missing_target(t,sim,JSON.parse_string(saved))
	_pause(t,sim,JSON.parse_string(saved))
	_invalid(t,sim,JSON.parse_string(saved))
	var legacy := F.run_config()
	legacy.character_id = "mikasa_01"
	var old: Dictionary = sim.new_run(F.chapter(),22,legacy)
	F.step(sim,old,Vector2.ZERO,[F.spawn("legacy",[65,0],"brute")])
	t.check(not old.has("character_skill") and sim.restore(old).get("ok",false),"revision-less Mikasa retains only historical attacks")
func _missing_target(t,sim,state: Dictionary) -> void:
	state.entities[0].hp = 0.0
	sim._remove_dead(state)
	var restored: Dictionary = sim.restore(state)
	t.check(restored.get("ok",false),"vanished target does not corrupt pending checkpoint")
	if not restored.get("ok",false): return
	state = restored.state
	var executed := 0
	var hits := 0
	for i in 16:
		var events := F.step(sim,state,Vector2.ZERO)
		executed += _attacks(events).size()
		hits += _hits(events).size()
	t.check(executed == 2 and hits == 0 and state.character_skill.pending_cast_id == "","vanished target produces two visual misses without retarget")
func _pause(t,sim,state: Dictionary) -> void:
	var result: Dictionary = sim.restore(state)
	if not result.get("ok",false): return
	state = result.state
	sim.set_pause(state,"user",true)
	var before := state.duplicate(true)
	for i in 20: F.step(sim,state,Vector2.ZERO)
	t.check(state == before,"pause freezes stages and signature cooldown")
func _invalid(t,sim,state: Dictionary) -> void:
	for field in ["character_skill","revision","pending","damage","owner"]:
		var bad := state.duplicate(true)
		match field:
			"character_skill": bad.erase("character_skill")
			"revision": bad.run_config.erase("character_skill_revision")
			"pending": bad.character_skill.pending_cast_id = ""
			"damage": bad.player_attack_instances[0].damage += 0.00001
			"owner": bad.player_attack_instances[0].base_item_id = "blade_slash"
		var original := JSON.stringify(bad,"",true,true)
		t.check(not sim.restore(bad).get("ok",false),"Core rejects forged signature "+field)
		t.check(JSON.stringify(bad,"",true,true) == original,"failed restore is side-effect free "+field)
