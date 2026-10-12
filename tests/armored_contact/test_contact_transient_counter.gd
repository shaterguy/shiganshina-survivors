extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Director = preload("res://game/director/spawn_director.gd")
const F = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class FaultMoveHelper:
	extends "res://game/core/streamed_run_world.gd"
	var armed := false
	var injected := false
	func fresh(): return FaultMoveHelper.new(_definitions)
	func move(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
		if armed and radius == 8.0:
			injected = true
			return _query_result(failure("world_not_ready"))
		return super.move(position,delta,radius)
func run(t) -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider,FaultMoveHelper.new(chapter.world_definitions))
	var state := core.new_run(chapter,42,F.run_config())
	state.player.position = [384.0,384.0]
	state.player.attack_ready_ticks.blade_slash = 200000
	state.active_tick = 107999; state.survival_tick = 107999
	var commands := Director.new().plan(state,chapter)
	for command in commands:
		if H.spatial_command(command): command.origin_revision = state.world.origin_revision
	t.check(core.prepare_world(state,HF.hydration(H.requirements(state,commands)),commands).get("ok",false),"real city final fixture prepares")
	F.step(core,state,Vector2.ZERO,commands)
	t.check(state.entities.size() == 1,"real final actor spawned")
	var actor: Dictionary = state.entities[0]
	var target := {}
	var origin := Vector2.ZERO
	var player := Vector2.ZERO
	for prop in core._streamed.props_query(Rect2(-512,-512,1792,1792)).props:
		if not prop.destructible or prop.collision_mask == 0: continue
		var box: Rect2 = prop.ground_footprint
		var start := box.get_center()-Vector2.RIGHT*(box.size.x/2+110)
		var finish := box.get_center()+Vector2.RIGHT*(box.size.x/2+40)
		if not Rect2(-448,-448,1664,1664).has_point(start) or not Rect2(-448,-448,1664,1664).has_point(finish): continue
		if start.distance_to(finish) <= 420 and core._streamed.walkable(start,32).get("walkable",false) and core._streamed.walkable(finish,8).get("walkable",false) and core._final_contact_ready(state,start,Vector2.RIGHT,state.rules.enemy_catalog.armored_titan.action_profile,core._streamed).get("clear",false):
			target = prop; origin = start; player = finish; break
	t.check(not target.is_empty(),"authored destructible has legal opposite approaches")
	if target.is_empty(): return
	actor.position = [origin.x,origin.y]
	state.player.position = [player.x,player.y]
	state.telegraphs.clear()
	core._set_action(actor,"move",int(state.active_tick),0)
	actor.next_action_tick = state.active_tick
	t.check(core.prepare_world(state,HF.hydration(H.requirements(state))).get("ok",false),"arranged real actor is accepted by full restore")
	var reached := false
	for tick in 140:
		actor = state.entities[0]
		if actor.action_state == "attack":
			var profile: Dictionary = state.rules.enemy_catalog.armored_titan.action_profile
			var speed: float = core._final_charge_speed(profile,int(state.active_tick)+1-int(actor.action_started_tick))
			var contact: Dictionary = core._final_contact_sweep(state,Vector2(actor.position[0],actor.position[1]),Vector2.RIGHT*speed/60.0,Vector2.RIGHT,profile,core._streamed)
			if contact.get("ok",false) and contact.get("contact",{}).get("prop_id","") == target.prop_id and contact.fraction < 1:
				reached = true; break
		F.step(core,state,Vector2.ZERO,Director.new().plan(state,chapter))
	t.check(reached,"next real tick reaches selected destructible")
	if not reached: return
	state.event_seq = Core.MAX_COUNTER
	t.check(core.restore(state,core._streamed._hydration).get("ok",false),"counter-limit pre-impact state restores")
	var before := state.duplicate(true)
	var helper = core._streamed
	var events := F.step(core,state,Vector2.ZERO,Director.new().plan(state,chapter))
	var result := {"events":events,"step_status":core.step_status(),"state_unchanged":state == before,"helper_preserved":core._streamed == helper,"current_tick":state.active_tick,"witnesses":core._final_sweeps}
	print("INDEPENDENT_COUNTER_REJECT ",JSON.stringify(result))
	FileAccess.open("res://../counter-reject.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	t.check(events.is_empty() and state == before and not core.step_status().get("ok",false),"counter overflow rolls back the actual impact")
	t.check(core._final_sweeps.is_empty(),"rejected tick cannot publish its uncommitted shoulder witness")
