extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
const Behavior = preload("res://tests/core/behavior_fixture.gd")
const ACTIONS := ["move","windup","attack","recover","airborne"]
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_five_ordinary_profiles(t,sim)
	test_scripted_warning_before_hit(t,sim)
	test_locked_physical_dash(t,sim)
	test_leap_target_airborne_immunity(t,sim)
	test_combo_and_recovery(t,sim)
	test_behavior_restore_and_corruption(t,sim)
	test_source_death_and_warning_consistency(t,sim)
	test_restore_movement_and_hazard_ownership(t,sim)
func test_five_ordinary_profiles(t,sim) -> void:
	var hazard_shapes: Dictionary = {}
	for enemy_id in ["walker","runner","brute","sweeper","grabber"]:
		var state: Dictionary = Behavior.run_with_enemy(sim,enemy_id,[-350.0,0.0])
		var seen: Array = []
		for tick in 1000:
			var actor: Dictionary = state.entities[0]
			var action: String = actor.get("action_state","")
			if not action in seen: seen.append(action)
			for hazard in state.telegraphs:
				hazard_shapes[enemy_id] = hazard.shape
				t.check(hazard.warning_ticks >= 45 and hazard.source_id == "actor","scripted danger has >=45 tick warning and stable source")
				if enemy_id == "sweeper": t.check(hazard.arc_degrees == 90.0,"ordinary sweep is a readable 90 degree sector")
			Fixture.step(sim,state,Vector2.ZERO,[])
		if enemy_id == "walker":
			t.check(seen == ["move"] and not hazard_shapes.has(enemy_id),"walker is steady chase/contact without scripted attack")
		else:
			t.check("windup" in seen and "attack" in seen and "recover" in seen,"actual ordinary action cycle: "+enemy_id)
	t.check(hazard_shapes.get("runner","") == "line" and hazard_shapes.get("brute","") == "circle" and hazard_shapes.get("sweeper","") == "sector" and hazard_shapes.get("grabber","") == "line","five ordinary profiles dispatch distinct rush/slam/sweep/grab geometry")
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	for enemy_id in Behavior.IDS: t.check(definitions.has(enemy_id),"real data ID matches behavior dispatch: "+enemy_id)
func test_scripted_warning_before_hit(t,sim) -> void:
	for enemy_id in ["runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_grabber"]:
		var state: Dictionary = Behavior.run_with_enemy(sim,enemy_id,[-70.0,0.0])
		var warned := Behavior.until_action(sim,state,"windup")
		t.check(warned,"scripted enemy reaches windup: "+enemy_id)
		if not warned or state.telegraphs.is_empty(): continue
		var hazard: Dictionary = state.telegraphs[-1]
		state.player.position = [0.0,0.0]
		var hp: float = state.player.hp
		var actor_start: Array = state.entities[0].position.duplicate()
		while state.active_tick < hazard.active_from_tick-1:
			Fixture.step(sim,state,Vector2.ZERO,[])
		t.check(state.player.hp == hp and state.entities[0].position == actor_start,"windup is stationary and does not hit before warning: "+enemy_id)
		Fixture.step(sim,state,Vector2.ZERO,[])
		t.check(state.player.hp < hp and state.entities[0].action_state == "attack","exact active tick applies readable attack: "+enemy_id)
func test_locked_physical_dash(t,sim) -> void:
	for enemy_id in ["runner","grabber","boss_charger","boss_grabber"]:
		var state: Dictionary = Behavior.run_with_enemy(sim,enemy_id,[-160.0,0.0])
		var warned := Behavior.until_action(sim,state,"windup")
		t.check(warned,"dash/lurch windup exists: "+enemy_id)
		if not warned: continue
		var actor: Dictionary = state.entities[0]
		var direction: Array = actor.locked_direction.duplicate()
		state.player.position = [0.0,180.0]
		if not Behavior.until_action(sim,state,"attack"): t.check(false,"physical attack begins"); continue
		var position: Vector2 = Behavior.vec(actor.position)
		Fixture.step(sim,state,Vector2.ZERO,[])
		var moved := Behavior.vec(actor.position)-position
		t.check(moved.length() > actor.speed/60.0 and absf(moved.normalized().dot(Behavior.vec(direction))-1.0)<0.0001,"physical rush/lurch follows locked direction faster than chase: "+enemy_id)
		var recovered := Behavior.until_action(sim,state,"recover")
		t.check(recovered,"physical action has recovery: "+enemy_id)
		if recovered:
			var stopped: Array = actor.position.duplicate()
			Fixture.step(sim,state,Vector2.ZERO,[])
			t.check(actor.position == stopped,"recovery is stationary: "+enemy_id)
