extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const W = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const D = preload("res://game/director/spawn_director.gd")
const Flow = preload("res://game/app/final_evacuation_flow.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
class FaultCover:
	extends "res://game/core/streamed_run_world.gd"
	var armed := false
	func cover_query(origin: Vector2, target: Vector2, radius: float, mask: int) -> Dictionary:
		if armed: return _query_result(failure("world_not_ready"))
		return super.cover_query(origin,target,radius,mask)
func _make(t, point: Array = [384.0,384.0], fault := false) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var config := F.run_config(); config.character_id = "mikasa_01"; config.character_skill_revision = 1
	var sim := Core.new(provider,FaultCover.new(chapter.world_definitions) if fault else null)
	var state := sim.new_run(chapter,42,config)
	state.player.position = point.duplicate()
	state.player.attack_ready_ticks.blade_slash = 200000
	var hydration := W.hydration(H.requirements(state))
	t.check(sim.prepare_world(state,hydration).get("ok",false),"signature streamed fixture uses real current world geometry")
	return {"sim":sim,"state":state,"chapter":chapter,"provider":provider}
func _step(f: Dictionary, move := Vector2.ZERO, commands: Array = []) -> Array[Dictionary]:
	for command in commands:
		if H.spatial_command(command): command.origin_revision = f.state.world.origin_revision
	return F.step(f.sim,f.state,move,commands)
func run(t) -> void:
	_rollback(t)
	_rebase(t)
	_dock(t)
func _rollback(t) -> void:
	var f := _make(t,[384.0,384.0],true)
	var before: Dictionary = f.state.duplicate(true)
	f.sim._streamed.armed = true
	var events := _step(f,Vector2.ZERO,[F.spawn("fault-target",[450,384],"brute")])
	t.check(events.is_empty() and f.state == before and f.sim.step_status().get("error_code") == "world_not_ready","late acquisition cover failure rolls back probe clock spawn IDs events and state")
	f.sim._streamed.armed = false
	events = _step(f,Vector2.ZERO,[F.spawn("fault-target",[450,384],"brute")])
	t.check(f.sim.step_status().get("ok",false) and f.state.active_tick == 1 and not f.state.character_skill.pending_cast_id.is_empty(),"geometry recovery retries original tick with one signature cast")
func _rebase(t) -> void:
	var f := _make(t,[766.0,384.0])
	_step(f,Vector2.ZERO,[F.spawn("rebase-target",[696,384],"brute")])
	t.check(f.state.player_attack_instances.size() == 2,"real city first strike leaves pending signature")
	if f.state.player_attack_instances.size() != 2: return
	_step(f,Vector2.RIGHT)
	var source: Dictionary = f.state.duplicate(true)
	var events := _step(f)
	t.check(f.sim.step_status().get("ok",false) and f.state.world.origin_revision == source.world.origin_revision+1,"actual Core rebase occurs between signature strikes")
	t.check(f.state.character_skill == source.character_skill and f.state.player_attack_instances[0].origin[0] == source.player_attack_instances[0].origin[0]-768.0,"rebase changes only local origin and preserves cast clocks")
	var next := Core.new(f.provider)
	var hydration := W.hydration(H.requirements(f.state))
	var cold := next.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)),hydration)
	t.check(cold.get("ok",false),"rebased pending signature cold restores")
	if not cold.get("ok",false): return
	t.check(next.prepare_world(cold.state,hydration).get("ok",false),"cold rebased signature prepares actual geometry")
	var hits := []
	for i in 14:
		events = F.step(next,cold.state,Vector2.ZERO)
		for e in events:
			if e.type == "damage" and e.payload.get("source_id") == Signature.TOKEN: hits.append(e.tick)
	t.check(hits == [9,17],"rebase and cold restore retain exactly two future hits")
func _dock(t) -> void:
	var f := _make(t)
	f.state.active_tick = 107999; f.state.survival_tick = 107999
	_step(f,Vector2.ZERO,D.new().plan(f.state,f.chapter))
	t.check(f.state.phase == "evacuation" and not f.state.entities.is_empty(),"actual streamed final phase produces armored actor")
	var authority := {"checkpoint":f.sim.snapshot(f.state)}
	var selection := Flow.prepare(f.sim,f.state,authority,f.chapter)
	t.check(selection.get("action") == "passage_selection","actual final flow selects passage")
	if selection.get("action") != "passage_selection": return
	f.state = selection.candidate.checkpoint.duplicate(true)
	var hydration := W.hydration(H.requirements(f.state))
	t.check(f.sim.prepare_world(f.state,hydration).get("ok",false),"selected passage and signature state validate together")
	# Evacuation rejects ordinary spawns. Use the actual invulnerable actor,
	# arranged at a legal nearby road point before its real next windup.
	var actor: Dictionary = f.state.entities[0]
	actor.position = [470.0,384.0]
	actor.locked_origin = actor.position.duplicate()
	actor.locked_target = f.state.player.position.duplicate()
	f.state.telegraphs.clear()
	f.sim._set_action(actor,"move",int(f.state.active_tick),0)
	actor.next_action_tick = f.state.active_tick
	var armor_events: Array[Dictionary] = []
	for i in 6: armor_events.append_array(_step(f))
	t.check(armor_events.any(func(e): return e.type == "armor_blocked" and e.payload.get("source_id") == Signature.TOKEN) and actor.hp == actor.max_hp,"signature cannot bypass actual final armor invulnerability")
	t.check(f.state.player_attack_instances.size() == 2,"signature is truly pending immediately before dock handoff")
	if f.state.player_attack_instances.size() != 2: return
	var clocks: Dictionary = f.state.character_skill.duplicate(true)
	authority.checkpoint = f.sim.snapshot(f.state)
	var proposal := Flow.prepare(f.sim,f.state,authority,f.chapter)
	t.check(proposal.get("action") == "dock_transition","actual final actor handoff produces dock checkpoint")
	if proposal.get("action") != "dock_transition": return
	var checkpoint: Dictionary = proposal.candidate.checkpoint
	t.check(checkpoint.player_attack_instances.is_empty() and checkpoint.character_skill.pending_cast_id == "","dock retirement consumes signature pointer together with pending attacks")
	t.check(checkpoint.character_skill.ready_tick == clocks.ready_tick and checkpoint.character_skill.next_probe_tick == clocks.next_probe_tick,"dock retirement retains both signature clocks")
	var next := Core.new(f.provider)
	var restored := next.restore(JSON.parse_string(JSON.stringify(checkpoint,"",true,true)))
	t.check(restored.get("ok",false),"cancelled signature dock checkpoint cold restores")
	if not restored.get("ok",false): return
	t.check(next.prepare_world(restored.state,{}).get("ok",false),"restored dock geometry prepares")
	var repeats := 0
	for i in 20:
		for e in F.step(next,restored.state,Vector2.ZERO):
			if e.type == "player_attack" and e.payload.get("base_item_id") == Signature.TOKEN: repeats += 1
	t.check(repeats == 0,"retired city strikes never replay after cold dock restore")
