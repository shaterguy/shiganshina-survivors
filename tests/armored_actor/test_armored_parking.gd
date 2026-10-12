extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	var f := R.new()._make(t)
	if f.is_empty(): return
	var a := S.actor(f.state)
	a.position = [-900.0,384.0]
	f.core._set_action(a,"move",int(f.state.active_tick),0)
	f.state.telegraphs.clear()
	# Stale move-only anchors remain validated data, never active geometry.
	a.locked_origin = [-20000.0,384.0]; a.locked_target = [-19900.0,384.0]
	var id = a.id
	var needed := H.requirements(f.state)
	t.check(needed.get("ok",false),"A3 quiescent final parking drops stale move anchors from geometry requirements")
	if not needed.get("ok",false): return
	t.check(f.core.prepare_world(f.state,F.hydration(needed)).get("ok",false),"A3 quiescent final parking candidate prepares")
	S.step(f)
	t.check(S.actor(f.state).is_empty() and f.state.world.get("dormant",{}).get("entities",[]).size() == 1,"A3 persistent final actor parks once in existing absolute v2 record")
	if S.actor(f.state).size() > 0: return
	var entry: Dictionary = f.state.world.dormant.entities[0]
	t.check(entry.record.id == id and entry.record.enemy_id == "armored_titan" and entry.record.action_state == "move" and f.state.world.dormant.drops.is_empty(),"A3 final dormant identity remains distinct from five minibosses")
	var start: int = f.state.active_tick
	for tick in 60: S.step(f)
	t.check(f.state.active_tick == start+60 and f.state.final_started_tick == 108000 and f.state.world.dormant.entities[0] == entry,"A3 parked actor preserves absolute data while final timer continues")
	var restored: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)),f.core._streamed._hydration)
	t.check(restored.get("ok",false),"A3 dormant final actor cold restore uses current real Core")
	t.check(f.core.final_actor_transition_ready(f.state),"A3 quiescent dormant final can cross dock seam")
	var dock: Dictionary = f.core.final_actor_handoff(f.state,f.chapter.authored_dock)
	t.check(dock.get("ok",false) and dock.entity.id == id and dock.entity.action_state == "move" and dock.telegraphs.is_empty() and dock.entity.locked_origin == dock.entity.position,"A3 dormant dock handoff keeps same ID and has no cancelled or duplicated warning")
	_dock_restart(t,f,id)
	var bad: Dictionary = f.state.duplicate(true)
	bad.world.dormant.entities[0].record.enemy_id = "boss_charger"
	t.check(not H.validate_world(bad).get("ok",false),"A3 final-phase dormant cannot retain ordinary miniboss")
	bad = f.state.duplicate(true)
	bad.world.dormant.entities.append(entry.duplicate(true))
	t.check(not H.validate_world(bad).get("ok",false),"A3 final-phase dormant cannot contain two final actors")
	bad = f.state.duplicate(true)
	bad.world.dormant.drops.append({"chunk":entry.chunk.duplicate(),"record":{"id":"ghost","position":[384,384],"xp":1}})
	t.check(not H.validate_world(bad).get("ok",false),"A3 final-phase dormant cannot retain XP drops")
	var relative: Dictionary = H.Address.relative(entry.chunk,Vector2(entry.record.position[0],entry.record.position[1]),f.state.world.origin_chunk)
	f.state.player.position = [relative.local.x+900,relative.local.y]
	needed = H.requirements(f.state)
	t.check(needed.get("ok",false) and f.core.prepare_world(f.state,F.hydration(needed)).get("ok",false),"A3 returning near parked final prepares verified wake geometry")
	S.step(f)
	t.check(S.actor(f.state).get("id") == id and f.state.world.dormant.entities.is_empty() and f.state.final_started_tick == 108000,"A3 returning player wakes original actor without respawn/reward/timer reset")
	t.check(f.state.stats.kills == 0 and f.state.player.xp == 0 and f.core.restore(f.state,f.core._streamed._hydration).get("ok",false),"A3 wake cannot farm rewards and remains cold-restorable")

func _dock_restart(t, f: Dictionary, id: Variant) -> void:
	var source: Dictionary = f.state.duplicate(true)
	source.player.position = [384.0,384.0]
	var core := S.Core.new(f.provider)
	var needed := H.requirements(source)
	if not core.prepare_world(source,F.hydration(needed)).get("ok",false): t.check(false,"A3 parked source prepares at actual passage"); return
	var passage: Dictionary = core._streamed.passage_proposal(source)
	if not passage.get("ok",false): t.check(false,"A3 parked source selects actual passage"); return
	source.world = passage.world
	core.prepare_world(source,F.hydration(H.requirements(source)))
	var command := {"command_id":"armored-parked-dock","kind":"dock_transition","origin_revision":source.world.origin_revision,"payload":{"passage_id":source.world.evacuation.passage_id}}
	var proposed: Dictionary = core._streamed.dock_transition_proposal(source,command,f.chapter.authored_dock)
	t.check(proposed.get("ok",false),"A3 actual passage accepts dormant final while preserving original city source")
	if not proposed.get("ok",false): return
	var retained: Dictionary = core.final_actor_handoff(source,f.chapter.authored_dock)
	if not retained.get("ok",false): t.check(false,"A3 parked source produces legal handoff"); return
	var candidate: Dictionary = source.duplicate(true)
	candidate.world = proposed.candidate_world
	candidate.player.position = [proposed.player_position.x,proposed.player_position.y]
	candidate.escape_zone = f.chapter.authored_dock.escape_rect.duplicate()
	for collection in proposed.retire_ids:
		if candidate.has(collection): candidate[collection].clear()
	if candidate.world.get("schema_version") == 2:
		candidate.world.dormant.entities = candidate.world.dormant.entities.filter(func(entry): return str(entry.record.id) != str(retained.entity.id))
	candidate.entities.append(retained.entity)
	candidate.telegraphs.append_array(retained.telegraphs)
	var dock_core := S.Core.new(f.provider)
	t.check(dock_core.prepare_world(candidate,{}).get("ok",false) and source.world.stage == "city" and source.world.dormant.entities[0].record.id == id,"A3 dormant-to-dock private candidate prepares atomically without altering city")
	var run := {"core":dock_core,"state":candidate,"chapter":f.chapter}
	S.step(run)
	var actor := S.actor(candidate)
	t.check(actor.id == id and actor.action_state == "windup" and actor.action_ends_tick-candidate.active_tick == 72 and candidate.telegraphs.size() == 1 and candidate.final_started_tick == 108000,"A3 dormant move starts one fresh72tick warning on first actual dock tick")
	t.check(dock_core.restore(JSON.parse_string(JSON.stringify(candidate,"",true,true))).get("ok",false),"A3 first dock warning cold-restores after parked handoff")
