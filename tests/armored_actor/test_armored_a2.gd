extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Population = preload("res://game/core/city_population.gd")
func run(t) -> void:
	_restore(t)
	_contact_recovery(t)
	_four_faces(t)
	_spawn_deferred(t)
	_persistence(t)
func _restore(t) -> void:
	var f := S.make()
	S.begin(f)
	S.arrange_windup(f,Vector2.ZERO,Vector2(300,0))
	var a := S.actor(f.state)
	var cuts := {}
	var start: int = f.state.active_tick
	var direction: Array = a.locked_direction.duplicate()
	for index in 205:
		if int(f.state.active_tick)-int(a.action_started_tick) >= 5 and not cuts.has(a.action_state) and a.action_state in ["windup","attack","brake","recover"]:
			cuts[a.action_state] = true
			var next = S.Core.new(f.provider)
			var restored: Dictionary = next.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)))
			t.check(restored.get("ok",false),"A2 JSON cold restore admits real final phase "+a.action_state)
			if restored.get("ok",false):
				var replay := {"core":next,"state":restored.state,"chapter":f.chapter}
				var original_copy := {"core":S.Core.new(f.provider),"state":f.state.duplicate(true),"chapter":f.chapter}
				for tick in 5:
					var before: Array = S.step(original_copy)
					var after: Array = S.step(replay)
					t.check(before == after and original_copy.state == replay.state,"A2 cold restore exact next tick "+a.action_state+":"+str(tick))
			var bad: Dictionary = f.state.duplicate(true)
			S.actor(bad).position[0] += 2.0
			t.check(not next.restore(bad).get("ok",false),"A2 changed pose is rejected in "+a.action_state)
		if index == 10:
			f.state.pause_reasons.append("user")
			var before: Dictionary = f.state.duplicate(true)
			for tick in 5: S.step(f)
			t.check(f.state == before,"A2 pause consumes no final clock, motion or sweep")
			f.state.pause_reasons.clear()
		S.step(f)
		t.check(a.locked_direction == direction,"A2 shoulder charge keeps originally warned direction")
	t.check(cuts.size() == 4 and f.state.active_tick-start == 205,"A2 all warning charge brake recover phases have JSON cut coverage")
	var bad: Dictionary = f.state.duplicate(true)
	for field in ["action_state","action_started_tick","action_ends_tick","next_action_tick","pattern_index","attack_kind","locked_origin","locked_direction","locked_target","facing"]: S.actor(bad).erase(field)
	t.check(not f.core.restore(bad).get("ok",false),"A2 final actor cannot omit its entire FSM")
func _contact_recovery(t) -> void:
	var f := S.make()
	S.begin(f)
	S.arrange_windup(f,Vector2.ZERO,Vector2(300,0))
	var a := S.actor(f.state)
	for tick in 180:
		if a.action_state == "brake": break
		S.step(f)
	for action in ["brake","recover"]:
		var found := false
		for tick in 120:
			if a.action_state == action:
				found = true
				f.state.player.position = a.position.duplicate()
				f.state.player.invulnerable_until = 0
				var hp: float = f.state.player.hp
				S.step(f)
				t.check(f.state.player.hp == hp,"A2 overlapping "+action+" actor has no generic contact damage")
				break
			S.step(f)
		t.check(found,"A2 reached "+action+" for actual contact check")
func _four_faces(t) -> void:
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[-40,-40,80,80]]},[500,500])
		S.begin(f)
		var point: Vector2 = -direction*170
		var target: Vector2 = direction*160
		S.arrange_windup(f,point,target)
		var a := S.actor(f.state)
		var hp: float = f.state.player.hp
		for tick in 135:
			S.step(f)
			if a.action_state == "brake": break
		t.check(a.action_state == "brake" and S.Core.World.walkable(Vector2(a.position[0],a.position[1]),32,f.state.rules.world_geometry),"A2 four-face wall collision ends in valid stopped pose "+str(direction))
		t.check(f.state.player.hp == hp and f.core.restore(f.state).get("ok",false),"A2 four-face wall blocks damage and cold-restores brake "+str(direction))
func _spawn_deferred(t) -> void:
	var f := S.make({"bounds":[-40,-40,80,80],"obstacles":[]})
	var events := S.begin(f)
	t.check(S.actor(f.state).is_empty() and f.state.phase == "evacuation" and events.any(func(e): return e.type == "final_actor_spawn_deferred"),"A2 failed legal-space search explicitly defers physical spawn")
	var start: int = f.state.active_tick
	for tick in 40: S.step(f)
	t.check(f.state.active_tick == start+40 and f.state.final_started_tick == 108000 and f.state.next_entity_id == 1,"A2 bounded failed spawn retries keep final clock running and consume no actor IDs")
func _persistence(t) -> void:
	var f := S.make()
	S.begin(f)
	var a := S.actor(f.state)
	var state: Dictionary = f.state.duplicate(true)
	state.world = {"stage":"city","schema_version":2,"dormant":{"entities":[],"drops":[]}}
	S.actor(state).position = [1800.0,0.0]
	S.actor(state).action_state = "move"
	state.telegraphs.clear()
	var plan := Population.plan(state)
	t.check(plan.get("ok",false) and plan.retire.is_empty() and plan.park_entities == [0],"A2 final actor is persisted rather than retired when quiescent beyond current distance policy")
