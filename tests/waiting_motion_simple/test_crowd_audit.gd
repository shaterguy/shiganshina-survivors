extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
const Audit = preload("res://tests/waiting_motion_simple/audit_core.gd")
const Plan = preload("res://tests/waiting_motion_simple/test_preferred_peer_independence.gd")
func run(t) -> void:
	var f := F.make(t,[[130.0,0.0],[132.0,0.0],[134.0,0.0]])
	var sim = Audit.new(F.F.Current.new())
	var result: Dictionary = sim.restore(f.state)
	t.check(result.get("ok",false),"coincident crowd audit restores an existing valid overlapping save")
	if not result.get("ok",false): return
	f.sim=sim; f.state=result.state
	F.write("crowd-initial-simple.json",f.state)
	for i in 120:
		var before: Dictionary = f.state.duplicate(true)
		F.step(f)
		for id in ["wait:0","wait:1","wait:2"]:
			var old := F.actor(before,id); var current := F.actor(f.state,id)
			var expected := F.point(old)+Plan.preferred(before,old,int(f.state.active_tick))
			t.check(F.point(current).distance_to(expected)<0.0001,"all forced-peer ticks preserve the original unblocked phase intention")
		t.check(f.sim.step_status().get("ok",false),"crowded audit tick commits with original safety admission")
		t.check(f.state.enemy_attack_instances.is_empty(),"persistent player body pressure still denies attacks in crowded audit")
	for row in sim.audit.rows:
		t.check(row.moves.size()<=2,"every actual waiting call uses at most two real terrain moves")
		var before := Vector2(row.before[0],row.before[1]); var after := Vector2(row.after[0],row.after[1])
		var step_bound := 0.0
		for move in row.moves: step_bound=maxf(step_bound,Vector2(move.delta[0],move.delta[1]).length())
		t.check(before.distance_to(after)<=step_bound+0.0001,"actual waiting endpoint never exceeds the original finite step bound")
	t.check(sim.audit.hash_failures.is_empty(),"each crowded deferred batch retains an exact shared spatial hash")
	F.write("crowd-audit-simple.json",sim.audit)
	# Keep the historical same-position spawn contract exercised directly.
	var legacy = F.F.simulation(t)
	var existing = preload("res://tests/core/test_combat.gd").new()
	existing.test_drop_merge_and_spatial_query(t,legacy)
