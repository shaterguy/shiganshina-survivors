extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Director = preload("res://game/director/spawn_director.gd")
func run(t) -> void:
	_capacity(t)
	_retry_lifecycle(t)
	_opaque_and_future(t)
	_bosses_and_final(t)
	_numeric_shapes(t)
	_dormant_owner(t)
	_failed_tick_retry(t)
func _new(sim) -> Dictionary:
	var state: Dictionary = sim.new_run(F.chapter(),17,F.run_config())
	state.player.attack_ready_ticks.blade_slash = 2147483647
	state.player.invulnerable_until = 2147483647
	return state
func _spawn(id: Variant, tick: int, command_id: String, enemy := "walker") -> Dictionary:
	return {"command_id":command_id,"kind":"spawn_enemy","payload":{"entity_id":id,"enemy_id":enemy,"position":[40.0,0.0],"spawned_tick":tick}}
func _capacity(t) -> void:
	var sim = Core.new(Current.new())
	var state: Dictionary = _arranged(sim,90000)
	t.check(sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state)))).get("ok",false),"arranged cap is cold-restorable before its first actual tick")
	F.step(sim,state,Vector2.ZERO)
	t.check(state.entities[0].pattern_index == 16384 and state.entities[0].action_state == "windup" and state.telegraphs.size() == 1,"history at prior cap does not permanently disable ordinary attack")
	t.check(state.command_ids_applied.size() < 16,"obsolete numeric behavior history compacts without raising snapshot cap")
	var cold := Core.new(Current.new())
	var restored: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state))))
	t.check(restored.get("ok",false),"new active action survives cold restore after compaction")
	if restored.get("ok",false):
		for tick in 250:
			t.check(F.step(sim,state,Vector2.ZERO) == F.step(cold,restored.state,Vector2.ZERO),"cold replay emits identical action events")
			t.check(state == restored.state,"cold replay keeps complete deterministic state")
	var final: Dictionary = _arranged(sim,107999)
	var commands: Array[Dictionary] = Director.new().plan(final,F.chapter())
	var events := F.step(sim,final,Vector2.ZERO,commands)
	t.check(final.phase == "evacuation" and final.final_started_tick == 108000 and F.types(events,"boss_spawned").size() == 1,"actual Director final begins at prior full ledger")
	var final_tick: int = final.final_started_tick
	events = F.step(sim,final,Vector2.ZERO,commands)
	t.check(final.final_started_tick == final_tick and F.types(events,"boss_spawned").is_empty(),"final duplicate retry stays once after history compaction")
func _retry_lifecycle(t) -> void:
	var sim = Core.new(Current.new())
	var state := _new(sim)
	var command := _spawn(1,1,"enemy_1_0")
	var changed_same_tick := command.duplicate(true)
	changed_same_tick.payload.entity_id = 2
	F.step(sim,state,Vector2.ZERO,[command,command,changed_same_tick])
	t.check(state.entities.size() == 1,"same-tick canonical duplicate applies once")
	# These are arranged old Director IDs, not invented natural history.
	for tick in range(2,1100): state.command_ids_applied.append("enemy_%d_0"%tick)
	state.active_tick = 1100; state.survival_tick = 1100
	state.entities.clear()
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.entities.is_empty() and not "enemy_1_0" in state.command_ids_applied,"retired canonical command cannot replay after its history is dropped")
	var changed := command.duplicate(true)
	changed.payload.entity_id = state.next_entity_id
	changed.payload.spawned_tick = state.active_tick+1
	F.step(sim,state,Vector2.ZERO,[changed])
	t.check(state.entities.is_empty(),"reusing old command ID with new payload cannot bypass tick identity")
	F.step(sim,state,Vector2.ZERO,[_spawn(1,state.active_tick+1,"opaque-reuse")])
	t.check(state.entities.is_empty(),"next_entity_id high-water rejects reincarnation of retired numeric actor")
	var wrong_kind := F.hazard("enemy_%d_0"%(state.active_tick+1))
	F.step(sim,state,Vector2.ZERO,[wrong_kind])
	t.check(state.telegraphs.is_empty(),"compactable Director namespace cannot be forged as another command kind")
	var behavior_spoof := F.hazard("behavior:1:1")
	F.step(sim,state,Vector2.ZERO,[behavior_spoof])
	t.check(state.telegraphs.is_empty(),"retired numeric behavior command ID cannot be replayed externally")
	var new_command := _spawn(state.next_entity_id,state.active_tick+1,"enemy_%d_0"%(state.active_tick+1),"sweeper")
	F.step(sim,state,Vector2.ZERO,[new_command,new_command])
	t.check(state.entities.size() == 1 and state.telegraphs.size() == 1,"fresh numeric actor and current attack still work after old ID refusals")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot(state)))
	var cold := Core.new(Current.new())
	var restored: Dictionary = cold.restore(snapshot)
	t.check(restored.get("ok",false),"compacted identity boundaries survive cold restore")
	if restored.get("ok",false):
		F.step(cold,restored.state,Vector2.ZERO,[command,behavior_spoof])
		t.check(restored.state.entities.size() == 1,"cold restore keeps old spawn and behavior replay refused")
	snapshot.command_ids_applied.append(snapshot.command_ids_applied[0])
	t.check(not cold.restore(snapshot).get("ok",false),"duplicate ledger validation is never hidden by compaction")
