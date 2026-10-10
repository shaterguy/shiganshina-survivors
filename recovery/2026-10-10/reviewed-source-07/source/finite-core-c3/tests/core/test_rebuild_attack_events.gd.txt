extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var sim = load("res://game/core/run_simulation.gd").new()
	var chapter := Fixture.v2_chapter()
	_base_events(t,sim,chapter)
	_evolved_events(t,sim,chapter)
	_reservation_boundaries(t,sim,chapter)
func _base_events(t,sim,chapter: Dictionary) -> void:
	for item in Fixture.EQUIPMENT_IDS:
		var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
		state.equipment = {item:1}
		var events: Array = Fixture.step(sim,state,Vector2.LEFT,[_spawn("target","brute",[45,0])])
		var attacks := Fixture.types(events,"player_attack")
		t.check(attacks.size() == 1,"actual base cast emits exactly one player_attack: "+item)
		if attacks.size() != 1: continue
		var payload: Dictionary = attacks[0].payload
		t.check(payload.base_item_id == item and payload.evolution_id == "" and payload.phase == "executed","base event uses actual skill/phase: "+item)
		t.check(payload.direction[0] > 0.99 and state.player.facing[0] < 0,"aim follows target while walking opposite direction: "+item)
		t.check(payload.cast_id == state.run_id+":attack:1" and payload.attack_id == payload.cast_id+":0" and attacks[0].event_id.begins_with(state.run_id+":"),"cast/stage/event identities bind actual run")
		t.check(payload.attack_started_tick == 1 and payload.execute_tick == 1 and payload.stage_index == 0 and payload.stage_count == 1,"base cast timing records exact active tick")
		t.check(payload.geometry.origin == payload.origin and payload.geometry.direction == payload.direction,"render geometry and contact origin/direction agree")
		if item in ["wall_cannon","ally_cover"]:
			t.check(state.projectiles.size() == 1 and payload.geometry.shape == "projectile","projectile cast creates one real projectile")
			if state.projectiles.size() == 1:
				t.check(payload.radius == 4.0 and payload.geometry.radius == 4.0 and state.projectiles[0].radius == 4.0,"actual projectile collision radius is4, never acquisition range")
				t.check(payload.geometry.projectile_id == state.projectiles[0].id and state.projectiles[0].attack_id == payload.attack_id and state.projectiles[0].cast_id == payload.cast_id,"projectile stays bound to original cast identity")
				t.check(state.projectiles[0].position == payload.origin,"new projectile does not advance on its launch tick")
		else:
			t.check(not Fixture.types(events,"damage").is_empty(),"base contact applies actual damage: "+item)
		var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
		t.check(restored.get("ok",false),"actual post-cast snapshot restores: "+item)
	var first: Dictionary = sim.new_run(chapter,42,Fixture.run_config(1))
	var second: Dictionary = sim.new_run(chapter,42,Fixture.run_config(2))
	var a := Fixture.types(Fixture.step(sim,first,Vector2.ZERO,[_spawn("target","brute",[45,0])]),"player_attack")
	var b := Fixture.types(Fixture.step(sim,second,Vector2.ZERO,[_spawn("target","brute",[45,0])]),"player_attack")
	if not a.is_empty() and not b.is_empty(): t.check(a[0].event_id != b[0].event_id and a[0].payload.cast_id != b[0].payload.cast_id,"same seed new serial has distinct cast and event IDs")
