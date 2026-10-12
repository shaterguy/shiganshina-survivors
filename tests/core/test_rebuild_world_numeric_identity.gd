extends RefCounted
# NEW regression for semantically equal JSON numeric authority at preparation.
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Fixture = preload("res://tests/core/test_rebuild_streamed_tick.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var setup := Fixture.new().fixture(t)
	if setup.is_empty(): return
	var variants := []
	for field in ["schema_version","origin_revision","world_revision","next_structure_strike_tick"]:
		var candidate: Dictionary = setup.state.duplicate(true)
		candidate.world[field] = float(candidate.world[field])
		variants.append({"name":field,"state":candidate})
	for integer_value in [2147483648,4294967296,9007199254740990,9007199254740991]:
		var value := float(integer_value)
		var candidate: Dictionary = setup.state.duplicate(true)
		candidate.world.origin_revision = value
		variants.append({"name":"wide origin "+str(value),"state":candidate})
	var root_float: Dictionary = setup.state.duplicate(true)
	root_float.world.delta_root.format_revision = 1.0
	variants.append({"name":"nested root format","state":root_float})
	var seed_float: Dictionary = setup.state.duplicate(true)
	seed_float.seed = 42.0
	variants.append({"name":"seed","state":seed_float})
	var world_json: Dictionary = setup.state.duplicate(true)
	world_json.world = JSON.parse_string(JSON.stringify(world_json.world,"",true,true))
	variants.append({"name":"whole JSON world","state":world_json})
	for record in variants:
		var sim := Core.new(City.new())
		var state: Dictionary = record.state
		var before := state.duplicate(true)
		var control := Core.new(City.new())
		var restored := control.restore(state,setup.hydration)
		t.check(restored.get("ok",false),"numeric identity has valid canonical control: "+record.name)
		if not restored.get("ok",false): continue
		var canonical: Dictionary = restored.state
		t.check(control.prepare_world(canonical,setup.hydration).ok and sim.prepare_world(state,setup.hydration).ok,"canonical and JSON numeric forms prepare: "+record.name)
		t.check(state == before,"successful preparation preserves numeric caller input: "+record.name)
		t.check(sim._streamed.readiness(state).ok,"successful preparation is immediately ready for caller: "+record.name)
		var helper_id: int = sim._streamed.get_instance_id()
		var a := F.step(sim,state,Vector2.RIGHT)
		var b := F.step(control,canonical,Vector2.RIGHT)
		t.check(state.active_tick == 1 and a == b,"numeric authority advances actual matching tick/events: "+record.name)
		var result := sim.restore(state,setup.hydration)
		t.check(result.get("ok",false) and result.state == canonical,"numeric preparation has exact normalized cold state: "+record.name)
		t.check(sim._streamed.get_instance_id() == helper_id,"numeric matching does not recreate helper per tick: "+record.name)
	_identity_changes(t,setup)
	_dirty_identity(t,setup)
	_dock_identity(t,setup)
func _identity_changes(t,setup: Dictionary) -> void:
	var sim = setup.sim
	var source: Dictionary = setup.state
	var view: Dictionary = sim._streamed.render_view(source)
	var helper_id: int = sim._streamed.get_instance_id()
	var cases := []
	for field in ["origin_revision","world_revision","next_structure_strike_tick"]:
		var changed := source.duplicate(true)
		changed.world[field] += 1
		cases.append(changed)
	for value in [["0","1"],["1","0"]]:
		var changed := source.duplicate(true)
		changed.world.origin_chunk = value
		cases.append(changed)
	for pair in [["run_id","different-run"],["seed",43],["seed",true],["seed",NAN],["seed",INF]]:
		var changed := source.duplicate(true)
		changed[pair[0]] = pair[1]
		cases.append(changed)
	for value in [NAN,INF,-INF,true,[],"0"]:
		var changed := source.duplicate(true)
		changed.world.origin_revision = value
		cases.append(changed)
	var extra := source.duplicate(true)
	extra.world.extra = 0
	cases.append(extra)
	for changed in cases:
		t.check(not sim._streamed.matches(changed),"changed or unsafe authority cannot match prepared identity")
	var wrong_hydration: Dictionary = setup.hydration.duplicate(true)
	wrong_hydration.erase(wrong_hydration.keys()[0])
	var candidate := source.duplicate(true)
	candidate.world.origin_revision = 1.0
	t.check(not sim.prepare_world(candidate,wrong_hydration).get("ok",false),"failed float authority preparation stays explicit")
	t.check(sim._streamed.get_instance_id() == helper_id and sim._streamed.matches(source) and sim._streamed.render_view(source) == view,"failed B preparation preserves complete A identity/cache")
	var before := source.duplicate(true)
	source.world.origin_revision = 1
	t.check(not sim._streamed.matches(source),"caller mutation cannot alter saved prepared identity by alias")
	source.world = before.world
	t.check(sim._streamed.matches(source),"restoring original authority matches retained identity")
func _dirty_identity(t,setup: Dictionary) -> void:
	var props: Dictionary = setup.sim._streamed.props_query(Rect2(0,0,768,768))
	var changes := []
	for prop in props.props:
		if prop.destructible:
			changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
			if changes.size() == 2: break
	t.check(changes.size() == 2,"identity fixture uses two real destructible slots")
	if changes.size() != 2: return
	changes.sort_custom(func(a,b): return a.slot_id < b.slot_id)
	var state: Dictionary = setup.state.duplicate(true)
	state.world.world_revision = 1
	state.world.dirty_chunks = [{"chunk":["0","0"],"props":changes}]
	var sim := Core.new(City.new())
	var numeric := state.duplicate(true)
	numeric.world = JSON.parse_string(JSON.stringify(numeric.world,"",true,true))
	t.check(sim.prepare_world(numeric,setup.hydration).get("ok",false),"JSON dirty HP/revision authority prepares")
	t.check(sim._streamed.matches(numeric) and sim._streamed.matches(state),"nested numeric dirty records share exact semantic identity")
	var reordered := state.duplicate(true)
	reordered.world.dirty_chunks[0].props.reverse()
	t.check(not sim._streamed.matches(reordered),"array order remains part of prepared identity")
	var changed := state.duplicate(true)
	changed.world.dirty_chunks[0].props[0].destroyed = false
	t.check(not sim._streamed.matches(changed),"nested world property change invalidates identity")
	var before := numeric.duplicate(true)
	F.step(sim,numeric,Vector2.RIGHT)
	t.check(numeric.active_tick == before.active_tick+1 and sim.restore(numeric,setup.hydration).get("ok",false),"prepared numeric dirty geometry supports actual restorable tick")
func _dock_identity(t,setup: Dictionary) -> void:
	var state: Dictionary = setup.state.duplicate(true)
	var sim := Core.new(City.new())
	state.active_tick = 107999; state.survival_tick = 107999
	t.check(sim.prepare_world(state,setup.hydration).ok,"dock identity starts from valid city")
	F.step(sim,state,Vector2.ZERO,[{"command_id":"numeric-final","kind":"begin_evacuation","origin_revision":0,"payload":{"boss_id":"ch01_final_armored","escape_zone":[0,0,0,0],"evacuation_ticks":4500}}])
	var passage: Dictionary = sim._streamed.passage_proposal(state)
	t.check(passage.get("ok",false),"dock identity selects actual passage")
	if not passage.get("ok",false): return
	state.world = passage.world
	var transition: Dictionary = sim._streamed.dock_transition_proposal(state,{"command_id":"numeric-dock","kind":"dock_transition","origin_revision":0,"payload":{"passage_id":state.world.evacuation.passage_id}},setup.chapter.authored_dock)
	t.check(transition.get("ok",false),"dock identity uses actual contact transition")
	if not transition.get("ok",false): return
	state.world = transition.candidate_world
	state.player.position = [transition.player_position.x,transition.player_position.y]
	state.escape_zone = setup.chapter.authored_dock.escape_rect.duplicate()
	state.world = JSON.parse_string(JSON.stringify(state.world,"",true,true))
	var before := state.duplicate(true)
	t.check(sim.prepare_world(state,{}).get("ok",false) and state == before,"JSON dock preparation accepts nested ticks/escape without caller mutation")
	t.check(sim._streamed.readiness(state).ok,"prepared JSON dock identity is immediately ready")
	F.step(sim,state,Vector2.RIGHT)
	t.check(state.active_tick == 108001 and sim.restore(state).get("ok",false),"actual numeric dock authority advances and restores")
