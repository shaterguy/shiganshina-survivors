extends RefCounted
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Core = preload("res://game/core/run_simulation.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class TraceHelper:
	extends "res://game/core/streamed_run_world.gd"
	var trace := {"routes":[],"sweeps":[],"moves":[],"armed":false,"failed":false}
	func fresh():
		var next = TraceHelper.new(_definitions)
		next.trace = trace
		return next
	func direction(position: Vector2,target: Vector2,radius: float,tick: int,actor_id: String = "") -> Dictionary:
		trace.routes.append({"tick":tick,"id":actor_id,"position":position,"target":target})
		return super.direction(position,target,radius,tick,actor_id)
	func sweep(position: Vector2,delta: Vector2,radius: float) -> Dictionary:
		trace.sweeps.append({"position":position,"delta":delta,"radius":radius})
		return super.sweep(position,delta,radius)
	func move(position: Vector2,delta: Vector2,radius: float) -> Dictionary:
		if trace.armed and radius == 18.0:
			trace.failed = true
			# Real missing-coverage guard, not a manufactured return status.
			super.walkable(Vector2(9000,384),radius)
		var result := super.move(position,delta,radius)
		trace.moves.append({"position":position,"delta":delta,"radius":radius,"result":result})
		return result
static func make(t, enemy := "walker", id := "stagger:1", ordinal := 0) -> Dictionary:
	var provider = City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var sim = Core.new(provider,TraceHelper.new(chapter.world_definitions))
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	state.player.position = [384.0,384.0]
	state.active_tick = 1000; state.survival_tick = 1000
	state.player.attack_ready_ticks = {"blade_slash":200000}
	var hydration := HF.hydration(H.requirements(state))
	t.check(sim.prepare_world(state,hydration).get("ok",false),"steering fixture prepares real city")
	var pair := obstacle_pair(sim,float(state.rules.enemy_catalog[enemy].radius),ordinal)
	t.check(not pair.is_empty(),"steering fixture finds a real obstructed legal route")
	if pair.is_empty(): return {}
	state.player.position = [pair.target.x,pair.target.y]
	var commands: Array[Dictionary] = [{"command_id":"spawn:"+id,"kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":id,"enemy_id":enemy,"position":[pair.point.x,pair.point.y],"spawned_tick":1000}}]
	hydration = HF.hydration(H.requirements(state,commands))
	t.check(sim.prepare_world(state,hydration,commands).get("ok",false),"steering fixture prepares actual spawn")
	sim.step(state,Vector2.ZERO,commands)
	t.check(sim.step_status().get("ok",false) and state.entities.size()==1,"steering fixture actually spawns one actor")
	if state.entities.size()!=1: return {}
	if not sim._is_live_role(state.entities[0]): state.entities[0].next_action_tick = 200000
	clear(sim)
	return {"provider":provider,"chapter":chapter,"sim":sim,"state":state,"hydration":hydration,"pair":pair}
static func obstacle_pair(sim,radius: float,ordinal := 0) -> Dictionary:
	var found := 0
	for prop in sim._streamed.props_query(Rect2(0,0,768,768)).props:
		if prop.collision_mask == 0: continue
		var box: Rect2 = prop.ground_footprint
		for axis in [Vector2.RIGHT,Vector2.DOWN]:
			var half_size := box.size.x*.5 if axis == Vector2.RIGHT else box.size.y*.5
			var point: Vector2 = box.get_center()-axis*(half_size+radius+10)
			var target: Vector2 = box.get_center()+axis*(half_size+radius+10)
			if not Rect2(32,32,704,704).has_point(point) or not Rect2(32,32,704,704).has_point(target): continue
			if not sim._streamed.walkable(point,radius).get("walkable",false) or not sim._streamed.walkable(target,radius).get("walkable",false): continue
			if sim._streamed.sweep(point,target-point,radius).get("fraction",1.0)==1.0: continue
			var route: Dictionary = sim._streamed.direction(point,target,radius,1000)
			if route.get("ok",false) and not route.get("blocked",false) and not route.direction.is_zero_approx():
				if found == ordinal: return {"point":point,"target":target,"prop":prop}
				found += 1
	return {}
static func clear(sim) -> void:
	for key in ["routes","sweeps","moves"]: sim._streamed.trace[key].clear()
static func cold(t,f: Dictionary,state: Dictionary) -> Dictionary:
	var sim = Core.new(f.provider,TraceHelper.new(f.chapter.world_definitions))
	var hydration := HF.hydration(H.requirements(state))
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
	t.check(restored.get("ok",false),"steering snapshot passes actual cold restore")
	if not restored.get("ok",false): return {}
	t.check(sim.prepare_world(restored.state,hydration).get("ok",false),"steering cold instance prepares")
	clear(sim)
	return {"sim":sim,"state":restored.state}