func _evolved_events(t,sim,chapter: Dictionary) -> void:
	for evolution in ["evo_wing_cut","evo_crossfire"]:
		var state := evolved_state(sim,chapter,evolution)
		t.check(sim.restore(state).get("ok",false),"synthetically arranged prerequisite build passes real Core before cast: "+evolution)
		var events: Array = Fixture.step(sim,state,Vector2.ZERO,[_spawn("target","brute",[60,0])])
		var attacks := Fixture.types(events,"player_attack")
		var scheduled := attacks.filter(func(event): return event.payload.phase == "scheduled")
		t.check(scheduled.size() == 2,"whole evolved cast emits two scheduled stages: "+evolution)
		if scheduled.size() != 2: continue
		var start := int(state.active_tick)
		var delay0 := 0 if evolution == "evo_wing_cut" else 36
		var delay1 := 12 if evolution == "evo_wing_cut" else 66
		t.check(scheduled[0].payload.execute_tick == start+delay0 and scheduled[1].payload.execute_tick == start+delay1,"authored two-stage timing: "+evolution)
		var expected_damage := [27.0,36.0] if evolution == "evo_wing_cut" else [44.8,44.8]
		t.check(is_equal_approx(scheduled[0].payload.damage,expected_damage[0]) and is_equal_approx(scheduled[1].payload.damage,expected_damage[1]),"hand damage values snapshotted at cast: "+evolution)
		if evolution == "evo_crossfire":
			t.check(is_equal_approx(scheduled[0].payload.origin[1],-24) and is_equal_approx(scheduled[1].payload.origin[1],24),"crossfire locks perpendicular target offsets24")
			t.check(state.player.attack_ready_ticks.wall_cannon == start+128,"crossfire applies required fire_interval3 exactly once")
		else: t.check(state.player.attack_ready_ticks.blade_slash == start+48,"wing keeps authored48 cooldown")
		var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
		t.check(restored.get("ok",false),"scheduled evolved snapshot accepted by actual restore")
		if not restored.get("ok",false): continue
		var reserved_snapshot: Dictionary = restored.state.duplicate(true)
		var resumed: Dictionary = restored.state
		# A later passive upgrade must not retroactively change reserved damage/range.
		state.passives.damage = 1
		resumed.passives.damage = 1
		var execution_count := attacks.filter(func(event): return event.payload.phase == "executed").size()
		for index in range(delay1):
			var left: Array = Fixture.step(sim,state,Vector2.RIGHT)
			var right: Array = Fixture.step(sim,resumed,Vector2.RIGHT)
			t.check(left == right and state == resumed,"save/resume deterministic through evolved stage tick"+str(index))
			for event in Fixture.types(left,"player_attack"):
				if event.payload.phase != "executed": continue
				execution_count += 1
				t.check(is_equal_approx(event.payload.damage,expected_damage[event.payload.stage_index]),"late passive does not buff old stage")
				if evolution == "evo_wing_cut": t.check(event.payload.origin == state.player.position and event.payload.direction[0] > 0.99,"second wing origin follows current player with locked cast direction")
				else: t.check(event.payload.origin == scheduled[event.payload.stage_index].payload.origin,"crossfire never homes after movement")
		t.check(execution_count == 2 and state.player_attack_instances.is_empty(),"each cast executes both stages once and retires them")
		var malformed: Dictionary = reserved_snapshot.duplicate(true)
		if not malformed.player_attack_instances.is_empty():
			malformed.player_attack_instances[0].execute_tick += 1
			t.check(not sim.restore(malformed).get("ok",false),"tampered stage timing fails restore")
static func evolved_state(sim,chapter: Dictionary,evolution: String) -> Dictionary:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	var base := "blade_slash" if evolution == "evo_wing_cut" else "wall_cannon"
	state.equipment = {base:5}
	state.passives = {"movement":3} if evolution == "evo_wing_cut" else {"fire_interval":3}
	state.evolutions = {base:evolution}
	state.active_tick = 18099
	state.survival_tick = 18099
	state.boss_ids_fired = ["ch01_b05"]
	state.reward_ids_claimed = ["boss:ch01_b05"]
	state.stats.minibosses_defeated = 1
	state.stats.kills = 1
	return state
static func _spawn(id: String, enemy: String, position: Array) -> Dictionary:
	return {"command_id":"spawn:"+id,"kind":"spawn_enemy","payload":{"entity_id":id,"enemy_id":enemy,"position":position,"spawned_tick":0}}
func _reservation_boundaries(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	state.equipment = {"ally_cover":1,"wall_cannon":1}
	Fixture.step(sim,state,Vector2.ZERO,[_spawn("target","brute",[45,0])])
	var projectile: Dictionary = state.projectiles[0].duplicate(true)
	state.projectiles.clear()
	for index in 255:
		var copy := projectile.duplicate(true)
		copy.id = index+100
		copy.cast_id = state.run_id+":attack:"+str(index+1)
		copy.attack_id = copy.cast_id+":0"
		copy.position = [1000.0,1000.0]
		state.projectiles.append(copy)
	state.next_entity_id = 1000
	state.attack_seq = 255
	state.player.attack_ready_ticks.clear()
	t.check(sim.restore(state).get("ok",false),"near-cap projectile arrangement passes real restore")
	var events := Fixture.step(sim,state,Vector2.ZERO)
	t.check(state.projectiles.size() == 256 and Fixture.types(events,"player_attack").size() == 1,"concurrent projectile casts reserve the last slot exactly once")
	t.check(state.attack_seq == 256 and not state.player.attack_ready_ticks.has("wall_cannon"),"refused projectile has no cast sequence or cooldown side effects")
	state.player.attack_ready_ticks.clear()
	var before: int = state.attack_seq
	t.check(Fixture.types(Fixture.step(sim,state,Vector2.ZERO),"player_attack").is_empty() and state.attack_seq == before and state.player.attack_ready_ticks.is_empty(),"full projectile budget silently defers entire casts")
	var resolver = load("res://game/combat/evolved_attack_resolver.gd").new()
	t.check(not resolver.validate_records({"player_attack_instances":[]}),"record validator rejects missing context even for empty schedules")
	for broken in [{},{"evolutions":0}]:
		var result: Dictionary = resolver.reserve(broken,"blade_slash",Vector2.ZERO,Vector2.RIGHT,"bogus")
		t.check(not result.get("ok",false),"cast proposal rejects malformed context without script error")
