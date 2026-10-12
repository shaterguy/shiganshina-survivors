extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
const Counter = preload("res://tests/waiting_motion_v21/profile_counter.gd")
const Transactions = preload("res://tests/waiting_motion/test_transactions.gd")
class SwitchProvider:
	extends RefCounted
	var chapter: Dictionary
	func _init(value: Dictionary): chapter=value.duplicate(true)
	func load_chapter(_id: String) -> Dictionary: return {"ok":true,"chapter":chapter.duplicate(true)}
func run(t) -> void:
	var f := F.make(t)
	var sim = Counter.new(F.F.Current.new())
	var restored: Dictionary = sim.restore(f.state)
	t.check(restored.get("ok",false),"counter restores the real six-waiter setup")
	if not restored.get("ok",false): return
	f.sim=sim;f.state=restored.state
	F.F.step(sim,f.state,Vector2.ZERO,[F.F.spawn("extra:0",[-200.0,-100.0],"stone_thrower"),F.F.spawn("extra:1",[-100.0,70.0],"grabber"),F.F.spawn("extra:2",[100.0,-90.0],"quadruped")])
	F.step(f)
	var a: Dictionary = sim.batches[-1]
	t.check(a.waiters==6 and a.calls=={"stone_thrower":1,"grabber":1,"quadruped":1},"one waiting batch decodes each of three role profiles once, not per actor")
	for role in F.ROLES:
		t.check(a.uses[role].size()==2 and is_same(a.uses[role][0],a.uses[role][1]),"same-batch same-role normalized profile is read-only shared: "+role)
	t.check(not a.mutated,"waiting helper does not mutate shared profile contents")
	F.step(f)
	var b: Dictionary = sim.batches[-1]
	for role in F.ROLES: t.check(not is_same(a.profiles[role],b.profiles[role]),"profile identity never survives the batch boundary: "+role)
	var other = Counter.new(F.F.Current.new())
	var cold: Dictionary = other.restore(f.state)
	t.check(cold.get("ok",false),"second actual Core restores independently")
	if cold.get("ok",false):
		F.F.step(other,cold.state,Vector2.ZERO)
		for role in F.ROLES: t.check(not is_same(b.profiles[role],other.batches[-1].profiles[role]),"different Core never shares profile instances: "+role)
	_chapter_boundary(t)
	_failed_batch(t)
func _chapter_boundary(t) -> void:
	var chapter := F.F.chapter()
	var provider := SwitchProvider.new(chapter)
	var sim = Counter.new(provider)
	var original: Dictionary = sim.new_run(chapter,42,F.F.run_config())
	t.check(not original.has("error_code"),"real original chapter starts before provider replacement")
	var replacement := F.F.geometry_chapter({"bounds":[-600.0,-600.0,1200.0,1200.0],"obstacles":[]},[0.0,0.0])
	provider.chapter=replacement
	t.check(sim.new_run(replacement,42,F.F.run_config()).get("error_code")=="content_mismatch","existing immutable Core rejects actual provider/chapter replacement")
	var fresh = Counter.new(provider)
	var state: Dictionary = fresh.new_run(replacement,42,F.F.run_config())
	t.check(not state.has("error_code") and fresh._chapter.content_fingerprint!=sim._chapter.content_fingerprint,"new Core accepts the actual replacement chapter with its own catalog")
	if state.has("error_code"): return
	state.active_tick=12000;state.survival_tick=12000;state.player.attack_ready_ticks={"blade_slash":2147483647}
	F.F.step(fresh,state,Vector2.ZERO,[F.F.spawn("role",[100.0,0.0],"stone_thrower"),F.F.spawn("pressure",[0.0,0.0])])
	F.F.step(fresh,state,Vector2.ZERO)
	t.check(fresh.batches[-1].calls=={"stone_thrower":1} and not fresh.batches[-1].mutated,"replacement chapter's batch derives its own normalized profile")
func _failed_batch(t) -> void:
	var fixture := Transactions.new()._city(t)
	var sim = Counter.new(fixture.provider,Transactions.MoveHelper.new(fixture.chapter.world_definitions))
	var restored: Dictionary = sim.restore(fixture.state,fixture.hydration)
	t.check(restored.get("ok",false),"failure boundary uses actual city restore")
	if not restored.get("ok",false): return
	var state: Dictionary = restored.state
	t.check(sim.prepare_world(state,fixture.hydration).get("ok",false),"failure boundary prepares real geometry")
	var before := state.duplicate(true)
	sim._streamed.trace.armed=true
	var failed := F.F.step(sim,state,Vector2.ZERO)
	t.check(sim._streamed.trace.failed and state==before and failed.is_empty(),"real coverage failure rolls back the complete waiting tick")
	var previous_profile: Dictionary = sim.batches[-1].profiles.stone_thrower
	var original_width: float = previous_profile.width
	previous_profile.width=9999.0 # Mutate only the test-held discarded reference.
	sim._streamed.trace.armed=false
	var expected = Counter.new(fixture.provider,Transactions.MoveHelper.new(fixture.chapter.world_definitions))
	var restored_expected: Dictionary = expected.restore(before,fixture.hydration)
	t.check(restored_expected.get("ok",false) and expected.prepare_world(restored_expected.state,fixture.hydration).get("ok",false),"uninterrupted cold comparison prepares at the failed boundary")
	var retried := F.F.step(sim,state,Vector2.ZERO)
	var correct := F.F.step(expected,restored_expected.state,Vector2.ZERO)
	t.check(state==restored_expected.state and retried==correct,"retry with a fresh local profile equals uninterrupted cold state and events")
	var next_profile: Dictionary = sim.batches[-1].profiles.stone_thrower
	t.check(sim.step_status().get("ok",false) and next_profile.width==original_width and not is_same(previous_profile,next_profile),"failed batch reference cannot poison the next exact retry")
