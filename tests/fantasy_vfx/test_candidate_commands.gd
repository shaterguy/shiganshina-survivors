extends RefCounted
const QA = preload("res://tests/fantasy_vfx/candidate_command_qa.gd")
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Actual = preload("res://tests/fantasy_vfx/test_actual_fantasy_vfx.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
func run(t) -> void:
	var qa := QA.new()
	t.check(qa.problems.is_empty(),"isolated candidate QA validates actual unapproved raster SHA/dimensions/metadata: "+str(qa.problems))
	if not qa.problems.is_empty(): return
	var before := qa.metadata.duplicate(true)
	for pair in [["chain_lightning",""],["chain_lightning","evo_storm_chain"],["fire_zone",""],["fire_zone","evo_inferno_zone"]]: _cast_commands(t,qa,pair[0],pair[1])
	t.check(qa.metadata == before and qa.metadata.values().all(func(a): return a.vfx_approved == false),"candidate command QA never changes approval flags")
func _cast_commands(t,qa,base: String,evolution: String) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {base:1}
	if evolution != "":
		state = Actual.new()._earned_empty(t,sim,evolution)
		if state.is_empty(): return
	var spawned := []
	for i in (12 if base == "chain_lightning" else 1): spawned.append(F.spawn("draw-"+str(i),[80+i*40,0],"brute"))
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,spawned)
	var snapshot: Dictionary = sim.snapshot(state)
	state.player.attack_ready_ticks[base] = 999999
	var director := Director.new()
	director.consume(events,snapshot)
	var effects := director.present(snapshot)
	var commands: Array[Dictionary] = qa.commands(effects,snapshot)
	t.check(not commands.is_empty(),"actual Core event/snapshot produces isolated raster commands "+base+evolution)
	var actual := events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == base and e.payload.phase == "executed")
	for event in actual:
		var matches := commands.filter(func(c): return c.attack_id == event.payload.attack_id)
		t.check(matches.size() == 1,"one actual stage becomes one isolated main raster command")
		if matches.is_empty(): continue
		var command: Dictionary = matches[0]
		t.check(command.world_anchor == Vector2(event.payload.origin[0],event.payload.origin[1]) and command.contact_geometry == event.payload.geometry,"raster anchors and contact geometry are the exact executed segment/disk")
		t.check(command.atlas_region.position == Vector2.ZERO and command.alpha == 1.0,"contact starts at authored frame zero on actual execute tick")
		t.check(command.cast_id == event.payload.cast_id and command.evolution_id == evolution,"command identity retains actual cast and evolution")
		if base == "chain_lightning":
			t.check(command.contact_size == Vector2(event.payload.length,event.payload.width),"chain uses executed link length and eight-pixel width")
			var bound: Array = qa.metadata[command.asset_id].vfx_bounds_px
			var anchor: Array = qa.metadata[command.asset_id].anchor_px
			t.check(bound[0] == anchor[0] and bound[1]+bound[3]/2.0 == anchor[1],"authored trimmed bounds map chain start and centerline to actual origin")
	# Production Renderer and Bridge remain closed even though isolated commands exist.
	var renderer := Renderer.new()
	var denied: Array[Dictionary] = renderer.commands(effects,{"tick":snapshot.active_tick,"origin_revision":0,"asset_metadata":qa.metadata})
	t.check(denied.all(func(c): return c.has("diagnostic")) and denied.any(func(c): return c.get("diagnostic") == "unapproved_art"),"production renderer does not draw unapproved fantasy art")
	var bridge := Bridge.new(qa.metadata)
	t.check(bridge.consume(events,snapshot),"production bridge validates real successful tick even while art is gated")
	t.check(bridge.present(snapshot).all(func(c): return c.has("diagnostic")),"production bridge cannot bypass unapproved raster gate")
	var reduced: Array[Dictionary] = qa.commands(effects,snapshot,true)
	t.check(reduced.size() == commands.size(),"reduced mode preserves bounded main fantasy forms")
	if base != "fire_zone": return
	var start := int(snapshot.active_tick)
	var last := int(state.player_attack_instances[-1].execute_tick)
	var area := commands.filter(func(c): return c.role == "area")
	t.check(area.size() == 1 and is_equal_approx(area[0].alpha,0.55) and area[0].render_pass == "ground","persistent floor remains subdued behind actual contact pulse")
	var first_frame: Rect2 = area[0].atlas_region if not area.is_empty() else Rect2()
	while state.active_tick < last:
		events = F.step(sim,state,Vector2.ZERO)
		snapshot = sim.snapshot(state)
		director.consume(events,snapshot)
		commands = qa.commands(director.present(snapshot),snapshot)
		if state.active_tick == start+11:
			area = commands.filter(func(c): return c.role == "area")
			t.check(area.size() == 1 and area[0].atlas_region != first_frame and is_equal_approx(area[0].alpha,0.55),"floor animates across the quiet gap without lifetime fading")
			t.check(qa.commands(director.present(snapshot),snapshot) == commands,"active-clock pause freezes isolated raster phase")
		if state.active_tick == last:
			t.check(not commands.any(func(c): return c.role == "area"),"last stage retires persistent raster floor")
			if evolution == "evo_inferno_zone":
				var final := commands.filter(func(c): return c.role == "impact")
				t.check(final.size() == 1 and final[0].asset_id == "vfx_crossfire_contact_blast" and final[0].contact_size.x > 200 and final[0].atlas_region.position == Vector2.ZERO,"ultimate final eruption uses real larger disk and new contact frame, distinct from prior floor")
