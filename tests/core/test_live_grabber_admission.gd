extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
func run(t) -> void:
	_broadphase(t)
	var fixture := G.setup()
	var sim = fixture.sim
	var state: Dictionary = fixture.state
	F.step(sim,state,Vector2.ZERO,[G.spawn(7,[-170.0,0.0]),G.spawn(91,[170.0,0.0]),G.spawn(444,[0.0,170.0])])
	t.check(state.enemy_attack_instances.size() == 1,"one evaluation accepts at most one role per tick")
	if state.enemy_attack_instances.is_empty(): return
	t.check(state.enemy_attack_instances[0].source_id == "7","equal wait uses numeric source ordering")
	F.step(sim,state,Vector2.ZERO)
	t.check(state.enemy_attack_instances.size() == 2,"second eligible role can be admitted on following tick")
	F.step(sim,state,Vector2.ZERO)
	t.check(state.enemy_attack_instances.size() == 2,"early two-slot bound is not bypassed by wait")
	var waiting: Dictionary = state.entities[2]
	t.check(waiting.role_wait_since == 1 and waiting.role_retry_tick == 18,"denial preserves oldest wait and retries 15 active ticks later")
	var checked: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(checked.get("ok",false) and checked.get("state") == state,"retry and waiting state are durable")
	var accepted := 2
	var max_work := 0
	var max_wait := 0
	for tick in range(4,100):
		F.step(sim,state,Vector2.ZERO)
		var diagnostics: Dictionary = sim.step_status().get("role_admission",{})
		max_work = maxi(max_work,int(diagnostics.get("work_units",0)))
		if diagnostics.get("accepted",false):
			accepted += 1
			max_wait = maxi(max_wait,int(diagnostics.get("wait_ticks",0)))
		t.check(int(diagnostics.get("evaluations",0)) <= 1 and int(diagnostics.get("work_units",0)) <= 8192,"bounded one-eval logical cost")
	t.check(accepted >= 3 and max_work > 0,"capacity recovery eventually admits high source ID with measured nonzero work")
	print("GRABBER_ADMISSION accepted=%d max_work=%d max_wait=%d" % [accepted,max_work,max_wait])
	fixture = G.setup(); sim = fixture.sim; state = fixture.state
	state.active_tick = 10800; state.survival_tick = 10800
	F.step(sim,state,Vector2.ZERO,[G.spawn(77,[170.0,0.0]),G.spawn(88,[-170.0,0.0],"runner")])
	t.check(state.enemy_attack_instances.size() == 1 and not state.telegraphs.is_empty(),"late cost1 grabber coexists with actually started cost2 legacy attack")
	var d: Dictionary = sim.step_status().get("role_admission",{})
	t.check(d.get("strong_slots_used",0) == 3 and d.get("observation_counts",{}).get("reservation_count",0) == 1,"current legacy pass reservation counted once per source")
func _broadphase(t) -> void:
	var Fixture = load("res://tests/core/new_current_regression_fixture.gd")
	var results := []
	for distant_count in [0,178]:
		var chapter: Dictionary = Fixture.geometry_chapter({"bounds":[-2048,-2048,4096,4096],"obstacles":[]},[0.0,0.0])
		var sim = Fixture.geometry_sim(chapter)
		var state: Dictionary = sim.new_run(chapter,42,F.run_config())
		state.active_tick = 28800; state.survival_tick = 28800
		state.player.attack_ready_ticks = {"blade_slash":2147483647}
		var commands := []
		for index in distant_count: commands.append(G.spawn(index+1,[900.0+index,900.0],"walker"))
		commands.append(G.spawn(179,[170.0,0.0]))
		commands.append(G.spawn(180,[-170.0,0.0],"runner"))
		F.step(sim,state,Vector2.ZERO,commands)
		var d: Dictionary = sim.step_status().get("role_admission",{})
		t.check(state.entities.size() == distant_count+2 and state.enemy_attack_instances.size() == 1,"actual Core mixed admission with distant bodies "+str(distant_count))
		t.check(d.get("observation_counts",{}).get("hash_candidates",-1) == 0 and d.get("observation_counts",{}).get("body_exact_tests",-1) == 0,"far body population is not repeated in reaction prefix or path search")
		results.append(d)
	t.check(results[0].accepted == results[1].accepted and results[0].paths_tested == results[1].paths_tested and results[1].work_units-results[0].work_units == 178,"full owner collection work is charged without changing nearby threat decision")
	print("GRABBER_CORE_BROADPHASE ",JSON.stringify(results))
