extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
func run(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	var state: Dictionary = f.state
	var original: Dictionary = state.entities[0].duplicate(true)
	# Private movement branch probes use the real geometry but arrange canonical
	# pursuit fields directly, isolating cadence from unrelated attack admission.
	while (int(state.active_tick)+str(original.id).hash())%3 == 0: state.active_tick += 1
	original.action_started_tick = int(state.active_tick)-10
	for reason in ["zero","recent_transition","attack_speed","boss","final","blocked_line"]:
		var actor: Dictionary = original.duplicate(true)
		if reason == "zero": actor.velocity = [0.0,0.0]
		if reason == "recent_transition": actor.action_started_tick = int(state.active_tick)-1
		if reason == "attack_speed": actor.velocity = [900.0,0.0]
		if reason == "boss": actor.boss_id = "test:excluded"
		if reason == "final": actor.enemy_id = "armored_titan"
		if reason == "blocked_line":
			var box: Rect2 = f.pair.prop.ground_footprint
			var near := Vector2(box.position.x-18.01,box.get_center().y)
			t.check(f.sim._streamed.walkable(near,18.0).get("walkable",false),"blocked inertia starts legally outside wall")
			actor.position = [near.x,near.y]; actor.velocity = [float(actor.speed),0.0]
		F.clear(f.sim)
		f.sim._move_pursuing_enemy(state,actor)
		t.check(f.sim._streamed.trace.routes.size()==1,reason+" immediately uses authoritative route")
		t.check(f.sim._streamed.walkable(Vector2(actor.position[0],actor.position[1]),18.0).walkable,reason+" final position is legal")
	# Direct LOS ignores stale direction even on an inertia tick.
	var actor: Dictionary = original.duplicate(true)
	actor.position = [384.0,384.0]; actor.velocity = [-float(actor.speed),0.0]
	state.player.position = [430.0,384.0]
	F.clear(f.sim); f.sim._move_pursuing_enemy(state,actor)
	t.check(actor.velocity[0]>0 and actor.position[0]>384.0 and f.sim._streamed.trace.routes.is_empty(),"direct target updates immediately instead of retaining stale velocity")
	# Removing and respawning an identity carries no hidden steering state.
	state.entities.clear()
	var commands := [{"command_id":"lifecycle:respawn","kind":"spawn_enemy","origin_revision":state.world.origin_revision,"payload":{"entity_id":original.id,"enemy_id":"walker","position":original.position,"spawned_tick":state.active_tick}}]
	state.player.position = [f.pair.target.x,f.pair.target.y]
	F.clear(f.sim)
	F.F.step(f.sim,state,Vector2.ZERO,commands)
	t.check(f.sim.step_status().get("ok",false) and state.entities.size()==1,"retired actor identity can be recreated by real spawn path")
	t.check(f.sim._streamed.trace.routes.size()==1,"new actor never inherits departed actor steering")
