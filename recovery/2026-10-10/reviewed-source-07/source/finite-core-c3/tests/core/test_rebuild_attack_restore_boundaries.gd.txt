extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const A = preload("res://tests/core/test_rebuild_attack_events.gd")
func run(t) -> void:
	var sim = load("res://game/core/run_simulation.gd").new()
	var chapter := F.v2_chapter()
	_hostile_types(t,sim,chapter)
	_extreme_vectors(t,sim,chapter)
	_counter_exhaustion(t,sim,chapter)
	_variant_keys(t,sim,chapter)
	_nested_counters(t,sim,chapter)
	var state := A.evolved_state(sim,chapter,"evo_crossfire")
	F.step(sim,state,Vector2.ZERO,[A._spawn("target","brute",[60,13])])
	var original := state.duplicate(true)
	for index in 2:
		var malformed := state.duplicate(true)
		malformed.player_attack_instances.remove_at(index)
		t.check(not sim.restore(malformed).get("ok",false),"missing not-yet-executed stage of admitted whole cast is rejected")
	for field in ["origin","direction","damage","radius","attack_started_tick"]:
		var malformed := state.duplicate(true)
		malformed.passives.damage = 1
		malformed.passives.attack_range = 1
		match field:
			"origin": malformed.player_attack_instances[1].origin = [999.0,999.0]
			"direction": malformed.player_attack_instances[1].direction = [0.0,1.0]
			"damage": malformed.player_attack_instances[1].damage *= 1.15
			"radius": malformed.player_attack_instances[1].radius *= 1.12
			"attack_started_tick":
				malformed.player_attack_instances[1].attack_started_tick -= 1
				malformed.player_attack_instances[1].execute_tick -= 1
		t.check(not sim.restore(malformed).get("ok",false),"same cast stages require coherent frozen "+field)
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false) and restored.get("state") == state,"nonaxis reservation coordinates canonically roundtrip at full JSON precision")
	if restored.get("ok",false):
		for index in 66:
			var left := F.step(sim,state,Vector2.RIGHT)
			var right := F.step(sim,restored.state,Vector2.RIGHT)
			t.check(state == restored.state and left == right,"nonaxis replay states/events match through both scheduled stages")
			if index in [34,35,36,64,65]:
				var cut: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
				t.check(cut.get("ok",false) and cut.get("state") == state,"before/at/after execution cut remains a legal complete pending cast")
	state = sim.new_run(chapter,42,F.run_config())
	state.equipment = {"ally_cover":1}
	F.step(sim,state,Vector2.ZERO,[A._spawn("target","brute",[45,13])])
	for patch in [{"damage":999999.0},{"item_id":"blade_slash"},{"velocity":[0,0]},{"radius":999.0},{"remaining_distance":999999.0},{"splash_radius":40.0}]:
		var malformed := state.duplicate(true)
		malformed.projectiles[0].merge(patch,true)
		t.check(not sim.restore(malformed).get("ok",false),"projectile impossible cast parameters fail restore: "+str(patch))
	var duplicate := state.duplicate(true)
	var copy: Dictionary = duplicate.projectiles[0].duplicate(true)
	copy.id = duplicate.next_entity_id
	duplicate.next_entity_id += 1
	duplicate.projectiles.append(copy)
	t.check(not sim.restore(duplicate).get("ok",false),"two entity IDs cannot replay the same projectile attack twice")
	state.equipment.ally_cover = 2
	state.passives = {"damage":1,"attack_range":1}
	t.check(sim.restore(state).get("ok",false),"later weapon/passive upgrades preserve already-flying original projectile tuning")
	t.check(original.player_attack_instances.size() == 2,"hostile restore attempts did not alias the valid cast")
func _hostile_types(t,sim,chapter: Dictionary) -> void:
	var state := A.evolved_state(sim,chapter,"evo_crossfire")
	F.step(sim,state,Vector2.ZERO,[A._spawn("target","brute",[60,13])])
	for bad in [null,true,false,"two",[],{},0.5,-1,NAN,INF]:
		for path in [["player","id"],["player","hp"],["player_attack_instances",0,"stage_count"]]:
			if path == ["player","hp"] and bad is float and bad == 0.5: continue # Fractional surviving HP is legal.
			var invalid := state.duplicate(true)
			if path.size() == 2: invalid[path[0]][path[1]] = bad
			else: invalid[path[0]][path[1]][path[2]] = bad
			t.check(not sim.restore(invalid).get("ok",false),"hostile scalar type rejected quietly: "+str(path)+" value="+str(bad))