func _opaque_and_future(t) -> void:
	var sim = Core.new(Current.new())
	var state := _new(sim)
	F.step(sim,state,Vector2.ZERO,[_spawn(1,1,"ordinary-spawn","sweeper")])
	var current := "behavior:1:1"
	var future := "behavior:1:2"
	state.command_ids_applied.append(future)
	state.command_ids_applied.append("final:armored_actor")
	state.command_ids_applied.append("final-impact:1:1")
	state.command_ids_applied.append("behavior:string-actor:1")
	for tick in range(2,1100): state.command_ids_applied.append("enemy_%d_0"%tick)
	state.active_tick = 2 # Future timed IDs must remain, not be silently erased.
	F.step(sim,state,Vector2.ZERO)
	t.check(current in state.command_ids_applied and future in state.command_ids_applied,"current and previously claimed future behavior identities remain guarded")
	t.check("final:armored_actor" in state.command_ids_applied and "final-impact:1:1" in state.command_ids_applied,"final actor once marker and current impact marker retained")
	t.check("behavior:string-actor:1" in state.command_ids_applied and "ordinary-spawn" in state.command_ids_applied,"opaque and string-identity historical duplicates are not weakened")
func _bosses_and_final(t) -> void:
	var sim = Core.new(Current.new())
	var state := _new(sim)
	var boss_events := 0
	for boss in F.chapter().boss_schedule:
		state.active_tick = boss.tick-1; state.survival_tick = state.active_tick
		var command := {"command_id":boss.boss_id,"kind":"spawn_boss","payload":{"entity_id":state.next_entity_id,"boss_id":boss.boss_id,"enemy_id":boss.enemy_id,"position":[40.0,0.0],"scheduled_tick":boss.tick}}
		boss_events += F.types(F.step(sim,state,Vector2.ZERO,[command,command]),"boss_spawned").size()
		F.step(sim,state,Vector2.ZERO,[command])
	t.check(boss_events == 5 and state.boss_ids_fired.size() == 5,"five scheduled miniboss commands stay exactly once")
	state.active_tick = 107999; state.survival_tick = 107999
	var final := Director.new().plan(state,F.chapter())
	boss_events += F.types(F.step(sim,state,Vector2.ZERO,final),"boss_spawned").size()
	F.step(sim,state,Vector2.ZERO,final)
	t.check(boss_events == 6 and state.boss_ids_fired.size() == 6 and state.final_started_tick == 108000,"five minibosses plus final marker remain exactly once")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state)))).get("ok",false),"five-boss final cold snapshot remains valid")

func _arranged(sim, tick: int) -> Dictionary:
	var state: Dictionary = sim.new_run(F.chapter(),17,F.run_config())
	state.player.attack_ready_ticks.blade_slash = 2147483647
	F.step(sim,state,Vector2.ZERO,[{"command_id":"arranged-spawn","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":"sweeper","position":[40.0,0.0],"spawned_tick":0}}])
	state.active_tick = tick
	state.survival_tick = tick
	state.next_entity_id = 20000
	state.telegraphs.clear()
	var actor: Dictionary = state.entities[0]
	actor.action_state = "move"
	actor.action_started_tick = tick
	actor.action_ends_tick = tick
	actor.next_action_tick = tick
	actor.pattern_index = 16383
	state.command_ids_applied = ["arranged-spawn"]
	for n in range(1,16384): state.command_ids_applied.append("behavior:1:%d"%n)
	return state
func _numeric_shapes(t) -> void:
	for shape in [1,1.0,"1","01"]:
		var sim = Core.new(Current.new())
		var state := _new(sim)
		F.step(sim,state,Vector2.ZERO,[_spawn(shape,1,"opaque-first")])
		t.check(state.entities.size() == 1,"numeric/string input accepted according to existing DTO: "+str(shape))
		state.entities.clear()
		F.step(sim,state,Vector2.ZERO,[_spawn(shape,2,"opaque-second")])
		t.check(state.entities.size() == (1 if shape is String and shape == "01" else 0),"canonical int/float/string identities share high-water, noncanonical string stays opaque: "+str(shape))
	var sim = Core.new(Current.new())
	var spoofed := _new(sim)
	F.step(sim,spoofed,Vector2.ZERO,[_spawn(1,1,"enemy_9000_0")])
	t.check(spoofed.entities.is_empty() and spoofed.command_ids_applied.is_empty(),"future command-ID tick with otherwise current payload cannot reserve a future identity")
	var state := _new(sim)
	F.step(sim,state,Vector2.ZERO,[_spawn(1,2,"enemy_2_0")])
	t.check(state.entities.is_empty() and state.command_ids_applied.is_empty(),"future canonical spawn tick cannot reserve or apply command early")
	F.step(sim,state,Vector2.ZERO,[_spawn(1,2,"enemy_2_0")])
	t.check(state.entities.size() == 1,"previously refused future command can execute when its tick actually arrives")
