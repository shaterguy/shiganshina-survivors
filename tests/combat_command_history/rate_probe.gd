extends SceneTree
# Arranged maximum-population stationary attack-rate test. This advances exact
# FSM boundary times, not all movement/world ticks and not natural survival.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Director = preload("res://game/director/spawn_director.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Core.new(Current.new())
	var state: Dictionary = sim.new_run(F.chapter(),19,F.run_config())
	state.player.attack_ready_ticks.blade_slash = 2147483647
	state.player.invulnerable_until = 2147483647
	var commands: Array[Dictionary] = []
	for index in 180:
		commands.append({"command_id":"enemy_1_%d"%index,"kind":"spawn_enemy","payload":{"entity_id":index+1,"enemy_id":"sweeper","position":[40.0,0.0],"spawned_tick":1}})
	F.step(sim,state,Vector2.ZERO,commands)
	var first_cap := -1
	var peak: int = state.command_ids_applied.size()
	var cycles := 1
	var start_time: int = Time.get_ticks_msec()
	var replay_ok := true
	var cold = null
	var replay := {}
	while state.active_tick < 107999:
		var next_tick := 108000
		for entity in state.entities:
			next_tick = mini(next_tick,int(entity.next_action_tick) if entity.action_state == "move" else int(entity.action_ends_tick))
		if next_tick <= state.active_tick:
			first_cap = state.active_tick
			break
		if next_tick >= 108000: break
		state.active_tick = next_tick-1
		state.survival_tick = next_tick-1
		var events := F.step(sim,state,Vector2.ZERO)
		peak = maxi(peak,state.command_ids_applied.size())
		cycles = int(state.entities[0].pattern_index)
		if cold != null:
			replay.active_tick = next_tick-1
			replay.survival_tick = next_tick-1
			replay_ok = replay_ok and events == F.step(cold,replay,Vector2.ZERO) and state == replay
		elif next_tick > 100000:
			cold = Core.new(Current.new())
			var result: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state))))
			replay_ok = result.get("ok",false)
			if replay_ok: replay = result.state
			else: cold = null
		if state.command_ids_applied.size() == 16384 and first_cap < 0:
			first_cap = state.active_tick
		if first_cap >= 0: break
	var admitted := 0
	for entity in state.entities: admitted += int(entity.pattern_index)
	var before_final := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state))))
	state.active_tick = 107999; state.survival_tick = 107999
	var events := F.step(sim,state,Vector2.ZERO,Director.new().plan(state,F.chapter()))
	print(JSON.stringify({"scope":"ARRANGED_FSM_BOUNDARY_TIMES_NOT_FULLWORLD_OR_NATURAL_SURVIVAL","actors":180,"profile":"authored sweeper","cycles_first_actor":cycles,"admitted_actions":admitted,"peak_command_ids":peak,"first_cap_tick":first_cap,"cold_restorable":before_final.get("ok",false),"cold_replay_exact":replay_ok,"final_started_tick":state.final_started_tick,"final_boss_events":F.types(events,"boss_spawned").size(),"elapsed_ms":Time.get_ticks_msec()-start_time}))
	quit(0)