func _extreme_vectors(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	state.equipment = {"ally_cover":1}
	F.step(sim,state,Vector2.ZERO,[A._spawn("target","brute",[45,13])])
	state.drops.append({"id":state.next_entity_id,"position":[100,0],"xp":1})
	state.next_entity_id += 1
	for path in [["player","velocity"],["projectiles",0,"position"],["drops",0,"position"]]:
		var invalid := state.duplicate(true)
		if path.size() == 2: invalid[path[0]][path[1]] = [1e100,0]
		else: invalid[path[0]][path[1]][path[2]] = [1e100,0]
		t.check(not sim.restore(invalid).get("ok",false),"finite-double coordinate that becomes float32 INF is refused: "+str(path))
	var hazard: Dictionary = F.hazard("extreme","circle",{"origin":[1e100,0]})
	var clean: Dictionary = sim.new_run(chapter,42,F.run_config())
	F.step(sim,clean,Vector2.ZERO,[hazard])
	t.check(clean.telegraphs.is_empty() and not "extreme" in clean.command_ids_applied,"extreme command vector is rejected before live canonicalization")
	t.check(load("res://game/contracts/game_contracts.gd").new()._json_safe(clean),"live state remains JSON safe after hostile command")
func _counter_exhaustion(t,sim,chapter: Dictionary) -> void:
	for field in ["next_entity_id","event_seq","active_tick","view_revision"]:
		var state: Dictionary=sim.new_run(chapter,42,F.run_config())
		state.equipment={"ally_cover":1}
		state[field]=2147483647
		t.check(sim.restore(state).get("ok",false),"counter maximum is a legal serialized endpoint: "+field)
		var before:=state.duplicate(true)
		var events:=F.step(sim,state,Vector2.ZERO,[A._spawn("target","brute",[45,0])])
		t.check(sim.restore(state).get("ok",false),"counter exhaustion never leaves invalid authority: "+field)
		if field != "view_revision": t.check(events.is_empty() and state==before,"required exhausted counter rejects entire tick atomically: "+field)
func _variant_keys(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,F.run_config())
	state.equipment={&"ally_cover":1,"wall_cannon":1}
	var restored: Dictionary=sim.restore(state)
	t.check(restored.get("ok",false),"StringName dictionary keys are a supported structural input")
	if not restored.get("ok",false): return
	for key in restored.state.equipment:
		t.check(key is String,"restore canonicalizes inventory keys to String")
	var parsed: Dictionary=sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	if not parsed.get("ok",false): return
	var command:=A._spawn("target","walker",[100,0])
	var direct:=F.step(sim,state,Vector2.ZERO,[command])
	var resumed:=F.step(sim,parsed.state,Vector2.ZERO,[command])
	t.check(direct==resumed and state==parsed.state,"mixed Variant dictionary keys cannot change sorted cast order or replay state")
	t.check(sim.restore(state).get("ok",false),"cast from accepted dictionary keys remains serializable")
func _nested_counters(t,sim,chapter: Dictionary) -> void:
	for field in ["kills","drop_xp"]:
		var state: Dictionary=sim.new_run(chapter,42,F.run_config())
		state.equipment={"blade_slash":5}
		if field=="kills": state.stats.kills=2147483647
		else:
			state.drops=[{"id":99,"position":[60.0,0.0],"xp":2147483647}]
			state.next_entity_id=100
		t.check(sim.restore(state).get("ok",false),"nested counter endpoint is initially legal: "+field)
		var before:=state.duplicate(true)
		var events:=F.step(sim,state,Vector2.ZERO,[A._spawn("target","walker",[60,0])])
		t.check(events.is_empty() and state==before and sim.restore(state).get("ok",false),"nested counter overflow rejects whole tick: "+field)
