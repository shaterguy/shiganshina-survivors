extends RefCounted
const T = preload("res://tests/core/test_rebuild_streamed_tick.gd")
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const F = preload("res://tests/core/core_fixture.gd")
const N = preload("res://game/world/precise_city_navigation.gd")
const View = preload("res://game/world/streamed_navigation_view.gd")
const NF = preload("res://tests/navigation_view/test_streamed_navigation_view.gd")
const WF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	_moving_goal(t)
	_exact_cache_inputs(t)
	_radius_replay(t)
	_geometry_revisions(t)
func _moving_goal(t) -> void:
	var setup := T.new().fixture(t,[35.0,131.0])
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.attack_ready_ticks = {"blade_slash":10000}
	state.player.invulnerable_until = 10000
	var spawn := {"command_id":"moving-goal","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"moving-goal-walker","enemy_id":"walker","position":[384,384],"spawned_tick":0}}
	F.step(sim,state,Vector2.ZERO,[spawn])
	t.check(state.entities.size() == 1,"moving-goal replay uses an actual generated-city walker")
	var cold := Core.new(City.new())
	for tick in 36:
		var restored := cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),setup.hydration)
		t.check(restored.get("ok",false) and cold.prepare_world(restored.state,setup.hydration).ok,"moving target has a valid cold JSON control: "+str(tick))
		if not restored.get("ok",false): return
		var replay: Dictionary = restored.state
		var before_tick: int = state.active_tick
		var warm_events := F.step(sim,state,Vector2.DOWN)
		var cold_events := F.step(cold,replay,Vector2.DOWN)
		t.check(state.active_tick == before_tick+1,"moving goal cannot freeze a fully covered warm city tick: "+str(tick))
		t.check(state == replay and warm_events == cold_events,"moving-goal warm/cold Core state and events remain exact: "+str(tick))
		if state != replay: return
func _exact_cache_inputs(t) -> void:
	var setup := T.new().fixture(t)
	if setup.is_empty(): return
	var helper = setup.sim._streamed
	var origin := Vector2(384,384)
	var goal := Vector2(35,155)
	var first: Dictionary = helper.direction(origin,goal,18.1,1)
	t.check(first.ok,"cache-input control has an actual obstructed route")
	if not first.ok: return
	var a: Dictionary = helper._navigation.diagnostics()
	var second: Dictionary = helper.direction(origin,goal,19.9,2)
	var b: Dictionary = helper._navigation.diagnostics()
	t.check(second.ok and b.grid_builds == a.grid_builds and b.route_builds == a.route_builds+1,"actual radius change within clearance20 refreshes only reverse distances")
	var third: Dictionary = helper.direction(origin,goal,19.9,3)
	var c: Dictionary = helper._navigation.diagnostics()
	t.check(third.ok and c == b,"identical precise goal/radius retains the distance field")
	var fourth: Dictionary = helper.direction(origin,goal+Vector2(0,1),19.9,4)
	var d: Dictionary = helper._navigation.diagnostics()
	t.check(fourth.ok and d.grid_builds == c.grid_builds and d.route_builds == c.route_builds+1,"same-cell exact goal movement refreshes distances without rebuilding geometry")

func _radius_replay(t) -> void:
	for pair in [[Vector2(100,384),Vector2(67,35)],[Vector2(384,384),Vector2(579,35)]]:
		var setup := T.new().fixture(t)
		if setup.is_empty(): return
		var warm = setup.sim._streamed
		var first: Dictionary = warm.direction(pair[0],pair[1],17.0,10)
		t.check(first.ok,"radius17 warm-up has a real covered obstructed route")
		var result: Dictionary = warm.direction(pair[0],pair[1],18.0,11)
		var cold = warm.fresh()
		t.check(cold.prepare(setup.state,setup.hydration).ok,"radius18 control gets independent fresh geometry/navigation")
		var expected: Dictionary = cold.direction(pair[0],pair[1],18.0,11)
		t.check(result.ok and expected.ok and result == expected,"same-clearance radius17→18 path matches cold route exactly")

func _geometry_revisions(t) -> void:
	var fixture := NF.new()._fixture()
	var world = fixture.world
	var nav := N.new(View.new(world))
	var origin := Vector2(496,194)
	var target := Vector2(1152,384)
	var first := nav.direction(origin,target,8,0)
	t.check(first.ok,"precise navigation has a real cross-chunk geometry control")
	var changes := []
	for prop in world.localized_chunk("0,0").props:
		if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
	t.check(world.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"precise cache test applies real destruction geometry")
	t.check(nav.direction(origin,target,8,1) == N.new(View.new(world)).direction(origin,target,8,1),"geometry revision invalidates precise fields and grids exactly")
	fixture = NF.new()._fixture()
	world = fixture.world
	nav = N.new(View.new(world))
	first = nav.direction(origin,target,8,0)
	var chunks := []
	for y in range(-1,2):
		for x in range(0,3): chunks.append([str(x),str(y)])
	t.check(world.prepare(chunks,[],WF.hydration({"chunks":chunks}),["1","0"]).ok,"precise cache test publishes actual rebased coverage")
	var shifted_origin := origin-Vector2(768,0)
	var shifted_target := target-Vector2(768,0)
	var rebased := nav.direction(shifted_origin,shifted_target,8,2)
	t.check(rebased == N.new(View.new(world)).direction(shifted_origin,shifted_target,8,2) and rebased.ok and rebased.length == first.length,"precise warm rebase route equals cold geometry with one shift")
	fixture = NF.new()._fixture()
	nav = N.new(View.new(fixture.world))
	shifted_origin = Vector2(384,384)
	shifted_target = Vector2(35,131)
	nav.direction(shifted_origin,shifted_target,18,2)
	var before := nav.diagnostics()
	var durations := []
	var route_count := 0
	for tick in 60:
		var goal := shifted_target+Vector2(0,float(tick%5))
		var start := Time.get_ticks_usec()
		var route := nav.direction(shifted_origin,goal,18,tick+3)
		durations.append(Time.get_ticks_usec()-start)
		if route.ok: route_count += 1
	var after := nav.diagnostics()
	durations.sort()
	t.check(route_count == 60 and after.grid_builds == before.grid_builds and after.route_builds-before.route_builds == 59,"sixty moving-goal routes retain immutable geometry grids")
	print("PRECISE_NAV_ROUTE_DIAGNOSTIC count=60 median_us=%d max_us=%d distance_builds=%d grid_builds=%d"%[durations[30],durations[-1],after.route_builds-before.route_builds,after.grid_builds-before.grid_builds])
