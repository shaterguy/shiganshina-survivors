extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const CityFixture = preload("res://tests/core/test_rebuild_streamed_tick.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
func run(t) -> void:
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
		_impact(t,direction,false)
		_impact(t,direction,false,true)
	_impact(t,Vector2.RIGHT,true)
func _impact(t, direction: Vector2, exhausted: bool, durable: bool = false) -> void:
	var raw := CityFixture.new().fixture(t)
	if raw.is_empty(): return
	var f := {"core":raw.sim,"state":raw.state,"chapter":raw.chapter,"disk":raw.disk}
	f.state.active_tick = 107999
	f.state.survival_tick = 107999
	f.state.player.attack_ready_ticks.blade_slash = 200000
	var commands: Array = S.Director.new().plan(f.state,f.chapter)
	for command in commands:
		if Helper.spatial_command(command): command.origin_revision = f.state.world.origin_revision
	S.F.step(f.core,f.state,Vector2.ZERO,commands)
	var a := S.actor(f.state)
	t.check(not a.is_empty(),"A3 real city final boundary creates legal physical actor")
	if a.is_empty(): return
	var query: Dictionary = f.core._streamed.props_query(Rect2(-512,-512,1792,1792))
	var target := {}
	var origin := Vector2.ZERO
	var player := Vector2.ZERO
	for prop in query.props:
		if prop.destructible == durable or prop.collision_mask == 0: continue
		var box: Rect2 = prop.ground_footprint
		var half: float = absf(direction.x)*box.size.x/2+absf(direction.y)*box.size.y/2
		var start: Vector2 = box.get_center()-direction*(half+110)
		var end: Vector2 = box.get_center()+direction*(half+40)
		if not Rect2(-448,-448,1664,1664).has_point(start) or not Rect2(-448,-448,1664,1664).has_point(end): continue
		if start.distance_to(end) <= 420 and f.core._streamed.walkable(start,32).get("walkable",false) and f.core._streamed.walkable(end,8).get("walkable",false) and f.core._final_contact_ready(f.state,start,direction,f.state.rules.enemy_catalog.armored_titan.action_profile,f.core._streamed).get("clear",false):
			var predicted: Dictionary = f.core._final_contact_sweep(f.state,start,direction*270,direction,f.state.rules.enemy_catalog.armored_titan.action_profile,f.core._streamed)
			if not predicted.get("ok",false) or predicted.contact.get("prop_id","") != prop.prop_id: continue
			target = prop; origin = start; player = end; break
	t.check(not target.is_empty(),"A3 four-face fixture finds real destructible legal corridor "+str(direction))
	if target.is_empty(): return
	a.position = [origin.x,origin.y]
	f.state.player.position = [player.x,player.y]
	f.state.telegraphs.clear()
	f.core._set_action(a,"move",int(f.state.active_tick),0)
	a.next_action_tick = int(f.state.active_tick)
	if exhausted: f.state.world.next_structure_strike_tick = int(f.state.active_tick)+1000
	var needed := Helper.requirements(f.state)
	var hydrated: Dictionary = f.disk.hydrate(f.state.world.delta_root,needed.chunks)
	t.check(f.core.prepare_world(f.state,hydrated.deltas).get("ok",false),"A3 arranged actual city encounter prepares")
	var hp: float = f.state.player.hp
	var events := []
	for tick in 140:
		events.append_array(S.step(f))
		a = S.actor(f.state)
		if a.action_state == "brake": break
	t.check(a.action_state == "brake" and f.core.step_status().get("ok",false),"A3 reached wall stops actual Core charge "+str(direction))
	var breaks: Array = events.filter(func(e): return e.type == "structure_destroyed")
	if exhausted or durable:
		t.check(breaks.is_empty() and f.state.world.world_revision == 0,"A3 durable solid or exhausted budget stops actor without damaging building")
	else:
		t.check(breaks.size() == 1 and breaks[0].payload.prop_id == target.prop_id and f.state.world.world_revision == 1 and not f.state.world.dirty_chunks.is_empty(),"A3 physical shoulder collision destroys reached structure exactly once "+str(direction))
		for tick in 10: events.append_array(S.step(f))
		t.check(events.filter(func(e): return e.type == "structure_destroyed").size() == 1,"A3 stopped impact cannot repeat building damage")
		t.check(f.core.restore(f.state,f.core._streamed._hydration).get("ok",false),"A3 destroyed delta and stopped actor cold-restore together")
	t.check(f.state.player.hp == hp,"A3 physical structure contact never reaches player beyond wall")
