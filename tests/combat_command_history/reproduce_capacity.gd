extends SceneTree
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Director = preload("res://game/director/spawn_director.gd")
func _initialize() -> void:
	call_deferred("run")
func arranged(sim, tick: int) -> Dictionary:
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
func run() -> void:
	var sim = Core.new(Finite.new())
	var state := arranged(sim,90000)
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state))))
	var result := {"scope":"ARRANGED_CAP: actual Core, synthetic prior history; not natural reachability", "cap":state.command_ids_applied.size(),"cold_restore_ok":restored.get("ok",false)}
	F.step(sim,state,Vector2.ZERO)
	result.attack_after = {"pattern_index":state.entities[0].pattern_index,"action_state":state.entities[0].action_state,"telegraphs":state.telegraphs.size(),"commands":state.command_ids_applied.size()}
	var final := arranged(sim,107999)
	var commands: Array[Dictionary] = Director.new().plan(final,F.chapter())
	var events: Array = F.step(sim,final,Vector2.ZERO,commands)
	result.final_after = {"phase":final.phase,"final_started_tick":final.final_started_tick,"boss_events":F.types(events,"boss_spawned").size(),"commands":final.command_ids_applied.size()}
	print(JSON.stringify(result))
	quit(0)