func test_leap_target_airborne_immunity(t,sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"boss_leaper",[-160.0,0.0])
	var warned := Behavior.until_action(sim,state,"windup")
	t.check(warned,"leaper locks landing during windup")
	if not warned: return
	var actor: Dictionary = state.entities[0]
	var landing: Array = actor.locked_target.duplicate()
	state.player.position = [200.0,100.0]
	var airborne := Behavior.until_action(sim,state,"airborne")
	t.check(airborne,"leaper actually enters airborne movement")
	if not airborne: return
	var hp: float = state.player.hp
	for tick in 10:
		state.player.position = actor.position.duplicate()
		Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.player.hp == hp and actor.position != [-160.0,0.0],"airborne displaces physically with contact immunity")
	state.player.position = [500.0,500.0]
	var landed := Behavior.until_action(sim,state,"attack")
	t.check(landed and actor.position == landing,"leaper lands at fixed warned target despite player moving")
func test_combo_and_recovery(t,sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"boss_abnormal",[-160.0,0.0])
	var attack_kinds: Array = []
	var last_pattern := -1
	var recovery_seen := false
	for tick in 1200:
		var actor: Dictionary = state.entities[0]
		if actor.get("action_state","") == "windup" and actor.get("pattern_index",-1) != last_pattern:
			last_pattern = actor.pattern_index
			attack_kinds.append(actor.attack_kind)
		if actor.get("action_state","") == "recover":
			recovery_seen = true
			var damaging := false
			for hazard in state.telegraphs:
				if state.active_tick >= hazard.active_from_tick and state.active_tick < hazard.expires_tick: damaging = true
			t.check(not damaging,"combo recovery contains no active scripted danger")
		Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(attack_kinds.size() >= 2 and attack_kinds[0] == "charge" and attack_kinds[1] == "sweep" and recovery_seen,"abnormal deterministically alternates physical charge and sweep with recovery")
func test_behavior_restore_and_corruption(t,sim) -> void:
	for action in ["windup","airborne"]:
		var state: Dictionary = Behavior.run_with_enemy(sim,"boss_leaper",[-160.0,0.0])
		var reached := Behavior.until_action(sim,state,action)
		t.check(reached,"save fixture reaches "+action)
		if not reached: continue
		var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot(state)))
		var restored: Dictionary = sim.restore(saved)
		t.check(restored.ok and restored.state == state,"behavior clocks and locked vectors roundtrip at "+action)
		if not restored.ok: continue
		for tick in 140:
			Fixture.step(sim,state,Vector2.RIGHT,[])
			Fixture.step(sim,restored.state,Vector2.RIGHT,[])
		t.check(restored.state == state,"restored behavior replay deterministic at "+action)
		for key in ["action_state","action_started_tick","action_ends_tick","locked_direction","locked_target","pattern_index"]:
			var broken: Dictionary = saved.duplicate(true)
			broken.entities[0][key] = "bad" if key != "action_state" else "teleport"
			var before: Dictionary = broken.duplicate(true)
			t.check(not sim.restore(broken).ok and broken == before,"malformed behavior field rejected unchanged: "+key)
