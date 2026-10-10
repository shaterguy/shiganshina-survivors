extends RefCounted
const Fixture := preload("res://tests/enemy_roles/role_fixture.gd")
const Model := preload("res://game/combat/enemy_attack_model.gd")
const Catalog := preload("res://game/combat/enemy_role_catalog.gd")
const World := preload("res://game/combat/world_geometry.gd")
const Geometry := preload("res://game/combat/attack_geometry.gd")
func run(t) -> void:
	var path := "res://game/combat/enemy_threat_budget.gd"
	t.check(FileAccess.file_exists(path),"pure threat budget exists")
	if not FileAccess.file_exists(path): return
	var budget = load(path)
	t.check(budget != null and budget.can_instantiate(),"threat budget compiles")
	if budget == null or not budget.can_instantiate(): return
	var catalog := Fixture.read_catalog(t)
	if catalog.is_empty(): return
	test_budget_two_then_three(t,budget,catalog)
	test_legacy_boss_reservation(t,budget,catalog)
	test_135_speed_clears_slam_72_tick_warning(t,budget,catalog)
	test_no_exit_defers(t,budget,catalog)
	test_inputs_order_wait_and_work_budget(t,budget,catalog)
	test_reaction_and_horizon(t,budget,catalog)
	test_visibility_and_bad_projection_types(t,budget,catalog)
	test_wall_adjacent_player_keeps_real_escape(t,budget,catalog)
	test_identical_path_prefixes_share_queries(t,budget,catalog)
	test_legacy_fixed_damage_ignores_new_visibility(t,budget,catalog)
func _context(speed: float = 135.0) -> Dictionary:
	return {"tick":100,"survival_tick":0,"move_speed":speed,"player_radius":8.0,"reaction_ticks":21,"margin":8.0,"candidate_wait_since":80,"geometry_fully_loaded":true,"max_work_units":8192}
func _attack(catalog: Dictionary,role: String = "brute",source: int = 1,origin: Array = [0.0,0.0],target: Array = [0.0,0.0]) -> Dictionary:
	var actor := Fixture.actor(role,origin)
	actor.id = source
	return Model.begin(actor,Fixture.player(target),100,Catalog.profile(catalog,role),{},"run:enemy:%d:1" % source).attack
func _legacy(id: String = "boss:1", origin: Array = [1000.0,1000.0], from_tick: int = 172, ends: int = 184) -> Dictionary:
	return {"legacy_projection":true,"attack_id":id,"source_id":"boss1","active_from_tick":from_tick,"attack_ends_tick":ends,"threat_cost":2,"damage_geometry":[{"shape":"circle","origin":origin,"radius":96.0}]}
func test_budget_two_then_three(t,budget,catalog: Dictionary) -> void:
	var candidate := _attack(catalog)
	var active: Array[Dictionary] = [_attack(catalog,"runner",2,[1000,1000],[1096,1000]),_attack(catalog,"grabber",3,[1000,-1000],[1190,-1000])]
	var c := _context()
	c.survival_tick = 10799
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "budget_full","two strong slots before 180 seconds")
	c.survival_tick = 10800
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).accepted,"third slot opens at exactly 180 seconds")
	var walkers: Array[Dictionary] = [_attack(catalog,"walker",2,[1000,1000],[1000,1000]),_attack(catalog,"walker",3,[-1000,1000],[-1000,1000])]
	t.check(budget.evaluate(_attack(catalog,"walker"),walkers,Fixture.player(),{},c).reason == "budget_full","walker has separate two-attack proximity budget")
	active[0].started_tick = 0
	active[0].active_from_tick = 45
	active[0].attack_ends_tick = 87
	active[0].recover_ends_tick = 153
	c.survival_tick = 0
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).accepted,"recovery does not reserve strong budget")
func test_legacy_boss_reservation(t,budget,catalog: Dictionary) -> void:
	var c := _context()
	var active: Array[Dictionary] = [_legacy()]
	var candidate := _attack(catalog)
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "budget_full","legacy boss costs two slots")
	c.survival_tick = 10800
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).accepted,"known legacy adapter coexists with one normal at three slots")
	active = [_legacy("boss:instant",[0,0],100,101)]
	var result: Dictionary = budget.evaluate(candidate,active,Fixture.player(),{},c)
	t.check(not result.accepted and result.reason == "no_safe_path","legacy projection active shape is checked during reaction wait")
	active[0].legacy_projection = "unrecognized"
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "invalid_candidate","unknown projection format rejected")
	active = [_legacy()]
	active[0].damage_geometry[0].shape = "laser"
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "invalid_candidate","unknown legacy geometry rejected")
func test_135_speed_clears_slam_72_tick_warning(t,budget,catalog: Dictionary) -> void:
	var candidate := _attack(catalog)
	for speed in [135.0,150.0,225.0]:
		var c := _context(speed)
		var result: Dictionary = budget.evaluate(candidate,_empty(),Fixture.player([0.0,0.0],speed),{},c)
		t.check(result.accepted and not result.safe_path.is_empty(),"speed %s can clear warned radius with margin" % speed)
		if result.safe_path.is_empty(): continue
		var impact: Dictionary = result.safe_path[72]
		t.check(Vector2(impact.position[0],impact.position[1]).length() > 112.0,"player plus safety margin outside slam at impact")
		for point in result.safe_path:
			if point.tick <= 121: t.check(point.position == [0.0,0.0],"full 21-tick reaction interval is stationary")
		c.geometry_fully_loaded = false
		t.check(budget.evaluate(candidate,_empty(),Fixture.player(),{},c).reason == "world_unavailable","unloaded terrain is never empty terrain")
	# Off-axis obstacle requires a different stable direction, without corner cutting.
	var world := {"bounds":[-240,-320,480,640],"obstacles":[[25,-40,100,80],[-80,35,50,80]]}
	var result: Dictionary = budget.evaluate(candidate,_empty(),Fixture.player(),world,_context())
	t.check(result.accepted,"corner/diagonal case preserves a legal escape")
	if result.accepted:
		for point in result.safe_path: t.check(World.walkable(Vector2(point.position[0],point.position[1]),16,world),"safe path includes static clearance")
