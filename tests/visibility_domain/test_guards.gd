extends RefCounted
const S = preload("res://tests/visibility_domain/support.gd")
const CustomStream = preload("res://tests/visibility_domain/custom_stream.gd")
const CustomCached = preload("res://tests/visibility_domain/custom_cached.gd")
const CustomView = preload("res://tests/visibility_domain/custom_view.gd")
func run(t) -> void:
	var before: int = t.cases.size()
	for cached in [false,true]:
		_invalid_and_limits(t,cached)
		_sticky_errors(t,cached)
		_geometry_and_origin(t,cached)
		_custom(t,cached,false)
		_custom(t,cached,true)
	t.check(t.cases.size()-before == 90,"guard all 90 comparisons returned")
	t.completed.append("test_guards.gd")
func _invalid_and_limits(t, cached: bool) -> void:
	var entries: Array = [
		["negative_radius",Vector2(100,120),Vector2(220,120),-1.0],
		["too_large_radius",Vector2(100,120),Vector2(220,120),32.00001],
		["nan_radius",Vector2(100,120),Vector2(220,120),NAN],
		["inf_radius",Vector2(100,120),Vector2(220,120),INF],
		["nan_position",Vector2(NAN,120),Vector2(220,120),8.0],
		["inf_position",Vector2(INF,120),Vector2(220,120),8.0],
		["minus_inf_position",Vector2(-INF,120),Vector2(220,120),8.0],
		["nan_target",Vector2(100,120),Vector2(NAN,120),8.0],
		["inf_target",Vector2(100,120),Vector2(INF,120),8.0],
		["position_above_limit",Vector2(49152.00390625,120),Vector2(49152.00390625,120),0.0],
		["position_below_limit",Vector2(-49152.00390625,120),Vector2(-49152.00390625,120),0.0],
		["delta_above_limit",Vector2.ZERO,Vector2(49152.00390625,0),0.0],
		["diagonal_components_not_length",Vector2.ZERO,Vector2(40000,40000),0.0]
	]
	for entry in entries:
		var p: Dictionary = S.pair(t,cached)
		var result: Dictionary = S.query(t,p,entry[1],entry[2],entry[3],entry[0],"full")
		t.check(not result.ok,"invalid native argument fails")
		S.expect_status(t,p,"","invalid_query","invalid_query",entry[0])
		for world in p.worlds: t.check(world._query_count == 0,"invalid query does not read geometry")
	for endpoints in [
		[Vector2(49152,0),Vector2(49152,0)],
		[Vector2(-49152,0),Vector2(-49152,0)],
		[Vector2.ZERO,Vector2(49152,0)],
		[Vector2.ZERO,Vector2(-49152,0)],
		[Vector2(49152,0),Vector2(98304,0)],
		[Vector2(49151.99609375,0),Vector2(49151.99609375,0)]
	]:
		var p: Dictionary = S.pair(t,cached)
		t.check(S.Stream._valid_query(endpoints[0],endpoints[1]-endpoints[0],0.0),"exact large finite coordinates satisfy real guard")
		var result: Dictionary = S.query(t,p,endpoints[0],endpoints[1],0.0,"valid_large_"+str(endpoints),"full")
		t.check(not result.ok,"valid large coordinate fails missing coverage")
		S.expect_status(t,p,"world_not_ready","world_not_ready","world_not_ready","valid large uncovered")
func _sticky_errors(t, cached: bool) -> void:
	var p: Dictionary = S.pair(t,cached)
	for view in p.views: view.sweep(Vector2(100,120),Vector2(100000,0),8.0)
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"preexisting_view_latch","full"),true,"successful fallback after View error")
	S.expect_status(t,p,"","invalid_query","invalid_query","prior View error survives")
	for view in p.views: view.begin_navigation_queries()
	S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"explicit_view_begin")
	S.expect_status(t,p,"","","invalid_query","View reset cannot clear existing helper failure")
	p = S.pair(t,cached)
	for world in p.worlds: t.check(not world.covered(Rect2(10000,10000,1,1)),"real coverage establishes world error")
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"preexisting_world_error","full"),true,"world-only prior error")
	S.expect_status(t,p,"world_not_ready","","","successful fallback retains world-only error")
	for coverage_first in [true,false]:
		p = S.pair(t,cached,[],[["0","0"]])
		var first := Vector2(800,120) if coverage_first else Vector2(100000,120)
		var second := Vector2(100000,120) if coverage_first else Vector2(800,120)
		S.query(t,p,Vector2(100,120),first,8.0,"ordered_first_"+str(coverage_first),"full")
		var first_latch: Dictionary = p.views[0]._query_failure.duplicate(true)
		S.query(t,p,Vector2(100,120),second,8.0,"ordered_second_"+str(coverage_first),"full")
		S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"ordered_success_"+str(coverage_first),"full")
		t.check(S.same(p.views[0]._query_failure,first_latch) and S.same(p.helpers[0]._query_failure,first_latch),"View and helper retain exact first failure payload")
