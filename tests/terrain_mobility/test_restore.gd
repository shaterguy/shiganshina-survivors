extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
func run(t) -> void:
	if not F.available(t): return
	var m = load(F.PATH)
	for phase in ["ground","boost"]:
		var s: Dictionary = F.make(t)
		t.check(F.reach(s,phase),"full Core reaches save phase "+phase)
		if s.state.get("player_mobility",{}).get("phase") != phase: continue
		var raw: Dictionary = s.core.snapshot(s.state)
		var wire: Dictionary = JSON.parse_string(JSON.stringify(raw))
		for saved in [raw,wire]:
			var restored: Dictionary = s.core.restore(saved,s.hydration)
			t.check(restored.get("ok",false),"raw/JSON boost save validates without forced cancellation: "+phase)
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
		t.check(sample.has_all(["height","anchors","ground_position","phase"]) and sample.ground_position == raw.player.position and sample.height == 0.0,"visual contract exposes actual plane position and zero authority height")
		for field in ["cast_id","phase","progress","direction","path","anchors","landing","hit_ids","cooldown_until","cancelled"]:
			var malformed: Dictionary = raw.duplicate(true)
			malformed.player_mobility.erase(field)
			t.check(not s.core.restore(malformed,s.hydration).get("ok",false),"strict save rejects missing mobility "+field)
	var old: Dictionary = F.make(t)
	old.state.erase("player_mobility")
	var old_restore: Dictionary = old.core.restore(old.state,old.hydration)
	t.check(old_restore.get("ok",false) and not old_restore.get("state",{}).has("player_mobility"),"optional old snapshot is never rewritten during restore")
	var released: Dictionary = F.make(t)
	t.check(F.reach(released,"boost"),"released-input restore begins in a real paired corridor")
	var before: Dictionary = released.state.duplicate(true)
	released.core.set_pause(released.state,"user",true)
	var paused: Dictionary = released.state.duplicate(true)
	t.check(F.step(released,Vector2.ZERO).is_empty() and F.same(paused,released.state),"pause freezes all mobility authority")
	released.core.set_pause(released.state,"user",false)
	F.step(released,Vector2.ZERO)
	t.check(released.state.player_mobility.phase == "ground","first active zero-input tick cancels continued attack")
	var distance := 0.0
	for tick in 40:
		var previous: Vector2 = F.vec(released.state.player.position)
		F.step(released,Vector2.ZERO)
		distance += previous.distance_to(F.vec(released.state.player.position))
	t.check(released.state.player_mobility.phase == "ground" and distance == 0.0,"released boost stops on the first active zero-input tick")
	t.check(released.core._streamed.walkable(F.vec(released.state.player.position),8).get("walkable",false),"cancelled boost remains outside every solid")
	t.check(before.player.position == released.state.player.position,"release preserves exact saved ground position without forced movement")

	var malformed_source: Dictionary = F.make(t)
	t.check(F.reach(malformed_source,"boost"),"malformed semantic cases use a genuine boost state")
	for mutation in ["nan_progress","negative_cooldown","duplicate_hits","direction","far_path","position","phase","anchor_revision","travel_ticks","roll"]:
		var invalid: Dictionary = malformed_source.state.duplicate(true)
		match mutation:
			"nan_progress": invalid.player_mobility.progress = NAN
			"negative_cooldown": invalid.player_mobility.cooldown_until = -1
			"duplicate_hits": invalid.player_mobility.hit_ids = ["same","same"]
			"direction": invalid.player_mobility.direction = [0,0]
			"far_path": invalid.player_mobility.path[1].chunk = ["9007199254740993","0"]
			"position": invalid.player.position[0] += 4.0
			"phase": invalid.player_mobility.phase = "ground"
			"anchor_revision": invalid.player_mobility.anchors[0].geometry_revision = "f".repeat(64)
			"travel_ticks": invalid.player_mobility.travel_ticks += 1
			"roll": invalid.player_mobility.roll += 1
		t.check(not malformed_source.core.restore(invalid,malformed_source.hydration).get("ok",false),"strict semantic validation rejects "+mutation)

	var approach: Dictionary = F.make(t)
	F.step(approach)
	var stopped: Array = approach.state.player.position.duplicate()
	for tick in 6:
		F.step(approach,Vector2.ZERO)
		t.check(approach.state.player.position == stopped,"zero-input release holds its exact legal ground point")
	t.check(approach.state.player_mobility.phase == "ground","cancelled boost stays grounded across subsequent zero-input ticks")
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
	for direction in [Vector2(0.2,-1.0).normalized(),Vector2(-0.2,-1.0).normalized()]:
		var angled: Dictionary = load("res://tests/corridor_mobility/corridor_fixture.gd").make(t,[F.AF.slot("left","house_narrow",[100,224]),F.AF.slot("right","house_narrow",[260,224])],[160.0,256.0])
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
	t.check(F.reach(visual_cancel,"boost"),"cancelled visual fixture enters exact paired boost")
	F.step(visual_cancel,Vector2.ZERO)
	var visual: Dictionary = m.visual_sample(visual_cancel.state)
	t.check(visual.phase == "ground" and visual.anchors.is_empty() and visual.height == 0.0 and visual.get("roof_prop_id","") == "","release detaches both wires and never applies a roof depth override")
	var ground_visual: Dictionary = m.visual_sample(F.make(t).state)
	t.check(ground_visual.has("roof_prop_id") and ground_visual.roof_prop_id == "","ground sample carries no roof depth override")
	_legacy_admission(t)

func _legacy_admission(t) -> void:
	for phase in ["ground","glide","rise","over","land"]:
		var s := F.AF.legacy(phase)
		var core := F.Core.new(F.Provider.new())
		var raw: Dictionary = s.state.duplicate(true)
		var restored: Dictionary = core.restore(raw,s.hydration)
		t.check(restored.get("ok",false),"captured valid v1 phase remains admitted: "+phase)
		if not restored.get("ok",false): continue
		t.check(restored.state.player_mobility.schema_version == 2 and restored.state.player_mobility.phase == "ground","admitted v1 phase migrates to ground-only v2: "+phase)
		t.check(s.helper.walkable(F.vec(restored.state.player.position),8).get("walkable",false),"v1 migration selects a real walkable ground point: "+phase)
		for field in ["cast_id","phase","progress","direction","path","anchor","landing","hit_ids","cooldown_until","cancelled"]:
			var malformed: Dictionary = raw.duplicate(true)
			malformed.player_mobility.erase(field)
			t.check(not core.restore(malformed,s.hydration).get("ok",false),"v1 admission still rejects missing field "+field+": "+phase)
		if phase == "ground": continue
		for mutation in ["nan_progress","negative_cooldown","duplicate_hits","direction","far_path","position","phase","anchor_revision","travel_ticks","roll"]:
			var invalid: Dictionary = raw.duplicate(true)
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
			t.check(not core.restore(invalid,s.hydration).get("ok",false),"v1 migration never repairs semantic corruption "+mutation+": "+phase)