func test_no_exit_defers(t,budget,catalog: Dictionary) -> void:
	var world := {"bounds":[-32,-300,64,600],"obstacles":[]}
	var boss := _legacy("boss:corridor",[0,170],172,184)
	boss.damage_geometry.append({"shape":"circle","origin":[0,-170],"radius":96.0})
	var active: Array[Dictionary] = [boss]
	var c := _context()
	c.survival_tick = 10800
	c.max_work_units = 100000
	var control: Dictionary = budget.evaluate(_attack(catalog,"walker"),active,Fixture.player(),world,c)
	t.check(control.accepted and control.diagnostics.paths_tested > 16,"turning candidate escapes existing front/back reservation without extra slam")
	var result: Dictionary = budget.evaluate(_attack(catalog),active,Fixture.player(),world,c)
	t.check(not result.accepted and result.reason == "no_safe_path","new slam cannot remove final corridor escape")
	t.check(result.safe_path.is_empty() and result.diagnostics.paths_tested == 272,"full 16 plus 16x16 search exhausted distinctly from CPU budget")
func test_inputs_order_wait_and_work_budget(t,budget,catalog: Dictionary) -> void:
	var candidate := _attack(catalog)
	var active: Array[Dictionary] = [_attack(catalog,"runner",3,[1000,1000],[1096,1000]),_attack(catalog,"runner",2,[-1000,1000],[-904,1000])]
	var c := _context()
	c.survival_tick = 10800
	var player := Fixture.player()
	var before := [candidate.duplicate(true),active.duplicate(true),player.duplicate(true),c.duplicate(true)]
	var result: Dictionary = budget.evaluate(candidate,active,player,{},c)
	t.check([candidate,active,player,c] == before,"evaluate is input immutable")
	active.reverse()
	t.check(result == budget.evaluate(candidate,active,player,{},c),"input attack order cannot change decision, path or work count")
	t.check(result.diagnostics.role_id == "brute" and result.diagnostics.wait_ticks == 20 and result.diagnostics.candidate_wait_since == 80,"per-role wait diagnostics available to Core")
	t.check(result.diagnostics.work_units > 0 and result.diagnostics.paths_tested > 0,"measured path work reported")
	c.max_work_units = 1
	var exhausted: Dictionary = budget.evaluate(candidate,_empty(),player,{},c)
	t.check(not exhausted.accepted and exhausted.reason == "work_budget_exhausted" and exhausted.safe_path.is_empty(),"partial safety proof cannot be accepted")
	t.check(exhausted.diagnostics.work_units == 1 and exhausted.diagnostics.deferral_reason == "work_budget_exhausted","exact CPU work ceiling and deferral reason reported")
func test_reaction_and_horizon(t,budget,catalog: Dictionary) -> void:
	var c := _context()
	c.survival_tick = 10800
	var candidate := _attack(catalog)
	var active: Array[Dictionary] = [_legacy("boss:reaction",[0,0],110,111)]
	var result: Dictionary = budget.evaluate(candidate,active,Fixture.player(),{},c)
	t.check(result.reason == "no_safe_path","no path may teleport out during reaction delay")
	active = [_legacy("boss:future",[1000,0],280,282)]
	result = budget.evaluate(candidate,active,Fixture.player(),{},c)
	t.check(not result.accepted and result.diagnostics.detail == "horizon_exceeds_limit","reservations beyond 180 ticks defer rather than truncate safety proof")
	var bad := candidate.duplicate(true)
	bad.locked_direction = [0,0]
	t.check(budget.evaluate(bad,_empty(),Fixture.player(),{},c).reason == "invalid_candidate","invalid model candidate rejected")
	c.move_speed = NAN
	t.check(budget.evaluate(candidate,_empty(),Fixture.player(),{},c).reason == "invalid_candidate","nonfinite motion context rejected")