func _geometry_and_origin(t, cached: bool) -> void:
	var records: Array = [S.prop("block",Rect2(128,100,40,40))]
	var p: Dictionary = S.pair(t,cached,records,S.neighborhood(["0","0"],2))
	for repeat in 2: S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"warm_before_destroy_"+str(repeat)),false,"warm blocker")
	for world in p.worlds:
		t.check(not world._collision_bucket_cache.is_empty(),"candidate records are warm")
		t.check(world.apply_props([{"chunk":["0","0"],"props":[{"slot_id":"block","hp":0,"destroyed":true}]}],1).get("ok",false),"public geometry revision changes")
		t.check(world._collision_bucket_cache.is_empty(),"revision retires candidate bucket cache")
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"after_destroy"),true,"destroyed prop gone")
	for world in p.worlds: t.check(not world.apply_props([],1).ok,"stale world revision rejected")
	S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"after_stale_revision","full")
	S.expect_status(t,p,"stale_world_revision","","","rejected mutation error retained")
	p = S.pair(t,cached,records,S.neighborhood(["0","0"],2))
	S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"before_rebase")
	S.prepare_all(t,p,S.neighborhood(["0","0"],2),["1","0"])
	S.expect_visible(t,S.query(t,p,Vector2(-668,120),Vector2(-548,120),8.0,"same_physical_after_rebase"),false,"rebase keeps physical blocker")
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"same_local_after_rebase"),true,"rebase refreshes local geometry")
	# Warm a domain, then retire an endpoint cell. A stale proof must not admit.
	p = S.pair(t,cached,[],[["0","0"],["1","0"]])
	S.query(t,p,Vector2(100,120),Vector2(768,120),0.0,"before_residency_retire","one")
	S.prepare_all(t,p,[["0","0"]],["0","0"])
	S.query(t,p,Vector2(100,120),Vector2(768,120),0.0,"after_residency_retire","full")
	S.expect_status(t,p,"world_not_ready","","","retired endpoint cell cannot remain cached")
	var origin: Array = ["9007199254740993","-9007199254740993"]
	p = S.pair(t,cached,records,S.neighborhood(origin),origin)
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"int64_origin"),false,"no lossy absolute origin conversion")
	var shifted: Array = ["9007199254740994","-9007199254740993"]
	S.prepare_all(t,p,S.neighborhood(origin),shifted)
	S.expect_visible(t,S.query(t,p,Vector2(-668,120),Vector2(-548,120),8.0,"int64_rebase"),false,"int64 physical segment after rebase")
func _custom(t, cached: bool, derived_view: bool) -> void:
	var p: Dictionary = S.pair(t,cached)
	if derived_view:
		for index in 3: p.views[index] = CustomView.new(p.worlds[index])
	else:
		var script = CustomCached if cached else CustomStream
		for index in 3:
			p.worlds[index] = script.new(S.Generator.new(),42)
			t.check(p.worlds[index].prepare(p.chunks,[],S.F.hydration(p.chunks),["0","0"]).get("ok",false),"custom fixture prepares")
			p.views[index] = S.View.new(p.worlds[index])
			p.helpers[index]._world = p.worlds[index]
	for index in 3: S.query(t,p,Vector2(100,120),Vector2(220+index,120),8.0,"derived_view="+str(derived_view)+"_"+str(index),"full")
	for index in [1,2]:
		var a = p.views[0] if derived_view else p.worlds[0]
		var b = p.views[index] if derived_view else p.worlds[index]
		t.check(S.same(a.sweep_calls,b.sweep_calls) and a.sweep_calls.size() == 3,"derived callback exact arguments and order")
		if not derived_view: t.check(S.same(a.public_calls,b.public_calls) and not a.public_calls.is_empty(),"custom owned public-query callbacks preserved")
	t.check(not p.helpers[0].query_status().ok and str(p.helpers[0].query_status().error_code).ends_with("second_failure"),"actual helper sees custom second failure after later success")
