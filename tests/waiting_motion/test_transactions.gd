extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class MoveHelper:
	extends "res://game/core/streamed_run_world.gd"
	var trace := {"armed":false,"failed":false,"moves":0}
	func fresh():
		var next = MoveHelper.new(_definitions)
		next.trace = trace
		return next
	func move(position: Vector2,delta: Vector2,radius: float) -> Dictionary:
		if radius==24.0:
			trace.moves += 1
			if trace.armed:
				trace.failed = true
				# Real coverage failure in the existing world-query path.
				super.walkable(Vector2(9000.0,384.0),radius)
		return super.move(position,delta,radius)
func _city(t, edge := false) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var sim = F.Core.new(provider,MoveHelper.new(chapter.world_definitions))
	var state: Dictionary = sim.new_run(chapter,42,F.F.run_config())
	state.active_tick = 12000; state.survival_tick = 12000
	state.player.position = [767.0 if edge else 384.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	var commands: Array[Dictionary] = []
	for item in [["wait:0","stone_thrower",[650.0 if edge else 554.0,384.0]],["pressure","walker",state.player.position.duplicate()]]:
		commands.append({"command_id":"spawn:"+item[0],"kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":item[0],"enemy_id":item[1],"position":item[2],"spawned_tick":12000}})
	var hydration := HF.hydration(H.requirements(state,commands))
	t.check(sim.prepare_world(state,hydration,commands).get("ok",false),"waiting city fixture prepares real coverage")
	sim.step(state,Vector2.ZERO,commands)
	t.check(sim.step_status().get("ok",false) and state.enemy_attack_instances.is_empty() and F.actor(state,"wait:0").role_wait_since==12001,"actual city role waits under observed legacy pressure")
	return {"sim":sim,"state":state,"chapter":chapter,"provider":provider,"hydration":hydration}
func _cold(t,f: Dictionary) -> Dictionary:
	var sim = F.Core.new(f.provider,MoveHelper.new(f.chapter.world_definitions))
	var hydration := HF.hydration(H.requirements(f.state))
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)),hydration)
	t.check(restored.get("ok",false),"moving waiter passes cold JSON restore")
	if not restored.get("ok",false): return {}
	t.check(sim.prepare_world(restored.state,hydration).get("ok",false),"moving waiter cold helper prepares")
	return {"sim":sim,"state":restored.state}
func run(t) -> void:
	var f := _city(t)
	for checkpoint in [0,15,30,59]:
		while int(f.state.active_tick)<12001+checkpoint: F.step(f)
		var cold := _cold(t,f)
		if cold.is_empty(): return
		for i in 4:
			var a := F.step(f); var b := F.step(cold)
			t.check(f.state==cold.state and a==b and f.sim.step_status()==cold.sim.step_status(),"waiting warm/cold next state, scheduler, movement and events are exact")
	var before: Dictionary = f.state.duplicate(true)
	var expected := _cold(t,f)
	f.sim._streamed.trace.armed = true
	var events := F.step(f)
	t.check(f.sim._streamed.trace.failed,"waiting movement reaches actual coverage-failure guard")
	t.check(f.state==before and events.is_empty() and f.sim.step_status().get("error_code")=="world_not_ready","failed waiting move atomically rolls position/age/retry/events back")
	f.sim._streamed.trace.armed = false
	var retried := F.step(f); var correct := F.step(expected)
	t.check(f.sim.step_status().get("ok",false) and f.state==expected.state and retried==correct,"same tick retry matches uninterrupted cold next state")
	f = _city(t,true)
	var cold := _cold(t,f)
	if cold.is_empty(): return
	var initial_origin: int = f.state.world.origin_revision
	for i in 8:
		var a := F.step(f,Vector2.RIGHT); var b := F.step(cold,Vector2.RIGHT)
		t.check(f.sim.step_status().get("ok",false) and cold.sim.step_status().get("ok",false),"waiting actor crossing ticks accept")
		t.check(f.state==cold.state and a==b,"real chunk crossing preserves exact waiting warm/cold state and events")
	t.check(f.state.world.origin_revision>initial_origin,"actual waiting observation crosses a chunk origin")
	var after_rebase := _cold(t,f)
	if after_rebase.is_empty(): return
	var a := F.step(f,Vector2.LEFT); var b := F.step(after_rebase,Vector2.LEFT)
	t.check(f.state==after_rebase.state and a==b,"post-rebase waiting motion has no hidden helper history")
	F.write("transactions.json",{"ok":true,"rebase_revision":f.state.world.origin_revision,"final_state":f.state})