func _empty() -> Array[Dictionary]:
	return []

func test_visibility_and_bad_projection_types(t,budget,catalog: Dictionary) -> void:
	var c := _context(0.0)
	c.survival_tick = 10800
	var candidate := _attack(catalog)
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]}
	var result: Dictionary = budget.evaluate(candidate,_empty(),Fixture.player([60,0]),world,c)
	t.check(result.accepted and result.diagnostics.visibility_blocked > 0,"budget shares damage visibility gate for protected wall-back path")
	var active: Array[Dictionary] = [_legacy()]
	active[0].threat_cost = "two"
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "invalid_candidate","projection wrong cost type rejected without exception")
	active = [_legacy()]
	active[0].damage_geometry[0].unrecognized_projection = true
	t.check(budget.evaluate(candidate,active,Fixture.player(),{},c).reason == "invalid_candidate","projection rejects unknown geometry format fields")

func test_wall_adjacent_player_keeps_real_escape(t,budget,catalog: Dictionary) -> void:
	var world := {"bounds":[-32,-300,64,600],"obstacles":[]}
	var result: Dictionary = budget.evaluate(_attack(catalog),_empty(),Fixture.player([24,0]),world,_context())
	t.check(result.accepted,"legal wall-adjacent player can flee along wall instead of making enemies permanently idle")
	if result.accepted:
		for point in result.safe_path: t.check(World.walkable(Vector2(point.position[0],point.position[1]),8,world),"actual player body stays clear of wall")

func test_identical_path_prefixes_share_queries(t,budget,catalog: Dictionary) -> void:
	var c := _context()
	c.survival_tick = 10800
	c.max_work_units = 100000
	var world := {"bounds":[-32,-300,64,600],"obstacles":[]}
	var boss := _legacy("boss:corridor",[0,170],172,184)
	boss.damage_geometry.append({"shape":"circle","origin":[0,-170],"radius":96.0})
	var active: Array[Dictionary] = [boss]
	var result: Dictionary = budget.evaluate(_attack(catalog),active,Fixture.player(),world,c)
	t.check(result.reason == "no_safe_path" and result.diagnostics.paths_tested == 272 and result.diagnostics.work_units == 11798,"cached search retains every candidate path and exact logical cost")
	t.check(result.diagnostics.get("path_prefix_reuses",0) > 0,"common first-direction prefixes are reused without repeating per-tick traversal")
	t.check(result.diagnostics.get("cache_hits",0) > 0,"identical reaction and turning prefixes reuse exact transition queries")
	t.check(result.diagnostics.get("actual_query_units",result.diagnostics.work_units) < result.diagnostics.work_units,"actual queries are lower than separately preserved logical work units")
	c.max_work_units = 8192
	var limited: Dictionary = budget.evaluate(_attack(catalog),active,Fixture.player(),world,c)
	t.check(limited.reason == "work_budget_exhausted" and limited.diagnostics.work_units == 8192 and limited.diagnostics.paths_tested == 198,"cache never turns partial logical budget into success")

func test_legacy_fixed_damage_ignores_new_visibility(t,budget,catalog: Dictionary) -> void:
	# The retained Core legacy path uses this raw overlap predicate, without
	# Model.visibility. The planner may not invent a wall exemption for it.
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]}
	var candidate := _attack(catalog,"walker",1,[150,0],[120,0])
	var c := _context(0.0)
	c.survival_tick = 10800
	for shape in [{"shape":"circle","origin":[0,0],"radius":96.0},{"shape":"sector","origin":[0,0],"direction":[1.0,0.0],"radius":96.0,"arc_degrees":70.0}]:
		var legacy := _legacy("boss:instant",[0,0],100,101)
		legacy.damage_geometry = [shape]
		var active: Array[Dictionary] = [legacy]
		t.check(Geometry.overlaps(shape,Vector2(60,0),8.0),"legacy actual damage predicate overlaps wall-back player")
		var result: Dictionary = budget.evaluate(candidate,active,Fixture.player([60,0]),world,c)
		t.check(not result.accepted and result.reason == "no_safe_path","legacy fixed danger cannot be narrowed by new radial visibility")
		t.check(result.diagnostics.visibility_blocked == 0,"legacy projection has explicit no-visibility-exemption semantics")
