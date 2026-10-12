extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class NoPathHelper:
	extends "res://game/core/streamed_run_world.gd"
	# Controlled navigation unavailability with real collision geometry. The
	# production Core must still permit a quiescent seam, never await a route.
	func direction(_position: Vector2, _target: Vector2, _radius: float, _tick: int, _actor_id: String = "") -> Dictionary:
		return {"ok":true,"direction":Vector2.ZERO,"blocked":true,"deferred":true,"wait_ticks":0}
func run(t) -> void:
	_no_path(t)
	var f := R.new()._make(t)
	if f.is_empty(): return
	var a := S.actor(f.state)
	f.state.player.position = [384.0,384.0]
	a.position = [-300.0,384.0]
	a.locked_origin = [-18000.0,384.0]
	a.locked_target = [-17900.0,384.0]
	f.state.telegraphs.clear()
	f.core._set_action(a,"move",int(f.state.active_tick),0)
	var needed := H.requirements(f.state)
	t.check(f.core.prepare_world(f.state,F.hydration(needed)).get("ok",false),"A3 active move at684distance is valid actual city state with inactive stale anchors")
	var before: Dictionary = f.state.duplicate(true)
	t.check(f.core.final_actor_transition_ready(f.state),"A3 quiescent active move is a safe seam without waiting for range or pathfinding")
	var retained: Dictionary = f.core.final_actor_handoff(f.state,f.chapter.authored_dock)
	t.check(retained.get("ok",false) and f.state == before,"A3 active move returns private handoff instead of potential no-path deadlock")
	if not retained.get("ok",false): return
	t.check(retained.entity.id == a.id and retained.entity.action_state == "move" and retained.entity.locked_origin == [0.0,-220.0] and retained.entity.locked_target == [0.0,0.0] and retained.telegraphs.is_empty(),"A3 active move resets inactive anchors to dock without changing identity or inventing warnings")
	var passage: Dictionary = f.core._streamed.passage_proposal(f.state)
	t.check(passage.get("ok",false),"A3 active move player overlaps actual selected passage")
	if not passage.get("ok",false): return
	var source: Dictionary = f.state.duplicate(true)
	source.world = passage.world
	f.core.prepare_world(source,F.hydration(H.requirements(source)))
	var command := {"command_id":"active-move-dock","kind":"dock_transition","origin_revision":source.world.origin_revision,"payload":{"passage_id":source.world.evacuation.passage_id}}
	var proposal: Dictionary = f.core._streamed.dock_transition_proposal(source,command,f.chapter.authored_dock)
	t.check(proposal.get("ok",false),"A3 active move actual geometry proposal succeeds without action-clock delay")
	if not proposal.get("ok",false): return
	var candidate: Dictionary = source.duplicate(true)
	candidate.world = proposal.candidate_world
	candidate.player.position = [proposal.player_position.x,proposal.player_position.y]
	candidate.escape_zone = f.chapter.authored_dock.escape_rect.duplicate()
	for collection in proposal.retire_ids:
		if candidate.has(collection): candidate[collection].clear()
	candidate.entities.append(retained.entity)
	candidate.telegraphs.append_array(retained.telegraphs)
	var core := S.Core.new(f.provider)
	t.check(core.prepare_world(candidate,{}).get("ok",false),"A3 active move candidate cold-validates with original final ID")
	var run := {"core":core,"state":candidate,"chapter":f.chapter}
	S.step(run)
	var actor := S.actor(candidate)
	t.check(actor.id == a.id and actor.action_state == "windup" and actor.action_ends_tick-candidate.active_tick == 72 and candidate.telegraphs.size() == 1 and candidate.final_started_tick == before.final_started_tick,"A3 active move begins one fresh72tick warning after atomic dock adoption")
	t.check(core.restore(JSON.parse_string(JSON.stringify(candidate,"",true,true))).get("ok",false),"A3 active move first dock warning restores without stale city anchors")

func _no_path(t) -> void:
	var f := R.new()._make(t)
	if f.is_empty(): return
	f.state.player.position = [384.0,384.0]
	var a := S.actor(f.state)
	var point := Vector2(INF,INF)
	for y in [-128.0,128.0,384.0,640.0,896.0,1152.0]:
		for x in [-128.0,128.0,384.0,640.0,896.0,1152.0]:
			var origin := Vector2(x,y)
			var delta := Vector2(384,384)-origin
			if delta.length() <= 420 or delta.length() >= 1536: continue
			if not f.core._streamed.walkable(origin,32).get("walkable",false): continue
			var contact: Dictionary = f.core._streamed.sweep(origin,delta,32)
			if contact.get("ok",false) and contact.fraction < 1:
				point = origin; break
		if is_finite(point.x): break
	t.check(is_finite(point.x),"A3 no-path regression finds real obstructed420–1536 corridor")
	if not is_finite(point.x): return
	a.position = [point.x,point.y]; a.locked_origin = a.position.duplicate()
	a.locked_target = f.state.player.position.duplicate()
	f.core._set_action(a,"move",int(f.state.active_tick),0)
	f.state.telegraphs.clear()
	var core := S.Core.new(f.provider,NoPathHelper.new(f.chapter.world_definitions))
	var needed := H.requirements(f.state)
	t.check(core.prepare_world(f.state,F.hydration(needed)).get("ok",false),"A3 actual obstructed encounter prepares with controlled unavailable navigation")
	f.core = core
	var start: int = f.state.active_tick
	for tick in 30: S.step(f)
	a = S.actor(f.state)
	t.check(f.state.active_tick == start+30 and a.position == [point.x,point.y] and a.action_state == "move" and f.state.telegraphs.is_empty(),"A3 no-path keeps actual Core ticking with same quiescent physical actor")
	t.check(core.final_actor_transition_ready(f.state) and core.final_actor_handoff(f.state,f.chapter.authored_dock).get("ok",false),"A3 no-path active move cannot indefinitely block physical passage handoff")
	print("ACTIVE_MOVE_NO_PATH ",JSON.stringify({"actor":a.position,"player":f.state.player.position,"ticks":f.state.active_tick-start,"handoff_ready":core.final_actor_transition_ready(f.state)}))
