extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
func run(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	# First post-spawn move plans; the next chosen phase reuses actual velocity.
	while (int(f.state.active_tick)+1+str(f.state.entities[0].id).hash())%3 == 0:
		F.F.step(f.sim,f.state,Vector2.ZERO)
	var before: Dictionary = f.state.duplicate(true)
	var cold := F.cold(t,f,before)
	F.clear(f.sim)
	f.sim._streamed.trace.armed = true
	var events := F.F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.sim._streamed.trace.routes.is_empty(),"late failure is specifically during retained-velocity movement")
	t.check(f.sim._streamed.trace.failed and events.is_empty() and f.state==before and f.sim.step_status().get("error_code")=="world_not_ready","inertia move failure rolls back complete tick")
	f.sim._streamed.trace.armed = false
	var a := F.F.step(f.sim,f.state,Vector2.ZERO)
	var b := F.F.step(cold.sim,cold.state,Vector2.ZERO)
	t.check(f.sim.step_status().get("ok",false) and f.state==cold.state and a==b,"same-tick retry with saved pursuit velocity equals cold execution")