func _dormant_owner(t) -> void:
	var source = load("res://tests/city_continuity/test_population_integration.gd").new()
	var f: Dictionary = source._fixture(t)
	f.state.active_tick = 17999; f.state.survival_tick = 17999
	var command := {"command_id":"numeric-parked-boss","kind":"spawn_boss","origin_revision":0,"payload":{"entity_id":1,"enemy_id":"boss_charger","boss_id":"ch01_b05","position":[-1154.0,384.0],"scheduled_tick":18000}}
	var helper = load("res://game/core/streamed_run_world.gd")
	var hydration: Dictionary = load("res://tests/core_world/new_streamed_helper_fixture.gd").hydration(helper.requirements(f.state,[command]))
	t.check(f.core.prepare_world(f.state,hydration,[command]).get("ok",false),"numeric boss parking control prepares")
	F.step(f.core,f.state,Vector2.ZERO,[command]); F.step(f.core,f.state,Vector2.ZERO)
	t.check(f.state.world.schema_version == 2 and f.state.world.dormant.entities.size() == 1,"numeric boss actually becomes dormant")
	if f.state.world.get("schema_version") != 2 or f.state.world.dormant.entities.size() != 1: return
	var actor: Dictionary = f.state.world.dormant.entities[0].record
	actor.pattern_index = 3
	f.state.command_ids_applied.append("behavior:1:1")
	f.state.command_ids_applied.append("behavior:1:2")
	f.state.command_ids_applied.append("behavior:1:3")
	f.state.command_ids_applied.append("final-impact:1:3")
	for tick in range(1,1100): f.state.command_ids_applied.append("enemy_%d_0"%tick)
	t.check(f.core.restore(JSON.parse_string(JSON.stringify(f.state)),hydration).get("ok",false),"arranged dormant current-pattern marker remains valid before collection")
	F.step(f.core,f.state,Vector2.ZERO)
	t.check("behavior:1:3" in f.state.command_ids_applied and "final-impact:1:3" in f.state.command_ids_applied and not "behavior:1:2" in f.state.command_ids_applied,"dormant owner retains only current/future action identity")
	t.check(f.core.restore(JSON.parse_string(JSON.stringify(f.state)),hydration).get("ok",false),"dormant pattern owner survives compacted cold restore")
func _failed_tick_retry(t) -> void:
	var f: Dictionary = load("res://tests/core/test_rebuild_streamed_tick.gd").new().fixture(t,[384.0,384.0],true)
	if f.is_empty(): return
	var sim = f.sim
	var state: Dictionary = f.state
	state.equipment = {"blade_slash":5}
	state.active_tick = 1500; state.survival_tick = 1500
	for tick in range(1,1100): state.command_ids_applied.append("enemy_%d_0"%tick)
	var command := {"command_id":"enemy_1501_0","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":1,"enemy_id":"walker","position":[430.0,384.0],"spawned_tick":1501}}
	var helper = load("res://game/core/streamed_run_world.gd")
	var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,helper.requirements(state,[command]).chunks)
	t.check(sim.prepare_world(state,hydrated.deltas,[command]).get("ok",false),"late fault history-compaction control prepares")
	var before := state.duplicate(true)
	sim._streamed.armed = true
	var events := F.step(sim,state,Vector2.RIGHT,[command])
	t.check(sim._streamed.cover_calls == 2 and events.is_empty() and state == before,"failed streamed tick rolls history compaction back with every other mutation")
	sim._streamed.armed = false; sim._streamed.cover_calls = 0
	events = F.step(sim,state,Vector2.RIGHT,[command])
	t.check(state.active_tick == 1501 and state.command_ids_applied == ["enemy_1501_0"],"same held command retries once after successful compacted transaction")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state)),hydrated.deltas).get("ok",false),"successful retried compacted transaction cold-restores")
	var paused := state.duplicate(true)
	sim.set_pause(state,"user",true)
	paused = state.duplicate(true)
	F.step(sim,state,Vector2.RIGHT,[command])
	t.check(state == paused,"paused input cannot compact history or consume a pending command")
