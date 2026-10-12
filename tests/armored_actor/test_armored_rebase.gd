extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class FaultHelper:
	extends "res://game/core/streamed_run_world.gd"
	var blocked := false
	func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
		if blocked: return _query_result(failure("world_not_ready"))
		return super.sweep(position,delta,radius)
func run(t) -> void:
	for phase in ["windup","attack","brake","recover"]: _rebase(t,phase)
	_rollback(t)
func _make(t) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := S.Core.new(provider,FaultHelper.new(chapter.world_definitions))
	var state := core.new_run(chapter,42,S.F.run_config())
	state.player.position = [766.0,384.0]
	state.player.attack_ready_ticks.blade_slash = 200000
	state.active_tick = 107999; state.survival_tick = 107999
	var commands: Array = S.Director.new().plan(state,chapter)
	for command in commands:
		if H.spatial_command(command): command.origin_revision = state.world.origin_revision
	var hydration := F.hydration(H.requirements(state,commands))
	t.check(core.prepare_world(state,hydration,commands).get("ok",false),"A2 real final rebase fixture prepares")
	S.F.step(core,state,Vector2.ZERO,commands)
	var f := {"core":core,"state":state,"chapter":chapter,"provider":provider,"hydration":hydration}
	var a := S.actor(state)
	if a.is_empty(): t.check(false,"A2 real final rebase actor spawned"); return {}
	a.position = [600.1234741210938,384.0]
	state.telegraphs.clear()
	core._set_action(a,"move",int(state.active_tick),0); a.next_action_tick = state.active_tick
	a.locked_origin = a.position.duplicate(); a.locked_target = state.player.position.duplicate()
	t.check(core.prepare_world(state,hydration).get("ok",false),"A2 final rebase actual actor arrangement remains Core valid")
	return f
func _until(f: Dictionary, phase: String) -> bool:
	for index in 260:
		var a := S.actor(f.state)
		if a.action_state == phase and int(f.state.active_tick)-int(a.action_started_tick) >= 5: return true
		S.step(f)
	return false
func _rebase(t, phase: String) -> void:
	var f := _make(t)
	if f.is_empty(): return
	t.check(_until(f,phase),"A2 real final reaches mid-"+phase+" before rebase")
	S.step(f,Vector2.RIGHT)
	var source: Dictionary = f.state.duplicate(true)
	var original := S.actor(source)
	var next := S.Core.new(f.provider)
	var hydrated := F.hydration(H.requirements(source))
	var checked := next.restore(JSON.parse_string(JSON.stringify(source,"",true,true)),hydrated)
	t.check(checked.get("ok",false),"A2 pending rebase final pose cold-restores in "+phase)
	if not checked.get("ok",false): return
	t.check(next.prepare_world(checked.state,hydrated).get("ok",false),"A2 cold final rebase helper prepares in "+phase)
	var replay := {"core":next,"state":checked.state,"chapter":f.chapter}
	var warm_events := S.step(f)
	var cold_events := S.step(replay)
	t.check(f.core.step_status().get("ok",false) and f.state.world.origin_revision == source.world.origin_revision+1,"A2 actual Core rebase commits in "+phase+" "+str(f.core.step_status()))
	t.check(f.state == replay.state and warm_events == cold_events,"A2 warm/cold rebase agree exactly in "+phase)
	var a := S.actor(f.state)
	t.check(a.id == original.id and a.action_ends_tick == original.action_ends_tick and f.state.final_started_tick == source.final_started_tick,"A2 rebase preserves final actor identity and remaining phase "+phase)
	t.check(f.core.restore(f.state,f.core._streamed._hydration).get("ok",false),"A2 rebased final pose remains valid "+phase)
func _rollback(t) -> void:
	var f := _make(t)
	if f.is_empty(): return
	t.check(_until(f,"attack"),"A2 late geometry failure is inside actual final attack")
	var before: Dictionary = f.state.duplicate(true)
	var helper = f.core._streamed
	helper.blocked = true
	var events := S.step(f)
	t.check(events.is_empty() and f.state == before and f.core._streamed == helper and f.core.step_status().get("error_code") == "world_not_ready","A2 failed real final sweep rolls back clocks/actor/HP/events atomically")
	helper.blocked = false
	S.step(f)
	t.check(f.core.step_status().get("ok",false) and f.state.active_tick == before.active_tick+1,"A2 repaired geometry retries same final tick without duplicate motion")
