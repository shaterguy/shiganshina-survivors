extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
func run(t) -> void:
	if not F.available(t): return
	var m = load(F.PATH)
	for phase in ["ground","glide","rise","over","land"]:
		var s: Dictionary = F.make(t)
		t.check(F.reach(s,phase),"full Core reaches save phase "+phase)
		if s.state.get("player_mobility",{}).get("phase") != phase: continue
		var raw: Dictionary = s.core.snapshot(s.state)
		var wire: Dictionary = JSON.parse_string(JSON.stringify(raw))
		for saved in [raw,wire]:
			var restored: Dictionary = s.core.restore(saved,s.hydration)
			t.check(restored.get("ok",false),"raw/JSON airborne save validates without forced landing: "+phase)
			if not restored.get("ok",false): continue
			t.check(F.same(raw,restored.state),"restore preserves precise mobility progress/position: "+phase)
			var cold = F.Core.new(s.provider)
			t.check(cold.prepare_world(restored.state,s.hydration).get("ok",false),"cold geometry admits same saved phase: "+phase)
			var warm_state: Dictionary = raw.duplicate(true)
			var cold_state: Dictionary = restored.state
			for tick in 4:
				var left: Array[Dictionary] = F.F.step(s.core,warm_state,Vector2.UP)
				var right: Array[Dictionary] = F.F.step(cold,cold_state,Vector2.UP)
				t.check(F.same(left,right) and F.same(warm_state,cold_state),"warm/cold same-input replay exact: "+phase)
		var sample: Dictionary = m.visual_sample(raw)
		t.check(sample.has_all(["height","anchor","ground_position","phase"]) and sample.ground_position == raw.player.position,"visual contract exposes actual plane position and authority height")
		for field in ["cast_id","phase","progress","direction","path","anchor","landing","hit_ids","cooldown_until","cancelled"]:
			var malformed: Dictionary = raw.duplicate(true)
			malformed.player_mobility.erase(field)
			t.check(not s.core.restore(malformed,s.hydration).get("ok",false),"strict save rejects missing mobility "+field)
	var old: Dictionary = F.make(t)
	old.state.erase("player_mobility")
	var old_restore: Dictionary = old.core.restore(old.state,old.hydration)
	t.check(old_restore.get("ok",false) and not old_restore.get("state",{}).has("player_mobility"),"optional old snapshot is never rewritten during restore")
	var released: Dictionary = F.make(t)
	t.check(F.reach(released,"over"),"released-input restore begins above actual roof")
	var before: Dictionary = released.state.duplicate(true)
	released.core.set_pause(released.state,"user",true)
	var paused: Dictionary = released.state.duplicate(true)
	t.check(F.step(released,Vector2.ZERO).is_empty() and F.same(paused,released.state),"pause freezes all mobility authority")
	released.core.set_pause(released.state,"user",false)
	F.step(released,Vector2.ZERO)
	t.check(released.state.player_mobility.cancelled,"first active zero-input tick cancels continued attack")
	var distance := 0.0
	for tick in 40:
		var previous: Vector2 = F.vec(released.state.player.position)
		F.step(released,Vector2.ZERO)
		distance += previous.distance_to(F.vec(released.state.player.position))
	t.check(released.state.player_mobility.phase == "ground" and distance <= 320.0,"released rooftop save lands within bounded forward cancellation")
	t.check(released.core._streamed.walkable(F.vec(released.state.player.position),8).get("walkable",false),"cancelled roof restore never grounds inside a solid")
	t.check(before.player.position != released.state.player.position,"resume keeps original save then completes real forward landing")

	var malformed_source: Dictionary = F.make(t)
	t.check(F.reach(malformed_source,"over"),"malformed semantic cases use a genuine over state")
	for mutation in ["nan_progress","negative_cooldown","duplicate_hits","direction","far_path","position","phase","anchor_revision","travel_ticks","roll"]:
		var invalid: Dictionary = malformed_source.state.duplicate(true)
		match mutation:
			"nan_progress": invalid.player_mobility.progress = NAN
			"negative_cooldown": invalid.player_mobility.cooldown_until = -1
			"duplicate_hits": invalid.player_mobility.hit_ids = ["same","same"]
			"direction": invalid.player_mobility.direction = [0,0]
			"far_path": invalid.player_mobility.path[2].chunk = ["9007199254740993","0"]
			"position": invalid.player.position[0] += 4.0
			"phase": invalid.player_mobility.phase = "ground"
			"anchor_revision": invalid.player_mobility.anchor.geometry_revision = "f".repeat(64)
			"travel_ticks": invalid.player_mobility.travel_ticks += 1
			"roll": invalid.player_mobility.roll += 1
		t.check(not malformed_source.core.restore(invalid,malformed_source.hydration).get("ok",false),"strict semantic validation rejects "+mutation)

	var approach: Dictionary = F.make(t)
	F.step(approach)
	var stopped: Array = approach.state.player.position.duplicate()
	for tick in 6:
		F.step(approach,Vector2.ZERO)
		t.check(approach.state.player.position == stopped,"pre-roof release holds legal planar point during bounded descent")
	t.check(approach.state.player_mobility.phase == "ground","pre-roof cancel descends in six ticks")
	F.step(approach,Vector2.DOWN)
	t.check(approach.state.player.position[1] > stopped[1],"finished cancellation applies current reversed input on next tick")
	for clock in [0,1,2,17,59,60,617,17998,17999]:
		var entropy_case: Dictionary = F.make(t,"dev5",clock)
		F.step(entropy_case)
		t.check(entropy_case.state.player_mobility.cast_id == 1,"real eligible first cast uses independent seed/tick vector at "+str(clock))
		var json_packet: Dictionary = JSON.parse_string(JSON.stringify(entropy_case.core.snapshot(entropy_case.state)))
		var json_restore: Dictionary = entropy_case.core.restore(json_packet,entropy_case.hydration)
		t.check(json_restore.get("ok",false),"probability-domain save survives real JSON parser at clock "+str(clock))
		if json_restore.get("ok",false): t.check(F.same(json_restore.state,entropy_case.state),"probability result and all authority remain exact after JSON at clock "+str(clock))
	for direction in [Vector2(0.2,-1.0).normalized(),Vector2(-0.37,-1.0).normalized()]:
		var angled: Dictionary = F.make(t)
		F.step(angled,direction)
		t.check(angled.state.player_mobility.cast_id == 1,"real diagonal joystick starts legal fixed-direction route")
		var raw_angle: Dictionary = angled.core.snapshot(angled.state)
		var wire_angle: Dictionary = JSON.parse_string(JSON.stringify(raw_angle))
		var restored_angle: Dictionary = angled.core.restore(wire_angle,angled.hydration)
		t.check(restored_angle.get("ok",false),"diagonal mobility JSON validates physical saved path")
		if not restored_angle.get("ok",false): continue
		t.check(F.same(raw_angle,restored_angle.state),"diagonal direction and absolute path retain exact Vector2 authority after JSON")
		var cold_angle = F.Core.new(angled.provider)
		t.check(cold_angle.prepare_world(restored_angle.state,angled.hydration).get("ok",false),"cold diagonal geometry prepares without position correction")
		var warm_angle: Dictionary = raw_angle.duplicate(true)
		for tick in 4:
			var warm_events: Array[Dictionary] = F.F.step(angled.core,warm_angle,direction)
			var cold_events: Array[Dictionary] = F.F.step(cold_angle,restored_angle.state,direction)
			t.check(F.same(warm_events,cold_events) and F.same(warm_angle,restored_angle.state),"diagonal warm/cold future authority and events remain exact")
	var visual_cancel: Dictionary = F.make(t)
	t.check(F.reach(visual_cancel,"over"),"cancelled-over depth fixture enters exact roof")
	var expected_roof: String = visual_cancel.state.player_mobility.anchor.prop_id
	F.step(visual_cancel,Vector2.ZERO)
	var visual: Dictionary = m.visual_sample(visual_cancel.state)
	t.check(visual.phase == "over" and visual.anchor.is_empty() and visual.get("roof_prop_id","") == expected_roof,"cancelled over detaches wire but preserves exact derived target-roof depth")
	var ground_visual: Dictionary = m.visual_sample(F.make(t).state)
	t.check(ground_visual.has("roof_prop_id") and ground_visual.roof_prop_id == "","ground sample carries no roof depth override")
