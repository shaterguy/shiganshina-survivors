extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
static func setup() -> Dictionary:
	var sim = load("res://game/core/run_simulation.gd").new()
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,F.run_config())
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	return {"sim":sim,"state":state}
static func spawn(id: Variant = 77, point: Array = [170.0,0.0], enemy: String = "grabber") -> Dictionary:
	return {"command_id":"live-grabber:"+str(id),"kind":"spawn_enemy","payload":{"entity_id":id,"enemy_id":enemy,"position":point,"spawned_tick":0}}
func run(t) -> void:
	var fixture := setup()
	var sim = fixture.sim
	var state: Dictionary = fixture.state
	F.step(sim,state,Vector2.ZERO,[spawn()])
	t.check(state.enemy_attack_instances.size() == 1,"ordinary grabber spawn enters actual Core raw attack ownership")
	if state.enemy_attack_instances.is_empty(): return
	var attack: Dictionary = state.enemy_attack_instances[0].duplicate(true)
	var origin: Array = state.entities[0].position.duplicate()
	t.check(state.entities[0].speed == 50.0 and state.telegraphs.is_empty(),"only grabber definition adopts role speed and no legacy hazard")
	t.check(attack.started_tick == 1 and attack.active_from_tick == 61 and attack.attack_ends_tick == 77 and attack.recover_ends_tick == 161,"W60 A16 R84 exact clocks")
	var hurt := 0
	for tick in range(2,162):
		var events := F.step(sim,state,Vector2.ZERO)
		hurt += F.types(events,"damage").size()
		t.check(state.entities[0].position == origin,"grabber torso stays fixed through complete W/A/R")
		if tick in [60,61,76,77,160,161]:
			var phase: String = "windup" if tick < 61 else ("attack" if tick < 77 else ("recover" if tick < 161 else "move"))
			t.check(state.entities[0].action_state == phase,"role phase boundary "+str(tick))
			t.check(sim.restore(state).get("ok",false),"owned role state restores at boundary "+str(tick))
	t.check(hurt == 1 and state.player.hp == state.player.max_hp-12.0,"real travelling hand applies accepted damage only once")
	t.check(state.enemy_attack_instances.is_empty() and state.entities[0].role_hand_reach == -1.0 and state.entities[0].next_action_tick == 251,"finish removes attack and retains full cooldown")
	for id in ["opaque", "fixture:grabber", "x:enemy:y", " "]:
		fixture = setup(); sim = fixture.sim; state = fixture.state
		F.step(sim,state,Vector2.ZERO,[spawn(id)])
		t.check(state.enemy_attack_instances.size() == 1 and sim.restore(state).get("ok",false),"actual Core source identity is supported: "+id)
	fixture = setup(); sim = fixture.sim; state = fixture.state
	F.step(sim,state,Vector2.ZERO,[spawn(77,[190.0,0.0])])
	t.check(state.enemy_attack_instances.size() == 1,"trigger range 190 is inclusive")
	fixture = setup(); sim = fixture.sim; state = fixture.state
	F.step(sim,state,Vector2.ZERO,[spawn(77,[190.01,0.0])])
	t.check(state.enemy_attack_instances.is_empty(),"outside trigger does not silently use legacy shorter attack")