func test_source_death_and_warning_consistency(t,sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"brute",[-50.0,0.0])
	state.equipment = {"blade_slash":5}
	state.entities[0].hp = 1.0
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.entities.is_empty() and state.telegraphs.is_empty(),"dead scripted source cancels its pending danger")
	state = Behavior.run_with_enemy(sim,"boss_leaper",[-160.0,0.0])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
	for corruption in ["early_active","wrong_expiry","wrong_locked_target"]:
		var broken: Dictionary = saved.duplicate(true)
		match corruption:
			"early_active": broken.telegraphs[0].active_from_tick -= 1
			"wrong_expiry": broken.telegraphs[0].expires_tick += 1
			"wrong_locked_target": broken.entities[0].locked_target = [50.0,50.0]
		var before: Dictionary = broken.duplicate(true)
		t.check(not sim.restore(broken).ok and broken == before,"behavior danger and clock mismatch rejected unchanged: "+corruption)
	for enemy_id in ["runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]:
		for action in ["attack","recover"]:
			state = Behavior.run_with_enemy(sim,enemy_id,[-70.0,0.0])
			var reached := Behavior.until_action(sim,state,action)
			t.check(reached and sim.restore(JSON.parse_string(JSON.stringify(state))).ok,"legitimate behavior checkpoint accepted: "+enemy_id+" "+action)
func full_precision(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func test_restore_movement_and_hazard_ownership(t,sim) -> void:
	for case in [["boss_charger","windup"],["boss_charger","attack"],["boss_charger","recover"],["boss_leaper","airborne"],["boss_leaper","attack"],["boss_leaper","recover"],["brute","attack"]]:
		var state: Dictionary = Behavior.run_with_enemy(sim,case[0],[-160.123456789,-PI])
		var reached := Behavior.until_action(sim,state,case[1])
		t.check(reached,"movement integrity fixture reaches "+case[0]+" "+case[1])
		if not reached: continue
		for index in 3: Fixture.step(sim,state,Vector2.ZERO,[])
		var saved: Dictionary = full_precision(state)
		var restored: Dictionary = sim.restore(saved)
		t.check(restored.ok and restored.state == state,"fractional trajectory checkpoint accepted exactly: "+case[0]+" "+case[1])
		if restored.ok:
			var original: Dictionary = sim.snapshot(state)
			for index in 10:
				Fixture.step(sim,original,Vector2(0.6,0.8),[])
				Fixture.step(sim,restored.state,Vector2(0.6,0.8),[])
			t.check(original == restored.state,"fractional diagonal input replay exact: "+case[0]+" "+case[1])
		for corruption in ["position","velocity"]:
			var broken: Dictionary = saved.duplicate(true)
			broken.entities[0][corruption][1] += 200.0
			var before: Dictionary = broken.duplicate(true)
			t.check(not sim.restore(broken).ok and broken == before,"displaced action "+corruption+" rejected unchanged: "+case[0]+" "+case[1])
	for corruption in ["orphan","duplicate","legacy_source","inactive_source","dead_source","wrong_source","wrong_pattern"]:
		var state: Dictionary = Behavior.run_with_enemy(sim,"brute",[-50.0,0.0])
		var saved: Dictionary = full_precision(state)
		match corruption:
			"orphan": saved.entities.clear()
			"duplicate":
				var duplicate: Dictionary = saved.telegraphs[0].duplicate(true)
				duplicate.id = 999
				saved.telegraphs.append(duplicate)
			"legacy_source":
				for key in ["action_state","action_started_tick","action_ends_tick","next_action_tick","pattern_index","attack_kind","locked_origin","locked_direction","locked_target","facing"]: saved.entities[0].erase(key)
			"inactive_source": saved.entities[0].action_state = "move"
			"dead_source": saved.entities[0].hp = 0.0
			"wrong_source": saved.telegraphs[0].source_id = "missing"
			"wrong_pattern": saved.entities[0].pattern_index = 99
		var before: Dictionary = saved.duplicate(true)
		t.check(not sim.restore(saved).ok and saved == before,"invalid behavior hazard ownership rejected unchanged: "+corruption)
	var state: Dictionary = sim.new_run(Behavior.chapter(),1)
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.hazard("director_owned","circle",{"source_id":"armored","warning_ticks":95})])
	t.check(sim.restore(full_precision(state)).ok,"director-owned evacuation hazard requires no entity")
	state = Behavior.run_with_enemy(sim,"walker",[-70.0,0.0])
	for key in ["action_state","action_started_tick","action_ends_tick","next_action_tick","pattern_index","attack_kind","locked_origin","locked_direction","locked_target","facing"]: state.entities[0].erase(key)
	t.check(sim.restore(full_precision(state)).ok,"legacy action-less actor without behavior hazard remains compatible")
