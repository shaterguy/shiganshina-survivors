extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
const Behavior = preload("res://tests/core/behavior_fixture.gd")
const OwnerTests = preload("res://tests/core/test_enemy_behaviors.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ",label)
func _initialize() -> void:
	var sim = Sim.new()
	OwnerTests.new().test_restore_movement_and_hazard_ownership(self,sim)
	var samples := 0
	for enemy_id in Behavior.IDS:
		var state: Dictionary = sim.new_run(Behavior.chapter(),44)
		state.player.hp = 10000.0
		state.player.max_hp = 10000.0
		for tick in 17: Fixture.step(sim,state,Vector2(0.6,0.8),[])
		var player := Behavior.vec(state.player.position)
		var origin := player+Vector2(-160.123456789,-PI)
		Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("actor",[origin.x,origin.y],enemy_id)])
		var phases: Array[String] = []
		for tick in 500:
			var actor: Dictionary = state.entities[0]
			var phase: String = actor.action_state
			if not phase in phases:
				phases.append(phase)
				var saved: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
				var unchanged: Dictionary = saved.duplicate(true)
				var restored: Dictionary = sim.restore(saved)
				check(restored.ok,"canonical diagonal checkpoint accepted: "+enemy_id+" "+phase)
				check(saved==unchanged,"canonical restore does not mutate input: "+enemy_id+" "+phase)
				if restored.ok:
					check(restored.state==state,"canonical diagonal state equality: "+enemy_id+" "+phase)
					var replay: Dictionary = sim.snapshot(state)
					for offset in 20:
						Fixture.step(sim,replay,Vector2(0.6,-0.8),[])
						Fixture.step(sim,restored.state,Vector2(0.6,-0.8),[])
						check(replay==restored.state,"canonical diagonal exact replay: "+enemy_id+" "+phase)
				samples += 1
			Fixture.step(sim,state,Vector2.ZERO,[])
	print("CANONICAL_DIAGONAL samples=%d ids=10 initial_diagonal_ticks=17"%samples)
	print("REVIEW_BEHAVIOR_CANONICAL checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
