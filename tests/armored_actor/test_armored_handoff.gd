extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
func run(t) -> void:
	var f := R.new()._make(t)
	if f.is_empty(): return
	t.check(f.core.has_method("final_actor_transition_ready") and f.core.has_method("final_actor_handoff"),"A3 Core exposes pure safe-seam actor handoff contract")
	if not f.core.has_method("final_actor_handoff"): return
	for phase in ["windup","brake","recover"]:
		var current := R.new()._make(t)
		t.check(R.new()._until(current,phase),"A3 actual city reaches handoff phase "+phase)
		var before: Dictionary = current.state.duplicate(true)
		var a := S.actor(before)
		t.check(current.core.final_actor_transition_ready(current.state),"A3 safe-seam admission "+phase)
		var result: Dictionary = current.core.final_actor_handoff(current.state,current.chapter.authored_dock)
		t.check(result.get("ok",false) and current.state == before,"A3 handoff creates private actor proposal only "+phase)
		if not result.get("ok",false): continue
		var proposed: Dictionary = result.entity
		t.check(proposed.id == a.id and proposed.position == [0.0,-220.0] and proposed.action_started_tick == a.action_started_tick and proposed.action_ends_tick == a.action_ends_tick and proposed.locked_direction == a.locked_direction,"A3 dock anchor retains identity/direction/remaining phase "+phase)
		t.check(proposed.locked_origin == proposed.position and S.Core.World.walkable(Vector2(0,-220),float(a.radius),current.chapter.authored_dock.geometry),"A3 authored anchor and stationary phase origin are geometry legal "+phase)
		if phase == "windup":
			t.check(result.telegraphs.size() == 1 and result.telegraphs[0].id == before.telegraphs[0].id and result.telegraphs[0].active_from_tick == before.telegraphs[0].active_from_tick and result.telegraphs[0].expires_tick == before.telegraphs[0].expires_tick and result.telegraphs[0].origin == proposed.position,"A3 windup warning moves once with original ID and deadlines")
		else: t.check(result.telegraphs.is_empty(),"A3 stopped phase carries no duplicate warning "+phase)
		var invalid: Dictionary = current.chapter.authored_dock.duplicate(true)
		invalid.final_actor_entry_position = [0,0]
		t.check(not current.core.final_actor_handoff(current.state,invalid).get("ok",false) and current.state == before,"A3 invalid anchor fails without changing city actor or clock")
	R.new()._until(f,"attack")
	var start: int = f.state.active_tick
	var deadline: int = S.actor(f.state).action_ends_tick
	var before: Dictionary = f.state.duplicate(true)
	t.check(not f.core.final_actor_transition_ready(f.state) and f.core.final_actor_handoff(f.state,f.chapter.authored_dock).get("error_code") == "final_actor_busy" and f.state == before,"A3 active charge refuses transfer without mutation")
	while f.state.active_tick <= deadline and not f.core.final_actor_transition_ready(f.state): S.step(f)
	t.check(f.core.final_actor_transition_ready(f.state) and f.state.active_tick > start and f.state.active_tick <= deadline and f.state.final_started_tick == 108000,"A3 deferred seam reaches safe phase with continuously running 75-second clock")
