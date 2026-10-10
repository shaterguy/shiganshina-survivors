extends RefCounted
const Sim = preload("res://game/core/run_simulation.gd")
const Chapter = preload("res://game/director/chapter_catalog.gd")
const Director = preload("res://game/director/spawn_director.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var sim = Sim.new()
	var chapter: Dictionary = Chapter.new().load_chapter("chapter_01_shiganshina").chapter
	chapter.initial_equipment = {}
	var director = Director.new()
	var planned: Dictionary = sim.new_run(chapter,42)
	planned.active_tick = 17999
	planned.survival_tick = 17999
	sim.step(planned,Vector2.ZERO,director.plan(planned,chapter))
	t.check(planned.entities[0].id is int,"actual director creates integer actor IDs")
	_check_roundtrip(t,sim,planned,"actual director boss/wave commands")
	for enemy_id in ["walker","runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]:
		var local := chapter.duplicate(true)
		local.spawn_position = [632,408] if enemy_id == "boss_leaper" else [490,46]
		var state: Dictionary = sim.new_run(local,42)
		state.player.hp = 10000.0
		state.player.max_hp = 10000.0
		var commands: Array[Dictionary] = [{"command_id":"numeric_actor","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":enemy_id,"position":[330,46],"spawned_tick":0}}]
		sim.step(state,Vector2.ZERO,commands)
		var phases: Dictionary = {}
		for tick in 900:
			var key: String = state.entities[0].action_state
			if not phases.has(key):
				phases[key] = true
				_check_roundtrip(t,sim,state,enemy_id+":"+key)
			Fixture.step(sim,state,Vector2.ZERO,[])
		if enemy_id != "walker": t.check(phases.has("windup") and phases.has("attack") and phases.has("recover"),"numeric real-data actor samples every action phase: "+enemy_id)
	_test_fractional_rejection(t,sim,chapter)
	_test_actual_store(t,sim,chapter)
func _check_roundtrip(t,sim,state: Dictionary,label: String) -> void:
	var runtime_before := state.duplicate(true)
	var runtime: Dictionary = sim.restore(sim.snapshot(state))
	t.check(runtime.ok and runtime.state == state and state == runtime_before,"raw generated snapshot restores unchanged: "+label)
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
	var unchanged := encoded.duplicate(true)
	var result: Dictionary = sim.restore(encoded)
	t.check(result.ok,"JSON numeric-ID checkpoint accepted: "+label)
	t.check(encoded == unchanged,"successful restore leaves supplied JSON unchanged: "+label)
	if not result.ok: return
	t.check(result.state == state,"numeric-ID generated snapshot exact equality: "+label)
	var expected := state.duplicate(true)
	for tick in 12:
		Fixture.step(sim,expected,Vector2.ZERO,[])
		Fixture.step(sim,result.state,Vector2.ZERO,[])
		t.check(result.state == expected,"numeric-ID restored full-state replay: "+label)
func _test_fractional_rejection(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42)
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"numeric_actor","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":"walker","position":[150,0],"spawned_tick":0}}])
	for field in ["id","entity_id","spawned_tick","action_started_tick","next_action_tick","pattern_index"]:
		var corrupt: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
		corrupt.entities[0][field] += 0.5
		var unchanged := corrupt.duplicate(true)
		t.check(not sim.restore(corrupt).ok and corrupt == unchanged,"fractional integer actor field is rejected without mutation: "+field)
	for field in ["active_tick","survival_tick","next_entity_id","event_seq","seed"]:
		var corrupt: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
		corrupt[field] += 0.5
		var unchanged := corrupt.duplicate(true)
		t.check(not sim.restore(corrupt).ok and corrupt == unchanged,"fractional integer root field is rejected without mutation: "+field)
	for bad in [1e30,9223372036854775808.0]:
		var corrupt := state.duplicate(true)
		corrupt.entities[0].entity_id = bad
		var unchanged := corrupt.duplicate(true)
		t.check(not sim.restore(corrupt).ok and corrupt == unchanged,"integer conversion overflow is rejected without mutation")

func _test_actual_store(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42)
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"numeric_actor","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":"runner","position":[160,0],"spawned_tick":0}}])
	t.check(state.entities[0].action_state == "windup" and state.entities[0].id is int,"numeric SaveStore regression starts with actual windup")
	var store = load("res://game/persistence/save_store.gd").new("user://test_numeric_behavior_"+str(OS.get_process_id()))
	var unchanged := state.duplicate(true)
	var saved: Dictionary = store.save_checkpoint(sim.snapshot(state))
	t.check(saved.ok and state == unchanged,"SaveStore saves generated numeric-ID windup without mutation")
	if not saved.ok: return
	var loaded: Dictionary = store.load_checkpoint()
	t.check(loaded.ok and loaded.snapshot == state,"SaveStore full-precision numeric behavior load is exactly equal")
	if not loaded.ok: return
	for tick in 180:
		Fixture.step(sim,state,Vector2.ZERO,[])
		Fixture.step(sim,loaded.snapshot,Vector2.ZERO,[])
		t.check(loaded.snapshot == state,"SaveStore checkpoint exactly replays windup, charge, recovery")
