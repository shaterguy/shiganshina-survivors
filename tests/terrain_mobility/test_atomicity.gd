extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
func run(t) -> void:
	if not F.available(t): return
	for hp in [2,0]:
		var s: Dictionary = F.make(t)
		t.check(F.reach(s,"boost"),"damage cancellation reaches a real paired boost")
		# Advance on the real collision-checked corridor before anchor damage.
		F.step(s); F.step(s)
		s.state.world = s.state.world.duplicate(true)
		s.state.world.world_revision += 1
		s.state.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":"left","hp":hp,"destroyed":hp == 0}]}]
		t.check(s.core.prepare_world(s.state,s.hydration).get("ok",false),"cold restore admits physical damage hazard without moving saved player")
		var previous: Vector2 = F.vec(s.state.player.position)
		for tick in 40:
			var events: Array[Dictionary] = F.step(s)
			var current: Vector2 = F.vec(s.state.player.position)
			t.check(current.distance_to(previous) <= 8.0001,"damaged anchor cancels without teleport")
			t.check(events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").is_empty(),"damaged anchor cancellation cannot attack")
			previous = current
		t.check(s.state.player_mobility.phase == "ground" and s.core._streamed.walkable(previous,8).get("walkable",false),"partially damaged/destroyed anchor finishes on legal ground")
	var uncovered: Dictionary = F.make(t)
	t.check(F.reach(uncovered,"boost"),"coverage refusal fixture reaches boost")
	var before: Dictionary = uncovered.state.duplicate(true)
	uncovered.core._streamed._world._chunks.erase("0,0")
	uncovered.core._streamed._world._coverage_revision += 1
	t.check(F.F.step(uncovered.core,uncovered.state,Vector2.UP).is_empty() and F.same(before,uncovered.state),"missing active route coverage refuses all tick movement/damage/clocks")
	var rebased: Dictionary = F.make(t)
	t.check(F.reach(rebased,"boost"),"rebase fixture reaches boost")
	var saved_path: Array = rebased.state.player_mobility.path.duplicate(true)
	rebased.state.world = rebased.state.world.duplicate(true)
	rebased.state.world.origin_chunk = ["-1","0"]
	rebased.state.world.origin_revision += 1
	rebased.state.player.position[0] += 768.0
	var hydration: Dictionary = F.HF.hydration(F.H.requirements(rebased.state))
	t.check(rebased.core.prepare_world(rebased.state,hydration).get("ok",false),"grounded boost geometry prepares before origin normalization")
	F.step(rebased)
	t.check(rebased.state.world.origin_chunk == ["0","0"] and rebased.state.player_mobility.path == saved_path,"rebase changes plane frame once and never shifts absolute mobility path")
	var reverse: Dictionary = F.make(t)
	t.check(F.reach(reverse,"boost"),"reversal fixture reaches boost")
	F.step(reverse,Vector2.DOWN)
	t.check(reverse.state.player_mobility.phase == "ground","opposite input ends boost immediately instead of auto-targeting")
	var turned: Dictionary = F.make(t)
	t.check(F.reach(turned,"boost"),"meaningful input turn fixture reaches boost")
	var prior_point: Vector2 = F.vec(turned.state.player.position)
	var turn_events: Array[Dictionary] = F.step(turned,Vector2(1,-1).normalized())
	t.check(turned.state.player_mobility.phase == "boost" and not turned.state.player_mobility.cancelled,"non-reversing diagonal input keeps the locked forward corridor")
	t.check(prior_point.distance_to(F.vec(turned.state.player.position)) <= 8.0001 and F.vec(turned.state.player.position).x == prior_point.x,"diagonal input keeps one bounded grounded step without retargeting")
	t.check(turn_events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").is_empty(),"empty corridor emits no synthetic damage when input changes")
	var changed_geometry: Dictionary = F.make(t)
	t.check(F.reach(changed_geometry,"boost"),"physical metadata mutation fixture reaches boost")
	var saved_anchor: Dictionary = changed_geometry.state.player_mobility.anchors[0]
	var actual_prop: Dictionary = changed_geometry.core._streamed._world._props[saved_anchor.prop_id]
	actual_prop.mobility_anchor = actual_prop.mobility_anchor.duplicate(true)
	actual_prop.mobility_anchor.roof_height += 1.0
	var stale_pair: Dictionary = changed_geometry.core._streamed.mobility_pair_check(changed_geometry.state,changed_geometry.state.player_mobility.anchors)
	t.check(not stale_pair.get("ok",false),"runtime pair cannot ignore changed actual physical anchor metadata")
