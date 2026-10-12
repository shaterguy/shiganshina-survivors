extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
func run(t) -> void:
	_cold_phases(t)
	_failure_retry(t)
	_rebase(t)
	_geometry(t)
func _cold_phases(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	for phase in 6:
		var cold := F.cold(t,f,f.state)
		if cold.is_empty(): return
		for i in 3:
			var a := F.F.step(f.sim,f.state,Vector2.ZERO)
			var b := F.F.step(cold.sim,cold.state,Vector2.ZERO)
			t.check(f.sim.step_status().get("ok",false) and cold.sim.step_status().get("ok",false),"warm and cold accepted tick")
			t.check(f.state==cold.state and a==b,"same input exact next state/events at every cadence phase")
			t.check(f.sim.step_status()==cold.sim.step_status(),"same input exact statuses at every cadence phase")
		F.F.step(f.sim,f.state,Vector2.ZERO)
func _failure_retry(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	var before: Dictionary = f.state.duplicate(true)
	var cold := F.cold(t,f,before)
	f.sim._streamed.trace.armed = true
	var events := F.F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.sim._streamed.trace.failed,"actual actor movement triggers real missing coverage guard")
	t.check(f.sim.step_status().get("error_code")=="world_not_ready" and events.is_empty() and f.state==before,"failed move rolls back all authoritative state/events")
	f.sim._streamed.trace.armed = false
	var retried := F.F.step(f.sim,f.state,Vector2.ZERO)
	var expected := F.F.step(cold.sim,cold.state,Vector2.ZERO)
	t.check(f.sim.step_status().get("ok",false) and f.state.active_tick==before.active_tick+1,"retry commits exactly one tick")
	t.check(f.state==cold.state and retried==expected,"refused same-tick retry equals fresh cold execution")
func _rebase(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	f.state.player.position = [767.0,384.0]
	var hydration := F.HF.hydration(F.H.requirements(f.state))
	t.check(f.sim.prepare_world(f.state,hydration).get("ok",false),"rebase fixture actual coverage")
	var cold := F.cold(t,f,f.state)
	if cold.is_empty(): return
	for i in 6:
		var a := F.F.step(f.sim,f.state,Vector2.RIGHT)
		var b := F.F.step(cold.sim,cold.state,Vector2.RIGHT)
		t.check(f.sim.step_status().get("ok",false) and f.state==cold.state and a==b,"real origin crossing preserves cold next-state identity")
	t.check(f.state.world.origin_revision>0,"actual rebase occurred")
	var next := F.cold(t,f,f.state)
	if next.is_empty(): return
	var a := F.F.step(f.sim,f.state,Vector2.LEFT)
	var b := F.F.step(next.sim,next.state,Vector2.LEFT)
	t.check(f.state==next.state and a==b,"post-rebase saved velocity resumes deterministically")
func _geometry(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	var target: Dictionary = f.pair.prop
	t.check(target.destructible,"obstacle fixture owns actual destructible geometry")
	if not target.destructible: return
	var tick := int(f.state.active_tick)
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"steering:geometry","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":tick,"expires_tick":tick,"structure_damage":target.hp}
	var changed: Dictionary = f.sim._streamed.destruction_proposal(f.state,attack,{"prop_id":target.prop_id,"reached":true,"tick":tick,"fraction":1.0})
	t.check(changed.get("ok",false),"geometry test gets actual canonical destruction proposal")
	if not changed.get("ok",false): return
	f.state.world = changed.world
	var hydration := F.HF.hydration(F.H.requirements(f.state))
	t.check(f.sim.prepare_world(f.state,hydration).get("ok",false),"actual geometry replacement prepares")
	var cold := F.cold(t,f,f.state)
	if cold.is_empty(): return
	F.clear(f.sim)
	var a := F.F.step(f.sim,f.state,Vector2.ZERO)
	var b := F.F.step(cold.sim,cold.state,Vector2.ZERO)
	t.check(f.state==cold.state and a==b,"geometry replacement has no hidden steering history")
	t.check(f.sim._streamed.trace.routes.is_empty(),"new direct LOS takes effect immediately after structure destruction")
