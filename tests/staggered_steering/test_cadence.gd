extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
func run(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	var state: Dictionary = f.state
	var sim = f.sim
	var initial: Array = state.entities[0].position.duplicate()
	var per_tick: Array = []
	for i in 9:
		F.clear(sim)
		F.F.step(sim,state,Vector2.ZERO)
		t.check(sim.step_status().get("ok",false),"cadence actual Core tick accepts")
		per_tick.append(sim._streamed.trace.routes.size())
		t.check(sim._streamed.trace.sweeps.size()>=1,"direct LOS still runs every tick")
		t.check(sim._streamed.trace.moves.any(func(m): return m.radius == 18.0),"real actor axis movement still runs every tick")
		t.check(sim._streamed.walkable(Vector2(state.entities[0].position[0],state.entities[0].position[1]),18).walkable,"actor stays legal")
	t.check(per_tick.count(0)>=5,"obstructed ordinary route queries are staggered across three ticks")
	for i in 7: t.check(per_tick[i]+per_tick[i+1]+per_tick[i+2]>=1,"no three consecutive ticks omit route replanning")
	t.check(state.entities[0].position!=initial,"cadence keeps real displacement")
	print("STEERING_CADENCE ",JSON.stringify(per_tick))
